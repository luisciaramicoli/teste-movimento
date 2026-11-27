import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assessment_models.dart';

/// Persistência local do histórico de avaliações (JSON em SharedPreferences).
///
/// Dados que não podem ser lidos nunca são apagados por uma gravação: um
/// registro ilegível continua na lista como está, e um conteúdo que não é uma
/// lista JSON é copiado para outra chave antes de ser substituído.
class AssessmentHistoryStore {
  static const String _key = 'assessment_history_v1';
  static const String _backupPrefix = '${_key}_backup_';

  /// Avaliações legíveis, da mais recente para a mais antiga.
  Future<List<AssessmentRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = <AssessmentRecord>[];
    for (final entry in _decode(prefs.getString(_key)) ?? const []) {
      final record = _parse(entry);
      if (record != null) list.add(record);
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> add(AssessmentRecord record) =>
      _update((entries) => entries.add(record.toJson()));

  Future<void> delete(String id) => _update(
      (entries) => entries.removeWhere((e) => e is Map && e['id'] == id));

  /// Número sequencial do próximo teste deste voluntário (1, 2, 3...).
  /// Considera também os registros ilegíveis, para não repetir números.
  Future<int> nextTestNumber(String volunteerCode) async {
    final prefs = await SharedPreferences.getInstance();
    final wanted = volunteerCode.toLowerCase();
    var last = 0;
    for (final entry in _decode(prefs.getString(_key)) ?? const []) {
      if (entry is! Map) continue;
      final code = entry['volunteerCode'];
      final number = entry['testNumber'];
      if (code is String &&
          code.trim().toLowerCase() == wanted &&
          number is num &&
          number > last) {
        last = number.toInt();
      }
    }
    return last + 1;
  }

  /// Aplica [change] às entradas gravadas, sem passar pelo modelo.
  Future<void> _update(void Function(List<dynamic> entries) change) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    var entries = _decode(raw);
    if (entries == null) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      if (!await prefs.setString('$_backupPrefix$stamp', raw!)) {
        throw StateError('Não foi possível preservar o histórico anterior.');
      }
      entries = [];
    }
    change(entries);
    await prefs.setString(_key, jsonEncode(entries));
  }

  /// Lista vazia se não há histórico; `null` se o conteúdo não é uma lista JSON.
  List<dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  AssessmentRecord? _parse(dynamic entry) {
    try {
      return AssessmentRecord.fromJson(Map<String, dynamic>.from(entry as Map));
    } catch (_) {
      return null;
    }
  }
}
