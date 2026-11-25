import '../models/assessment_models.dart';

enum RepPhase { rest, active }

/// Detecta repetições por histerese sobre um ângulo "condutor" e registra os
/// ângulos de todas as articulações no instante de pico de cada repetição.
///
/// - Abdução de ombro: condutor = média dos ombros (sobe de ~20° até ~90°).
/// - Agachamento: condutor = joelho do lado visível (desce de ~170° até ~100°).
class RepTracker {
  final MovementSpec spec;
  final List<RepMeasurement> reps = [];
  RepPhase phase = RepPhase.rest;

  Map<String, double>? _peakAngles;
  Map<String, double> _peakConfidences = const {};

  // Extremos desde o fim da repetição anterior (inclui a fase de repouso).
  final Map<String, double> _min = {};
  final Map<String, double> _max = {};

  int processedFrames = 0;
  int discardedFrames = 0;
  double? _peakDriver;
  double _activeSince = 0;

  static const double minRepSeconds = 0.5;

  // Abdução: conta quando o condutor passa de [abductionPeak] e volta abaixo de [abductionRest].
  static const double abductionPeak = 70.0;
  static const double abductionRest = 45.0;
  // Agachamento: conta quando o joelho fica abaixo de [squatPeak] e volta acima de [squatRest].
  static const double squatPeak = 130.0;
  static const double squatRest = 155.0;

  RepTracker(this.spec);

  bool get isComplete => reps.length >= spec.repetitions;
  bool get isAbduction => spec.view == CaptureView.frontal;

  double? driver(Map<String, double> a) {
    if (isAbduction) {
      final l = a['ombro_esq'];
      final r = a['ombro_dir'];
      if (l == null || r == null) return null;
      return (l + r) / 2;
    }
    return a[spec.view == CaptureView.profileLeft ? 'joelho_esq' : 'joelho_dir'];
  }

  /// Processa um quadro. Retorna true quando uma repetição acabou de ser concluída.
  bool update(Map<String, double> angles, double t,
      {Map<String, double> confidences = const {}}) {
    if (isComplete) return false;
    processedFrames++;
    final d = driver(angles);
    if (d == null) {
      discardedFrames++;
      return false;
    }
    for (final e in _filtered(angles).entries) {
      final low = _min[e.key], high = _max[e.key];
      if (low == null || e.value < low) _min[e.key] = e.value;
      if (high == null || e.value > high) _max[e.key] = e.value;
    }

    final bool reachedPeakZone = isAbduction ? d >= abductionPeak : d <= squatPeak;
    final bool backToRest = isAbduction ? d <= abductionRest : d >= squatRest;
    final bool better = _peakDriver == null ||
        (isAbduction ? d > _peakDriver! : d < _peakDriver!);

    if (phase == RepPhase.rest) {
      if (reachedPeakZone) {
        phase = RepPhase.active;
        _activeSince = t;
        _peakDriver = d;
        _peakAngles = _filtered(angles);
        _peakConfidences = _filtered(confidences);
      }
      return false;
    }

    if (better) {
      _peakDriver = d;
      _peakAngles = _filtered(angles);
      _peakConfidences = _filtered(confidences);
    }
    if (backToRest) {
      phase = RepPhase.rest;
      final valid = t - _activeSince >= minRepSeconds && _peakAngles != null;
      final snapshot = _peakAngles;
      _peakAngles = null;
      _peakDriver = null;
      final low = Map<String, double>.of(_min);
      final high = Map<String, double>.of(_max);
      _min.clear();
      _max.clear();
      if (valid) {
        reps.add(RepMeasurement(
            index: reps.length + 1,
            angles: snapshot!,
            minAngles: low,
            maxAngles: high,
            confidences: _peakConfidences));
        return true;
      }
    }
    return false;
  }

  /// Quadro sem pessoa detectada durante a captura.
  void discardFrame() {
    if (isComplete) return;
    processedFrames++;
    discardedFrames++;
  }

  /// Interrompe uma repetição em curso (ex.: usuário saiu do enquadramento).
  void cancelActive() {
    phase = RepPhase.rest;
    _peakAngles = null;
    _peakDriver = null;
    _min.clear();
    _max.clear();
  }

  Map<String, double> _filtered(Map<String, double> a) =>
      {for (final k in spec.joints) if (a[k] != null) k: a[k]!};

  MovementResult toResult() => MovementResult(
      movementId: spec.id,
      reps: List.unmodifiable(reps),
      processedFrames: processedFrames,
      discardedFrames: discardedFrames);
}
