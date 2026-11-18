import 'dart:math';

/// Vista da câmera exigida para o movimento.
enum CaptureView { frontal, profileLeft, profileRight }

/// Articulações avaliadas (chaves usadas pelo PoseDetectorService).
const List<String> kFrontalJoints = [
  'ombro_esq',
  'ombro_dir',
  'quadril_esq',
  'quadril_dir',
  'joelho_esq',
  'joelho_dir',
  'tornozelo_esq',
  'tornozelo_dir',
];

const List<String> kLeftJoints = [
  'ombro_esq',
  'quadril_esq',
  'joelho_esq',
  'tornozelo_esq',
];

const List<String> kRightJoints = [
  'ombro_dir',
  'quadril_dir',
  'joelho_dir',
  'tornozelo_dir',
];

String jointLabel(String key) {
  final side = key.endsWith('_esq') ? 'esquerdo' : 'direito';
  final base = key.replaceAll(RegExp(r'_(esq|dir)$'), '');
  switch (base) {
    case 'ombro':
      return 'Ombro $side';
    case 'quadril':
      return 'Quadril $side';
    case 'joelho':
      return 'Joelho $side';
    case 'tornozelo':
      return 'Tornozelo $side';
  }
  return key;
}

/// Definição estática de um movimento do protocolo.
class MovementSpec {
  final String id;
  final String title;
  final String viewLabel;
  final CaptureView view;
  final String instruction;
  final int repetitions;
  final List<String> joints;

  const MovementSpec({
    required this.id,
    required this.title,
    required this.viewLabel,
    required this.view,
    required this.instruction,
    required this.joints,
    this.repetitions = 3,
  });
}

const List<MovementSpec> kProtocolMovements = [
  MovementSpec(
    id: 'abducao_ombro',
    title: 'Abdução de ombro',
    viewLabel: 'De frente para a câmera',
    view: CaptureView.frontal,
    instruction:
        'Fique de frente para a câmera, em pé, com os braços ao lado do corpo. '
        'Eleve os dois braços lateralmente até a altura dos ombros e retorne. '
        'Realize 3 repetições.',
    joints: kFrontalJoints,
  ),
  MovementSpec(
    id: 'agachamento_perfil_esq',
    title: 'Agachamento, perfil esquerdo',
    viewLabel: 'Lado esquerdo voltado para a câmera',
    view: CaptureView.profileLeft,
    instruction:
        'Posicione-se de perfil, com o lado esquerdo voltado para a câmera. '
        'Estenda os braços à frente e agache até a profundidade confortável, '
        'depois retorne. Realize 3 repetições.',
    joints: kLeftJoints,
  ),
  MovementSpec(
    id: 'agachamento_perfil_dir',
    title: 'Agachamento, perfil direito',
    viewLabel: 'Lado direito voltado para a câmera',
    view: CaptureView.profileRight,
    instruction:
        'Posicione-se de perfil, com o lado direito voltado para a câmera. '
        'Estenda os braços à frente e agache até a profundidade confortável, '
        'depois retorne. Realize 3 repetições.',
    joints: kRightJoints,
  ),
];

MovementSpec? movementSpecById(String id) {
  for (final m in kProtocolMovements) {
    if (m.id == id) return m;
  }
  return null;
}

/// Ângulos (graus) registrados no instante de pico de uma repetição.
class RepMeasurement {
  final int index;
  final Map<String, double> angles;

  const RepMeasurement({required this.index, required this.angles});

  Map<String, dynamic> toJson() => {'index': index, 'angles': angles};

  factory RepMeasurement.fromJson(Map<String, dynamic> j) => RepMeasurement(
        index: (j['index'] as num).toInt(),
        angles: (j['angles'] as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}

class MovementResult {
  final String movementId;
  final List<RepMeasurement> reps;

  const MovementResult({required this.movementId, required this.reps});

  MovementSpec? get spec => movementSpecById(movementId);

  /// Média por articulação, considerando apenas repetições com leitura válida.
  Map<String, double> get averages {
    final out = <String, double>{};
    for (final key in _jointKeys) {
      final v = _values(key);
      if (v.isNotEmpty) out[key] = _round(v.reduce((a, b) => a + b) / v.length);
    }
    return out;
  }

  /// Desvio padrão amostral por articulação (precisa de 2+ repetições).
  Map<String, double> get deviations {
    final out = <String, double>{};
    for (final key in _jointKeys) {
      final v = _values(key);
      if (v.length >= 2) out[key] = _round(stdDev(v));
    }
    return out;
  }

  Iterable<String> get _jointKeys {
    final spec = this.spec;
    if (spec != null) return spec.joints;
    return reps.expand((r) => r.angles.keys).toSet();
  }

  List<double> _values(String key) =>
      [for (final r in reps) if (r.angles[key] != null) r.angles[key]!];

  Map<String, dynamic> toJson() => {
        'movementId': movementId,
        'reps': reps.map((r) => r.toJson()).toList(),
      };

  factory MovementResult.fromJson(Map<String, dynamic> j) => MovementResult(
        movementId: j['movementId'] as String,
        reps: (j['reps'] as List)
            .map((e) => RepMeasurement.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Uma avaliação completa (3 movimentos) salva no histórico.
class AssessmentRecord {
  final String id;
  final DateTime createdAt;
  final String volunteerCode;
  final int testNumber;
  final String engine;
  final List<MovementResult> movements;

  const AssessmentRecord({
    required this.id,
    required this.createdAt,
    required this.volunteerCode,
    required this.testNumber,
    required this.movements,
    this.engine = 'Google ML Kit Pose Detection (base)',
  });

  MovementResult? movement(String id) {
    for (final m in movements) {
      if (m.movementId == id) return m;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'volunteerCode': volunteerCode,
        'testNumber': testNumber,
        'engine': engine,
        'movements': movements.map((m) => m.toJson()).toList(),
      };

  factory AssessmentRecord.fromJson(Map<String, dynamic> j) => AssessmentRecord(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        volunteerCode: j['volunteerCode'] as String,
        testNumber: (j['testNumber'] as num).toInt(),
        engine: (j['engine'] as String?) ?? 'Google ML Kit Pose Detection',
        movements: (j['movements'] as List)
            .map((e) => MovementResult.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

double stdDev(List<double> v) {
  if (v.length < 2) return 0;
  final mean = v.reduce((a, b) => a + b) / v.length;
  final ss = v.fold<double>(0, (s, x) => s + (x - mean) * (x - mean));
  return sqrt(ss / (v.length - 1));
}

double _round(double x) => (x * 10).roundToDouble() / 10;
