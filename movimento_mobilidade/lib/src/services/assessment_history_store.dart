import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assessment_models.dart';

/// Persistência local do histórico de avaliações (JSON em SharedPreferences).
class AssessmentHistoryStore {
  static const String _key = 'assessment_history_v1';

  Future<List<AssessmentRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AssessmentRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<AssessmentRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  Future<void> add(AssessmentRecord record) async {
    final all = await loadAll();
    all.add(record);
    await _saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((r) => r.id == id);
    await _saveAll(all);
  }

  /// Número sequencial do próximo teste deste voluntário (1, 2, 3...).
  Future<int> nextTestNumber(String volunteerCode) async {
    final all = await loadAll();
    final mine = all.where((r) => r.volunteerCode.toLowerCase() == volunteerCode.toLowerCase());
    if (mine.isEmpty) return 1;
    return mine.map((r) => r.testNumber).reduce((a, b) => a > b ? a : b) + 1;
  }
}
