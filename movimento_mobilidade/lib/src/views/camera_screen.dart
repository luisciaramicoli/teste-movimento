import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/joint_angle.dart';
import '../models/perfil_avaliado.dart';
import '../models/protocol_models.dart';
import '../services/pose_camera_session.dart';
import '../services/protocol_service.dart';
import '../services/rep_counter_service.dart';
import '../services/performance_monitor.dart';
import '../theme/app_theme.dart';
import '../painters/pose_painter.dart';
import 'report_screen.dart';

class CameraScreen extends StatefulWidget {
  final PerfilAvaliado? perfil;

  /// Recebe os valores sempre que uma sessão com posturas avaliadas termina.
  final ValueChanged<ProtocolSessionResult>? onSessionFinished;

  const CameraScreen({
    super.key,
    this.perfil,
    this.onSessionFinished,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Mesma sessão da avaliação: MediaPipe, com ML Kit de reserva.
  PoseCameraSession? _camera;
  bool _isInitializingCamera = false;
  bool _isDisposed = false;
  bool _isPausedForReport = false;
  int _lastRenderTickMs = 0;

  late final JointAngleTracker _tracker;
  late final ProtocolService _protocol;
  late final RepCounterService _repCounter;

  // Pose bruta do detector para o banner superior
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

  int _renderFrameCount = 0;
  DateTime _lastRenderFpsTime = DateTime.now();
  double _renderFps = 60.0;

  /// Motivo de a câmera não ter aberto; enquanto houver, nada é medido.
  String? _cameraError;

  /// Motores que processaram os quadros avaliados.
  final Set<String> _engines = {};

  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tracker = JointAngleTracker();
    _protocol = ProtocolService(
      stage: ProtocolStage.positioning,
      enablePostureIntro: true,
    );
    _repCounter = RepCounterService(initialExercise: 'free');

    _renderTicker = createTicker(_onRenderTick)..start();

    _initCamera();
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
      mirrored: target.mirrored,
    );

    _currentInterpolatedPose = nextPose;
    _smoothDisplayPoseNotifier.value = nextPose;
  }

  Future<void> _initCamera() async {
    if (_isInitializingCamera || _isDisposed) return;
    _isInitializingCamera = true;
    if (_cameraError != null) setState(() => _cameraError = null);

    final session = PoseCameraSession(
      onPose: _onPose,
      screenSize: () => MediaQuery.of(context).size,
      // Os ângulos-alvo das posturas dependem desta compensação.
      compensatePerspective: true,
    );
    _camera = session;
    final error = await session.start(onPreviewReady: _onPreviewReady);
    _isInitializingCamera = false;

    if (error != null && mounted && !_isDisposed) {
      await _stopCamera();
      _showCameraError(error);
    }
  }

  void _onPreviewReady() {
    if (!mounted) return;
    _stopwatch
      ..reset()
      ..start();
    setState(() {});
  }

  void _showCameraError(String message) {
    if (!mounted) return;
    setState(() => _cameraError = message);
  }

  Widget _buildCameraError(String message) => Theme(
        data: AppTheme.camera,
        child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Câmera indisponível',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(message, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _initCamera,
                    child: const Text('Tentar novamente')),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Voltar')),
              ],
            ),
          ),
        ),
        ),
      );

  void _resetSessionData() {
    _perf.reset();
    _tracker.resetAll();
    _protocol.reset();
    _repCounter.reset();
    _engines.clear();
    _camera?.poseService.resetSmoothing();
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

  final PerformanceMonitor _perf = PerformanceMonitor();

  /// Recebe cada quadro analisado; [pose] é null sem pessoa na imagem.
  void _onPose(ExtractedPoseData? pose) {
    if (!mounted || _isPausedForReport) return;
    if (_protocol.stage == ProtocolStage.postureReplication &&
        _protocol.isShowingPostureIntro) {
      return;
    }
    final screenSize = MediaQuery.of(context).size;
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;

    if (pose == null || pose.landmarks.isEmpty) {
      _protocol.update(null, screenSize, elapsed);
      _latestTargetPose = null;
      _currentInterpolatedPose = null;
      _poseNotifier.value = null;
      _smoothDisplayPoseNotifier.value = null;
      return;
    }

    final session = _camera;
    if (session != null) _engines.add(session.lastEngine);
    _tracker.update(
      pose.angles,
      elapsed,
      calfLeftPct: pose.calfElevationLeftPct,
      calfRightPct: pose.calfElevationRightPct,
    );
    final stageChanged = _protocol.update(pose, screenSize, elapsed);
    _latestTargetPose = pose;
    _poseNotifier.value = pose;
    if (stageChanged) {
      setState(() {});
      if (_protocol.stage == ProtocolStage.completed) {
        _finishSession();
        return;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _perf.record(captureMs: now - (session?.latencyMs ?? 0), displayMs: now);
  }

  Future<void> _switchCamera() async {
    final session = _camera;
    if (session == null || _isInitializingCamera || _isDisposed) return;
    _isInitializingCamera = true;
    try {
      await session.switchCamera(onPreviewReady: _onPreviewReady);
    } catch (e) {
      debugPrint('Erro ao trocar câmera: $e');
      await _stopCamera();
      _showCameraError('Não foi possível trocar de câmera.');
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _finishSession() async {
    if (_isPausedForReport) return;
    _isPausedForReport = true;
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
    final completedSnapshot = List<PostureEvaluationResult>.from(
      _protocol.completedPostures,
    );

    if (completedSnapshot.isNotEmpty) {
      widget.onSessionFinished?.call(ProtocolSessionResult(
        postures: List.unmodifiable(completedSnapshot),
        engine: _engines.join(' + '),
      ));
    }

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
          perfil: widget.perfil,
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
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _renderTicker?.dispose();
    final session = _camera;
    _camera = null;
    if (session != null) unawaited(session.dispose());
    _poseNotifier.dispose();
    _smoothDisplayPoseNotifier.dispose();
    _fpsNotifier.dispose();
    _introTimerNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O pedido de permissão também pausa o app: não interrompe a abertura.
    if (_isDisposed || _isInitializingCamera) return;

    if (state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _initCamera();
    }
  }

  Future<void> _stopCamera() async {
    final session = _camera;
    _camera = null;
    if (session == null) return;
    if (mounted) setState(() {});
    await session.dispose();
  }

  Widget _buildCameraPreview(Size screenSize) {
    final session = _camera;
    if (session == null || !session.isPreviewReady) {
      return Container(
        color: const Color(0xFF181818),
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00E5FF),
          ),
        ),
      );
    }
    return session.buildPreview(screenSize);
  }

  @override
  Widget build(BuildContext context) {
    final cameraError = _cameraError;
    if (cameraError != null) return _buildCameraError(cameraError);

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
      bigCommand = pos.horizontalMessage.toUpperCase();
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

  void _showStatusSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
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
                _showStatusSnackBar('Protocolo e valores de ROM reiniciados.');
              },
            ),
            if ((_camera?.cameras.length ?? 0) > 1)
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
