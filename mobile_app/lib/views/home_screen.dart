import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'new_assessment_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text('MOVEMENT', style: AppText.label),
              const SizedBox(height: 6),
              const Text('Avaliação biomecânica', style: AppText.title),
              const SizedBox(height: 8),
              const Text(
                  'Medição de ângulos articulares de ombro, quadril, joelho e tornozelo por visão computacional.',
                  style: AppText.muted),
              const SizedBox(height: 32),
              const Divider(height: 1),
              const _Row('Movimentos', 'Abdução de ombro; agachamento (perfil direito)'),
              const Divider(height: 1),
              const _Row('Repetições', '3 por movimento, com média por articulação'),
              const Divider(height: 1),
              const _Row('Motor de pose', 'Google ML Kit Pose Detection'),
              const Divider(height: 1),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NewAssessmentScreen())),
                child: const Text('Nova avaliação'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen())),
                child: const Text('Histórico'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String k;
  final String v;
  const _Row(this.k, this.v);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: AppText.muted)),
            Expanded(child: Text(v, style: AppText.body)),
          ],
        ),
      );
}
