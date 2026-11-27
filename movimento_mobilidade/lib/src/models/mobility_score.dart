import 'dart:math';

import 'assessment_models.dart';
import 'reference_norms.dart';

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
  final double ombroDir;
  final double ombroEsq;
  final double quadril;
  final double joelho;
  final double tornozelo;

  /// Indica que a referência inclui valores provisórios.
  final bool provisional;

  /// Origem dos valores, exibida na tela de resultado.
  final String? note;

  const MobilityReference({
    required this.ombroDir,
    required this.ombroEsq,
    required this.quadril,
    required this.joelho,
    required this.tornozelo,
    this.provisional = false,
    this.note,
  }) : assert(ombroDir > 0 &&
            ombroEsq > 0 &&
            quadril > 0 &&
            joelho > 0 &&
            tornozelo > 0);

  static const double _illustrativeShoulder = 150;
  static const double _illustrativeAnkle = 35;

  /// Valores só ilustrativos, os mesmos dos exemplos da coletânea de regras.
  /// Também é a referência das avaliações salvas sem referência.
  static const MobilityReference illustrative = MobilityReference(
      ombroDir: _illustrativeShoulder,
      ombroEsq: _illustrativeShoulder,
      quadril: 120,
      joelho: 140,
      tornozelo: _illustrativeAnkle,
      provisional: true,
      note: 'Referências ilustrativas da coletânea de mobilidade.');

  static const standard = MobilityReference(
    ombroDir: pooledShoulderRightMean,
    ombroEsq: pooledShoulderLeftMean,
    quadril: squatHipRightMean,
    joelho: squatKneeRightMean,
    tornozelo: squatAnkleRightMean,
    note: 'Referência padrão de abdução ativa dos ombros baseada em Gill et al. '
        '(2020), tabela 2. Quadril, joelho e tornozelo usam as médias do lado '
        'direito no agachamento profundo de Endo et al. (2020), tabela 1.',
  );

  /// Compatibilidade com chamadas que ainda informam os dados do perfil.
  factory MobilityReference.forProfile({int? idade, Sexo? sexo}) => standard;

  double of(MobilityJoint joint) => switch (joint) {
        MobilityJoint.ombroDir => ombroDir,
        MobilityJoint.ombroEsq => ombroEsq,
        MobilityJoint.quadril => quadril,
        MobilityJoint.joelho => joelho,
        MobilityJoint.tornozelo => tornozelo,
      };

  Map<String, dynamic> toJson() => {
        'ombroDir': ombroDir,
        'ombroEsq': ombroEsq,
        'quadril': quadril,
        'joelho': joelho,
        'tornozelo': tornozelo,
        'provisional': provisional,
        'note': note,
      };

  /// Registros da versão anterior tinham um único valor `ombro` ou notas
  /// legadas com texto "ilustrativo"/"provisório".
  factory MobilityReference.fromJson(Map<String, dynamic> j) {
    double shoulder(String key) => ((j[key] ?? j['ombro']) as num).toDouble();
    final rawNote = j['note'] as String?;
    final wasUniversal = rawNote ==
        'Referência normativa geral (todas as idades e gêneros).';
    return MobilityReference(
      ombroDir: shoulder('ombroDir'),
      ombroEsq: shoulder('ombroEsq'),
      quadril: (j['quadril'] as num).toDouble(),
      joelho: (j['joelho'] as num).toDouble(),
      tornozelo: (j['tornozelo'] as num).toDouble(),
      provisional: wasUniversal || (j['provisional'] as bool? ?? false),
      note: wasUniversal ? 'Referência fixa usada nesta avaliação anterior.' : rawNote,
    );
  }
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
  /// Amplitude de cada repetição com leitura válida.
  final List<double> repAngles;

  const JointScore(
      {required this.joint,
      required this.angle,
      required this.reference,
      this.repAngles = const []});

  /// Desvio padrão amostral das repetições; null com menos de duas.
  double? get deviation => repAngles.length < 2
      ? null
      : (stdDev(repAngles) * 10).roundToDouble() / 10;

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
          {MobilityReference reference = MobilityReference.standard,
          Map<MobilityJoint, List<double>> repAngles = const {}}) =>
      MobilityScore._([
        for (final j in MobilityJoint.values)
          if (angles[j] != null)
            JointScore(
                joint: j,
                angle: angles[j]!,
                reference: reference.of(j),
                repAngles: repAngles[j] ?? const [])
      ], reference);

  /// Score da avaliação, com a referência gravada nela.
  factory MobilityScore.fromRecord(AssessmentRecord record) =>
      MobilityScore.fromAngles(mobilityAngles(record),
          reference: record.reference,
          repAngles: {
            for (final j in MobilityJoint.values)
              j: [for (final r in mobilityJointReps(record, j)) r.angle]
          });

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

  /// Toda a análise em tipos JSON, com a meta para [months] meses.
  Map<String, dynamic> toJson({required int months}) {
    final asymmetry = shoulderAsymmetry;
    return {
      'score': score,
      'goalMonths': months,
      'goalScore': goalScore(months),
      'joints': [
        for (final j in joints)
          {
            'joint': j.joint.name,
            'label': j.joint.label,
            'angle': j.angle,
            'repAngles': j.repAngles,
            'deviation': j.deviation,
            'reference': j.reference,
            'percent': j.percent,
            'grade': j.grade,
            'band': j.band.name,
            'goalAngle': j.goalAngle(months),
          }
      ],
      'missing': [for (final j in missing) j.name],
      'shoulderAsymmetry': asymmetry == null
          ? null
          : {
              'degrees': asymmetry.degrees,
              'percent': asymmetry.percent,
              'alert': asymmetry.alert,
            },
      'reference': reference.toJson(),
    };
  }

  double? _mean(double Function(JointScore) value) {
    if (missing.isNotEmpty) return null;
    return joints.fold<double>(0, (s, j) => s + value(j)) / joints.length;
  }
}

