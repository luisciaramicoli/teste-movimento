import '../models/assessment_models.dart';
import '../utils/csv_utils.dart';
import 'volunteer_code.dart';

/// CSV de uma avaliação (RF09): uma linha por repetição/articulação, mais a
/// média. Identifica o voluntário só por código (RF10). Campos sem dado ficam
/// vazios; os contadores de quadros (RF06) valem para o movimento inteiro.
class AssessmentCsv {
  AssessmentCsv._();

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

  static String build(AssessmentRecord record) {
    final rows = <List<String>>[header];
    final when = record.createdAt.toIso8601String();
    final code = VolunteerCode.sanitize(record.volunteerCode);

    for (final movement in record.movements) {
      final title = movement.spec?.title ?? movement.movementId;

      List<String> buildRow(
        String rep,
        String jointKey,
        double angle, {
        double? confidence,
        double? min,
        double? max,
      }) =>
          [
            when,
            code,
            '${record.testNumber}',
            title,
            rep,
            jointSideLabel(jointKey),
            jointBaseKey(jointKey),
            angle.toStringAsFixed(1),
            confidence?.toStringAsFixed(2) ?? '',
            min?.toStringAsFixed(1) ?? '',
            max?.toStringAsFixed(1) ?? '',
            '${movement.processedFrames ?? ''}',
            '${movement.discardedFrames ?? ''}',
          ];

      for (final rep in movement.reps) {
        rep.angles.forEach((joint, angle) {
          rows.add(buildRow(
            '${rep.index}',
            joint,
            angle,
            confidence: rep.confidences[joint],
            min: rep.minAngles[joint],
            max: rep.maxAngles[joint],
          ));
        });
      }
      movement.averages
          .forEach((joint, avg) => rows.add(buildRow('media', joint, avg)));
    }
    return rows.map((row) => row.map(escapeCsvCell).join(',')).join('\n');
  }
}
