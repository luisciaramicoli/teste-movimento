import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/src/models/assessment_models.dart';
import 'package:movimento_mobilidade/src/models/mobility_score.dart';
import 'package:movimento_mobilidade/src/models/reference_norms.dart';
import 'package:movimento_mobilidade/src/services/rep_tracker.dart';

/// Os valores esperados são os exemplos da coletânea de regras.
void main() {
  const example = {
    MobilityJoint.ombroDir: 172.0,
    MobilityJoint.ombroEsq: 165.0,
    MobilityJoint.quadril: 110.0,
    MobilityJoint.joelho: 128.0,
    MobilityJoint.tornozelo: 30.0,
  };

  test('nota e faixa da abdução com R = 150°', () {
    const cases = {160: 10.0, 140: 8.7, 120: 5.3, 100: 2.7, 75: 0.0, 60: 0.0};
    cases.forEach((angle, grade) {
      expect(mobilityGrade(angle.toDouble(), 150), closeTo(grade, 0.05),
          reason: '$angle°');
    });
    expect(mobilityBand(140, 150), MobilityBand.adequada);
    expect(mobilityBand(120, 150), MobilityBand.reduzida);
    expect(mobilityBand(100, 150), MobilityBand.limitada);
  });

  test('cortes exatos das faixas', () {
    expect(mobilityBand(126, 140), MobilityBand.adequada);
    expect(mobilityBand(105, 140), MobilityBand.reduzida);
    expect(mobilityGrade(126, 140), closeTo(8, 1e-6));
    expect(mobilityGrade(105, 140), closeTo(4, 1e-6));
    expect(mobilityGrade(70, 140), 0);
  });

  test('score é a média simples das 5 notas', () {
    final s = MobilityScore.fromAngles(example);
    expect(s.score, closeTo(8.7, 0.05));
    expect(s.score!.round(), 9);
    expect(s.joint(MobilityJoint.tornozelo)!.band, MobilityBand.reduzida);
  });

  test('sem as 5 articulações não há score', () {
    final s = MobilityScore.fromAngles(
        {...example}..remove(MobilityJoint.tornozelo));
    expect(s.score, isNull);
    expect(s.goalScore(3), isNull);
    expect(s.missing, [MobilityJoint.tornozelo]);
  });

  test('meta de 1, 3 e 6 meses', () {
    final s = MobilityScore.fromAngles(example);
    expect(s.goalScore(1), closeTo(9.1, 0.05));
    expect(s.goalScore(3), closeTo(9.8, 0.05));
    expect(s.goalScore(6), closeTo(10, 1e-6));
    expect(mobilityGoalAngle(110, 120, 1), closeTo(114, 1e-6));
    expect(mobilityGoalAngle(128, 140, 1), closeTo(132.7, 0.05));
    expect(mobilityGoalAngle(30, 35, 3), closeTo(33.5, 0.05));
    expect(mobilityGoalAngle(172, 150, 6), 172);
  });

  test('meta respeita o teto de 15% de R por Jornada', () {
    expect(mobilityGoalAngle(50, 100, 12), closeTo(65, 1e-6));
  });

  test('assimetria exige 15% e 10°', () {
    bool alert(double l, double r) =>
        ShoulderAsymmetry(right: r, left: l).alert;
    expect(alert(165, 172), isFalse);
    expect(alert(140, 155), isFalse);
    expect(alert(130, 165), isTrue);
    expect(
        const ShoulderAsymmetry(right: 165, left: 130).percent.round(), 21);
  });

  test('converte o registro em flexão e dorsiflexão', () {
    final record = AssessmentRecord(
        id: '1',
        createdAt: DateTime(2026, 11, 25),
        volunteerCode: 'V01',
        testNumber: 1,
        reference: const MobilityReference(
            ombroDir: 160,
            ombroEsq: 160,
            quadril: 100,
            joelho: 125,
            tornozelo: 20),
        movements: const [
          MovementResult(movementId: 'abducao_ombro', reps: [
            RepMeasurement(
                index: 1, angles: {'ombro_dir': 170, 'ombro_esq': 160}),
          ]),
          MovementResult(movementId: 'agachamento_perfil_dir', reps: [
            RepMeasurement(index: 1, angles: {
              'quadril_dir': 70,
              'joelho_dir': 52,
              'tornozelo_dir': 90,
            }, restAngles: {
              'tornozelo_dir': 120
            }),
          ]),
        ]);
    final back = AssessmentRecord.fromJson(record.toJson());
    expect(mobilityAngles(back), {
      MobilityJoint.ombroDir: 170,
      MobilityJoint.ombroEsq: 160,
      MobilityJoint.quadril: 110,
      MobilityJoint.joelho: 128,
      MobilityJoint.tornozelo: 30,
    });
    expect(back.reference.ombroDir, 160);
    expect(MobilityScore.fromRecord(back).score, 10);
  });

  test('registro antigo, sem linha de base, não inventa o tornozelo', () {
    final old = AssessmentRecord.fromJson({
      'id': '1',
      'createdAt': '2026-11-23T10:00:00.000',
      'volunteerCode': 'V01',
      'testNumber': 1,
      'movements': [
        {
          'movementId': 'agachamento_perfil_dir',
          'reps': [
            {
              'index': 1,
              'angles': {'tornozelo_dir': 90}
            }
          ]
        }
      ],
    });
    expect(mobilityAngles(old), isEmpty);
    expect(old.reference.provisional, isTrue);
  });

  test('referência do ombro segue sexo, faixa etária e lado', () {
    final man = MobilityReference.forProfile(idade: 34, sexo: Sexo.masculino);
    expect([man.ombroDir, man.ombroEsq], [157.0, 156.1]);
    expect(shoulderNorm(35, Sexo.masculino)!.right, 155.1);
    expect(shoulderNorm(20, Sexo.feminino)!.right, 156.4);
    expect(shoulderNorm(84, Sexo.feminino)!.left, 115.0);
    expect(shoulderNorm(95, Sexo.feminino)!.right, 119.5);
    expect(shoulderNorm(19, Sexo.feminino), isNull);
  });

  test('quadril e joelho usam o estudo de agachamento em todo perfil', () {
    for (final r in [
      MobilityReference.forProfile(),
      MobilityReference.forProfile(idade: 70, sexo: Sexo.feminino),
    ]) {
      expect([r.quadril, r.joelho, r.tornozelo], [124.6, 125.2, 35]);
      expect(r.provisional, isTrue);
    }
  });

  test('sem sexo ou abaixo de 20 anos o ombro fica ilustrativo e avisa', () {
    final noSex = MobilityReference.forProfile(idade: 30);
    expect(noSex.ombroDir, 150);
    expect(noSex.note, contains('faltam sexo ou idade'));
    final young =
        MobilityReference.forProfile(idade: 15, sexo: Sexo.masculino);
    expect(young.ombroEsq, 150);
    expect(young.note, contains('20 anos'));
  });

  test('cada ombro é avaliado contra a sua referência', () {
    final s = MobilityScore.fromAngles({
      MobilityJoint.ombroDir: 140,
      MobilityJoint.ombroEsq: 140,
    }, reference: MobilityReference.forProfile(idade: 30, sexo: Sexo.masculino));
    expect(s.joint(MobilityJoint.ombroDir)!.reference, 157.0);
    expect(s.joint(MobilityJoint.ombroEsq)!.reference, 156.1);
    expect(s.joint(MobilityJoint.ombroDir)!.band, MobilityBand.reduzida);
    expect(s.joint(MobilityJoint.ombroDir)!.grade, closeTo(7.8, 0.05));
  });

  test('lê referência salva com um único valor de ombro', () {
    final old = MobilityReference.fromJson(
        {'ombro': 150, 'quadril': 120, 'joelho': 140, 'tornozelo': 35});
    expect([old.ombroDir, old.ombroEsq], [150, 150]);
    final back = MobilityReference.fromJson(
        MobilityReference.forProfile(idade: 50, sexo: Sexo.feminino).toJson());
    expect([back.ombroDir, back.ombroEsq], [151.4, 149.3]);
    expect(back.note, contains('Gill'));
  });

  test('RepTracker guarda o tornozelo em pé como linha de base', () {
    final t = RepTracker(kProtocolMovements[1]);
    var time = 0.0;
    const frames = [
      [170.0, 120.0],
      [172.0, 121.0],
      [171.0, 119.0],
      [120.0, 100.0],
      [80.0, 90.0],
      [140.0, 110.0],
      [168.0, 120.0],
    ];
    for (final f in frames) {
      t.update({'joelho_dir': f[0], 'tornozelo_dir': f[1]}, time);
      time += 0.4;
    }
    expect(t.reps.single.restAngles['tornozelo_dir'], 120);
    expect(t.reps.single.angles['tornozelo_dir'], 90);
  });
}
