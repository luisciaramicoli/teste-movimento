import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

PostureEvaluationResult _posture(
        double accuracy, List<MobilityDeficitItem> deficits) =>
    PostureEvaluationResult(
      postureId: 'p$accuracy',
      postureTitle: 'Postura',
      gifAssetPath: '',
      accuracyScorePct: accuracy,
      capturedAngles: const {},
      targetAngles: const {},
      maxCalfElevationPct: 0,
      completionTimeSec: 1,
      mobilityStatus: 'Mobilidade Parcial',
      deficits: deficits,
    );

void main() {
  test('o protocolo devolve score e restrições já calculados', () {
    const deficit = MobilityDeficitItem(
        postureId: 'p',
        postureTitle: 'Postura',
        jointKey: 'joelho_dir',
        jointLabel: 'Joelho Dir.',
        achievedValue: 140,
        targetValue: 105,
        severity: 'Leve',
        description: '');
    final result = ProtocolSessionResult(engine: 'x', postures: [
      _posture(80, const [deficit]),
      _posture(60, const []),
    ]);
    expect(result.score, 70);
    expect(result.deficits, [deficit]);
    expect(const ProtocolSessionResult(postures: [], engine: '').score, 0);
  });
}
