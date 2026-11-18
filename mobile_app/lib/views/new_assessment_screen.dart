import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assessment_models.dart';
import '../services/assessment_history_store.dart';
import '../services/session_csv_exporter.dart';
import '../theme/app_theme.dart';
import 'assessment_screen.dart';

class NewAssessmentScreen extends StatefulWidget {
  const NewAssessmentScreen({super.key});

  @override
  State<NewAssessmentScreen> createState() => _NewAssessmentScreenState();
}

class _NewAssessmentScreenState extends State<NewAssessmentScreen> {
  final _controller = TextEditingController();
  final _store = AssessmentHistoryStore();
  String? _error;
  int? _nextTest;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String v) async {
    final code = SessionCsvExporter.normalizeCode(v);
    if (SessionCsvExporter.isValidVolunteerCode(code)) {
      final n = await _store.nextTestNumber(code);
      if (mounted) setState(() => _nextTest = n);
    } else if (_nextTest != null) {
      setState(() => _nextTest = null);
    }
  }

  Future<void> _start() async {
    final code = SessionCsvExporter.normalizeCode(_controller.text);
    if (!SessionCsvExporter.isValidVolunteerCode(code)) {
      setState(() => _error = 'Digite o nome do voluntário (mínimo 2 letras).');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final n = await _store.nextTestNumber(code);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AssessmentScreen(volunteerCode: code, testNumber: n)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova avaliação')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('VOLUNTÁRIO', style: AppText.label),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                LengthLimitingTextInputFormatter(60),
              ],
              onChanged: _onChanged,
              decoration: InputDecoration(
                labelText: 'Nome do voluntário',
                hintText: 'Ex.: Maria Silva',
                errorText: _error,
                helperText: _nextTest == null
                    ? 'O nome aparece no histórico e na exportação CSV.'
                    : 'Este será o teste nº $_nextTest deste voluntário.',
              ),
            ),
            const SizedBox(height: 28),
            const Text('PROTOCOLO', style: AppText.label),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < kProtocolMovements.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Text('${i + 1}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent)),
                      title: Text(kProtocolMovements[i].title),
                      subtitle: Text(
                          '${kProtocolMovements[i].viewLabel}  ·  ${kProtocolMovements[i].repetitions} repetições',
                          style: AppText.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
                'Em cada movimento é registrado o ângulo de ombro, quadril, joelho e tornozelo no pico de cada repetição, e calculada a média das três.',
                style: AppText.muted),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _start,
              child: const Text('Iniciar'),
            ),
          ],
        ),
      ),
    );
  }
}
