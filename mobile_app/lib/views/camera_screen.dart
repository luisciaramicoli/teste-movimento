import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/joint_angle.dart';
import '../models/protocol_models.dart';
import '../services/pose_detector_service.dart';
import '../services/protocol_service.dart';
import '../services/rep_counter_service.dart';
import '../services/performance_monitor.dart';
import '../painters/pose_painter.dart';
import 'report_screen.dart';

class CameraScreen extends StatefulWidget {
  final bool initialSimulationMode;

  const CameraScreen({super.key, this.initialSimulationMode = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  bool _isPausedForReport = false;
  int _lastRenderTickMs = 0;

  late final PoseDetectorService _poseService;
  late final JointAngleTracker _tracker;
  late final ProtocolService _protocol;
  late final RepCounterService _repCounter;

  // Pose bruta vinda do ML Kit para o banner superior
  final ValueNotifier<ExtractedPoseData?> _poseNotifier =
      ValueNotifier<ExtractedPoseData?>(null);

  // Pose interpolada para renderização fluida do esqueleto e ângulos
  final ValueNotifier<ExtractedPoseData?> _smoothDisplayPoseNotifier =
      ValueNotifier<ExtractedPoseData?>(null);

  final ValueNotifier<double> _fpsNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _introTimerNotifier = ValueNotifier<double>(5.0);
  ExtractedPoseData? _latestTargetPose;
  ExtractedPoseData? _currentInterpolatedPose;
  Ticker? _renderTicker;

  int _lastSubWidth = 720;
  int _lastSubHeight = 480;

  int _renderFrameCount = 0;
  DateTime _lastRenderFpsTime = DateTime.now();
  double _renderFps = 60.0;
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
    _tracker = JointAngleTracker();
    _protocol = ProtocolService(
      stage: ProtocolStage.positioning,
      enablePostureIntro: true,
    );
    _repCounter = RepCounterService(initialExercise: 'free');

    _renderTicker = createTicker(_onRenderTick)..start();

    _isSimulationMode = widget.initialSimulationMode;
    if (_isSimulationMode) {
      _startSimulation();
    } else {
      _initCamera();
    }
  }

  /// Interpola suavemente a 60 FPS contínuos os pontos e ângulos em direção à última leitura
  /// do detector, garantindo fluidez total na tela sem qualquer travamento.
  void _onRenderTick(Duration elapsed) {
    if (_isPausedForReport || !mounted) return;

    final int nowMs = elapsed.inMilliseconds;
    if (nowMs - _lastRenderTickMs < 16) return;
    final int dtMs = nowMs - _lastRenderTickMs;
    _lastRenderTickMs = nowMs;

    _renderFrameCount++;
    final now = DateTime.now();
    final diff = now.difference(_lastRenderFpsTime).inMilliseconds;
    if (diff >= 500) {
      _renderFps = (_renderFrameCount * 1000.0 / diff).clamp(1.0, 120.0);
      _renderFrameCount = 0;
      _lastRenderFpsTime = now;
      _fpsNotifier.value = _renderFps;
    }

    if (_protocol.stage == ProtocolStage.postureReplication &&
        _protocol.isShowingPostureIntro) {
      final elapsedSec = _stopwatch.elapsedMilliseconds / 1000.0;
      final finishedIntro = _protocol.updateIntroTimer(elapsedSec);
      _introTimerNotifier.value = _protocol.postureIntroRemainingSeconds;
      if (finishedIntro && mounted) {
        setState(() {});
      }
      return;
    }

    final target = _latestTargetPose;
    if (target == null) {
      if (_smoothDisplayPoseNotifier.value != null) {
        _smoothDisplayPoseNotifier.value = null;
      }
      return;
    }

    final current = _currentInterpolatedPose;
    if (current == null) {
      _currentInterpolatedPose = target;
      _smoothDisplayPoseNotifier.value = target;
      return;
    }

    final double lerpFactor = (dtMs / 36.0).clamp(0.20, 0.85);

    final Map<String, Point2D> interpLandmarks = {};
    target.landmarks.forEach((key, tgtPt) {
      final curPt = current.landmarks[key];
      if (curPt == null) {
        interpLandmarks[key] = tgtPt;
      } else {
        final double dx = tgtPt.x - curPt.x;
        final double dy = tgtPt.y - curPt.y;
        interpLandmarks[key] = Point2D(
          curPt.x + dx * lerpFactor,
          curPt.y + dy * lerpFactor,
          z: tgtPt.z,
          confidence: tgtPt.confidence,
        );
      }
    });

    final Map<String, JointAngleData> interpAngles = {};
    target.angles.forEach((key, tgtData) {
      if (!tgtData.isValid || tgtData.angle == null) {
        interpAngles[key] = tgtData;
        return;
      }
      final curData = current.angles[key];
      final double newAngle = (curData != null && curData.angle != null)
          ? curData.angle! + (tgtData.angle! - curData.angle!) * lerpFactor
          : tgtData.angle!;

      Point2D? newVertex = tgtData.vertex;
      if (tgtData.vertex != null &&
          curData != null &&
          curData.vertex != null) {
        newVertex = Point2D(
          curData.vertex!.x +
              (tgtData.vertex!.x - curData.vertex!.x) * lerpFactor,
          curData.vertex!.y +
              (tgtData.vertex!.y - curData.vertex!.y) * lerpFactor,
        );
      }

      interpAngles[key] = JointAngleData(
        key: tgtData.key,
        label: tgtData.label,
        angle: newAngle,
        vertex: newVertex,
        isValid: true,
      );
    });

    final nextPose = ExtractedPoseData(
      angles: interpAngles,
      landmarks: interpLandmarks,
      calfElevationLeftPct: target.calfElevationLeftPct,
      calfElevationRightPct: target.calfElevationRightPct,
      bodyOrientationAngle: target.bodyOrientationAngle,
      bodyOrientationLabel: target.bodyOrientationLabel,
    );

    _currentInterpolatedPose = nextPose;
    _smoothDisplayPoseNotifier.value = nextPose;
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _fallbackToSimulation();
        return;
      }

      final frontIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _selectedCameraIndex = frontIndex >= 0 ? frontIndex : 0;
      final camera = _cameras[_selectedCameraIndex];
      _isMirror = camera.lensDirection == CameraLensDirection.front;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      _stopwatch
        ..reset()
        ..start();
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
    _stopwatch
      ..reset()
      ..start();
    _simulationTimer?.cancel();
    _simulationTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_isPausedForReport) return;
      _simTime += 0.033;
      final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
      final screenSize = MediaQuery.of(context).size;

