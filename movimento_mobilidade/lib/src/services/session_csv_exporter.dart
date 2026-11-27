import '../models/joint_angle.dart';
import '../models/protocol_models.dart';
import '../utils/csv_utils.dart';
import 'volunteer_code.dart';

/// Exportação de sessão em CSV (RF09), identificando o voluntário só por código (RF10).
///
/// Esquema (Plano de Ação v2 / 06_01 seção 6.4):
/// data_hora, voluntario, movimento, lado, articulacao, angulo, confianca,
/// rom_min, rom_max
///
/// `confianca` fica vazia quando o motor de pose não informa o valor
/// agregado da articulação; nunca é preenchida com valor inventado.
class SessionCsvExporter {
  SessionCsvExporter._();

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

  static bool isValidVolunteerCode(String code) => VolunteerCode.isValid(code);

  static String normalizeCode(String code) => VolunteerCode.normalize(code);

  static String _formatAngle(double? value) =>
      value == null ? '' : value.toStringAsFixed(1);

  static String build({
    required String volunteerCode,
    required DateTime when,
    required JointAngleTracker tracker,
    required List<PostureEvaluationResult> postures,
  }) {
    if (!isValidVolunteerCode(volunteerCode)) {
      throw ArgumentError('Use um código de voluntário, como V01.');
    }
    final code = normalizeCode(volunteerCode);
    final stamp = when.toIso8601String();
    final rows = <String>[header.join(',')];

    for (final posture in postures) {
      posture.capturedAngles.forEach((key, angle) {
        final rec = tracker.records[key];
        rows.add([
          stamp,
          code,
          escapeCsvCell(posture.postureTitle),
          jointSideLabel(key),
          jointBaseKey(key),
          _formatAngle(angle),
          '',
          _formatAngle(rec?.minAngle),
          _formatAngle(rec?.maxAngle),
        ].join(','));
      });
    }
    return '${rows.join('\n')}\n';
  }
}
