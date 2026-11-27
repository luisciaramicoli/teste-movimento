import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/src/models/assessment_models.dart';
import 'package:movimento_mobilidade/src/views/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Relatório envia o PDF da avaliação exibida ao Android',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('movimento/relatorio');
    final messenger = tester.binding.defaultBinaryMessenger;
    MethodCall? export;
    messenger.setMockMethodCallHandler(channel, (call) async {
      export = call;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final record = AssessmentRecord(
      id: 'teste',
      createdAt: DateTime(2026, 11, 26),
      volunteerCode: 'V02',
      testNumber: 4,
      idade: 25,
      pesoKg: 80,
      movements: const [],
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(record: record)));
    await tester.pumpAndSettle();
    expect(find.text('Alcance'), findsNothing);
    expect(find.text('25 anos'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);
    await tester.tap(find.text('Relatório'));
    await tester.pumpAndSettle();
    expect(export?.method, 'salvarPdf');
    expect(export!.arguments['nome'], 'Mobilidade-V02-teste-4.pdf');
    final bytes = export!.arguments['bytes'] as Uint8List;
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(find.text('Relatório PDF salvo.'), findsOneWidget);
  });
}
