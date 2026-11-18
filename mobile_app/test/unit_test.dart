import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teste_movimento_app/models/joint_angle.dart';
import 'package:teste_movimento_app/models/protocol_models.dart';
import 'package:teste_movimento_app/services/protocol_service.dart';
import 'package:teste_movimento_app/services/rep_counter_service.dart';
import 'package:teste_movimento_app/services/motion_trail_service.dart';
import 'package:teste_movimento_app/services/one_euro_filter.dart';

void main() {
  group('Geometria e Cálculo Angular em Dart', () {
    test('Calcula ângulo reto de 90 graus', () {
      const a = Point2D(0, 1);
      const b = Point2D(0, 0);
      const c = Point2D(1, 0);

      final angle = calculateAngle(a, b, c);
      expect(angle, closeTo(90.0, 0.1));
    });

    test('Calcula ângulo reto de 180 graus (linha reta)', () {
      const a = Point2D(-1, 0);
      const b = Point2D(0, 0);
      const c = Point2D(1, 0);

      final angle = calculateAngle(a, b, c);
      expect(angle, closeTo(180.0, 0.1));
    });

    test('Calcula ângulo agudo de 45 graus', () {
      const a = Point2D(1, 1);
      const b = Point2D(0, 0);
      const c = Point2D(1, 0);

      final angle = calculateAngle(a, b, c);
      expect(angle, closeTo(45.0, 0.1));
    });
  });

  group('JointAngleTracker (10 Articulações + Panturrilha)', () {
    test('Rastreia amplitude mínima, máxima, tornozelo e elevação da panturrilha', () {
      final tracker = JointAngleTracker();

      expect(tracker.records.containsKey('tornozelo_esq'), isTrue);
      expect(tracker.records.containsKey('tornozelo_dir'), isTrue);

      final mockFrame1 = {
        'cotovelo_esq': const JointAngleData(
          key: 'cotovelo_esq',
          label: 'Cotovelo Esquerdo',
          angle: 150.0,
          isValid: true,
        ),
        'tornozelo_esq': const JointAngleData(
          key: 'tornozelo_esq',
          label: 'Tornozelo / Panturrilha Esq.',
          angle: 98.0,
          isValid: true,
        ),
      };
      tracker.update(mockFrame1, 0.5, calfLeftPct: 12.0, calfRightPct: 10.0);

      final mockFrame2 = {
        'cotovelo_esq': const JointAngleData(
          key: 'cotovelo_esq',
          label: 'Cotovelo Esquerdo',
          angle: 60.0,
          isValid: true,
        ),
        'tornozelo_esq': const JointAngleData(
          key: 'tornozelo_esq',
          label: 'Tornozelo / Panturrilha Esq.',
          angle: 142.0,
          isValid: true,
        ),
      };
      tracker.update(mockFrame2, 1.0, calfLeftPct: 78.5, calfRightPct: 75.0);

      final record = tracker.records['cotovelo_esq'];
      expect(record, isNotNull);
      expect(record!.minAngle, 60.0);
      expect(record.maxAngle, 150.0);
      expect(record.rom, 90.0);

      final ankleRecord = tracker.records['tornozelo_esq'];
      expect(ankleRecord!.rom, 44.0);
      expect(tracker.maxCalfElevationLeftPct, 78.5);
    });
  });

  group('ProtocolService - Posicionamento e Posturas de Exemplo', () {
    test('Detecta distância ideal, centralização e visibilidade dos calcanhares', () {
      final protocol = ProtocolService();
      const screenSize = Size(400, 800);

      final goodLandmarks = {
        'NOSE': const Point2D(200, 180),
        'LEFT_SHOULDER': const Point2D(165, 250),
        'RIGHT_SHOULDER': const Point2D(235, 250),
        'LEFT_ELBOW': const Point2D(150, 340),
        'RIGHT_ELBOW': const Point2D(250, 340),
        'LEFT_WRIST': const Point2D(145, 420),
        'RIGHT_WRIST': const Point2D(255, 420),
        'LEFT_HIP': const Point2D(175, 430),
        'RIGHT_HIP': const Point2D(225, 430),
        'LEFT_KNEE': const Point2D(175, 550),
        'RIGHT_KNEE': const Point2D(225, 550),
        'LEFT_ANKLE': const Point2D(175, 660),
        'RIGHT_ANKLE': const Point2D(225, 660),
        'LEFT_HEEL': const Point2D(178, 680),
        'RIGHT_HEEL': const Point2D(222, 680),
        'LEFT_FOOT_INDEX': const Point2D(165, 685),
        'RIGHT_FOOT_INDEX': const Point2D(235, 685),
      };

      final poseData = ExtractedPoseData(
        angles: const {},
        landmarks: goodLandmarks,
        bodyOrientationAngle: 10.0,
        bodyOrientationLabel: 'Frontal',
      );

      final assessment = protocol.evaluatePositioning(poseData, screenSize, 0.0);
      expect(assessment.areAllPointsVisible, isTrue);
      expect(assessment.isDistanceGood, isTrue);
      expect(assessment.isCentered, isTrue);
      expect(assessment.isAngleGood, isTrue);
      expect(assessment.isAllGood, isTrue);

      // Após segurar por 2.1 segundos na posição ideal, avança para a Etapa 2 (postureReplication)
      protocol.update(poseData, screenSize, 0.0);
      expect(protocol.stage, ProtocolStage.positioning);
      final transitioned = protocol.update(poseData, screenSize, 2.2);
      expect(transitioned, isTrue);
      expect(protocol.stage, ProtocolStage.postureReplication);
    });

    test('Avalia replicação da postura de Elevação de Panturrilha (Postura 3)', () {
      final protocol = ProtocolService(stage: ProtocolStage.postureReplication);
      protocol.currentPostureIndex = 2; // 3. Elevação de Panturrilha
      expect(protocol.currentPosture.id, 'elevacao_panturrilha');

      const screenSize = Size(400, 800);
      const calfPose = ExtractedPoseData(
        landmarks: {
          'NOSE': Point2D(200, 180),
          'LEFT_HEEL': Point2D(178, 660),
          'RIGHT_HEEL': Point2D(222, 660),
          'LEFT_FOOT_INDEX': Point2D(165, 685),
          'RIGHT_FOOT_INDEX': Point2D(235, 685),
        },
        angles: {
          'tornozelo_esq': JointAngleData(
            key: 'tornozelo_esq',
            label: 'Tornozelo Esq.',
            angle: 135.0,
            isValid: true,
          ),
          'tornozelo_dir': JointAngleData(
            key: 'tornozelo_dir',
            label: 'Tornozelo Dir.',
            angle: 134.0,
            isValid: true,
          ),
          'joelho_esq': JointAngleData(
            key: 'joelho_esq',
            label: 'Joelho Esq.',
            angle: 172.0,
            isValid: true,
          ),
          'joelho_dir': JointAngleData(
            key: 'joelho_dir',
            label: 'Joelho Dir.',
            angle: 171.0,
            isValid: true,
          ),
        },
        calfElevationLeftPct: 65.0,
        calfElevationRightPct: 62.0,
      );

      protocol.update(calfPose, screenSize, 1.0);
      expect(protocol.currentPostureAccuracyPct, greaterThanOrEqualTo(90.0));

      // Mantém a postura por 2.6s para aprovar e avançar
      final completed = protocol.update(calfPose, screenSize, 3.6);
      expect(completed, isTrue);
      expect(protocol.completedPostures.length, 1);
      expect(protocol.completedPostures.first.postureId, 'elevacao_panturrilha');
      expect(protocol.completedPostures.first.mobilityStatus, 'Mobilidade Plena');
      expect(protocol.currentPostureIndex, 3);
    });

    test('Detecta faltas de mobilidade automaticamente após janela de avaliação quando usuário não atinge o ângulo alvo', () {
      final protocol = ProtocolService(stage: ProtocolStage.postureReplication);
      protocol.currentPostureIndex = 1; // 2. Abdução de Ombros (Braços em T - 90°)
      const screenSize = Size(400, 800);

      // Usuário com restrição no ombro esquerdo (sobe só até 48° em vez de 90°)
      const restrictedPose = ExtractedPoseData(
        landmarks: {
          'NOSE': Point2D(200, 180),
        },
        angles: {
          'ombro_esq': JointAngleData(
            key: 'ombro_esq',
            label: 'Ombro Esq.',
            angle: 48.0,
            isValid: true,
          ),
          'ombro_dir': JointAngleData(
            key: 'ombro_dir',
            label: 'Ombro Dir.',
            angle: 88.0,
            isValid: true,
          ),
          'cotovelo_esq': JointAngleData(
            key: 'cotovelo_esq',
            label: 'Cotovelo Esq.',
            angle: 168.0,
            isValid: true,
          ),
          'cotovelo_dir': JointAngleData(
            key: 'cotovelo_dir',
            label: 'Cotovelo Dir.',
            angle: 170.0,
            isValid: true,
          ),
          'joelho_esq': JointAngleData(
            key: 'joelho_esq',
            label: 'Joelho Esq.',
            angle: 172.0,
            isValid: true,
          ),
          'joelho_dir': JointAngleData(
            key: 'joelho_dir',
            label: 'Joelho Dir.',
            angle: 172.0,
            isValid: true,
          ),
        },
      );

      protocol.update(restrictedPose, screenSize, 0.0);
      // Ao completar os 8 segundos da janela de avaliação de mobilidade, avança e registra o déficit
      final finishedWindow = protocol.update(restrictedPose, screenSize, 8.2);
      expect(finishedWindow, isTrue);
      expect(protocol.completedPostures.length, 1);

      final result = protocol.completedPostures.first;
      expect(result.postureId, 'bracos_t');
      expect(result.completedByIdealHold, isFalse);
      expect(result.deficits, isNotEmpty);
      expect(
        result.deficits.any((d) => d.jointKey == 'ombro_esq'),
        isTrue,
      );
      expect(
        result.deficits.any((d) => d.jointKey == 'assimetria_ombros'),
        isTrue,
      );
    });
  });

  group('OneEuroFilter', () {
    test('Suaviza sinal ruidoso mantendo convergência', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      final v1 = filter.filter(90.0, 0.0);
      final v2 = filter.filter(92.0, 0.033);
      expect(v1, 90.0);
      expect(v2, greaterThan(90.0));
      expect(v2, lessThan(92.0));
    });
  });

  group('RepCounterService e MotionTrailService', () {
    test('Contabiliza repetição de agachamento e trilha', () {
      final counter = RepCounterService(initialExercise: 'squat');
      counter.update({'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 165.0, isValid: true)}, 0.0);
      counter.update({'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 120.0, isValid: true)}, 0.5);
      counter.update({'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 85.0, isValid: true)}, 1.0);
      counter.update({'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 130.0, isValid: true)}, 1.5);
      final rep = counter.update({'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 162.0, isValid: true)}, 2.0);

      expect(rep, isNotNull);
      expect(counter.repCount, 1);

      final trail = MotionTrailService(maxLength: 4, enabled: true);
      for (int i = 0; i < 6; i++) {
        trail.update({'LEFT_WRIST': Point2D(100.0 + i, 200.0 + i)});
      }
      expect(trail.trails['LEFT_WRIST']!.length, 4);
    });
  });
}
