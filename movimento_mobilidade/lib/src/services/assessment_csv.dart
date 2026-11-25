import '../models/assessment_models.dart';
import 'volunteer_code.dart';

/// CSV de uma avaliação (RF09): uma linha por repetição/articulação, mais a
/// média. Identifica o voluntário só por código (RF10). Campos sem dado ficam
/// vazios; os contadores de quadros (RF06) valem para o movimento inteiro.
class AssessmentCsv {
  static const List<String> header = [
    'data_hora',
    'voluntario',
    'teste',
    'movimento',
    'repeticao',
    'lado',
    'articulacao',
    'angulo_graus',
    'confianca',
    'rom_min',
    'rom_max',
    'quadros_processados',
    'quadros_descartados',
  ];

  static String build(AssessmentRecord r) {
    final rows = <List<String>>[header];
    final when = r.createdAt.toIso8601String();
    final code = VolunteerCode.sanitize(r.volunteerCode);
    for (final m in r.movements) {
      final title = m.spec?.title ?? m.movementId;
      List<String> row(String rep, String joint, double angle,
              {double? confidence, double? min, double? max}) =>
          [
            when,
            code,
            '${r.testNumber}',
            title,
            rep,
            _side(joint),
            _joint(joint),
            angle.toStringAsFixed(1),
            confidence?.toStringAsFixed(2) ?? '',
            min?.toStringAsFixed(1) ?? '',
            max?.toStringAsFixed(1) ?? '',
            '${m.processedFrames ?? ''}',
            '${m.discardedFrames ?? ''}',
          ];
      for (final rep in m.reps) {
        rep.angles.forEach((joint, angle) {
          rows.add(row('${rep.index}', joint, angle,
              confidence: rep.confidences[joint],
              min: rep.minAngles[joint],
              max: rep.maxAngles[joint]));
        });
      }
      m.averages.forEach((joint, avg) => rows.add(row('media', joint, avg)));
    }
    return rows.map((row) => row.map(_escape).join(',')).join('\n');
  }

  static String _side(String key) => key.endsWith('_esq')
      ? 'esquerdo'
      : (key.endsWith('_dir') ? 'direito' : 'n/a');

  static String _joint(String key) =>
      key.replaceAll(RegExp(r'_(esq|dir)$'), '');

  static String _escape(String v) =>
      v.contains(',') || v.contains('"') ? '"${v.replaceAll('"', '""')}"' : v;
}
