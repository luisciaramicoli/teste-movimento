import 'package:flutter_test/flutter_test.dart';
import 'package:teste_movimento_app/models/joint_angle.dart';
import 'package:teste_movimento_app/services/rep_counter_service.dart';
import 'package:teste_movimento_app/services/motion_trail_service.dart';

void main() {
  group('Geometria e Cálculo Angular em Dart', () {
    test('Calcula ângulo reto de 90 graus', () {
      final a = const Point2D(0, 1);
      final b = const Point2D(0, 0);
      final c = const Point2D(1, 0);

      final angle = calculateAngle(a, b, c);
      expect(angle, closeTo(90.0, 0.1));
    });

    test('Calcula ângulo reto de 180 graus (linha reta)', () {
      final a = const Point2D(-1, 0);
      final b = const Point2D(0, 0);
      final c = const Point2D(1, 0);

      final angle = calculateAngle(a, b, c);
      expect(angle, closeTo(180.0, 0.1));
    });

    test('Calcula ângulo agudo de 45 graus', () {
      final a = const Point2D(1, 1);
      final b = const Point2D(0, 0);
      final c = const Point2D(1, 0);

      final angle = calculateAngle(a, b, c);
      expect(angle, closeTo(45.0, 0.1));
    });
  });

  group('JointAngleTracker', () {
    test('Rastreia amplitude mínima, máxima e ROM corretamente', () {
      final tracker = JointAngleTracker();

      final mockFrame1 = {
        'cotovelo_esq': const JointAngleData(
          key: 'cotovelo_esq',
          label: 'Cotovelo Esquerdo',
          angle: 150.0,
          isValid: true,
        ),
      };
      tracker.update(mockFrame1, 0.5);

      final mockFrame2 = {
        'cotovelo_esq': const JointAngleData(
          key: 'cotovelo_esq',
          label: 'Cotovelo Esquerdo',
          angle: 60.0,
          isValid: true,
        ),
      };
      tracker.update(mockFrame2, 1.0);

      final record = tracker.records['cotovelo_esq'];
      expect(record, isNotNull);
      expect(record!.minAngle, 60.0);
      expect(record.maxAngle, 150.0);
      expect(record.rom, 90.0);
      expect(record.averageAngle, 105.0);
    });
  });

  group('RepCounterService', () {
    test('Contabiliza repetição de agachamento com máquina de estados', () {
      final counter = RepCounterService(initialExercise: 'squat');
      expect(counter.repCount, 0);

      // 1. Inicia em pé (165°)
      counter.update({
        'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 165.0, isValid: true),
      }, 0.0);

      // 2. Desce até o pico do agachamento (85°)
      counter.update({
        'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 120.0, isValid: true),
      }, 0.5);
      counter.update({
        'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 85.0, isValid: true),
      }, 1.0);

      // 3. Sobe de volta até a posição estendida (160°)
      counter.update({
        'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 130.0, isValid: true),
      }, 1.5);
      final rep = counter.update({
        'joelho_esq': const JointAngleData(key: 'joelho_esq', label: 'Joelho', angle: 162.0, isValid: true),
      }, 2.0);

      expect(rep, isNotNull);
      expect(counter.repCount, 1);
      expect(rep!.isValid, isTrue);
      expect(rep.totalDuration, greaterThan(0.5));
      expect(rep.rom, greaterThan(60.0));
    });

    test('Contabiliza repetição de rosca bíceps', () {
      final counter = RepCounterService(initialExercise: 'curl');
      counter.update({'cotovelo_esq': const JointAngleData(key: 'cotovelo_esq', label: 'Cotovelo', angle: 150.0, isValid: true)}, 0.0);
      counter.update({'cotovelo_esq': const JointAngleData(key: 'cotovelo_esq', label: 'Cotovelo', angle: 90.0, isValid: true)}, 0.5);
      counter.update({'cotovelo_esq': const JointAngleData(key: 'cotovelo_esq', label: 'Cotovelo', angle: 45.0, isValid: true)}, 1.0);
      counter.update({'cotovelo_esq': const JointAngleData(key: 'cotovelo_esq', label: 'Cotovelo', angle: 110.0, isValid: true)}, 1.5);
      final rep = counter.update({'cotovelo_esq': const JointAngleData(key: 'cotovelo_esq', label: 'Cotovelo', angle: 148.0, isValid: true)}, 2.0);

      expect(rep, isNotNull);
      expect(counter.repCount, 1);
      expect(rep!.repNumber, 1);
    });
  });

  group('MotionTrailService', () {
    test('Armazena e limita histórico da trilha de movimento', () {
      final trail = MotionTrailService(maxLength: 4, enabled: true);

      for (int i = 0; i < 8; i++) {
        trail.update({
          'LEFT_WRIST': Point2D(100.0 + i, 200.0 + i),
        });
      }

      expect(trail.trails['LEFT_WRIST']!.length, 4);

      trail.toggle();
      expect(trail.enabled, isFalse);
      expect(trail.trails['LEFT_WRIST']!.length, 0);
    });
  });
}

