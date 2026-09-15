import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/joint_angle.dart';
import '../models/exercise_preset.dart';
import '../services/pose_detector_service.dart';
import '../services/rep_counter_service.dart';
import '../painters/pose_painter.dart';
import 'report_screen.dart';

class CameraScreen extends StatefulWidget {
  final bool initialSimulationMode;

  const CameraScreen({super.key, this.initialSimulationMode = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  late final PoseDetectorService _poseService;
  late final RepCounterService _repCounter;
  late final JointAngleTracker _tracker;

  final ValueNotifier<ExtractedPoseData?> _poseNotifier = ValueNotifier<ExtractedPoseData?>(null);
  final ValueNotifier<double> _fpsNotifier = ValueNotifier<double>(0.0);
  Uint8List? _cachedNv21Buffer;

  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  int _emptyPoseFrames = 0;

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  bool _isMirror = true;
  bool _isSimulationMode = false;
  Timer? _simulationTimer;
  double _simTime = 0.0;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poseService = PoseDetectorService();
    _repCounter = RepCounterService(initialExercise: 'free');
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
      _isMirror = camera.lensDirection == CameraLensDirection.front;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();
      if (!mounted) return;

      _cameraController!.addListener(() {
        if (!mounted) return;
        if (_cameraController != null && _cameraController!.value.hasError) {
          debugPrint('Camera error detectado: ${_cameraController!.value.errorDescription}');
          _reconnectCamera();
        }
      });

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

  bool _isReconnecting = false;
  Future<void> _reconnectCamera() async {
    if (_isReconnecting || !mounted) return;
    _isReconnecting = true;
    try {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
    } catch (_) {}
    _cameraController = null;
    _isCameraInitialized = false;
    await Future.delayed(const Duration(milliseconds: 400));
    _isReconnecting = false;
    if (mounted) {
      _initCamera();
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

      if (mounted) {
        _poseNotifier.value = extracted;
        _fpsNotifier.value = 30.0;
      }
    });
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    final sw = Stopwatch()..start();
    try {
      final t0 = sw.elapsedMilliseconds;
      final inputImage = _convertCameraImageToInputImage(image);
      final tConvert = sw.elapsedMilliseconds - t0;
      if (inputImage == null) return;

      final t1 = sw.elapsedMilliseconds;
      final poses = await _poseService.processImage(inputImage);
      final tMlKit = sw.elapsedMilliseconds - t1;

      if (mounted) {
        _frameCount++;
        final now = DateTime.now();
        final diff = now.difference(_lastFpsTime).inMilliseconds;
        if (diff >= 500) {
          _fps = (_frameCount * 1000.0 / diff).clamp(1.0, 60.0);
          _frameCount = 0;
          _lastFpsTime = now;
          _fpsNotifier.value = _fps;
          debugPrint('PoseTracking: ${image.width}x${image.height} | FPS: ${_fps.toStringAsFixed(1)} | Convert: ${tConvert}ms | MLKit: ${tMlKit}ms');
        }

        if (poses.isNotEmpty) {
          _emptyPoseFrames = 0;
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

          _poseNotifier.value = extracted;
        } else {
          _emptyPoseFrames++;
          // Permite tolerância de até 6 frames consecutivos vazios para não piscar o esqueleto
          if (_emptyPoseFrames > 6) {
            _poseService.resetSmoothing();
            if (_poseNotifier.value != null) {
              _poseNotifier.value = null;
            }
          }
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
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation != null) {
        if (camera.lensDirection == CameraLensDirection.front) {
          // Câmera frontal
          rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
        } else {
          // Câmera traseira
          rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }
    }
    rotation ??= InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;

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
        if (_cachedNv21Buffer == null || _cachedNv21Buffer!.length != ySize + uvSize) {
          _cachedNv21Buffer = Uint8List(ySize + uvSize);
        }
        final Uint8List nv21 = _cachedNv21Buffer!;
        final Plane yPlane = image.planes[0];
        final Plane uPlane = image.planes[1];
        final Plane vPlane = image.planes[2];

        // 1. Cópia ultra-rápida do plano Y
        if (yPlane.bytesPerRow == width) {
          nv21.setRange(0, ySize, yPlane.bytes);
        } else {
          final int yRowStride = yPlane.bytesPerRow;
          final Uint8List yBytes = yPlane.bytes;
          for (int y = 0; y < height; y++) {
            nv21.setRange(y * width, (y + 1) * width, yBytes, y * yRowStride);
          }
        }

        // 2. Cópia vetorizada dos planos UV (NV21 espera V seguido de U)
        final int vPixelStride = vPlane.bytesPerPixel ?? 1;
        if (vPixelStride == 2) {
          // No Android Camera2 (YUV_420_888), com pixelStride == 2, os dados VU já estão intercalados em memória!
          final int vRowStride = vPlane.bytesPerRow;
          final Uint8List vBytes = vPlane.bytes;
          final int vLen = vBytes.length;

          if (vRowStride == width) {
            // Buffer contíguo em uma única operação de cópia
            final int copyLen = min(uvSize, vLen);
            nv21.setRange(ySize, ySize + copyLen, vBytes);
            if (copyLen < uvSize && uPlane.bytes.isNotEmpty) {
              nv21[ySize + uvSize - 1] = uPlane.bytes.last;
            }
          } else {
            // Cópia bloco por bloco linha a linha usando setRange (evita loop pixel a pixel)
            final int halfHeight = height >> 1;
            for (int y = 0; y < halfHeight; y++) {
              final int srcOffset = y * vRowStride;
              final int dstOffset = ySize + y * width;
              final int available = vLen - srcOffset;
              if (available <= 0) break;
              final int bytesInRow = min(width, available);
              nv21.setRange(dstOffset, dstOffset + bytesInRow, vBytes, srcOffset);
              if (bytesInRow < width && uPlane.bytes.isNotEmpty && y == halfHeight - 1) {
                nv21[dstOffset + width - 1] = uPlane.bytes.last;
              }
            }
          }
        } else {
          // Fallback para pixelStride == 1
          int uvIndex = ySize;
          final int halfHeight = height >> 1;
          final int halfWidth = width >> 1;
          final int uRowStride = uPlane.bytesPerRow;
          final int vRowStride = vPlane.bytesPerRow;
          final Uint8List uBytes = uPlane.bytes;
          final Uint8List vBytes = vPlane.bytes;
          final int uLen = uBytes.length;
          final int vLen = vBytes.length;

          for (int y = 0; y < halfHeight; y++) {
            final int uRow = y * uRowStride;
            final int vRow = y * vRowStride;
            for (int x = 0; x < halfWidth; x++) {
              if (vRow + x < vLen && uvIndex < nv21.length) {
                nv21[uvIndex] = vBytes[vRow + x];
              }
              if (uRow + x < uLen && uvIndex + 1 < nv21.length) {
                nv21[uvIndex + 1] = uBytes[uRow + x];
              }
              uvIndex += 2;
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
        bytesPerRow: Platform.isAndroid ? width : image.planes[0].bytesPerRow,
      ),
    );
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _isMirror = _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
    _poseService.resetSmoothing();

    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await _cameraController!.initialize();

    _cameraController!.startImageStream(_processCameraFrame);
    if (mounted) setState(() {});
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
    WidgetsBinding.instance.removeObserver(this);
    _simulationTimer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _poseService.dispose();
    _poseNotifier.dispose();
    _fpsNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isSimulationMode) return;

    if (state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null || !_isCameraInitialized) {
        _initCamera();
      }
    }
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }
    if (controller != null) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
      await controller.dispose();
    }
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

    Widget previewWidget = SizedBox(
      width: previewW,
      height: previewH,
      child: CameraPreview(_cameraController!),
    );

    if (_isMirror) {
      previewWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(pi),
        child: previewWidget,
      );
    }

