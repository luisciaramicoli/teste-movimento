import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flow.dart';
import '../models/assessment_models.dart';
import '../models/joint_angle.dart';
import '../models/mobility_score.dart';
import '../painters/assessment_overlay_painter.dart';
import '../services/assessment_history_store.dart';
import '../services/framing_checker.dart';
import '../services/pose_camera_session.dart';
import '../services/rep_tracker.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';

enum _Phase { capture, error }

class _Live {
  final ExtractedPoseData? pose;
  final FramingStatus framing;
  final bool locked;
  final double lockProgress;
  final int reps;
  const _Live(this.pose, this.framing, this.locked, this.lockProgress, this.reps);
}

/// Telas 2 e 3: "Passo 1 / 2" e "Passo 2 / 2". Card de demonstração em cima e
/// câmera ao vivo com os ângulos embaixo.
class AssessmentScreen extends StatefulWidget {
  final String volunteerCode;
  final int testNumber;
  final AvaliacaoFluxo fluxo;
  const AssessmentScreen(
      {super.key,
      required this.volunteerCode,
      required this.testNumber,
      required this.fluxo});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0B0B0B);
  static const Color _blue = Color(0xFF1E9BE0);
  static const double _radius = 24;

  static const Map<String, String> _demoAssets = {
    'abducao_ombro': 'assets/images/abducao.png',
    'agachamento_perfil_dir': 'assets/images/agachamento.png',
  };

  /// Tempo que um problema de enquadramento precisa persistir para ser exibido.
  static const double _warnDelay = 0.35;

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);
  FramingStatus? _held;
  double? _badSince;
  FramingIssue? _lastHapticIssue;
  final VoiceService _voice = VoiceService();

  /// Tempo contínuo dentro do enquadramento antes de iniciar a contagem.
  static const double _lockSeconds = 1.5;

  /// Tolerância para saídas momentâneas do enquadramento durante a captura.
  static const double _graceSeconds = 0.8;

  late final PoseCameraSession _camera;
  final Stopwatch _clock = Stopwatch()..start();
  final ValueNotifier<_Live> _live = ValueNotifier(const _Live(
      null,
      FramingStatus(
          isInside: false,
          issue: FramingIssue.noPerson,
          message: 'Aguardando detecção.'),
      false,
      0,
      0));

  _Phase _phase = _Phase.capture;
  String _error = '';
  int _movementIndex = 0;
  late RepTracker _tracker;
  final List<MovementResult> _results = [];
  bool _saving = false;

  double? _insideSince;
  double? _outsideSince;
  bool _locked = false;

  /// Tamanho do card da câmera (usado no mapeamento dos pontos do ML Kit).
  Size _screen = const Size(360, 400);

  MovementSpec get _spec => kProtocolMovements[_movementIndex];

  @override
  void initState() {
    super.initState();
    _tracker = RepTracker(_spec);
    _camera = PoseCameraSession(
        onPose: _onPose,
        screenSize: () => _screen,
        onEmptyFrame: () {
          if (_locked && _phase == _Phase.capture) _tracker.discardFrame();
        });
    _camera.paused = true;
    _startCamera();
    _voice.speak(_spec.voiceGuide);
  }

  Future<void> _startCamera() async {
    final err = await _camera.start();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = err;
        _phase = _Phase.error;
      });
    } else {
      _beginCapture();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _camera.dispose();
    _live.dispose();
    _voice.stop();
    super.dispose();
  }

  void _beginCapture() {
    _tracker = RepTracker(_spec);
    _insideSince = null;
    _outsideSince = null;
    _locked = false;
    _held = null;
    _badSince = null;
    _camera.poseService.resetSmoothing();
    _camera.onlySide = switch (_spec.view) {
      CaptureView.frontal => null,
      CaptureView.profileRight => 'RIGHT',
      CaptureView.profileLeft => 'LEFT',
    };
    _camera.paused = false;
    _live.value = _Live(null, _live.value.framing, false, 0, 0);
    setState(() => _phase = _Phase.capture);
  }

  void _onPose(ExtractedPoseData? pose) {
    if (!mounted || _phase != _Phase.capture) return;
    final t = _clock.elapsedMilliseconds / 1000.0;
    final raw = FramingChecker.evaluate(pose, _screen, _spec.view,
        wasInside: _held?.isInside ?? false);

    // Debounce: um problema só vira aviso se persistir; evita piscar a cada quadro.
    FramingStatus framing = raw;
    if (raw.isInside) {
      _badSince = null;
      _held = raw;
    } else {
      _badSince ??= t;
      final held = _held;
      if (held != null && held.isInside && t - _badSince! < _warnDelay) {
        framing = held;
      } else {
        _held = raw;
      }
    }
    if (!framing.isInside && framing.issue != _lastHapticIssue) {
      HapticFeedback.lightImpact();
      if (framing.issue != null) _voice.speak(framing.message, interrupt: false);
    }
    _lastHapticIssue = framing.isInside ? null : framing.issue;

    if (framing.isInside) {
      _outsideSince = null;
      _insideSince ??= t;
      if (!_locked && t - _insideSince! >= _lockSeconds) {
        _locked = true;
        HapticFeedback.selectionClick();
        _voice.speak('Posição correta. Pode começar.', interrupt: false);
      }
    } else {
      _insideSince = null;
      _outsideSince ??= t;
      if (_locked && t - _outsideSince! > _graceSeconds) {
        _locked = false;
        _tracker.cancelActive();
      }
    }

    var finished = false;
    if (_locked && pose == null) _tracker.discardFrame();
    if (_locked && pose != null) {
      final angles = <String, double>{
        for (final e in pose.angles.entries)
          if (e.value.isValid && e.value.angle != null) e.key: e.value.angle!
      };
      final confidences = <String, double>{
        for (final e in pose.angles.entries)
          if (e.value.isValid && e.value.confidence != null)
            e.key: e.value.confidence!
      };
      if (_tracker.update(angles, t, confidences: confidences)) {
        HapticFeedback.mediumImpact();
        finished = _tracker.isComplete;
        if (!finished) _voice.speak('${_tracker.reps.length}');
      }
    }

    final progress = _locked
        ? 1.0
        : (_insideSince == null
            ? 0.0
            : ((t - _insideSince!) / _lockSeconds).clamp(0.0, 1.0));
    _live.value =
        _Live(pose, framing, _locked, progress, _tracker.reps.length);

    if (finished) _finishMovement();
  }

  /// Guarda o resultado e segue direto para o próximo passo, sem pausa.
  void _finishMovement() {
    _camera.paused = true;
    _results.add(_tracker.toResult());
    if (_movementIndex < kProtocolMovements.length - 1) {
      _movementIndex++;
      _voice.speak('Movimento concluído. Próximo: ${_spec.title}. '
          '${_spec.voiceGuide}');
      _beginCapture();
    } else {
      _voice.speak('Avaliação concluída.');
      _save();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final record = AssessmentRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      volunteerCode: widget.volunteerCode,
      testNumber: widget.testNumber,
      movements: List.of(_results),
      reference:
          widget.fluxo.perfil?.referencia ?? MobilityReference.illustrative,
    );
    await AssessmentHistoryStore().add(record);
    widget.fluxo.resultado = record;
    if (!mounted) return;
    if (widget.fluxo.mostrarResultado) {
      Navigator.of(context).pushReplacement(flowRoute(
          (_) => ResultScreen(record: record, fluxo: widget.fluxo)));
    } else {
      exitFlow(context);
    }
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Encerrar avaliação?'),
        content: const Text(
            'Os dados desta avaliação ainda não foram salvos e serão descartados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Continuar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Encerrar')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _exit() async {
    if (_phase == _Phase.error || await _confirmExit()) {
      if (mounted) exitFlow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Mobilidade'),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _exit),
        ),
        body: _phase == _Phase.error ? _buildError() : _buildStep(),
      ),
    );
  }

  Widget _buildError() => SafeArea(
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
              Text(_error, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              OutlinedButton(
                  onPressed: () => exitFlow(context),
                  child: const Text('Voltar')),
            ],
          ),
        ),
      );

  Widget _buildStep() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          children: [
            _stepHeader(),
            const SizedBox(height: 10),
            Expanded(child: _demoCard()),
            const SizedBox(height: 12),
            Expanded(child: _cameraCard()),
          ],
        ),
      ),
    );
  }

  Widget _stepHeader() {
    final total = kProtocolMovements.length;
    return Row(children: [
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Passo '),
          TextSpan(
              text: '${_movementIndex + 1}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' / $total', style: const TextStyle(fontSize: 13)),
        ]),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      const SizedBox(width: 12),
      for (var i = 0; i < total; i++)
        Container(
          width: 22,
          height: 5,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: i <= _movementIndex ? Colors.white : Colors.white30,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      const Spacer(),
      if (_camera.cameras.length > 1)
        GestureDetector(
          onTap: () async {
            await _camera.switchCamera();
            if (mounted) setState(() {});
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                color: _blue, borderRadius: BorderRadius.circular(5)),
            child: const Icon(Icons.cameraswitch_outlined,
                size: 15, color: Colors.white),
          ),
        ),
    ]);
  }

  Widget _demoCard() {
    final asset = _demoAssets[_spec.id];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(_radius)),
      clipBehavior: Clip.antiAlias,
      child: asset == null
          ? const SizedBox.shrink()
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(asset, package: kPackage, fit: BoxFit.contain),
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _cameraCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: LayoutBuilder(builder: (context, c) {
        _screen = Size(c.maxWidth, c.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            RepaintBoundary(child: _camera.buildPreview(_screen)),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => ValueListenableBuilder<_Live>(
                valueListenable: _live,
                builder: (context, live, _) => CustomPaint(
                  painter: AssessmentOverlayPainter(
                    pose: live.pose,
                    trackedJoints: _spec.joints,
                    framingOk: live.framing.isInside,
                    alertColor: _alertColor(live.framing.issue),
                    pulse: _pulse.value,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: ValueListenableBuilder<_Live>(
                valueListenable: _live,
                builder: (_, live, __) => _statusBanner(live),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: ValueListenableBuilder<_Live>(
                valueListenable: _live,
                builder: (_, live, __) => _repChip(live),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _repChip(_Live live) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Text('${live.reps} / ${_spec.repetitions}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()])),
      );

  /// Alertas usam sempre o vermelho da identidade visual.
  Color _alertColor(FramingIssue? issue) => AppColors.error;

  /// Problemas que impedem a medição (pessoa ausente ou corpo cortado).
  bool _isCritical(FramingIssue? issue) =>
      issue == FramingIssue.noPerson || issue == FramingIssue.bodyCutOff;

  IconData _alertIcon(FramingStatus f) => switch (f.issue) {
        FramingIssue.noPerson => Icons.person_search,
        FramingIssue.bodyCutOff => Icons.fit_screen,
        FramingIssue.tooFar => Icons.zoom_in_map,
        FramingIssue.tooClose => Icons.zoom_out_map,
        FramingIssue.offCenter =>
          f.horizontalOffset < 0 ? Icons.arrow_forward : Icons.arrow_back,
        FramingIssue.wrongOrientation => Icons.rotate_90_degrees_ccw,
        null => Icons.check_circle,
      };

  String _alertTitle(FramingStatus f) => switch (f.issue) {
        FramingIssue.noPerson => 'Não encontramos você',
        FramingIssue.bodyCutOff => 'Corpo cortado',
        FramingIssue.tooFar => 'Chegue mais perto',
        FramingIssue.tooClose => 'Afaste-se um pouco',
        FramingIssue.offCenter => f.horizontalOffset < 0
            ? 'Mova-se para a direita'
            : 'Mova-se para a esquerda',
        FramingIssue.wrongOrientation => 'Ajuste sua posição',
        null => '',
      };

  Widget _statusBanner(_Live live) {
    final f = live.framing;
    final bool ok = f.isInside;

    // Captura em andamento e tudo certo: só uma etiqueta discreta (pílula preta).
    if (ok && live.locked) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.black, borderRadius: BorderRadius.circular(40)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                  color: AppColors.error, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('Gravando',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ]),
        ),
      );
    }

    final String title = ok ? 'Ótimo, fique parado' : _alertTitle(f);
    final String detail = ok ? 'Iniciando a captura…' : f.message;
    final bool critical = !ok && _isCritical(f.issue);

    // Cartão no estilo dos cards da identidade visual (corpo cinza claro #F3F3F3, borda #B9B9B9).
    final Color badgeBg = ok
        ? AppColors.ok
        : (critical ? AppColors.alertBg : const Color(0xFFF3F3F3));
    final Color badgeFg = ok
        ? Colors.black
        : (critical ? AppColors.alertText : Colors.black);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB9B9B9)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
            child: Icon(_alertIcon(f), size: 30, color: badgeFg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.15)),
                const SizedBox(height: 2),
                Text(detail,
                    style: const TextStyle(
                        color: Color(0xFF212121),
                        fontSize: 18,
                        height: 1.25)),
              ],
            ),
          ),
        ]),
        if (ok) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: live.lockProgress,
              minHeight: 5,
              color: AppColors.ok,
              backgroundColor: const Color(0xFFE6E6E6),
            ),
          ),
        ],
      ]),
    );
  }
}
