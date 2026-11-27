import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

/// Aparelho sem câmera utilizável; conta quantas vezes ela foi procurada.
class _NoCamera extends CameraPlatform {
  _NoCamera({this.fails = false});

  final bool fails;
  int searches = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    searches++;
    if (fails) throw CameraException('CameraAccessDenied', 'negado');
    return const [];
  }
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Desmonta a tela para encerrar o ticker e o timer.
Future<void> _close(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  for (final fails in [false, true]) {
    final caso = fails ? 'câmera com falha' : 'aparelho sem câmera';
    testWidgets('$caso: mostra erro e permite tentar de novo', (tester) async {
      final platform = _NoCamera(fails: fails);
      CameraPlatform.instance = platform;
      await _open(tester);

      expect(find.text('Câmera indisponível'), findsOneWidget);

      // Tentar de novo consulta o aparelho outra vez, sem usar cache.
      final before = platform.searches;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(platform.searches, before + 1);
      expect(find.text('Câmera indisponível'), findsOneWidget);
      await _close(tester);
    });
  }
}
