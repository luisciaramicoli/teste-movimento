import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assessment_models.dart';
import '../services/assessment_csv.dart';
import '../services/assessment_history_store.dart';
import '../theme/app_theme.dart';
import 'assessment_summary.dart';

String formatDateTime(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year}  ${p(d.hour)}:${p(d.minute)}';
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _store = AssessmentHistoryStore();
  List<AssessmentRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _store.loadAll();
    if (mounted) setState(() => _records = r);
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final byVolunteer = <String, List<AssessmentRecord>>{};
    for (final r in records ?? const <AssessmentRecord>[]) {
      byVolunteer.putIfAbsent(r.volunteerCode, () => []).add(r);
    }
    final codes = byVolunteer.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: records == null
          ? const SizedBox.shrink()
          : records.isEmpty
              ? const Center(
                  child: Text('Nenhuma avaliação salva.', style: AppText.muted))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final code in codes) ...[
                      Row(children: [
                        Text('VOLUNTÁRIO $code', style: AppText.label),
                        const Spacer(),
                        if (byVolunteer[code]!.length >= 2)
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => RepeatabilityScreen(
                                        code: code,
                                        records: byVolunteer[code]!))),
                            child: const Text('Repetibilidade'),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Card(
                        child: Column(children: [
                          for (var i = 0; i < byVolunteer[code]!.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              title: Text(
                                  'Teste ${byVolunteer[code]![i].testNumber}'),
                              subtitle: Text(
                                  formatDateTime(byVolunteer[code]![i].createdAt),
                                  style: AppText.muted),
                              trailing: const Icon(Icons.chevron_right,
                                  color: AppColors.textSecondary),
                              onTap: () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => AssessmentDetailScreen(
                                            record: byVolunteer[code]![i])));
                                _load();
                              },
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
    );
  }
}

class AssessmentDetailScreen extends StatelessWidget {
  final AssessmentRecord record;
  final bool justSaved;
  const AssessmentDetailScreen(
      {super.key, required this.record, this.justSaved = false});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.border)),
        title: const Text('Excluir avaliação?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await AssessmentHistoryStore().delete(record.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${record.volunteerCode}  ·  Teste ${record.testNumber}'),
        actions: [
          IconButton(
            tooltip: 'Copiar CSV',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: AssessmentCsv.build(record)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CSV copiado.')));
              }
            },
          ),
          if (!justSaved)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(formatDateTime(record.createdAt), style: AppText.muted),
            Text('Motor: ${record.engine}', style: AppText.muted),
            if (justSaved) ...[
              const SizedBox(height: 12),
              const Row(children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: AppColors.ok),
                SizedBox(width: 8),
                Text('Avaliação salva no histórico.',
                    style: TextStyle(color: AppColors.ok)),
              ]),
            ],
            const SizedBox(height: 16),
            for (final m in record.movements) ...[
              MovementResultCard(result: m),
              const SizedBox(height: 12),
            ],
            if (justSaved) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Concluir'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compara as médias articulares entre testes do mesmo voluntário e mesmo
/// movimento, para validar a repetibilidade do modelo.
class RepeatabilityScreen extends StatelessWidget {
  final String code;
  final List<AssessmentRecord> records;
  const RepeatabilityScreen(
      {super.key, required this.code, required this.records});

  @override
  Widget build(BuildContext context) {
    final tests = [...records]..sort((a, b) => a.testNumber.compareTo(b.testNumber));
    return Scaffold(
      appBar: AppBar(title: Text('Repetibilidade  ·  $code')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
                'Média por articulação em cada teste, desvio padrão (DP) e variação máxima entre testes. ${tests.length} testes.',
                style: AppText.muted),
            const SizedBox(height: 16),
            for (final spec in kProtocolMovements) ...[
              _movementCard(spec, tests),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _movementCard(MovementSpec spec, List<AssessmentRecord> tests) {
    final rows = <TableRow>[
      TableRow(children: [
        const _H('ARTICULAÇÃO', left: true),
        for (final t in tests) _H('T${t.testNumber}'),
        const _H('DP'),
        const _H('VAR.'),
      ]),
    ];
    for (final j in spec.joints) {
      final vals = [
        for (final t in tests) t.movement(spec.id)?.averages[j],
      ];
      final present = vals.whereType<double>().toList();
      if (present.isEmpty) continue;
      final sd = present.length >= 2 ? stdDev(present) : null;
      final range = present.length >= 2
          ? present.reduce((a, b) => a > b ? a : b) -
              present.reduce((a, b) => a < b ? a : b)
          : null;
      rows.add(TableRow(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border))),
        children: [
          _V(jointLabel(j), left: true),
          for (final v in vals) _V(v == null ? '–' : '${v.toStringAsFixed(1)}°'),
          _V(sd == null ? '–' : sd.toStringAsFixed(1)),
          _V(range == null ? '–' : '${range.toStringAsFixed(1)}°', strong: true),
        ],
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Table(
              columnWidths: const {0: FlexColumnWidth(2.2)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: rows,
            ),
          ],
        ),
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  final bool left;
  const _H(this.t, {this.left = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Text(t,
            textAlign: left ? TextAlign.left : TextAlign.right,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppColors.textSecondary)),
      );
}

class _V extends StatelessWidget {
  final String t;
  final bool left;
  final bool strong;
  const _V(this.t, {this.left = false, this.strong = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Text(t,
            textAlign: left ? TextAlign.left : TextAlign.right,
            style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? AppColors.accent : AppColors.textPrimary)),
      );
}
