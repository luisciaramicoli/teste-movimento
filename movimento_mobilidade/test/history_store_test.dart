import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/src/models/assessment_models.dart';
import 'package:movimento_mobilidade/src/services/assessment_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'assessment_history_v1';

AssessmentRecord _record(String id, {int testNumber = 1}) => AssessmentRecord(
      id: id,
      createdAt: DateTime(2026, 11, 20, 10, testNumber),
      volunteerCode: 'V01',
      testNumber: testNumber,
      movements: const [],
    );

/// Registro que `fromJson` não consegue ler (sem data nem movimentos).
const _unreadable = {'id': 'ruim', 'volunteerCode': 'V01', 'testNumber': 7};

Future<List<dynamic>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString(_key)!) as List;
}

List<String> _ids(Iterable<dynamic> raw) =>
    [for (final e in raw) (e as Map)['id'] as String];

void main() {
  final store = AssessmentHistoryStore();

  void seed(String raw) => SharedPreferences.setMockInitialValues({_key: raw});

  group('um registro ilegível', () {
    setUp(() => seed(jsonEncode(
        [_record('a').toJson(), _unreadable, 'lixo', _record('b').toJson()])));

    test('não esconde os demais', () async {
      expect((await store.loadAll()).map((r) => r.id).toSet(), {'a', 'b'});
    });

    test('nada é apagado ao salvar outra avaliação', () async {
      await store.add(_record('c', testNumber: 8));
      final raw = await _stored();
      expect(raw, hasLength(5));
      expect(raw, contains('lixo'));
      expect(_ids(raw.whereType<Map>()), ['a', 'ruim', 'b', 'c']);
    });

    test('delete remove só o pedido', () async {
      await store.delete('a');
      final raw = await _stored();
      expect(_ids(raw.whereType<Map>()), ['ruim', 'b']);
      expect(raw, contains('lixo'));
    });

    test('o número do teste dele não é reutilizado', () async {
      expect(await store.nextTestNumber('v01'), 8);
    });
  });

  for (final entry in {
    'JSON truncado': '[{"id":"a"',
    'JSON que não é lista': '{"id":"a"}',
  }.entries) {
    test('${entry.key}: o conteúdo original é copiado antes de regravar',
        () async {
      seed(entry.value);
      expect(await store.loadAll(), isEmpty);

      await store.add(_record('novo'));

      final prefs = await SharedPreferences.getInstance();
      final backups =
          prefs.getKeys().where((k) => k.startsWith('${_key}_backup_'));
      expect(backups.map(prefs.getString), [entry.value]);
      expect(_ids(await _stored()), ['novo']);
    });
  }

  test('histórico vazio não gera cópia de segurança', () async {
    SharedPreferences.setMockInitialValues({});
    await store.add(_record('a'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {_key});
  });
}