/// Amplitudes individuais de cada repetição válida para [joint] no [record].
List<({int index, double angle})> mobilityJointReps(
    AssessmentRecord record, MobilityJoint joint) {
  const abduction = 'abducao_ombro';
  const squat = 'agachamento_perfil_dir';

  double? flexion(RepMeasurement rep, String key) {
    final v = rep.angles[key];
    return v == null ? null : max(0, 180 - v).toDouble();
  }

  final (String movementId, double? Function(RepMeasurement) read) =
      switch (joint) {
    MobilityJoint.ombroDir => (abduction, (RepMeasurement r) => r.angles['ombro_dir']),
    MobilityJoint.ombroEsq => (abduction, (RepMeasurement r) => r.angles['ombro_esq']),
    MobilityJoint.quadril => (squat, (RepMeasurement r) => flexion(r, 'quadril_dir')),
    MobilityJoint.joelho => (squat, (RepMeasurement r) => flexion(r, 'joelho_dir')),
    MobilityJoint.tornozelo => (
        squat,
        (RepMeasurement r) {
          final rest = r.restAngles['tornozelo_dir'];
          final peak = r.angles['tornozelo_dir'];
          return rest == null || peak == null
              ? null
              : max(0, rest - peak).toDouble();
        }
      ),
  };

  final movement = record.movement(movementId);
  if (movement == null) return const [];
  return [
    for (final rep in movement.reps)
      if (read(rep) case final v?)
        (index: rep.index, angle: (v * 10).roundToDouble() / 10),
  ];
}

/// Amplitudes das 5 articulações: média das repetições com leitura válida.
///
/// Os registros guardam ângulos internos (perna estendida ≈ 180°), convertidos
/// aqui. A dorsiflexão é quanto o ângulo do tornozelo fechou em relação à
/// posição em pé; sem essa linha de base (registros antigos), fica de fora.
Map<MobilityJoint, double> mobilityAngles(AssessmentRecord record) {
  final out = <MobilityJoint, double>{};
  for (final joint in MobilityJoint.values) {
    final reps = mobilityJointReps(record, joint);
    if (reps.isEmpty) continue;
    final mean =
        reps.fold<double>(0, (s, r) => s + r.angle) / reps.length;
    out[joint] = (mean * 10).roundToDouble() / 10;
  }
  return out;
}
