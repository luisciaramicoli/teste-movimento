import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

RepMeasurement _rep(int i, Map<String, double> angles) => RepMeasurement(
    index: i, angles: angles, restAngles: const {'tornozelo_dir': 100});

final _record = AssessmentRecord(
  id: '1',
  createdAt: DateTime(2026, 11, 26, 9),
  volunteerCode: 'V01',
  testNumber: 1,
  jornadaMeses: 6,
  movements: [
    MovementResult(movementId: 'abducao_ombro', reps: [
      _rep(1, {'ombro_dir': 150, 'ombro_esq': 120}),
      _rep(2, {'ombro_dir': 154, 'ombro_esq': 124}),
    ]),
    MovementResult(movementId: 'agachamento_perfil_dir', reps: [
      _rep(1, {'quadril_dir': 60, 'joelho_dir': 55, 'tornozelo_dir': 74}),
    ]),
  ],
);

void main() {
  test('a análise devolvida já traz repetições e desvio por articulação', () {
    final right = _record.analysis.joint(MobilityJoint.ombroDir)!;
    expect(right.angle, 152);
    expect(right.repAngles, [150, 154]);
    expect(right.deviation, 2.8);
    expect(_record.analysis.joint(MobilityJoint.joelho)!.deviation, isNull);
  });

  test('toResultJson entrega todos os valores prontos em JSON', () {
    final json = jsonDecode(jsonEncode(_record.toResultJson())) as Map;
    final analysis = json['analysis'] as Map;
    final score = _record.analysis;

    expect(analysis['score'], closeTo(score.score!, 1e-9));
    expect(analysis['goalMonths'], 6);
    expect(analysis['goalScore'], closeTo(score.goalScore(6)!, 1e-9));
    expect(analysis['missing'], isEmpty);
    expect((analysis['shoulderAsymmetry'] as Map)['alert'], isTrue);
    final knee = (analysis['joints'] as List)
        .cast<Map>()
        .singleWhere((j) => j['joint'] == 'joelho');
    expect(knee['angle'], 125);
    expect(knee.keys,
        containsAll(['reference', 'percent', 'grade', 'band', 'goalAngle']));
    final abduction = (json['movements'] as List).first as Map;
    expect((abduction['averages'] as Map)['ombro_dir'], 152);
    expect(abduction['deviations'], isNotEmpty);
  });

  test('o histórico guarda só as medidas, sem a análise', () {
    expect(_record.toJson().containsKey('analysis'), isFalse);
    expect(AssessmentRecord.fromJson(_record.toResultJson()).analysis.score,
        _record.analysis.score);
  });
}
