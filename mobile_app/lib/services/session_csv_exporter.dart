import '../models/joint_angle.dart';
import '../models/protocol_models.dart';

/// Exportação de sessão em CSV (RF09), identificando o voluntário pelo nome.
///
/// Esquema (Plano de Ação v2 / 06_01 seção 6.4):
/// data_hora, voluntario, movimento, lado, articulacao, angulo, confianca,
/// rom_min, rom_max
///
/// `confianca` fica vazia quando o motor de pose não informa o valor
/// agregado da articulação; nunca é preenchida com valor inventado.
class SessionCsvExporter {
  static const List<String> header = [
    'data_hora',
    'voluntario',
    'movimento',
    'lado',
    'articulacao',
    'angulo',
    'confianca',
    'rom_min',
    'rom_max',
  ];

  /// Nome válido: 2 a 60 caracteres, só letras (com acento), números, espaço,
  /// hífen, apóstrofo e ponto.
  static final RegExp _namePattern =
      RegExp(r"^[\p{L}\p{N}][\p{L}\p{N} .'\-]{1,59}$", unicode: true);

  static bool isValidVolunteerCode(String name) =>
      _namePattern.hasMatch(normalizeCode(name));

  /// Remove espaços extras e põe a inicial de cada palavra em maiúscula
  /// ("  maria   silva " -> "Maria Silva"), para o mesmo nome sempre agrupar igual.
  static String normalizeCode(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static String _side(String jointKey) {
    if (jointKey.endsWith('_esq')) return 'esquerdo';
    if (jointKey.endsWith('_dir')) return 'direito';
    return 'n/a';
  }

  static String _joint(String jointKey) =>
      jointKey.replaceAll(RegExp(r'_(esq|dir)$'), '');

  static String _escape(String v) =>
      (v.contains(',') || v.contains('"') || v.contains('\n'))
          ? '"${v.replaceAll('"', '""')}"'
          : v;

  static String _num(double? v) => v == null ? '' : v.toStringAsFixed(1);

  static String build({
    required String volunteerCode,
    required DateTime when,
    required JointAngleTracker tracker,
    required List<PostureEvaluationResult> postures,
  }) {
    if (!isValidVolunteerCode(volunteerCode)) {
      throw ArgumentError('Nome do voluntário inválido.');
    }
    final code = normalizeCode(volunteerCode);
    final stamp = when.toIso8601String();
    final rows = <String>[header.join(',')];

    for (final p in postures) {
      p.capturedAngles.forEach((key, angle) {
        final rec = tracker.records[key];
        rows.add([
          stamp,
          code,
          _escape(p.postureTitle),
          _side(key),
          _joint(key),
          _num(angle),
          '',
          _num(rec?.minAngle),
          _num(rec?.maxAngle),
        ].join(','));
      });
    }
    return '${rows.join('\n')}\n';
  }
}
