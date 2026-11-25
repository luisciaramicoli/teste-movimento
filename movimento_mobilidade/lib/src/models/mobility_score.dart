import 'dart:math';

import 'assessment_models.dart';

/// Regras do score de Mobilidade (coletânea de regras, seções 2 a 6).
///
/// Todos os ângulos aqui são **amplitudes**: abdução do ombro (0° = braço
/// abaixado), flexão de quadril e joelho (0° = estendido) e dorsiflexão do
/// tornozelo (0° = posição em pé).

/// Articulações que compõem o score, na ordem da tela. Pesos iguais (20%).
enum MobilityJoint {
  ombroDir('Ombro direito'),
  ombroEsq('Ombro esquerdo'),
  quadril('Quadril'),
  joelho('Joelho'),
  tornozelo('Tornozelo');

  final String label;
  const MobilityJoint(this.label);
}

enum MobilityBand {
  adequada('Adequada'),
  reduzida('Reduzida'),
  limitada('Limitada');

  final String label;
  const MobilityBand(this.label);
}

/// Referência R de cada articulação para o perfil do aluno, em graus.
class MobilityReference {
  final double ombro;
  final double quadril;
  final double joelho;
  final double tornozelo;

  /// True enquanto os valores não forem a tabela oficial por sexo e idade.
  final bool provisional;

  const MobilityReference({
    required this.ombro,
    required this.quadril,
    required this.joelho,
    required this.tornozelo,
    this.provisional = false,
  }) : assert(ombro > 0 && quadril > 0 && joelho > 0 && tornozelo > 0);

  /// Valores só ilustrativos, até a tabela por perfil chegar.
  static const MobilityReference illustrative = MobilityReference(
      ombro: 150, quadril: 120, joelho: 140, tornozelo: 35, provisional: true);

  double of(MobilityJoint joint) => switch (joint) {
        MobilityJoint.ombroDir || MobilityJoint.ombroEsq => ombro,
        MobilityJoint.quadril => quadril,
        MobilityJoint.joelho => joelho,
        MobilityJoint.tornozelo => tornozelo,
      };

  Map<String, dynamic> toJson() => {
        'ombro': ombro,
        'quadril': quadril,
        'joelho': joelho,
        'tornozelo': tornozelo,
        'provisional': provisional,
      };

  factory MobilityReference.fromJson(Map<String, dynamic> j) =>
      MobilityReference(
        ombro: (j['ombro'] as num).toDouble(),
        quadril: (j['quadril'] as num).toDouble(),
        joelho: (j['joelho'] as num).toDouble(),
        tornozelo: (j['tornozelo'] as num).toDouble(),
        provisional: (j['provisional'] as bool?) ?? false,
      );
}

/// Absorve o erro de ponto flutuante nos cortes (ex.: exatamente 90% de R).
const double _epsilon = 1e-9;

/// Faixa exibida na tela, pela fração do ângulo em relação à referência.
MobilityBand mobilityBand(double angle, double reference) {
  final ratio = angle / reference + _epsilon;
  if (ratio >= 0.90) return MobilityBand.adequada;
  if (ratio >= 0.75) return MobilityBand.reduzida;
  return MobilityBand.limitada;
}

/// Nota de 0 a 10, linear por trechos. Passar de R vale 10 (sem alerta).
double mobilityGrade(double angle, double reference) {
  final ratio = angle / reference;
  double lerp(double from, double to, double a, double b) =>
      a + (ratio - from) / (to - from) * (b - a);
  if (ratio >= 1.0 - _epsilon) return 10;
  if (ratio >= 0.90) return lerp(0.90, 1.00, 8, 10);
  if (ratio >= 0.75) return lerp(0.75, 0.90, 4, 8);
  if (ratio >= 0.50) return lerp(0.50, 0.75, 0, 4);
  return 0;
}

/// Melhora simulada por mês, como fração de R (+10% a cada 3 meses).
const double kGoalGainPerMonth = 0.10 / 3;

/// Teto de melhora por Jornada, como fração de R. A confirmar com o produto.
const double kGoalMaxGain = 0.15;

/// Ângulo-meta para uma Jornada de [months] meses. Quem já está em R ou acima
/// mantém o valor; a simulação nunca passa de R.
double mobilityGoalAngle(double angle, double reference, int months) {
  if (angle >= reference) return angle;
  final gain = reference * min(kGoalGainPerMonth * months, kGoalMaxGain);
  return min(angle + gain, reference);
}

/// Diferença entre os ombros. Só gera alerta; não altera o score.
class ShoulderAsymmetry {
  static const double minPercent = 15;
  static const double minDegrees = 10;

