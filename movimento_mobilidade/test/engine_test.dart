import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/src/models/assessment_models.dart';
import 'package:movimento_mobilidade/src/services/pose_camera_session.dart';

void main() {
  test('nome do motor distingue MediaPipe (com delegate) de ML Kit', () {
    expect(PoseCameraSession.engineLabel(usedNative: true, delegate: 'GPU'),
        'MediaPipe Pose Landmarker lite (GPU)');
    expect(PoseCameraSession.engineLabel(usedNative: false, delegate: ''),
        'ML Kit Pose Detection (base)');
  });

  test('sem motor informado, o registro não presume um', () {
    final record = AssessmentRecord(
        id: '1',
        createdAt: DateTime(2026),
        volunteerCode: 'V01',
        testNumber: 1,
        movements: const []);
    expect(record.engine, AssessmentRecord.unknownEngine);
    final json = record.toJson()..remove('engine');
    expect(AssessmentRecord.fromJson(json).engine,
        AssessmentRecord.unknownEngine);
  });

  AssessmentRecord read(String engine) => AssessmentRecord.fromJson(
      AssessmentRecord(
              id: '1',
              createdAt: DateTime(2026),
              volunteerCode: 'V01',
              testNumber: 1,
              movements: const [],
              engine: engine)
          .toJson());

  test('citação fixa de versões anteriores é descartada na leitura', () {
    for (final legacy in [
      'Google ML Kit Pose Detection (base)',
      'Google ML Kit Pose Detection',
    ]) {
      expect(read(legacy).engine, AssessmentRecord.unknownEngine);
    }
  });

  test('motor registrado de fato é preservado na leitura', () {
    for (final usedNative in [true, false]) {
      final label = PoseCameraSession.engineLabel(
          usedNative: usedNative, delegate: 'CPU');
      expect(read(label).engine, label);
    }
  });
}
