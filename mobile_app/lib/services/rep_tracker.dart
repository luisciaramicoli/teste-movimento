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
  bool update(Map<String, double> angles, double t) {
    if (isComplete) return false;
    final d = driver(angles);
    if (d == null) return false;

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
      }
      return false;
    }

    if (better) {
      _peakDriver = d;
      _peakAngles = _filtered(angles);
    }
    if (backToRest) {
      phase = RepPhase.rest;
      final valid = t - _activeSince >= minRepSeconds && _peakAngles != null;
      final snapshot = _peakAngles;
      _peakAngles = null;
      _peakDriver = null;
      if (valid) {
        reps.add(RepMeasurement(index: reps.length + 1, angles: snapshot!));
        return true;
      }
    }
    return false;
  }

  /// Interrompe uma repetição em curso (ex.: usuário saiu do enquadramento).
  void cancelActive() {
    phase = RepPhase.rest;
    _peakAngles = null;
    _peakDriver = null;
  }

  Map<String, double> _filtered(Map<String, double> a) =>
      {for (final k in spec.joints) if (a[k] != null) k: a[k]!};

  MovementResult toResult() =>
      MovementResult(movementId: spec.id, reps: List.unmodifiable(reps));
}
