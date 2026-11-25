import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

/// App de exemplo: mostra como chamar a biblioteca e usar o resultado.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MovimentoMobilidade.inicializar();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ExemploApp());
}

class ExemploApp extends StatelessWidget {
  const ExemploApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exemplo - Movimento Mobilidade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const ExemploHome(),
    );
  }
}

class ExemploHome extends StatefulWidget {
  const ExemploHome({super.key});

  @override
  State<ExemploHome> createState() => _ExemploHomeState();
}

class _ExemploHomeState extends State<ExemploHome> {
  AssessmentRecord? _ultima;
  final TextEditingController _idadeController =
      TextEditingController(text: '25');
  final TextEditingController _pesoController =
      TextEditingController(text: '70');

  final TextEditingController _codigoController =
      TextEditingController(text: 'V01');

  @override
  void dispose() {
    _codigoController.dispose();
    _idadeController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  Future<void> _avaliar() async {
    final idade = int.tryParse(_idadeController.text.trim()) ?? 25;
    final peso =
        double.tryParse(_pesoController.text.trim().replaceAll(',', '.')) ??
            70.0;

    final codigo = _codigoController.text;
    if (!VolunteerCode.isValid(codigo)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Use um código como V01. Não digite nomes.')));
      return;
    }

    final r = await MovimentoMobilidade.iniciarAvaliacao(context,
        voluntario: codigo,
        perfil: PerfilAvaliado(
            idade: idade,
            pesoKg: peso,
            alcanceCm: 24,
            alcanceTexto: '>24',
            alcanceClassificacao: 'Ruim',
            nota: 5));
    if (mounted) setState(() => _ultima = r ?? _ultima);
  }

  @override
  Widget build(BuildContext context) {
    final r = _ultima;
    return Scaffold(
      appBar: AppBar(title: const Text('App host')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codigoController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código do voluntário (ex.: V01)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idadeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Idade (anos)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pesoController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Peso (kg)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _avaliar, child: const Text('Iniciar avaliação')),
            const SizedBox(height: 24),
            if (r == null)
              const Text('Nenhuma avaliação concluída nesta sessão.')
            else ...[
              Text('${r.volunteerCode} · teste ${r.testNumber}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final m in r.movements)
                for (final e in m.averages.entries)
                  Text('${m.spec?.title ?? m.movementId} · '
                      '${jointLabel(e.key)}: ${e.value.toStringAsFixed(1)}°'),
            ],
          ],
        ),
      ),
    );
  }
}
