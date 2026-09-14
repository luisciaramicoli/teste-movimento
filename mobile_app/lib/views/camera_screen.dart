import 'dart:async';
import 'dart:io';
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
  Map<String, Point2D> _currentLandmarks = {};
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
    _repCounter = RepCounterService(initialExercise: 'free');
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

      // Procura câmera frontal por padrão para exercícios ou primeira disponível
      final frontIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _selectedCameraIndex = frontIndex >= 0 ? frontIndex : 0;
      final camera = _cameras[_selectedCameraIndex];

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
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
      final screenSize = MediaQuery.of(context).size;

      final extracted = _poseService.generateSyntheticAngles(_simTime, screenSize);
      _tracker.update(extracted.angles, elapsed);
      _repCounter.update(extracted.angles, elapsed);

      // Atualiza trilhas
      final Map<String, Point2D?> trailPts = {
        'LEFT_WRIST': extracted.landmarks['LEFT_WRIST'],
        'RIGHT_WRIST': extracted.landmarks['RIGHT_WRIST'],
        'LEFT_KNEE': extracted.landmarks['LEFT_KNEE'],
        'RIGHT_KNEE': extracted.landmarks['RIGHT_KNEE'],
      };
      _motionTrail.update(trailPts);

      if (mounted) {
        setState(() {
          _currentAngles = extracted.angles;
          _currentLandmarks = extracted.landmarks;
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
      if (mounted) {
        _frameCount++;
        if (_frameCount % 5 == 0) {
          final now = DateTime.now();
          final diff = now.difference(_lastFpsTime).inMilliseconds;
          if (diff > 0) {
            _fps = (5000.0 / diff).clamp(1.0, 60.0);
          }
          _lastFpsTime = now;
        }

        if (poses.isNotEmpty) {
          final pose = poses.first;
          final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;

          final isFront = _cameras.isNotEmpty &&
              _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;

          // No Android em modo retrato (rotação 90° ou 270°), a largura e altura são trocadas
          final bool isRotated = inputImage.metadata?.rotation == InputImageRotation.rotation90deg ||
              inputImage.metadata?.rotation == InputImageRotation.rotation270deg;
          final double rotatedWidth = isRotated ? image.height.toDouble() : image.width.toDouble();
          final double rotatedHeight = isRotated ? image.width.toDouble() : image.height.toDouble();

          final extracted = _poseService.extractAnglesFromPose(
            pose,
            inputImageSize: Size(rotatedWidth, rotatedHeight),
            screenSize: MediaQuery.of(context).size,
            isFrontCamera: isFront,
          );

          _tracker.update(extracted.angles, elapsed);
          _repCounter.update(extracted.angles, elapsed);

          // Atualização das trilhas de movimento
          final Map<String, Point2D?> trailPts = {
            'LEFT_WRIST': extracted.landmarks['LEFT_WRIST'],
            'RIGHT_WRIST': extracted.landmarks['RIGHT_WRIST'],
            'LEFT_KNEE': extracted.landmarks['LEFT_KNEE'],
            'RIGHT_KNEE': extracted.landmarks['RIGHT_KNEE'],
          };
          _motionTrail.update(trailPts);

          setState(() {
            _currentAngles = extracted.angles;
            _currentLandmarks = extracted.landmarks;
          });
        } else {
          setState(() {
            _currentAngles = {};
            _currentLandmarks = {};
          });
        }
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

    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;

    Uint8List bytes;
    InputImageFormat format;

    if (Platform.isAndroid) {
      format = InputImageFormat.nv21;
      if (image.planes.length == 1) {
        bytes = image.planes[0].bytes;
      } else {
        final Uint8List nv21 = Uint8List(ySize + uvSize);
        final Plane yPlane = image.planes[0];
        final Plane uPlane = image.planes[1];
        final Plane vPlane = image.planes[2];

        // 1. Cópia ultra-rápida do plano Y
        if (yPlane.bytesPerRow == width) {
          nv21.setRange(0, ySize, yPlane.bytes);
        } else {
          for (int y = 0; y < height; y++) {
            nv21.setRange(y * width, (y + 1) * width, yPlane.bytes, y * yPlane.bytesPerRow);
          }
        }

        // 2. Cópia dos planos UV (NV21 espera V seguido de U)
        final int vPixelStride = vPlane.bytesPerPixel ?? 1;
        if (vPixelStride == 2 && vPlane.bytesPerRow == width && vPlane.bytes.length >= uvSize) {
          // No Android CameraX YUV_420_888, vPlane já é o buffer entrelaçado VU contíguo
          nv21.setRange(ySize, ySize + uvSize, vPlane.bytes);
        } else {
          int uvIndex = ySize;
          final int halfHeight = height ~/ 2;
          final int halfWidth = width ~/ 2;
          final int uRowStride = uPlane.bytesPerRow;
          final int vRowStride = vPlane.bytesPerRow;
          final int uPixelStride = uPlane.bytesPerPixel ?? 1;

          for (int y = 0; y < halfHeight; y++) {
            final int uRow = y * uRowStride;
            final int vRow = y * vRowStride;
            for (int x = 0; x < halfWidth; x++) {
              nv21[uvIndex++] = vPlane.bytes[vRow + x * vPixelStride];
              nv21[uvIndex++] = uPlane.bytes[uRow + x * uPixelStride];
            }
          }
        }
        bytes = nv21;
      }
    } else {
      format = InputImageFormat.bgra8888;
      bytes = image.planes[0].bytes;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
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
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ...exercisePresets.values.map((preset) {
                final isSelected = _repCounter.config.name == preset.name;
                return ListTile(
                  leading: Icon(
                    preset.name == 'free' ? Icons.accessibility_new : Icons.fitness_center,
                    color: isSelected ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                  ),
                  title: Text(
                    preset.displayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                  onTap: () {
                    setState(() {
                      _repCounter.setExercise(preset.name);
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
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

  Widget _buildCameraPreview(Size screenSize) {
    if (!_isCameraInitialized || _cameraController == null) {
      return Container(
        color: const Color(0xFF181818),
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00E5FF),
          ),
        ),
      );
    }

    final previewSize = _cameraController!.value.previewSize;
    // Android portrait: previewSize is landscape (width > height), so swap
    final double previewW = previewSize != null ? previewSize.height : 720.0;
    final double previewH = previewSize != null ? previewSize.width : 1280.0;

    return ClipRect(
      child: Center(
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fundo da Câmera ou Placeholder do Modo Simulação
          if (_isSimulationMode)
            Container(
              color: const Color(0xFF181818),
              child: const Center(
                child: Text(
                  'Modo Simulação Ativo',
                  style: TextStyle(color: Colors.white38, fontSize: 18),
                ),
              ),
            )
          else
            _buildCameraPreview(screenSize),

          // 2. CustomPainter com Esqueleto, Badges e Comet Trail
          Positioned.fill(
            child: CustomPaint(
              size: screenSize,
              painter: PosePainter(
                anglesData: _currentAngles,
                landmarks: _currentLandmarks,
                motionTrail: _motionTrail,
                activeExercise: _repCounter.config.name,
              ),
            ),
          ),

          // 3. HUD Superior (Painel de Ângulos, FPS e Exercício)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildAnglesHud(),
                  if (_repCounter.config.name != 'free')
                    _buildRepCard()
                  else
                    _buildModeBadge(),
                ],
              ),
            ),
          ),

          // 4. Barra Inferior de Controles
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xD914181D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('MONITOR', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('${_fps.toStringAsFixed(0)} FPS', style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          _buildHudRow('Cotovelo', _currentAngles['cotovelo_esq']?.angle, _currentAngles['cotovelo_dir']?.angle),
          _buildHudRow('Ombro', _currentAngles['ombro_esq']?.angle, _currentAngles['ombro_dir']?.angle),
          _buildHudRow('Joelho', _currentAngles['joelho_esq']?.angle, _currentAngles['joelho_dir']?.angle),
          _buildHudRow('Quadril', _currentAngles['quadril_esq']?.angle, _currentAngles['quadril_dir']?.angle),
        ],
      ),
    );
  }

  Widget _buildHudRow(String name, double? left, double? right) {
    final strL = left != null ? '${left.round()}°' : '--';
    final strR = right != null ? '${right.round()}°' : '--';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Text(
        '$name E:$strL D:$strR',
        style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildModeBadge() {
    return GestureDetector(
      onTap: _openExerciseSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xD914181D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.accessibility_new, color: Color(0xFF00E5FF), size: 16),
            SizedBox(width: 6),
            Text(
              'Modo Livre',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRepCard() {
    return GestureDetector(
      onTap: _openExerciseSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xD914181D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF00E676)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E676).withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _repCounter.config.displayName.split(' ')[0],
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 14),
              ],
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _repCounter.progressPct,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                    _repCounter.progressPct >= 0.95 ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                  ),
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