  final double right;
  final double left;
  const ShoulderAsymmetry({required this.right, required this.left});

  double get degrees => (right - left).abs();

  /// Diferença em relação ao lado de maior amplitude.
  double get percent {
    final larger = max(right, left);
    return larger <= 0 ? 0 : degrees / larger * 100;
  }

  /// Exige os dois limites, para evitar alerta falso por erro da câmera.
  bool get alert =>
      percent + _epsilon >= minPercent && degrees + _epsilon >= minDegrees;
}

class JointScore {
  final MobilityJoint joint;
  final double angle;
  final double reference;
  const JointScore(
      {required this.joint, required this.angle, required this.reference});

  double get percent => angle / reference * 100;
  double get grade => mobilityGrade(angle, reference);
  MobilityBand get band => mobilityBand(angle, reference);
  bool get atReference => angle >= reference;
  double goalAngle(int months) => mobilityGoalAngle(angle, reference, months);
}

class MobilityScore {
  /// Só as articulações com medida válida, na ordem de [MobilityJoint].
  final List<JointScore> joints;
  final MobilityReference reference;

  const MobilityScore._(this.joints, this.reference);

  factory MobilityScore.fromAngles(Map<MobilityJoint, double> angles,
          {MobilityReference reference = MobilityReference.illustrative}) =>
      MobilityScore._([
        for (final j in MobilityJoint.values)
          if (angles[j] != null)
            JointScore(joint: j, angle: angles[j]!, reference: reference.of(j))
      ], reference);

  /// Score da avaliação, com a referência gravada nela.
  factory MobilityScore.fromRecord(AssessmentRecord record) =>
      MobilityScore.fromAngles(mobilityAngles(record),
          reference: record.reference);

  JointScore? joint(MobilityJoint joint) {
    for (final s in joints) {
      if (s.joint == joint) return s;
    }
    return null;
  }

  List<MobilityJoint> get missing => [
        for (final j in MobilityJoint.values)
          if (joint(j) == null) j
      ];

  /// Média simples das 5 notas (0 a 10), sem arredondar. Null se faltar alguma.
  double? get score => _mean((j) => j.grade);

  /// Score simulado ao atingir a meta de uma Jornada de [months] meses.
  double? goalScore(int months) =>
      _mean((j) => mobilityGrade(j.goalAngle(months), j.reference));

  ShoulderAsymmetry? get shoulderAsymmetry {
    final r = joint(MobilityJoint.ombroDir);
    final l = joint(MobilityJoint.ombroEsq);
    if (r == null || l == null) return null;
    return ShoulderAsymmetry(right: r.angle, left: l.angle);
  }

  double? _mean(double Function(JointScore) value) {
    if (missing.isNotEmpty) return null;
    return joints.fold<double>(0, (s, j) => s + value(j)) / joints.length;
  }
}

/// Amplitudes das 5 articulações: média das repetições com leitura válida.
///
/// Os registros guardam ângulos internos (perna estendida ≈ 180°), convertidos
/// aqui. A dorsiflexão é quanto o ângulo do tornozelo fechou em relação à
/// posição em pé; sem essa linha de base (registros antigos), fica de fora.
Map<MobilityJoint, double> mobilityAngles(AssessmentRecord record) {
  final out = <MobilityJoint, double>{};

  void add(MobilityJoint joint, String movementId,
      double? Function(RepMeasurement) read) {
    final movement = record.movement(movementId);
    if (movement == null) return;
    final values = [
      for (final rep in movement.reps)
        if (read(rep) case final v?) v
    ];
    if (values.isEmpty) return;
    final mean = values.reduce((a, b) => a + b) / values.length;
    out[joint] = (mean * 10).roundToDouble() / 10;
  }

  double? flexion(RepMeasurement rep, String key) {
    final v = rep.angles[key];
    return v == null ? null : max(0, 180 - v).toDouble();
  }

  const abduction = 'abducao_ombro';
  const squat = 'agachamento_perfil_dir';
  add(MobilityJoint.ombroDir, abduction, (r) => r.angles['ombro_dir']);
  add(MobilityJoint.ombroEsq, abduction, (r) => r.angles['ombro_esq']);
  add(MobilityJoint.quadril, squat, (r) => flexion(r, 'quadril_dir'));
  add(MobilityJoint.joelho, squat, (r) => flexion(r, 'joelho_dir'));
  add(MobilityJoint.tornozelo, squat, (r) {
    final rest = r.restAngles['tornozelo_dir'];
    final peak = r.angles['tornozelo_dir'];
    return rest == null || peak == null ? null : max(0, rest - peak).toDouble();
  });
  return out;
}
