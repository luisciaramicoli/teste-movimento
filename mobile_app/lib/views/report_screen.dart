import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/joint_angle.dart';
import '../models/protocol_models.dart';
import '../services/rep_counter_service.dart';
import '../services/session_csv_exporter.dart';

class ReportScreen extends StatefulWidget {
  final JointAngleTracker tracker;
  final RepCounterService? repCounter;
  final List<PostureEvaluationResult> completedPostures;
  final double sessionDuration;
  final String performanceSummary;
  final int initialTabIndex;

  const ReportScreen({
    super.key,
    required this.tracker,
    this.repCounter,
    this.completedPostures = const [],
    this.sessionDuration = 0.0,
    this.performanceSummary = '',
    this.initialTabIndex = 0,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    final controller = TextEditingController();
    String? error;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Exportar CSV'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nome do voluntário',
              hintText: 'Ex.: Maria Silva',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                if (SessionCsvExporter.isValidVolunteerCode(controller.text)) {
                  Navigator.pop(ctx, controller.text);
                } else {
                  setLocal(() => error = 'Digite o nome do voluntário.');
                }
              },
              child: const Text('Exportar'),
            ),
          ],
        ),
      ),
    );
    if (code == null || !mounted) return;
    final csv = SessionCsvExporter.build(
      volunteerCode: code,
      when: DateTime.now(),
      tracker: widget.tracker,
      postures: widget.completedPostures,
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('CSV copiado. Cole em uma planilha ou em um arquivo .csv.')));
  }

  List<MobilityDeficitItem> get _allDeficits =>
      widget.completedPostures.expand((p) => p.deficits).toList();

  double get _overallMobilityScore {
    if (widget.completedPostures.isEmpty) return 0.0;
    final sum = widget.completedPostures.fold<double>(
      0.0,
      (acc, p) => acc + p.accuracyScorePct,
    );
    return sum / widget.completedPostures.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161922),
        foregroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE51937),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'MOVEMENT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Relatório Biométrico',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.file_download, color: Colors.white),
            onPressed: _exportCsv,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE51937),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.replay, size: 16),
              label: const Text(
                'Novo Teste',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE51937),
          indicatorWeight: 3.0,
          labelColor: const Color(0xFFE51937),
          unselectedLabelColor: const Color(0xFFA0A8B8),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.health_and_safety), text: 'Mobilidade'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Amplitude (ROM)'),
            Tab(icon: Icon(Icons.show_chart), text: 'Evolução'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildTopSummaryCards(),
          if (widget.performanceSummary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(widget.performanceSummary,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA0A8B8))),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMobilityAndProtocolDiagnosisTab(),
                _buildRomBarChartTab(),
                _buildAngleTimeSeriesTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE51937),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                shadowColor: const Color(0xFFE51937).withOpacity(0.4),
              ),
              icon: const Icon(Icons.replay, size: 20),
              label: const Text(
                'NOVA AVALIAÇÃO BIOMÉTRICA',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSummaryCards() {
    final maxCalf = widget.tracker.maxCalfElevationLeftPct >
            widget.tracker.maxCalfElevationRightPct
        ? widget.tracker.maxCalfElevationLeftPct
        : widget.tracker.maxCalfElevationRightPct;
    final deficitsCount = _allDeficits.length;
    final score = _overallMobilityScore.round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: const BoxDecoration(
        color: Color(0xFF161922),
        border: Border(bottom: BorderSide(color: Color(0xFF282E3D))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Score Mobilidade',
            widget.completedPostures.isEmpty ? '--' : '$score%',
            Icons.accessibility_new,
            score >= 75
                ? const Color(0xFF00E676)
                : (score >= 50
                    ? const Color(0xFFFFC700)
                    : const Color(0xFFE51937)),
          ),
          _buildStatItem(
            'Restrições',
            '$deficitsCount',
            Icons.warning_amber_rounded,
            deficitsCount == 0
                ? const Color(0xFF00E676)
                : const Color(0xFFFF9100),
          ),
          _buildStatItem(
            'Panturrilha Máx',
            '${maxCalf.toStringAsFixed(0)}%',
            Icons.directions_walk,
            const Color(0xFFFF4081),
          ),
          _buildStatItem(
            'Duração',
            '${widget.sessionDuration.toStringAsFixed(0)}s',
            Icons.timer,
            const Color(0xFF00E5FF),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF282E3D)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Color(0xFFA0A8B8), fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobilityAndProtocolDiagnosisTab() {
    if (widget.completedPostures.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.accessibility_new,
                color: Color(0xFFFFD700),
                size: 48,
              ),
              SizedBox(height: 12),
              Text(
                'Nenhuma postura do protocolo foi avaliada nesta sessão.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Inicie o protocolo na câmera para avaliar automaticamente cada postura e identificar faltas de mobilidade.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final deficits = _allDeficits;
    final score = _overallMobilityScore;
    final int fullCount = widget.completedPostures
        .where((p) => p.mobilityStatus == 'Mobilidade Plena')
        .length;

    Color bannerColor;
    String verdictTitle;
    String verdictSubtitle;

    if (deficits.isEmpty && score >= 75) {
      bannerColor = const Color(0xFF00E676);
      verdictTitle = 'EXCELENTE MOBILIDADE FUNCIONAL!';
      verdictSubtitle =
          'Você atingiu os ângulos esperados em $fullCount/${widget.completedPostures.length} posturas sem restrições importantes.';
    } else if (score >= 55) {
      bannerColor = const Color(0xFFFFAB00);
      verdictTitle = 'MOBILIDADE PARCIAL — ATENÇÃO A RESTRIÇÕES';
      verdictSubtitle =
          'Foram identificadas ${deficits.length} limitações/assimetrias articulares durante o protocolo ($fullCount/${widget.completedPostures.length} posturas plenas).';
    } else {
      bannerColor = const Color(0xFFFF5252);
      verdictTitle = 'FALTAS DE MOBILIDADE DETECTADAS';
      verdictSubtitle =
          'O protocolo identificou ${deficits.length} restrições funcionais importantes nas posturas avaliadas. Veja o diagnóstico abaixo.';
    }

    return ListView(
      padding: const EdgeInsets.all(14.0),
      children: [
        // 1. Card de Veredito Geral do Protocolo
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bannerColor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bannerColor, width: 1.6),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: bannerColor.withOpacity(0.25),
                child: Text(
                  '${score.round()}%',
                  style: TextStyle(
                    color: bannerColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdictTitle,
                      style: TextStyle(
                        color: bannerColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verdictSubtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Seção de Faltas de Mobilidade Detectadas
        Row(
          children: [
            const Icon(
              Icons.find_in_page_outlined,
              color: Color(0xFFFF9100),
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              'Faltas de Mobilidade Detectadas (${deficits.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (deficits.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E676).withOpacity(0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF00E676), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nenhuma falta de mobilidade ou assimetria significativa foi detectada nas posturas avaliadas!',
                    style: TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          )
        else
          ...deficits.map((d) => _buildDeficitCard(d)),

        const SizedBox(height: 18),

        // 3. Resultado Detalhado por Postura (com GIF miniatura e ângulos)
        const Row(
          children: [
            Icon(
              Icons.fact_check_outlined,
              color: Color(0xFF00E5FF),
              size: 20,
            ),
            SizedBox(width: 6),
            Text(
              'Desempenho em Cada Postura',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ...widget.completedPostures.map((p) => _buildPostureResultCard(p)),
      ],
    );
  }

  Widget _buildDeficitCard(MobilityDeficitItem d) {
    Color sevColor;
    if (d.severity == 'Moderada/Severa') {
      sevColor = const Color(0xFFFF5252);
    } else if (d.severity == 'Assimetria') {
      sevColor = const Color(0xFFE040FB);
    } else {
      sevColor = const Color(0xFFFFAB00);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sevColor.withOpacity(0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  d.jointLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  d.severity.toUpperCase(),
                  style: TextStyle(
                    color: sevColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Postura: ${d.postureTitle}  •  Atingido: ${d.achievedValue.round()}${d.unit} (Meta: ${d.targetValue.round()}${d.unit})',
            style: TextStyle(
              color: sevColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            d.description,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPostureResultCard(PostureEvaluationResult item) {
    Color statusColor;
    if (item.mobilityStatus == 'Mobilidade Plena') {
      statusColor = const Color(0xFF00E676);
    } else if (item.mobilityStatus == 'Mobilidade Parcial') {
      statusColor = const Color(0xFFFFAB00);
    } else {
      statusColor = const Color(0xFFFF5252);
    }

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                item.gifAssetPath,
                width: 68,
                height: 84,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 68,
                  height: 84,
                  color: Colors.black26,
                  child: const Icon(
                    Icons.accessibility_new,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.postureTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.mobilityStatus,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Score: ${item.accuracyScorePct.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: item.targetAngles.entries.map((entry) {
                      final jKey = entry.key;
                      final range = entry.value;
                      final val = item.capturedAngles[jKey];
                      final ok = val != null && range.isWithinRange(val);
                      final chipCol =
                          ok ? const Color(0xFF00E676) : const Color(0xFFFF9100);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: chipCol.withOpacity(0.6)),
                        ),
                        child: Text(
                          '${range.label}: ${val != null ? "${val.round()}°" : "--"} (Alvo ${range.targetAngle.round()}°)',
                          style: TextStyle(
                            color: chipCol,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (item.postureId == 'elevacao_panturrilha' ||
                      item.maxCalfElevationPct > 5) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Panturrilha: Esq ${item.maxCalfLeftPct.round()}% | Dir ${item.maxCalfRightPct.round()}% (Máx: ${item.maxCalfElevationPct.round()}%)',
                      style: const TextStyle(
                        color: Color(0xFFFF80AB),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRomBarChartTab() {
    final records = widget.tracker.records.values
        .where((r) => r.minAngle != null && r.maxAngle != null)
        .toList();

    if (records.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum dado angular registrado nesta sessão.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Amplitude de Movimento Alcançada (Mín x Máx)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Elevação Máxima do Calcanhar: Esq ${widget.tracker.maxCalfElevationLeftPct.toStringAsFixed(0)}% | Dir ${widget.tracker.maxCalfElevationRightPct.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Color(0xFFFF80AB),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Colors.white24, height: 16),
              itemBuilder: (context, index) {
                final r = records[index];
                final minA = r.minAngle ?? 0;
                final maxA = r.maxAngle ?? 0;
                final rom = r.rom ?? 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          r.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: Text(
                            'ROM: ${rom.toStringAsFixed(0)}°',
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Mín: ${minA.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            color: Color(0xFF4E79A7),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Máx: ${maxA.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            color: Color(0xFFE15759),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 12,
                        color: Colors.white10,
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (maxA / 180.0).clamp(0.0, 1.0),
                              child: Container(color: const Color(0xFFE15759)),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (minA / 180.0).clamp(0.0, 1.0),
                              child: Container(color: const Color(0xFF4E79A7)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleTimeSeriesTab() {
    final records = widget.tracker.records.values
        .where((r) => r.angles.isNotEmpty)
        .toList();

    if (records.isEmpty) {
      return const Center(
        child: Text(
          'Sem séries temporais registradas.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final colors = [
      const Color(0xFF00E5FF),
      const Color(0xFF00E676),
      const Color(0xFFFFD700),
      const Color(0xFFFF9100),
      const Color(0xFFFF4081),
      const Color(0xFFAB47BC),
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evolução Angular ao Longo do Tempo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                backgroundColor: const Color(0xFF1E1E1E),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (value) =>
                      const FlLine(color: Colors.white12, strokeWidth: 1),
                  getDrawingVerticalLine: (value) =>
                      const FlLine(color: Colors.white12, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}°',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}s',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                minY: 0,
                maxY: 185,
                lineBarsData:
                    records.take(6).toList().asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final spots = <FlSpot>[];

                  final int total = r.timestamps.length;
                  final int step = total > 120 ? (total ~/ 120) : 1;
                  for (int i = 0; i < total; i += step) {
                    spots.add(FlSpot(r.timestamps[i], r.angles[i]));
                  }

                  return LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: colors[idx % colors.length],
                    barWidth: 2.2,
                    dotData: const FlDotData(show: false),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: records.take(6).toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final r = entry.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    color: colors[idx % colors.length],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    r.label,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
