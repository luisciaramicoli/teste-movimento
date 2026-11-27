import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MovimentoMobilidade.inicializar();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MovimentoMobilidadeApp());
}

class MovimentoMobilidadeApp extends StatelessWidget {
  const MovimentoMobilidadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movimento Mobilidade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _defaultVolunteerCode = 'V01';
  static const double _defaultWeightKg = 70.0;
  static const List<int> _journeyOptionsMonths = [1, 3, 6];

  final TextEditingController _codigoController =
      TextEditingController(text: _defaultVolunteerCode);
  final _idadeController = TextEditingController();
  final TextEditingController _pesoController =
      TextEditingController(text: '${_defaultWeightKg.toInt()}');

  int _jornadaMeses = 3;
  List<AssessmentRecord> _historico = const [];

  /// Valor devolvido pela última chamada de [MovimentoMobilidade.iniciarAvaliacao].
  AssessmentRecord? _retorno;
  bool _carregandoHistorico = true;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _idadeController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  Future<void> _carregarHistorico() async {
    try {
      final records = await MovimentoMobilidade.historico();
      if (!mounted) return;
      setState(() {
        _historico = records;
        _carregandoHistorico = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoHistorico = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double? _parseWeightKg() {
    final raw = _pesoController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0 || parsed > 400) return null;
    return parsed;
  }

  PerfilAvaliado? _validateAndBuildPerfil() {
    final peso = _parseWeightKg();
    if (peso == null) {
      _showMessage('Informe um peso válido em kg (maior que 0 até 400).');
      return null;
    }

    final rawAge = _idadeController.text.trim();
    final idade = int.tryParse(rawAge);
    if (rawAge.isNotEmpty && (idade == null || idade <= 0)) {
      _showMessage('Informe a idade em anos completos.');
      return null;
    }
    return PerfilAvaliado(
      pesoKg: peso,
      idade: idade,
      jornadaMeses: _jornadaMeses,
    );
  }

  Future<void> _iniciarAvaliacao() async {
    final codigo = _codigoController.text.trim();
    if (!VolunteerCode.isValid(codigo)) {
      _showMessage('Use um código como V01. Não digite nomes.');
      return;
    }

    final perfil = _validateAndBuildPerfil();
    if (perfil == null) return;

    final avaliacao = await MovimentoMobilidade.iniciarAvaliacao(
      context,
      voluntario: codigo,
      perfil: perfil,
    );
    if (!mounted) return;
    // null: o usuário saiu antes de concluir.
    if (avaliacao != null) setState(() => _retorno = avaliacao);
    await _carregarHistorico();
  }

  Future<void> _abrirResultado(AssessmentRecord record) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MovimentoMobilidade.telaResultado(
          record,
        ),
      ),
    );
  }

  Future<void> _copiarCsv(AssessmentRecord record) async {
    final csv = MovimentoMobilidade.exportarCsv(record);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    _showMessage(
      'CSV de ${record.volunteerCode} (teste ${record.testNumber}) copiado.',
    );
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Exemplo de leitura do retorno: a análise chega pronta da biblioteca, e o
  /// app só exibe. `avaliacao.toResultJson()` entrega o mesmo em JSON.
  Widget _buildResultSection(BuildContext context, AssessmentRecord avaliacao) {
    final theme = Theme.of(context);
    final analise = avaliacao.analysis;
    final score = analise.score;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Retorno da biblioteca', style: theme.textTheme.titleMedium),
            Text(score == null
                ? 'Score indisponível'
                : 'Score ${score.toStringAsFixed(1)}/10'),
            for (final item in analise.joints)
              Text('${item.joint.label}: ${item.angle}° · '
                  '${item.band.label} · nota ${item.grade.toStringAsFixed(1)}'),
            if (analise.missing.isNotEmpty)
              Text('Sem medida: '
                  '${analise.missing.map((j) => j.label).join(', ')}'),
            if (analise.shoulderAsymmetry?.alert ?? false)
              const Text('Assimetria entre os ombros'),
            Text('Motor: ${avaliacao.engine}',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Histórico de avaliações',
              style: theme.textTheme.titleMedium,
            ),
            IconButton(
              onPressed: _carregarHistorico,
              tooltip: 'Atualizar histórico',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_carregandoHistorico)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_historico.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nenhuma avaliação salva neste aparelho.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _historico.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _buildHistoryCard(context, _historico[index]),
          ),
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context, AssessmentRecord record) {
    final scoreValue = record.analysis.score;
    final scoreText = scoreValue == null
        ? 'Score indisponível'
        : 'Score ${scoreValue.toStringAsFixed(1)}/10';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _abrirResultado(record),
        title: Text('${record.volunteerCode} · Teste ${record.testNumber}'),
        subtitle: Text('${_formatDate(record.createdAt)} · $scoreText'),
        trailing: IconButton(
          icon: const Icon(Icons.copy_outlined),
          tooltip: 'Copiar CSV',
          onPressed: () => _copiarCsv(record),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Movimento Mobilidade')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Dados do avaliado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _codigoController,
              label: 'Código do voluntário (ex.: V01)',
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _pesoController,
              label: 'Peso (kg)',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _idadeController,
              label: 'Idade em anos (opcional)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Text('Meta da jornada', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: [
                for (final months in _journeyOptionsMonths)
                  ButtonSegment<int>(
                    value: months,
                    label: Text(months == 1 ? '1 mês' : '$months meses'),
                  ),
              ],
              selected: {_jornadaMeses},
              emptySelectionAllowed: false,
              onSelectionChanged: (v) =>
                  setState(() => _jornadaMeses = v.first),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _iniciarAvaliacao,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar avaliação'),
            ),
            if (_retorno case final retorno?) ...[
              const SizedBox(height: 16),
              _buildResultSection(context, retorno),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            _buildHistorySection(context),
          ],
        ),
      ),
    );
  }
}