    return ClipRect(
      child: Center(
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: FittedBox(
            fit: BoxFit.cover,
            child: previewWidget,
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
            RepaintBoundary(
              child: _buildCameraPreview(screenSize),
            ),

          // 2. CustomPainter com Esqueleto e Badges
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<ExtractedPoseData?>(
                valueListenable: _poseNotifier,
                builder: (context, poseData, _) {
                  return CustomPaint(
                    size: screenSize,
                    painter: PosePainter(
                      anglesData: poseData?.angles ?? const {},
                      landmarks: poseData?.landmarks ?? const {},
                      activeExercise: _repCounter.config.name,
                    ),
                  );
                },
              ),
            ),
          ),

          // 3. HUD Superior (Painel de Ângulos, FPS e Exercício)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0),
              child: ValueListenableBuilder<ExtractedPoseData?>(
                valueListenable: _poseNotifier,
                builder: (context, poseData, _) {
                  return ValueListenableBuilder<double>(
                    valueListenable: _fpsNotifier,
                    builder: (context, fps, _) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildAnglesHud(poseData?.angles ?? const {}, fps),
                          if (_repCounter.config.name != 'free')
                            _buildRepCard()
                          else
                            _buildModeBadge(),
                        ],
                      );
                    },
                  );
                },
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

  Widget _buildAnglesHud(Map<String, JointAngleData> angles, double fps) {
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
              Text('${fps.toStringAsFixed(0)} FPS', style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          _buildHudRow('Cotovelo', angles['cotovelo_esq']?.angle, angles['cotovelo_dir']?.angle),
          _buildHudRow('Ombro', angles['ombro_esq']?.angle, angles['ombro_dir']?.angle),
          _buildHudRow('Joelho', angles['joelho_esq']?.angle, angles['joelho_dir']?.angle),
          _buildHudRow('Quadril', angles['quadril_esq']?.angle, angles['quadril_dir']?.angle),
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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

          // Resetar
          IconButton.filledTonal(
            icon: const Icon(Icons.refresh),
            tooltip: 'Zerar Recordes',
            onPressed: () {
              setState(() {
                _tracker.resetAll();
                _repCounter.reset();
              });
            },
          ),

          // Alternar Modo Espelho / Modo Direto (Sincroniza Câmera e Esqueleto)
          IconButton.filledTonal(
            icon: const Icon(Icons.swap_horiz),
            tooltip: _isMirror ? 'Modo Espelho (Ativo)' : 'Modo Direto',
            onPressed: () {
              setState(() {
                _isMirror = !_isMirror;
              });
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isMirror ? 'Modo Espelho: Câmera e Esqueleto Espelhados' : 'Modo Direto: Visão Normal'),
                  duration: const Duration(milliseconds: 1000),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          // Trocar Câmera
          if (_cameras.length > 1)
            IconButton.filledTonal(
              icon: const Icon(Icons.switch_camera_outlined),
              tooltip: 'Trocar Câmera',
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

