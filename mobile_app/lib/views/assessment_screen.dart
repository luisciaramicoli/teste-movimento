import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assessment_models.dart';
import '../models/joint_angle.dart';
import '../painters/assessment_overlay_painter.dart';
import '../services/assessment_history_store.dart';
import '../services/framing_checker.dart';
import '../services/pose_camera_session.dart';
import '../services/rep_tracker.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';

enum _Phase { instruction, capture, error }

class _Live {
  final ExtractedPoseData? pose;
  final FramingStatus framing;
  final bool locked;
  final double lockProgress;
  final int reps;
  const _Live(this.pose, this.framing, this.locked, this.lockProgress, this.reps);
}

class AssessmentScreen extends StatefulWidget {
  final String volunteerCode;
  final int testNumber;
  const AssessmentScreen(
      {super.key, required this.volunteerCode, required this.testNumber});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen>
    with SingleTickerProviderStateMixin {
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

  _Phase _phase = _Phase.instruction;
  String _error = '';
  int _movementIndex = 0;
  late RepTracker _tracker;
  final List<MovementResult> _results = [];
  bool _cameraReady = false;
  bool _saving = false;

  double? _insideSince;
  double? _outsideSince;
  bool _locked = false;
  Size _screen = const Size(360, 640);

  MovementSpec get _spec => kProtocolMovements[_movementIndex];

  @override
  void initState() {
    super.initState();
    _tracker = RepTracker(_spec);
    _camera = PoseCameraSession(onPose: _onPose, screenSize: () => _screen);
    _camera.paused = true;
    _startCamera();
    _voice.speak(_spec.voiceGuide);
  }

  Future<void> _startCamera() async {
    final err = await _camera.start();
    if (!mounted) return;
    setState(() {
      if (err != null) {
        _error = err;
        _phase = _Phase.error;
      } else {
        _cameraReady = true;
      }
    });
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
    if (_locked && pose != null) {
      final angles = <String, double>{
        for (final e in pose.angles.entries)
          if (e.value.isValid && e.value.angle != null) e.key: e.value.angle!
      };
      if (_tracker.update(angles, t)) {
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

  /// Guarda o resultado e segue direto para o próximo movimento, sem pausa.
  void _finishMovement() {
    _camera.paused = true;
    _results.add(_tracker.toResult());
    if (_movementIndex < kProtocolMovements.length - 1) {
      _movementIndex++;
      _voice.speak('Movimento concluído. Próximo: ${_spec.title}. '
          '${_spec.voiceGuide}');
      _beginCapture();
    } else {
      _voice.speak('Avaliação concluída. Salvando.');
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
    );
    await AssessmentHistoryStore().add(record);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AssessmentDetailScreen(record: record, justSaved: true)));
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.border)),
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

  @override
  Widget build(BuildContext context) {
    _screen = MediaQuery.of(context).size;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (_phase == _Phase.error || await _confirmExit()) nav.pop();
      },
      child: Scaffold(
        body: switch (_phase) {
          _Phase.error => _buildError(),
          _Phase.instruction => _buildInstruction(),
          _Phase.capture => _buildCapture(),
        },
      ),
    );
  }

  Widget _stepHeader() => Row(children: [
        Expanded(
          child: Text(
              'MOVIMENTO ${_movementIndex + 1} DE ${kProtocolMovements.length}',
              style: AppText.label),
        ),
        _muteButton(),
      ]);

  Widget _muteButton() => IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: _voice.enabled ? 'Silenciar voz' : 'Ativar voz',
      onPressed: () {
        setState(() => _voice.enabled = !_voice.enabled);
        if (!_voice.enabled) _voice.stop();
      },
      icon: Icon(_voice.enabled ? Icons.volume_up : Icons.volume_off,
          size: 20));

  Widget _buildError() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Câmera indisponível', style: AppText.title),
              const SizedBox(height: 8),
              Text(_error, style: AppText.muted),
              const SizedBox(height: 24),
              OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Voltar')),
            ],
          ),
        ),
      );

  Widget _buildInstruction() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              IconButton(
                  onPressed: () async {
                    if (await _confirmExit() && mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.close)),
              const Spacer(),
              Text('${widget.volunteerCode}  ·  Teste ${widget.testNumber}',
                  style: AppText.muted),
            ]),
            const SizedBox(height: 16),
            _stepHeader(),
            const SizedBox(height: 6),
            Text(_spec.title, style: AppText.title),
            const SizedBox(height: 4),
            Text(_spec.viewLabel,
                style: const TextStyle(color: AppColors.accent, fontSize: 14)),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_spec.instruction, style: AppText.body),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ENQUADRAMENTO', style: AppText.label),
                    const SizedBox(height: 8),
                    Text(
                        'Apoie o celular na vertical, a cerca de 2,5 m, na altura do quadril. '
                        'O corpo inteiro, da cabeça aos pés, deve ficar dentro da moldura. '
                        'A captura inicia sozinha após ${_lockSeconds.toStringAsFixed(1)} s '
                        'de enquadramento correto.',
                        style: AppText.muted),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _cameraReady ? _beginCapture : null,
              child: Text(_cameraReady ? 'Iniciar posicionamento' : 'Abrindo câmera…'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapture() {
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
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _captureTopBar(),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                ValueListenableBuilder<_Live>(
                  valueListenable: _live,
                  builder: (_, live, __) => _statusBanner(live),
                ),
                const Spacer(),
                ValueListenableBuilder<_Live>(
                  valueListenable: _live,
                  builder: (_, live, __) => _repPanel(live),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel({required Widget child, Color? edge}) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xE6171D24),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: edge ?? AppColors.border),
        ),
        child: child,
      );

  Widget _captureTopBar() => _panel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  if (await _confirmExit() && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.close, size: 20)),
            Expanded(
              child: Text(_spec.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            ValueListenableBuilder<_Live>(
              valueListenable: _live,
              builder: (_, __, ___) => Text(
                  '${_camera.fps.toStringAsFixed(0)} FPS · ${_camera.latencyMs} ms',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ),
            _muteButton(),
            if (_camera.cameras.length > 1)
              IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Alternar câmera',
                  onPressed: () async {
                    await _camera.switchCamera();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.cameraswitch_outlined, size: 20)),
          ]),
        ),
      );

  Color _alertColor(FramingIssue? issue) => switch (issue) {
        FramingIssue.noPerson => AppColors.error,
        FramingIssue.bodyCutOff => AppColors.error,
        _ => const Color(0xFFFFB020),
      };

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
        FramingIssue.noPerson => 'PESSOA NÃO DETECTADA',
        FramingIssue.bodyCutOff => 'CORPO CORTADO',
        FramingIssue.tooFar => 'CHEGUE MAIS PERTO',
        FramingIssue.tooClose => 'AFASTE-SE',
        FramingIssue.offCenter => f.horizontalOffset < 0
            ? 'ANDE PARA A DIREITA'
            : 'ANDE PARA A ESQUERDA',
        FramingIssue.wrongOrientation => 'AJUSTE A POSIÇÃO',
        null => '',
      };

  Widget _statusBanner(_Live live) {
    final f = live.framing;
    final bool ok = f.isInside;
    final Color color = ok ? AppColors.ok : _alertColor(f.issue);

    // Captura em andamento e tudo certo: só uma etiqueta discreta, sem poluir.
    if (ok && live.locked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.ok, borderRadius: BorderRadius.circular(40)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fiber_manual_record, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('GRAVANDO — faça o movimento',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ]),
      );
    }

    final String title = ok ? 'ÓTIMO! FIQUE PARADO' : _alertTitle(f);
    final String detail = ok ? 'Iniciando a captura…' : f.message;
    final Color fg = ok ? Colors.white : const Color(0xFF1B1200);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_alertIcon(f), size: 52, color: fg),
          const SizedBox(width: 12),
          Flexible(
            child: Text(title,
                style: TextStyle(
                    color: fg,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.1)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(detail,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
        if (ok) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: live.lockProgress,
              minHeight: 10,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _repPanel(_Live live) => _panel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REPETIÇÕES', style: AppText.label),
                const SizedBox(height: 2),
                Text('${live.reps} / ${_spec.repetitions}',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            const Spacer(),
            Text(_spec.viewLabel,
                textAlign: TextAlign.right, style: AppText.muted),
          ]),
        ),
      );
}
