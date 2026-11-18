import 'package:flutter/material.dart';

import '../models/assessment_models.dart';
import '../theme/app_theme.dart';

/// Tabela de resultados de um movimento: repetições, média e desvio padrão.
class MovementResultCard extends StatelessWidget {
  final MovementResult result;
  const MovementResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final spec = result.spec;
    final avgs = result.averages;
    final sds = result.deviations;
    final joints = spec?.joints ?? avgs.keys.toList();
    final repCount = result.reps.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec?.title ?? result.movementId,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${spec?.viewLabel ?? ''}  ·  $repCount repetições',
                style: AppText.muted),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {0: FlexColumnWidth(2.2)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(children: [
                  const _Cell('ARTICULAÇÃO', header: true),
                  for (var i = 1; i <= repCount; i++) _Cell('R$i', header: true),
                  const _Cell('MÉDIA', header: true),
                  const _Cell('DP', header: true),
                ]),
                for (final j in joints)
                  if (avgs.containsKey(j))
                    TableRow(
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: AppColors.border)),
                      ),
                      children: [
                        _Cell(jointLabel(j), left: true),
                        for (final r in result.reps)
                          _Cell(r.angles[j] == null
                              ? '–'
                              : '${r.angles[j]!.toStringAsFixed(0)}°'),
                        _Cell('${avgs[j]!.toStringAsFixed(1)}°', strong: true),
                        _Cell(sds[j] == null
                            ? '–'
                            : sds[j]!.toStringAsFixed(1)),
                      ],
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool header;
  final bool strong;
  final bool left;
  const _Cell(this.text,
      {this.header = false, this.strong = false, this.left = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Text(
        text,
        textAlign: left || header && text == 'ARTICULAÇÃO'
            ? TextAlign.left
            : TextAlign.right,
        style: header
            ? const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppColors.textSecondary)
            : TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? AppColors.accent : AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
      ),
    );
  }
}