      final extracted =
          _poseService.generateSyntheticAngles(_simTime, screenSize);
      _tracker.update(
        extracted.angles,
        elapsed,
        calfLeftPct: extracted.calfElevationLeftPct,
        calfRightPct: extracted.calfElevationRightPct,
      );
      final stageChanged = _protocol.update(extracted, screenSize, elapsed);
      if (stageChanged && mounted) {
        setState(() {});
        if (_protocol.stage == ProtocolStage.completed) {
          _finishSession();
          return;
        }
      }

      if (mounted) {
        _latestTargetPose = extracted;
        _poseNotifier.value = extracted;
        _fpsNotifier.value = 30.0;
      }
    });
  }

  void _resetSessionData() {
    _perf.reset();
    _tracker.resetAll();
    _protocol.reset();
    _repCounter.reset();
    _poseService.resetSmoothing();
    _stopwatch
      ..reset()
      ..start();
    _latestTargetPose = null;
    _currentInterpolatedPose = null;
    _poseNotifier.value = null;
    _smoothDisplayPoseNotifier.value = null;
    if (mounted) {
      setState(() {});
    }
  }

  int _getImageRotationDegrees() {
    if (_cameras.isEmpty) return 0;
    final camera = _cameras[_selectedCameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isAndroid && _cameraController != null) {
      var rotationCompensation =
          _orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation != null) {
        if (camera.lensDirection == CameraLensDirection.front) {
          return (sensorOrientation + rotationCompensation) % 360;
        } else {
          return (sensorOrientation - rotationCompensation + 360) % 360;
        }
      }
    }
    return sensorOrientation;
  }

  int _lastInferenceTimestampMs = 0;
  final PerformanceMonitor _perf = PerformanceMonitor();

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame || _isPausedForReport || !mounted) return;
    if (_protocol.stage == ProtocolStage.postureReplication &&
        _protocol.isShowingPostureIntro) {
      return;
    }
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastInferenceTimestampMs < 20) return;
    _lastInferenceTimestampMs = nowMs;

    _isProcessingFrame = true;
    final int captureMs = nowMs;
    try {
      final screenSize = MediaQuery.of(context).size;
      final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
      final isFront = _cameras.isNotEmpty &&
          _cameras[_selectedCameraIndex].lensDirection ==
              CameraLensDirection.front;

      ExtractedPoseData? extracted;
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) return;
      final poses = await _poseService.processImage(inputImage);

      if (poses.isNotEmpty) {
        final pose = poses.first;
        final bool isRotated = inputImage.metadata?.rotation ==
                InputImageRotation.rotation90deg ||
            inputImage.metadata?.rotation ==
                InputImageRotation.rotation270deg;
        final double rotatedWidth = isRotated
            ? _lastSubHeight.toDouble()
            : _lastSubWidth.toDouble();
        final double rotatedHeight = isRotated
            ? _lastSubWidth.toDouble()
            : _lastSubHeight.toDouble();

        extracted = _poseService.extractAnglesFromPose(
          pose,
          inputImageSize: Size(rotatedWidth, rotatedHeight),
          screenSize: screenSize,
          isFrontCamera: isFront,
        );
      }

      if (mounted && !_isPausedForReport) {
        if (extracted != null && extracted.landmarks.isNotEmpty) {
          _emptyPoseFrames = 0;
          _tracker.update(
            extracted.angles,
            elapsed,
            calfLeftPct: extracted.calfElevationLeftPct,
            calfRightPct: extracted.calfElevationRightPct,
          );

          final stageChanged = _protocol.update(extracted, screenSize, elapsed);
          if (stageChanged && mounted) {
            setState(() {});
            if (_protocol.stage == ProtocolStage.completed) {
              _latestTargetPose = extracted;
              _poseNotifier.value = extracted;
              _finishSession();
              return;
            }
          }

          _latestTargetPose = extracted;
          _poseNotifier.value = extracted;
          _perf.record(
              captureMs: captureMs,
              displayMs: DateTime.now().millisecondsSinceEpoch);
        } else {
          _emptyPoseFrames++;
          if (_emptyPoseFrames > 8) {
            _poseService.resetSmoothing();
            _protocol.update(null, screenSize, elapsed);
            _latestTargetPose = null;
            _currentInterpolatedPose = null;
            if (_poseNotifier.value != null) {
              _poseNotifier.value = null;
              _smoothDisplayPoseNotifier.value = null;
            }
          }
        }
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('ERRO_FRAME: $e\n$st');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Uint8List? _reusableImageBytes;

  /// Subamostra SEMPRE a imagem da câmera (ex: 720x480 -> 240x160 com step=3) em < 0.15 ms.
  /// Isso reduz em 9x a quantidade de bytes trafegados via MethodChannel para o Java/ML Kit
  /// e acelera dramaticamente a etapa de pré-processamento e inferência do BlazePose!
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    if (_cameraController == null) return null;

    final camera = _cameras[_selectedCameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation != null) {
        if (camera.lensDirection == CameraLensDirection.front) {
          rotationCompensation =
              (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationCompensation =
              (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }
    }
    rotation ??= InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final int srcW = image.width;
    final int srcH = image.height;
    _lastSubWidth = srcW;
    _lastSubHeight = srcH;

    if (!Platform.isAndroid) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(srcW.toDouble(), srcH.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    if (image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(srcW.toDouble(), srcH.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    int totalSize = 0;
    for (final plane in image.planes) {
      totalSize += plane.bytes.length;
    }
    if (_reusableImageBytes == null || _reusableImageBytes!.length != totalSize) {
      _reusableImageBytes = Uint8List(totalSize);
    }
    int offset = 0;
    for (final plane in image.planes) {
      _reusableImageBytes!.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    return InputImage.fromBytes(
      bytes: _reusableImageBytes!,
      metadata: InputImageMetadata(
        size: Size(srcW.toDouble(), srcH.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _isMirror = _cameras[_selectedCameraIndex].lensDirection ==
        CameraLensDirection.front;
    _poseService.resetSmoothing();

    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    await _cameraController!.initialize();

    _cameraController!.startImageStream(_processCameraFrame);
    if (mounted) setState(() {});
  }

  Future<void> _finishSession() async {
    if (_isPausedForReport) return;
    _isPausedForReport = true;
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
    final completedSnapshot = List<PostureEvaluationResult>.from(
      _protocol.completedPostures,
    );

    final shouldRestart = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ReportScreen(
          tracker: _tracker,
          performanceSummary: _perf.summary,
          repCounter: _repCounter,
          completedPostures: completedSnapshot,
          sessionDuration: elapsed,
          initialTabIndex: 0,
        ),
      ),
    );

    if (!mounted) return;
    if (shouldRestart == true || _protocol.stage == ProtocolStage.completed) {
      _resetSessionData();
    }
    _isPausedForReport = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _renderTicker?.dispose();
    _simulationTimer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _poseService.dispose();
    _poseNotifier.dispose();
    _smoothDisplayPoseNotifier.dispose();
    _fpsNotifier.dispose();
    _introTimerNotifier.dispose();
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
    final double previewW = previewSize != null ? previewSize.height : 480.0;
    final double previewH = previewSize != null ? previewSize.width : 720.0;

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
    final bool showFullScreenBlackIntro =
        _protocol.stage == ProtocolStage.postureReplication &&
            _protocol.isShowingPostureIntro;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fundo da Câmera
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

          // 2. CustomPainter em 60/120 FPS com interpolação suave de ângulos e articulações
          if (!showFullScreenBlackIntro)
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<ExtractedPoseData?>(
                  valueListenable: _smoothDisplayPoseNotifier,
                  builder: (context, poseData, _) {
                    final double currentHold =
                        _protocol.stage == ProtocolStage.positioning
                            ? _protocol.currentPositioning.holdProgress
                            : (_protocol.stage ==
                                    ProtocolStage.postureReplication
                                ? _protocol.currentPostureHoldProgress
                                : 0.0);

                    return CustomPaint(
                      size: screenSize,
                      painter: PosePainter(
                        anglesData: poseData?.angles ?? const {},
                        landmarks: poseData?.landmarks ?? const {},
                        activeExercise: 'rom',
                        protocolStage: _protocol.stage,
                        positioningAssessment: _protocol.currentPositioning,
                        activePosture: _protocol.stage ==
                                ProtocolStage.postureReplication
                            ? _protocol.currentPosture
                            : null,
                        jointFeedbacks: _protocol.stage ==
                                ProtocolStage.postureReplication
                            ? _protocol.currentJointFeedbacks
                            : const {},
                        holdProgress: currentHold,
                        evaluationWindowProgress: _protocol.stage ==
                                ProtocolStage.postureReplication
                            ? _protocol.currentEvaluationWindowProgress
                            : 0.0,
                        postureAccuracyPct: _protocol.currentPostureAccuracyPct,
                        animationTimeSec:
                            _stopwatch.elapsedMilliseconds / 1000.0,
                      ),
                    );
                  },
                ),
              ),
            ),

          // 3. Pílula Interativa Estilo Gov.br no Topo (durante posicionamento e análise)
          if (!showFullScreenBlackIntro)
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<ExtractedPoseData?>(
                      valueListenable: _poseNotifier,
                      builder: (context, poseData, _) {
                        return ValueListenableBuilder<double>(
                          valueListenable: _fpsNotifier,
                          builder: (context, fps, _) {
                            return _buildGovStyleTopBanner(poseData, fps);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

          // 4. Barra Inferior Compacta de Controles
          if (!showFullScreenBlackIntro)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomControls(),
            ),

          // 5. TELA PRETA DE 5 SEGUNDOS EM TELA CHEIA (Sem câmera para não tirar a atenção!)
          // Mostra Visão de Frente + Visão de Lado / Zoom de Foco antes da análise de cada postura
          if (showFullScreenBlackIntro)
            Positioned.fill(
              child: _buildFullScreenBlackPostureIntro(),
            ),
        ],
      ),
    );
  }

  Widget _buildFullScreenBlackPostureIntro() {
    final posture = _protocol.currentPosture;

    return Container(
      color: const Color(0xFF050608),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Column(
            children: [
              // Cabeçalho com contador regressivo de 5 segundos e barra de progresso
              ValueListenableBuilder<double>(
                valueListenable: _introTimerNotifier,
                builder: (context, remSec, _) {
                  final int secInt = remSec.ceil().clamp(1, 5);
                  final double progress =
                      _protocol.postureIntroProgress.clamp(0.0, 1.0);

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE51937),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE51937).withOpacity(0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              'MOVEMENT • ${posture.badge}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer,
                                  color: Colors.black,
                                  size: 18,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'CÂMERA EM ${secInt}s',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFE51937),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 8),

              // Título do exercício em destaque acima do GIF limpo
              Text(
                posture.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18.0,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 8),

              // GIF Animado Gigante em Tela Dividida
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0E14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE51937).withOpacity(0.8),
                      width: 2.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      posture.gifAssetPath,
                      key: ValueKey<String>('intro_${posture.gifAssetPath}'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Caixa de Instrução e Foco Biomecânico
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161922),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF282E3D)),
                ),
                child: Column(
                  children: [
                    Text(
                      posture.focusSummary,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFC700),
                        fontSize: 14.0,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      posture.instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Botão para pular caso o usuário queira iniciar imediatamente
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE51937),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'INICIAR ANÁLISE AGORA',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _protocol.skipPostureIntro();
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGovStyleTopBanner(ExtractedPoseData? poseData, double fps) {
    if (_protocol.stage == ProtocolStage.freeRom) {
      final calfE = poseData?.calfElevationLeftPct.round() ?? 0;
      final calfD = poseData?.calfElevationRightPct.round() ?? 0;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00E5FF)),
            ),
            child: Text(
              'Panturrilha E:$calfE% D:$calfD%  •  ${fps.toStringAsFixed(0)} FPS',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildModeSwitchButton(),
        ],
      );
    }

    if (_protocol.stage == ProtocolStage.positioning) {
      return _buildGovPositioningBanner(fps);
    } else if (_protocol.stage == ProtocolStage.postureReplication) {
      return _buildGovPostureBanner(poseData, fps);
    } else {
      return _buildGovCompletedBanner();
    }
  }

  Widget _buildGovPositioningBanner(double fps) {
    final pos = _protocol.currentPositioning;

    Color statusColor;
    String bigCommand;
    IconData commandIcon;

    if (pos.isAllGood) {
      statusColor = const Color(0xFF00E676);
      bigCommand =
          'ÓTIMO! FIQUE PARADO... ${(pos.holdProgress * 100).round()}%';
      commandIcon = Icons.check_circle;
    } else if (!pos.areAllPointsVisible) {
      statusColor = const Color(0xFFFF3B30);
      bigCommand = 'AFASTE-SE: MOSTRE CORPO E PÉS';
      commandIcon = Icons.zoom_out_map;
    } else if (!pos.isDistanceGood) {
      statusColor = const Color(0xFFFF9500);
      bigCommand = pos.distanceStatus == 'too_far'
          ? 'APROXIME-SE DA CÂMERA'
          : 'AFASTE-SE UM POUCO DA CÂMERA';
      commandIcon = Icons.straighten;
    } else if (!pos.isCentered) {
      statusColor = const Color(0xFFFFCC00);
      bigCommand = pos.horizontalOffset < 0
          ? 'MOVA-SE PARA A DIREITA ➔'
          : '⬅ MOVA-SE PARA A ESQUERDA';
      commandIcon = Icons.swap_horiz;
    } else {
      statusColor = const Color(0xFFFFCC00);
      bigCommand = 'ALINHE A POSTURA RETA';
      commandIcon = Icons.accessibility_new;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _protocol.skipToPostureReplication();
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFD700)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Testar Posturas Agora',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Color(0xFFFFD700),
                      size: 11,
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${fps.toStringAsFixed(0)} FPS',
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildModeSwitchButton(),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.92),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(commandIcon, color: Colors.black, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  bigCommand,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGovPostureBanner(ExtractedPoseData? poseData, double fps) {
    final posture = _protocol.currentPosture;
    final accuracy = _protocol.currentPostureAccuracyPct.round();
    final holdProg = (_protocol.currentPostureHoldProgress * 100).round();
    final isMatched = _protocol.currentPostureHoldProgress > 0.01;
    final remSec = _protocol.remainingEvaluationSeconds.ceil();

    String liveCommand;
    Color pillColor;

    if (isMatched) {
      liveCommand = 'MANTENHA A POSE! ($holdProg%)';
      pillColor = const Color(0xFF00E676);
    } else {
      liveCommand = '${posture.shortCommand}  •  ${remSec}s';
      pillColor = const Color(0xFFFFEA00);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.70),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white30),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 15,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () =>
                          setState(() => _protocol.previousPosture()),
                    ),
                    Expanded(
                      child: Text(
                        posture.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 15,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () {
                        final elapsed =
                            _stopwatch.elapsedMilliseconds / 1000.0;
                        setState(() {
                          _protocol.nextPosture(
                            timestampSec: elapsed,
                            recordCurrentIfStarted: true,
                          );
                        });
                        if (_protocol.stage == ProtocolStage.completed) {
                          _finishSession();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            GestureDetector(
              onTap: () {
                setState(() {
                  _protocol.replayPostureIntro();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFEA00)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_circle_fill,
                      color: Color(0xFFFFEA00),
                      size: 14,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'GIF 5s',
                      style: TextStyle(
                        color: Color(0xFFFFEA00),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.70),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${fps.toStringAsFixed(0)} FPS',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 5),
            _buildModeSwitchButton(),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: pillColor.withOpacity(0.94),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: pillColor.withOpacity(0.35),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  liveCommand,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$accuracy%',
                  style: TextStyle(
                    color: isMatched
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFFEA00),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGovCompletedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676).withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'PROTOCOLO CONCLUÍDO! ✅',
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('Fazer de Novo'),
            onPressed: _resetSessionData,
          ),
        ],
      ),
    );
  }



  Widget _buildModeSwitchButton() {
    final bool isProtocol = _protocol.stage != ProtocolStage.freeRom;
    return GestureDetector(
      onTap: () {
        setState(() {
          _protocol.toggleFreeRomMode();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.70),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isProtocol
                ? const Color(0xFFFFD700)
                : const Color(0xFF00E5FF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isProtocol ? Icons.accessibility_new : Icons.fact_check,
              color: isProtocol
                  ? const Color(0xFFFFD700)
                  : const Color(0xFF00E5FF),
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              isProtocol ? 'Livre' : 'Protocolo',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Fazer de Novo / Reiniciar',
              onPressed: () {
                _resetSessionData();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Protocolo e valores de ROM reiniciados.'),
                    duration: Duration(milliseconds: 1000),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.swap_horiz, size: 20),
              tooltip: _isMirror ? 'Modo Espelho (Ativo)' : 'Modo Direto',
              onPressed: () {
                setState(() {
                  _isMirror = !_isMirror;
                });
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isMirror
                          ? 'Modo Espelho: Câmera e Esqueleto Espelhados'
                          : 'Modo Direto: Visão Normal',
                    ),
                    duration: const Duration(milliseconds: 1000),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            if (_cameras.length > 1)
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.switch_camera_outlined, size: 20),
                tooltip: 'Trocar Câmera',
                onPressed: _switchCamera,
              ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Finalizar', style: TextStyle(fontSize: 13)),
              onPressed: _finishSession,
            ),
          ],
        ),
      ),
    );
  }
}
