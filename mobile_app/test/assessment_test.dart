import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:teste_movimento_app/models/assessment_models.dart';
import 'package:teste_movimento_app/models/joint_angle.dart';
import 'package:teste_movimento_app/services/assessment_csv.dart';
import 'package:teste_movimento_app/services/framing_checker.dart';
import 'package:teste_movimento_app/services/rep_tracker.dart';

const screen = Size(400, 800);

Map<String, Point2D> body({
  double cx = 200,
  double top = 100,
  double bottom = 700,
  double shoulderHalf = 50,
}) {
  final h = bottom - top;
  return {
    'NOSE': Point2D(cx, top),
    'LEFT_SHOULDER': Point2D(cx - shoulderHalf, top + h * 0.13),
    'RIGHT_SHOULDER': Point2D(cx + shoulderHalf, top + h * 0.13),
    'LEFT_HIP': Point2D(cx - 30, top + h * 0.50),
    'RIGHT_HIP': Point2D(cx + 30, top + h * 0.50),
    'LEFT_KNEE': Point2D(cx - 30, top + h * 0.75),
    'RIGHT_KNEE': Point2D(cx + 30, top + h * 0.75),
    'LEFT_ANKLE': Point2D(cx - 30, bottom),
    'RIGHT_ANKLE': Point2D(cx + 30, bottom),
  };
}

ExtractedPoseData pose(Map<String, Point2D> lm, {double yaw = 0}) =>
    ExtractedPoseData(angles: const {}, landmarks: lm, bodyOrientationAngle: yaw);

