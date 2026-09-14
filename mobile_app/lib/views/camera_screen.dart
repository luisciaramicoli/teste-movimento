import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/joint_angle.dart';
import '../models/exercise_preset.dart';
import '../services/pose_detector_service.dart';
import '../services/rep_counter_service.dart';
import '../services/motion_trail_service.dart';
import '../painters/pose_painter.dart';
import 'report_screen.dart';

class CameraScreen extends StatefulWidget {
  final bool initialSimulationMode;

  const CameraScreen({super.key, this.initialSimulationMode = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  late final PoseDetectorService _poseService;
  late final RepCounterService _repCounter;
  late final MotionTrailService _motionTrail;
  late final JointAngleTracker _tracker;

  Map<String, JointAngleData> _currentAngles = {};
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();

  bool _isSimulationMode = false;
  Timer? _simulationTimer;
  double _simTime = 0.0;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _poseService = PoseDetectorService();
    _repCounter = RepCounterService(initialExercise: 'squat');
    _motionTrail = MotionTrailService(enabled: true);
    _tracker = JointAngleTracker();

    _isSimulationMode = widget.initialSimulationMode;
    if (_isSimulationMode) {
      _startSimulation();
    } else {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _fallbackToSimulation();
        return;
      }

      // Procura câmera frontal ou traseira
      _selectedCameraIndex = 0;
      final camera = _cameras[_selectedCameraIndex];

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      _stopwatch.start();
      _cameraController!.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Erro ao inicializar câmera: $e');
      _fallbackToSimulation();
    }
  }

  void _fallbackToSimulation() {
    if (!mounted) return;
    setState(() {
      _isSimulationMode = true;
    });
    _startSimulation();
  }

  void _startSimulation() {
    _stopwatch.start();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      _simTime += 0.033;
      final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;

      final angles = _poseService.generateSyntheticAngles(_simTime);
      _tracker.update(angles, elapsed);
      _repCounter.update(angles, elapsed);

      // Atualiza trilhas
      final Map<String, Point2D?> trailPts = {
        'LEFT_WRIST': const Point2D(120, 260),
        'RIGHT_WRIST': const Point2D(280, 260),
        'LEFT_KNEE': angles['joelho_esq']?.vertex,
        'RIGHT_KNEE': angles['joelho_dir']?.vertex,
      };
      _motionTrail.update(trailPts);

      if (mounted) {
        setState(() {
          _currentAngles = angles;
          _fps = 30.0;
        });
      }
    });
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) return;

      final poses = await _poseService.processImage(inputImage);
      if (poses.isNotEmpty && mounted) {
        final pose = poses.first;
        final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;

        final isFront = _cameras.isNotEmpty &&
            _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;

        final angles = _poseService.extractAnglesFromPose(
          pose,
          Size(image.width.toDouble(), image.height.toDouble()),
          MediaQuery.of(context).size,
          isFrontCamera: isFront,
        );

        _tracker.update(angles, elapsed);
        _repCounter.update(angles, elapsed);

        // Atualização das trilhas
        final Map<String, Point2D?> trailPts = {};
        angles.forEach((k, v) {
          if (v.vertex != null) {
            trailPts[k] = v.vertex;
          }
        });
        _motionTrail.update(trailPts);

        _frameCount++;
        if (_frameCount % 10 == 0) {
          final now = DateTime.now();
          final diff = now.difference(_lastFpsTime).inMilliseconds;
          if (diff > 0) {
            _fps = 10000.0 / diff;
          }
          _lastFpsTime = now;
        }

        setState(() {
          _currentAngles = angles;
        });
      }
    } catch (e) {
      debugPrint('Erro processando frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    if (_cameraController == null) return null;

    final camera = _cameras[_selectedCameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    switch (sensorOrientation) {
      case 0:
        rotation = InputImageRotation.rotation0deg;
        break;
      case 90:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = InputImageRotation.rotation270deg;
        break;
      default:
        rotation = InputImageRotation.rotation0deg;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Concatenação de planos
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;

    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    _cameraController!.startImageStream(_processCameraFrame);
    setState(() {});
  }

  void _openExerciseSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: exercisePresets.values.map((preset) {
              return ListTile(
                leading: Icon(
                  preset.name == 'free' ? Icons.accessibility_new : Icons.fitness_center,
                  color: const Color(0xFF00E5FF),
                ),
                title: Text(preset.displayName, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  setState(() {
                    _repCounter.setExercise(preset.name);
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _finishSession() {
    _simulationTimer?.cancel();
    _cameraController?.stopImageStream();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportScreen(
          tracker: _tracker,
          repCounter: _repCounter,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _cameraController?.dispose();
    _poseService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fundo da Câmera ou Placeholder do Modo Simulação
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            Container(
              color: const Color(0xFF181818),
              child: const Center(
                child: Text(
                  'Modo Simulação Ativo',
                  style: TextStyle(color: Colors.white38, fontSize: 18),
                ),
              ),
            ),

          // 2. CustomPainter com Esqueleto, Badges e Comet Trail
          CustomPaint(
            painter: PosePainter(
              anglesData: _currentAngles,
              motionTrail: _motionTrail,
            ),
          ),

          // 3. HUD Superior (Painel de Ângulos e FPS)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: _buildAnglesHud(),
            ),
          ),

          // 4. Card de Exercício e Repetições (Canto Superior Direito)
          if (_repCounter.config.name != 'free')
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: _buildRepCard(),
              ),
            ),

          // 5. Barra Inferior de Controles
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnglesHud() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('MONITORAMENTO', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('FPS: ${_fps.toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          ..._currentAngles.entries.take(4).map((entry) {
            final val = entry.value.angle != null ? '${entry.value.angle!.round()}°' : '--';
            return Text(
              '${entry.value.label.split(" ")[0]}: $val',
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRepCard() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xDD1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E676)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _repCounter.config.displayName,
            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'REPS: ${_repCounter.repCount}',
            style: const TextStyle(color: Color(0xFF00E676), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 90,
            height: 6,
            child: LinearProgressIndicator(
              value: _repCounter.progressPct,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                _repCounter.progressPct >= 0.95 ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _repCounter.feedbackMessage,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Alternar Exercício
          IconButton.filledTonal(
            icon: const Icon(Icons.fitness_center),
            tooltip: 'Exercício',
            onPressed: _openExerciseSelector,
          ),

          // Ligar/Desligar Trilha (Comet Trail)
          IconButton.filledTonal(
            icon: Icon(_motionTrail.enabled ? Icons.blur_on : Icons.blur_off),
            tooltip: 'Trilha de Movimento',
            onPressed: () {
              setState(() {
                _motionTrail.toggle();
              });
            },
          ),

          // Resetar
          IconButton.filledTonal(
            icon: const Icon(Icons.refresh),
            tooltip: 'Zerar Recordes',
            onPressed: () {
              setState(() {
                _tracker.resetAll();
                _repCounter.reset();
                _motionTrail.clear();
              });
            },
          ),

          // Trocar Câmera
          if (_cameras.length > 1)
            IconButton.filledTonal(
              icon: const Icon(Icons.flip_camera_android),
              tooltip: 'Inverter Câmera',
              onPressed: _switchCamera,
            ),

          // Finalizar e Ver Relatório
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.stop),
            label: const Text('Finalizar'),
            onPressed: _finishSession,
          ),
        ],
      ),
    );
  }
}
