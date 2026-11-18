import '../models/assessment_models.dart';

/// CSV de uma avaliação: uma linha por repetição/articulação, mais a média.
/// Identifica o voluntário pelo nome informado na avaliação.
class AssessmentCsv {
  static const List<String> header = [
    'data_hora',
    'voluntario',
    'teste',
    'movimento',
    'repeticao',
    'articulacao',
    'angulo_graus',
  ];

  static String build(AssessmentRecord r) {
    final rows = <List<String>>[header];
    final when = r.createdAt.toIso8601String();
    for (final m in r.movements) {
      final title = m.spec?.title ?? m.movementId;
      for (final rep in m.reps) {
        rep.angles.forEach((joint, angle) {
          rows.add([when, r.volunteerCode, '${r.testNumber}', title,
              '${rep.index}', jointLabel(joint), angle.toStringAsFixed(1)]);
        });
      }
      m.averages.forEach((joint, avg) {
        rows.add([when, r.volunteerCode, '${r.testNumber}', title, 'media',
            jointLabel(joint), avg.toStringAsFixed(1)]);
      });
    }
    return rows.map((row) => row.map(_escape).join(',')).join('\n');
  }

  static String _escape(String v) =>
      v.contains(',') || v.contains('"') ? '"${v.replaceAll('"', '""')}"' : v;
}