void main() {
  group('FramingChecker lado em perfil', () {
    ExtractedPoseData sided(String side) => ExtractedPoseData(
        angles: const {},
        landmarks: {
          for (final e in body().entries)
            if (!e.key.startsWith(side == 'LEFT' ? 'RIGHT_' : 'LEFT_')) e.key: e.value
        },
        bodyOrientationAngle: 80,
        visibleSide: side);

    test('lado errado em perfil pede para virar o outro lado', () {
      final s = FramingChecker.evaluate(
          sided('RIGHT'), screen, CaptureView.profileLeft);
      expect(s.issue, FramingIssue.wrongOrientation);
      expect(s.message, contains('esquerdo'));
    });

    test('lado correto em perfil é aceito', () {
      final s = FramingChecker.evaluate(
          sided('LEFT'), screen, CaptureView.profileLeft);
      expect(s.issue, isNot(FramingIssue.wrongOrientation));
    });
  });

  group('FramingChecker', () {
    test('aceita corpo inteiro, centralizado, de frente', () {
      final s = FramingChecker.evaluate(pose(body()), screen, CaptureView.frontal);
      expect(s.isInside, isTrue);
    });

    test('sem pessoa', () {
      final s = FramingChecker.evaluate(null, screen, CaptureView.frontal);
      expect(s.issue, FramingIssue.noPerson);
    });

    test('pés cortados pela borda inferior', () {
      final s = FramingChecker.evaluate(
          pose(body(bottom: 790)), screen, CaptureView.frontal);
      expect(s.issue, FramingIssue.bodyCutOff);
    });

    test('muito longe e muito perto', () {
      expect(
          FramingChecker.evaluate(
                  pose(body(top: 350, bottom: 550)), screen, CaptureView.frontal)
              .issue,
          FramingIssue.tooFar);
      expect(
          FramingChecker.evaluate(
                  pose(body(top: 40, bottom: 760)), screen, CaptureView.frontal)
              .issue,
          FramingIssue.tooClose);
    });

    test('descentralizado', () {
      final s = FramingChecker.evaluate(
          pose(body(cx: 300)), screen, CaptureView.frontal);
      expect(s.issue, FramingIssue.offCenter);
    });

    test('orientação: frontal exige yaw baixo, perfil exige yaw alto', () {
      expect(
          FramingChecker.evaluate(pose(body(), yaw: 70), screen, CaptureView.frontal)
              .issue,
          FramingIssue.wrongOrientation);
      expect(
          FramingChecker.evaluate(
                  pose(body(), yaw: 10), screen, CaptureView.profileLeft)
              .issue,
          FramingIssue.wrongOrientation);
      expect(
          FramingChecker.evaluate(
                  pose(body(), yaw: 80), screen, CaptureView.profileRight)
              .isInside,
          isTrue);
    });
  });

  group('RepTracker', () {
    test('abdução: conta 3 repetições e registra o pico', () {
      final t = RepTracker(kProtocolMovements[0]);
      var time = 0.0;
      for (var rep = 0; rep < 3; rep++) {
        for (final a in [20.0, 60.0, 85.0 + rep, 95.0 + rep, 60.0, 30.0]) {
          t.update({'ombro_esq': a, 'ombro_dir': a, 'joelho_esq': 170}, time);
          time += 0.4;
        }
      }
      expect(t.reps.length, 3);
      expect(t.isComplete, isTrue);
      expect(t.reps[0].angles['ombro_esq'], 95.0);
      expect(t.reps[2].angles['ombro_dir'], 97.0);
      final avg = t.toResult().averages['ombro_esq'];
      expect(avg, 96.0);
    });

    test('agachamento de perfil usa o joelho direito', () {
      final t = RepTracker(kProtocolMovements[1]);
      var time = 0.0;
      for (final k in [170.0, 140.0, 105.0, 100.0, 150.0, 165.0]) {
        t.update({
          'joelho_dir': k,
          'quadril_dir': k - 20,
          'tornozelo_dir': 80,
          'ombro_dir': 85,
          'joelho_esq': 170,
        }, time);
        time += 0.4;
      }
      expect(t.reps.length, 1);
      expect(t.reps.first.angles['joelho_dir'], 100.0);
      expect(t.reps.first.angles.containsKey('joelho_esq'), isFalse);
    });

    test('ignora movimento rápido demais e cancelamento zera a fase', () {
      final t = RepTracker(kProtocolMovements[0]);
      t.update({'ombro_esq': 90, 'ombro_dir': 90}, 0.0);
      t.update({'ombro_esq': 20, 'ombro_dir': 20}, 0.1);
      expect(t.reps, isEmpty);
      t.update({'ombro_esq': 90, 'ombro_dir': 90}, 1.0);
      t.cancelActive();
      expect(t.phase, RepPhase.rest);
    });
  });

  group('Resultado e histórico', () {
    final record = AssessmentRecord(
      id: '1',
      createdAt: DateTime(2026, 11, 18, 9, 30),
      volunteerCode: 'V01',
      testNumber: 2,
      movements: [
        MovementResult(movementId: 'abducao_ombro', reps: const [
          RepMeasurement(index: 1, angles: {'ombro_esq': 90, 'ombro_dir': 88}),
          RepMeasurement(index: 2, angles: {'ombro_esq': 94, 'ombro_dir': 92}),
          RepMeasurement(index: 3, angles: {'ombro_esq': 92, 'ombro_dir': 90}),
        ]),
      ],
    );

    test('média e desvio padrão por articulação', () {
      final m = record.movements.first;
      expect(m.averages['ombro_esq'], 92.0);
      expect(m.deviations['ombro_esq'], 2.0);
    });

    test('JSON ida e volta', () {
      final back = AssessmentRecord.fromJson(record.toJson());
      expect(back.volunteerCode, 'V01');
      expect(back.testNumber, 2);
      expect(back.movements.first.averages['ombro_dir'], 90.0);
    });

    test('CSV identifica pelo nome e inclui a média', () {
      final csv = AssessmentCsv.build(record);
      expect(csv.split('\n').first, AssessmentCsv.header.join(','));
      expect(csv, contains('V01'));
      expect(csv, contains('media'));
    });
  });
}
