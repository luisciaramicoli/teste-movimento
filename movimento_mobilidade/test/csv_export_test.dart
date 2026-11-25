import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/src/models/joint_angle.dart';
import 'package:movimento_mobilidade/src/models/protocol_models.dart';
import 'package:movimento_mobilidade/src/services/performance_monitor.dart';
import 'package:movimento_mobilidade/src/services/session_csv_exporter.dart';

void main() {
  test('aceita só código anônimo do voluntário (RF10)', () {
    expect(SessionCsvExporter.isValidVolunteerCode('V01'), isTrue);
    expect(SessionCsvExporter.isValidVolunteerCode(' v12 '), isTrue);
    expect(SessionCsvExporter.normalizeCode(' v12 '), 'V12');
    for (final nome in ['João da Silva', 'Maria', 'V1', 'V01 Maria', 'A', '']) {
      expect(SessionCsvExporter.isValidVolunteerCode(nome), isFalse,
          reason: 'deveria recusar "$nome"');
    }
  });

  test('CSV segue o esquema e usa só o código (RF09/RF10)', () {
    final tracker = JointAngleTracker();
    tracker.update({
      'ombro_esq': const JointAngleData(
          key: 'ombro_esq', label: 'Ombro', angle: 20.0, isValid: true)
    }, 0.0);
    tracker.update({
      'ombro_esq': const JointAngleData(
          key: 'ombro_esq', label: 'Ombro', angle: 90.0, isValid: true)
    }, 1.0);
    final csv = SessionCsvExporter.build(
      volunteerCode: 'v01',
      when: DateTime(2026, 11, 13, 10, 0),
      tracker: tracker,
      postures: const [
        PostureEvaluationResult(
          postureId: 'bracos_t',
          postureTitle: '2. Abdução de Ombros (Braços em T)',
          gifAssetPath: '',
          accuracyScorePct: 90,
          capturedAngles: {'ombro_esq': 88.5},
          targetAngles: {},
          maxCalfElevationPct: 0,
          completionTimeSec: 5,
          mobilityStatus: 'Plena',
        )
      ],
    );
    final lines = csv.trim().split('\n');
    expect(lines.first, SessionCsvExporter.header.join(','));
    expect(lines[1],
        '2026-11-13T10:00:00.000,V01,2. Abdução de Ombros (Braços em T),esquerdo,ombro,88.5,,20.0,90.0');
  });

  test('exportação recusa nome (RF10)', () {
    expect(
      () => SessionCsvExporter.build(
        volunteerCode: 'Maria Silva',
        when: DateTime.now(),
        tracker: JointAngleTracker(),
        postures: const [],
      ),
      throwsArgumentError,
    );
  });

  test('PerformanceMonitor calcula FPS e latência', () {
    final m = PerformanceMonitor();
    for (int i = 0; i < 31; i++) {
      m.record(captureMs: i * 40, displayMs: i * 40 + 50);
    }
    expect(m.avgFps, closeTo(25.0, 0.01));
    expect(m.avgLatencyMs, 50.0);
    expect(m.maxLatencyMs, 50);
  });
}
