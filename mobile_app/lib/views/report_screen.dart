import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/joint_angle.dart';
import '../services/rep_counter_service.dart';

class ReportScreen extends StatefulWidget {
  final JointAngleTracker tracker;
  final RepCounterService repCounter;

  const ReportScreen({
    super.key,
    required this.tracker,
    required this.repCounter,
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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Relatório Biomecânico',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Amplitude (ROM)'),
            Tab(icon: Icon(Icons.show_chart), text: 'Evolução'),
            Tab(icon: Icon(Icons.fitness_center), text: 'Repetições'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Resumo no topo
          _buildTopSummaryCards(),

          // Abas de gráficos
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRomBarChartTab(),
                _buildAngleTimeSeriesTab(),
                _buildRepsAnalysisTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSummaryCards() {
    final reps = widget.repCounter.repCount;
    final cadence = widget.repCounter.cadenceRpm;
    final avgTime = widget.repCounter.averageRepDuration;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      color: const Color(0xFF1E1E1E),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Repetições', '$reps', Icons.repeat, const Color(0xFF00E676)),
          _buildStatItem('Cadência', '${cadence.toStringAsFixed(1)} RPM', Icons.speed, const Color(0xFF00E5FF)),
          _buildStatItem('Tempo Médio', '${avgTime.toStringAsFixed(1)}s', Icons.timer, const Color(0xFFFFD700)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // --- Aba 1: Gráfico de Barras de Amplitude de Movimento ---
  Widget _buildRomBarChartTab() {
    final records = widget.tracker.records.values
        .where((r) => r.minAngle != null && r.maxAngle != null)
        .toList();

    if (records.isEmpty) {
      return const Center(
        child: Text('Nenhum dado angular registrado nesta sessão.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Amplitude de Movimento Alcançada (Mín x Máx)',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Azul: Ângulo Mínimo | Vermelho: Ângulo Máximo | Verde: ROM',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white24, height: 16),
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
                        Text(r.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: Text('ROM: ${rom.toStringAsFixed(0)}°', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Mín: ${minA.toStringAsFixed(0)}°', style: const TextStyle(color: Color(0xFF4E79A7), fontSize: 12)),
                        const Spacer(),
                        Text('Máx: ${maxA.toStringAsFixed(0)}°', style: const TextStyle(color: Color(0xFFE15759), fontSize: 12)),
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

  // --- Aba 2: Gráfico de Linhas Temporais (fl_chart) ---
  Widget _buildAngleTimeSeriesTab() {
    final records = widget.tracker.records.values
        .where((r) => r.angles.isNotEmpty)
        .toList();

    if (records.isEmpty) {
      return const Center(child: Text('Sem séries temporais registradas.', style: TextStyle(color: Colors.grey)));
    }

    final colors = [
      const Color(0xFF00E5FF),
      const Color(0xFF00E676),
      const Color(0xFFFFD700),
      const Color(0xFFFF9100),
      const Color(0xFFFF4081),
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Evolução Angular ao Longo do Tempo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                backgroundColor: const Color(0xFF1E1E1E),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white12, strokeWidth: 1),
                  getDrawingVerticalLine: (value) => FlLine(color: Colors.white12, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}°', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 25,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}s', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ),
                  ),
                ),
                minY: 0,
                maxY: 185,
                lineBarsData: records.take(5).toList().asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final spots = <FlSpot>[];

                  for (int i = 0; i < r.timestamps.length; i++) {
                    spots.add(FlSpot(r.timestamps[i], r.angles[i]));
                  }

                  return LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: colors[idx % colors.length],
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: records.take(5).toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final r = entry.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, color: colors[idx % colors.length]),
                  const SizedBox(width: 4),
                  Text(r.label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // --- Aba 3: Análise de Repetições ---
  Widget _buildRepsAnalysisTab() {
    final reps = widget.repCounter.repsHistory;

    if (reps.isEmpty) {
      return const Center(
        child: Text('Nenhuma repetição concluída nesta sessão.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Desempenho por Repetição (${widget.repCounter.config.displayName})',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Azul: Fase Concêntrica (Subida) | Laranja: Fase Excêntrica (Descida)',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: reps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final r = reps[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Repetição #${r.repNumber}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              '${r.totalDuration.toStringAsFixed(2)}s',
                              style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text('Concêntrico: ${r.concentricDuration.toStringAsFixed(2)}s', style: const TextStyle(color: Color(0xFF2B5C8F), fontSize: 12)),
                            const Spacer(),
                            Text('Excêntrico: ${r.eccentricDuration.toStringAsFixed(2)}s', style: const TextStyle(color: Color(0xFFE67E22), fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.feedback,
                          style: TextStyle(
                            color: r.isValid ? const Color(0xFF00E676) : Colors.orangeAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

