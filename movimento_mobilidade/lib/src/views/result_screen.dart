import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flow.dart';
import '../models/assessment_models.dart';
import '../models/mobility_score.dart';
import '../models/perfil_avaliado.dart';
import '../models/reference_norms.dart';
import '../services/assessment_pdf.dart';
import '../services/assessment_history_store.dart';
import 'assessment_screen.dart';

/// Medidas do layout do Figma (tela de 393 px de largura).
class _Fig {
  static const Color card = Color(0xFFF3F3F3);
  static const Color cardBorder = Color(0xFFB9B9B9);
  static const Color track = Color(0xFFE6E6E6);
  static const Color red = Color(0xFFE86969);
  static const Color green = Color(0xFF8BD44F);
  static const Color amber = Color(0xFFF2B84B);
  static const Color text = Color(0xFF212121);
  static const double radius = 18;
}

/// Número com 1 casa decimal e vírgula (detalhe e histórico).
String _decimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Graus com até 1 casa decimal ("120°", "132,7°").
String _degrees(double v) => '${_decimal(v).replaceAll(RegExp(r',0$'), '')}°';

/// Tela 4: resultado da avaliação — cabeçalho do avaliado, score, meta e uma
/// barra por articulação.
class ResultScreen extends StatefulWidget {
  final AssessmentRecord record;

  /// Fluxo em andamento; `null` quando a tela é usada de forma avulsa
  /// (somente leitura, sem "Refazer").
  final AvaliacaoFluxo? fluxo;

  /// Dados do cabeçalho; se `null`, usa os do [fluxo] (ou "--").
  final PerfilAvaliado? perfil;

  const ResultScreen({super.key, required this.record, this.fluxo, this.perfil});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

/// Imagem com fundo preto: o brilho do pixel vira a opacidade, então o preto
/// fica transparente e o resto da arte é preservado.
class _KeyedImage extends StatelessWidget {
  final String asset;
  final double width;
  final double height;
  final bool flip;

  /// Fração da largura cortada à direita (sobras da imagem original).
  final double cropRight;
  const _KeyedImage(this.asset,
      {required this.width,
      required this.height,
      this.flip = false,
      this.cropRight = 0});

  static const ColorFilter _blackToAlpha = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    4 * 0.2126, 4 * 0.7152, 4 * 0.0722, 0, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget img = ColorFiltered(
      colorFilter: _blackToAlpha,
      child: Image.asset(asset,
          package: kPackage, width: width, height: height, fit: BoxFit.contain),
    );
    if (cropRight > 0) {
      img = ClipRect(
        child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1 - cropRight,
            child: img),
      );
    }
    if (flip) img = Transform.flip(flipX: true, child: img);
    return img;
  }
}

/// Uma linha da tela: de onde vem o valor e onde cada elemento fica no cartão.
class _RowSpec {
  final MobilityJoint joint;
  final String label;

  /// Imagem da articulação e sua posição/tamanho no cartão (medidas do Figma).
  final String image;
  final double imgLeft;
  final double imgTop;
  final double imgW;
  final double imgH;
  final bool flip;
  final double cropRight;
  final double valueLeft;
  final double valueTop;
  final double labelLeft;
  final double labelTop;

  /// Espaço até a próxima linha.
  final double gapAfter;

  const _RowSpec(this.joint, this.label,
      {required this.image,
      required this.imgLeft,
      required this.imgTop,
      required this.imgW,
      required this.imgH,
      this.flip = false,
      this.cropRight = 0,
      required this.valueLeft,
      required this.valueTop,
      required this.labelLeft,
      required this.labelTop,
      required this.gapAfter});
}

class _ResultScreenState extends State<ResultScreen> {
  /// As 5 articulações do score, na ordem da tela. Os ombros vêm da abdução
  /// (frontal); quadril, joelho e tornozelo, do agachamento de perfil.
  static const List<_RowSpec> _rows = [
    _RowSpec(MobilityJoint.ombroDir, 'Ombro direito',
        image: 'assets/images/icone_ombro_dir.png',
        imgLeft: 4, imgTop: 0, imgW: 49, imgH: 53,
        valueLeft: 57, valueTop: 2, labelLeft: 148, labelTop: 17, gapAfter: 5),
    _RowSpec(MobilityJoint.ombroEsq, 'Ombro esquerdo',
        image: 'assets/images/icone_ombro_esq.png',
        imgLeft: 8, imgTop: 0, imgW: 49, imgH: 53,
        valueLeft: 57, valueTop: 2, labelLeft: 148, labelTop: 17, gapAfter: 26),
    _RowSpec(MobilityJoint.quadril, 'Quadril',
        image: 'assets/images/icone_quadril.png', cropRight: 0.07,
        imgLeft: 3, imgTop: -1, imgW: 53, imgH: 53,
        valueLeft: 61, valueTop: 3, labelLeft: 151, labelTop: 18, gapAfter: 22),
    _RowSpec(MobilityJoint.joelho, 'Joelho',
        image: 'assets/images/icone_joelho.png', flip: true,
        imgLeft: 6, imgTop: 5, imgW: 46, imgH: 46,
        valueLeft: 57, valueTop: 2, labelLeft: 148, labelTop: 17, gapAfter: 22),
    _RowSpec(MobilityJoint.tornozelo, 'Tornozelo',
        image: 'assets/images/icone_tornozelo.png',
        imgLeft: 6, imgTop: 4, imgW: 46, imgH: 46,
        valueLeft: 57, valueTop: 2, labelLeft: 136, labelTop: 17, gapAfter: 0),
  ];

  late AssessmentRecord _record = widget.record;
  List<AssessmentRecord> _history = const [];

  bool _exporting = false;
  PerfilAvaliado get _perfil {
    final provided = _record.id == widget.record.id
        ? widget.perfil ?? widget.fluxo?.perfil
        : null;
    return PerfilAvaliado(
      idade: _record.idade ?? provided?.idade,
      pesoKg: _record.pesoKg ?? provided?.pesoKg,
      jornadaMeses: _record.jornadaMeses ?? provided?.jornadaMeses ?? 3,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final all = await AssessmentHistoryStore().loadAll();
    if (!mounted) return;
    setState(() => _history = all
        .where((r) => r.volunteerCode == widget.record.volunteerCode)
        .toList());
  }

  void _close() {
    if (widget.fluxo != null) {
      exitFlow(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  String _historyLabel(AssessmentRecord r, int index) {
    if (index == 0) return 'Última avaliação';
    String p(int n) => n.toString().padLeft(2, '0');
    final d = r.createdAt;
    final score = MobilityScore.fromRecord(r).score;
    return 'Teste ${r.testNumber} · ${p(d.day)}/${p(d.month)}/${d.year}'
        '${score == null ? '' : ' · ${_decimal(score)}'}';
  }

  @override
  Widget build(BuildContext context) {
    final result = MobilityScore.fromRecord(_record);
    final asymmetry = result.shoulderAsymmetry;
    final months = _perfil.jornadaMeses;
    final rows = <Widget>[];
    for (final spec in _rows) {
      final joint = result.joint(spec.joint);
      if (joint == null) continue;
      rows.add(_JointRow(
        spec: spec,
        result: joint,
        months: months,
        onChartTap: () => _showJointDetailsSheet(spec, joint, months),
      ));
      if (spec.joint == MobilityJoint.ombroEsq &&
          asymmetry != null &&
          asymmetry.alert) {
        rows.add(_asymmetryAlert(asymmetry));
      }
      if (spec.gapAfter > 0) rows.add(SizedBox(height: spec.gapAfter));
    }
    final selectedIndex = _history.indexWhere((r) => r.id == _record.id);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          toolbarHeight: 72,
          automaticallyImplyLeading: false,
          leading: IconButton(
              iconSize: 27,
              icon: const Icon(Icons.arrow_back),
              onPressed: _close),
          title: const Text('Mobilidade'),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(29, 13, 29, 150),
              children: [
                Center(child: _historyPill(selectedIndex)),
                const SizedBox(height: 23),
                _header(result.score),
                if (result.score == null)
                  Text('Score indisponível. Falta medir: ${result.missing.map((j) => j.label).join(', ')}.'),
                const SizedBox(height: 23),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('Sem medições válidas.')),
                  ),
                ...rows,
              ],
            ),
            // Degradê branco que esmaece o fim da lista atrás dos botões.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withOpacity(0), Colors.white],
                      stops: const [0.1983, 0.8552],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 20),
                child: _buttons(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyPill(int selectedIndex) {
    final label = selectedIndex < 0
        ? 'Última avaliação'
        : _historyLabel(_record, selectedIndex);
    final pill = Container(
      constraints: const BoxConstraints(minWidth: 156, minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
          color: const Color(0xFFE6E6E6),
          borderRadius: BorderRadius.circular(23)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                letterSpacing: 0.5,
                color: Color(0xFF1A1A1A))),
        const SizedBox(width: 10),
        const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.black),
      ]),
    );
    if (_history.length < 2) return pill;
    return PopupMenuButton<AssessmentRecord>(
      onSelected: (r) => setState(() => _record = r),
      itemBuilder: (_) => [
        for (var i = 0; i < _history.length; i++)
          PopupMenuItem(
              value: _history[i], child: Text(_historyLabel(_history[i], i))),
      ],
      child: pill,
    );
  }

  Widget _asymmetryAlert(ShoulderAsymmetry a) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: _Fig.amber.withOpacity(0.22),
            border: Border.all(color: _Fig.amber),
            borderRadius: BorderRadius.circular(_Fig.radius)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: _Fig.text),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Diferença de ${a.percent.round()}% entre os lados',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _Fig.text))),
        ]),
      );

  static BoxDecoration _cardDecoration() => BoxDecoration(
        color: _Fig.card,
        border: Border.all(color: _Fig.cardBorder),
        borderRadius: BorderRadius.circular(_Fig.radius),
      );

  Widget _header(double? score) {
    final p = _perfil;
    String n(num? v) =>
        v == null ? '--' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));
    const small = TextStyle(fontSize: 12, height: 14 / 12, color: _Fig.text);
    const value = TextStyle(
        fontSize: 16,
        height: 19 / 16,
        fontWeight: FontWeight.w700,
        color: Colors.black);
    const scoreGrey = TextStyle(
        fontSize: 12,
        letterSpacing: -0.8,
        color: Color(0xEE464646));

    return Container(
      height: 109,
      decoration: _cardDecoration(),
      child: Stack(clipBehavior: Clip.none, children: [
        // Selo da nota (retângulo com ponta à direita).
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            width: 75,
            height: 69,
            decoration: BoxDecoration(
                color: const Color(0xFFB0CDD9),
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const Positioned(
          left: 83,
          top: 22.5,
          child: CustomPaint(
              size: Size(15, 26),
              painter: _PointerPainter(Color(0xFFB0CDD9))),
        ),
        // Boneco (image 284: 107x120 em left 75, top 178 do Figma).
        const Positioned(
          left: 46,
          top: -12,
          child: _KeyedImage('assets/images/boneco_ombro.png',
              width: 107, height: 120),
        ),
        Positioned(
          left: 8,
          top: 12,
          width: 46,
          height: 44,
          child: Center(
            child: Text(score == null ? '--' : '${score.round()}',
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: Color(0xFF137C9D))),
          ),
        ),
        const Positioned(
            left: 46,
            top: 19,
            width: 33,
            height: 30,
            child: Center(child: Text('/10', style: scoreGrey))),
        const Positioned(
            left: 13,
            top: 47,
            width: 67,
            height: 30,
            child: Center(child: Text('Atual', style: scoreGrey))),
        Align(
          alignment: const Alignment(0.68, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Idade', style: small),
              Text(p.idade == null ? '--' : '${p.idade} anos', style: value),
              const SizedBox(height: 6),
              const Text('Peso', style: small),
              Text(p.pesoKg == null ? '--' : '${n(p.pesoKg)} kg', style: value),
            ],
          ),
        ),
      ]),
    );

  }

  Widget _buttons() {
    final fluxo = widget.fluxo;
    Widget pill(
        {required Color bg,
        required Color fg,
        Color? borderColor,
        required IconData icon,
        required double iconSize,
        required String text,
        required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 141,
          height: 41,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: borderColor == null ? null : Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(42),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: iconSize, color: fg),
            const SizedBox(width: 10),
            Text(text,
                style: TextStyle(
                    fontSize: 16,
                    height: 15 / 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: fg)),
          ])),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (fluxo != null) ...[
          pill(
            bg: Colors.black,
            fg: Colors.white,
            icon: Icons.refresh,
            iconSize: 21,
            text: 'Refazer',
            onTap: () => Navigator.of(context).pushReplacement(flowRoute(
                (_) => AssessmentScreen(
                    volunteerCode: widget.record.volunteerCode,
                    testNumber: widget.record.testNumber + 1,
                    fluxo: fluxo))),
          ),
          const SizedBox(width: 13),
        ],
        pill(
          bg: _Fig.card,
          fg: _Fig.text,
          borderColor: _Fig.cardBorder,
          icon: Icons.picture_as_pdf_outlined,
          iconSize: 18,
          text: 'Relatório',
          onTap: _exportPdf,
        ),
      ],
    );
  }
  String _formatDateShort(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }

  Color _bandColor(MobilityBand band) => switch (band) {
        MobilityBand.adequada => _Fig.green,
        MobilityBand.reduzida => _Fig.amber,
        MobilityBand.limitada => _Fig.red,
      };

  Widget _studyReference(MobilityJoint joint) {
    if (joint == MobilityJoint.ombroDir || joint == MobilityJoint.ombroEsq) {
      return Text(
        'Abdução ativa · Gill et al. (2020)\n'
        'Médias ponderadas dos 2.404 adultos da tabela 2, reunindo todas as '
        'idades e ambos os sexos: ${_degrees(pooledShoulderRightMean)} à direita '
        'e ${_degrees(pooledShoulderLeftMean)} à esquerda.',
      );
    }
    if (joint == MobilityJoint.tornozelo) {
      return Text(
        'Dorsiflexão direita · Endo et al. (2020), tabela 1\n'
        'Média de ${_degrees(squatAnkleRightMean)} e desvio-padrão de '
        '${_degrees(squatAnkleRightSd)} no fundo do agachamento profundo de '
        'nove homens jovens. O app estima a amplitude pela variação entre '
        'a posição em pé e o fundo de cada repetição.',
      );
    }
    final hip = joint == MobilityJoint.quadril;
    final rows = {
      'Direito': hip ? squatHipRight : squatKneeRight,
      'Esquerdo': hip ? squatHipLeft : squatKneeLeft,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Agachamento profundo · Endo et al. (2020)'),
        const Text('Nove homens, idade média de 18,3 anos, com os braços '
            'elevados. Medidas no ponto mais profundo; o quadril foi medido em '
            'relação à pelve.'),
        for (final side in rows.entries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${side.key} · média ± desvio-padrão '
                '${_degrees(side.value.mean)} ± ${_degrees(side.value.sd)}'),
          ),
      ],
    );
  }

  void _showJointDetailsSheet(
      _RowSpec spec, JointScore joint, int months) {
    final reps = mobilityJointReps(_record, spec.joint);
    final sd = joint.deviation;
    final bandColor = _bandColor(joint.band);
    final goalText = joint.atReference
        ? 'Manter'
        : _degrees(joint.goalAngle(months));

    // Evolução desta articulação no histórico do voluntário (cronológico).
    final evolution = <({
      AssessmentRecord record,
      double angle,
      bool current,
    })>[];
    for (final rec in _history) {
      final a = mobilityAngles(rec)[spec.joint];
      if (a != null) {
        evolution.add((record: rec, angle: a, current: rec.id == _record.id));
      }
    }
    evolution.sort((a, b) => a.record.createdAt.compareTo(b.record.createdAt));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D0D0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                _KeyedImage(
                  spec.image,
                  width: 40,
                  height: 40,
                  flip: spec.flip,
                  cropRight: spec.cropRight,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: bandColor.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          joint.band.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _Fig.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _Fig.text),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Cartões de resumo métrico
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricTile('Média medida', _degrees(joint.angle),
                    highlight: true),
                _metricTile('Referência', _degrees(joint.reference)),
                _metricTile(
                    'Meta ($months ${months == 1 ? 'mês' : 'meses'})', goalText),
                _metricTile('Nota', '${_decimal(joint.grade)} / 10'),
                _metricTile('% da Ref.', '${joint.percent.round()}%'),
                if (sd != null)
                  _metricTile('DP das repetições', '±${_decimal(sd)}°'),
              ],
            ),
            const SizedBox(height: 20),
            _studyReference(joint.joint),
            const SizedBox(height: 20),
            const Text(
              'Repetições medidas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            if (reps.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _cardDecoration(),
                child: const Text(
                  'Sem repetições individuais registradas para esta articulação.',
                  style: TextStyle(fontSize: 13, color: _Fig.text),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: _cardDecoration(),
                child: _RepBarChart(
                  reps: reps,
                  reference: joint.reference,
                ),
              ),
            if (evolution.length >= 2) ...[
              const SizedBox(height: 22),
              Text(
                'Evolução no histórico (${evolution.length} avaliações)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    for (var i = 0; i < evolution.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _evolutionRow(
                        testNumber: evolution[i].record.testNumber,
                        dateLabel:
                            _formatDateShort(evolution[i].record.createdAt),
                        angle: evolution[i].angle,
                        reference: joint.reference,
                        delta: i == 0
                            ? null
                            : evolution[i].angle - evolution[i - 1].angle,
                        isCurrent: evolution[i].current,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, {bool highlight = false}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFE6F3F7) : _Fig.card,
        border: Border.all(
            color: highlight ? const Color(0xFF137C9D) : _Fig.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF555555))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: highlight ? const Color(0xFF137C9D) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _evolutionRow({
    required int testNumber,
    required String dateLabel,
    required double angle,
    required double reference,
    required double? delta,
    required bool isCurrent,
  }) {
    final band = mobilityBand(angle, reference);
    final barColor = _bandColor(band);
    final frac = (angle / reference).clamp(0.0, 1.0);
    final deltaText = delta == null
        ? null
        : '${delta >= 0 ? '+' : ''}${_decimal(delta)}°';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Teste $testNumber · $dateLabel',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent ? const Color(0xFF137C9D) : _Fig.text,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF137C9D).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Atual',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF137C9D),
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              _degrees(angle),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            if (deltaText != null) ...[
              const SizedBox(width: 6),
              Text(
                deltaText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: delta! >= 0
                      ? const Color(0xFF2E6B1E)
                      : const Color(0xFF913939),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 7,
            backgroundColor: _Fig.track,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    _exporting = true;
    final record = _record;
    try {
      final bytes = await buildAssessmentPdf(record, _perfil);
      if (!mounted) return;
      final saved = await const MethodChannel('movimento/relatorio')
          .invokeMethod<bool>('salvarPdf', {
        'nome': 'Mobilidade-${record.volunteerCode}-teste-${record.testNumber}.pdf',
        'bytes': bytes,
      });
      if (mounted && saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relatório PDF salvo.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao salvar o PDF. Tente novamente.')),
        );
      }
    } finally {
      _exporting = false;
    }
  }
}

/// Ponta triangular (apontando para a direita) ao lado do selo da nota.
class _PointerPainter extends CustomPainter {
  final Color color;
  const _PointerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => old.color != color;
}

class _JointRow extends StatelessWidget {
  final _RowSpec spec;
  final JointScore result;
  final int months;
  final VoidCallback onChartTap;
  const _JointRow({
    required this.spec,
    required this.result,
    required this.months,
    required this.onChartTap,
  });

  static const TextStyle _zone = TextStyle(
      fontSize: 12, height: 14 / 12, color: _Fig.text);

  @override
  Widget build(BuildContext context) {
    final angle = result.angle;
    final color = switch (result.band) {
      MobilityBand.adequada => _Fig.green,
      MobilityBand.reduzida => _Fig.amber,
      MobilityBand.limitada => _Fig.red,
    };
    // Barra cheia = referência do perfil.
    final frac = (angle / result.reference).clamp(0.0, 1.0);
    final goal = result.atReference
        ? 'Meta: manter'
        : 'Meta: ${_degrees(result.goalAngle(months))}';

    return Container(
      height: 102,
      decoration: BoxDecoration(
          color: _Fig.card, borderRadius: BorderRadius.circular(_Fig.radius)),
      child: LayoutBuilder(builder: (context, c) {
        final trackW = c.maxWidth - 14 - 10;
        final fillW = trackW * frac;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: spec.imgLeft,
            top: spec.imgTop,
            child: _KeyedImage(spec.image,
                width: spec.imgW,
                height: spec.imgH,
                flip: spec.flip,
                cropRight: spec.cropRight),
          ),
          Positioned(
            left: spec.valueLeft,
            top: spec.valueTop,
            width: 71,
            height: 48,
            child: Center(
              child: Text('${angle.round()}°',
                  style: const TextStyle(
                      fontSize: 24,
                      height: 28 / 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black)),
            ),
          ),
          Positioned(
            left: spec.labelLeft,
            top: spec.labelTop,
            child: Text(spec.label,
                style: const TextStyle(
                    fontSize: 16,
                    height: 19 / 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black)),
          ),
          // Botão de gráfico (46x26, abre detalhes e gráfico de repetições).
          Positioned(
            right: 6,
            top: 6,
            width: 46,
            height: 26,
            child: Semantics(
              button: true,
              label: 'Ver gráfico e detalhes de ${spec.label}',
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(31),
                  side: const BorderSide(color: Color(0xFF137C9D)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(31),
                  onTap: onChartTap,
                  child: const Center(
                    child: Icon(Icons.bar_chart,
                        size: 18, color: Color(0xFF137C9D)),
                  ),
                ),
              ),
            ),
          ),
          // Trilha, preenchimento e marcador.
          Positioned(
            left: 14,
            right: 10,
            top: 55,
            height: 9,
            child: Container(
                decoration: BoxDecoration(
                    color: _Fig.track, borderRadius: BorderRadius.circular(31))),
          ),
          Positioned(
            left: 14,
            top: 55,
            width: fillW,
            height: 9,
            child: Container(
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(31)))),
          ),
          Positioned(
            left: 14 + fillW - 3,
            top: 49,
            width: 6,
            height: 20,
            child: Container(
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(9))),
          ),
          Positioned(
            left: 14,
            right: 10,
            top: 76,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(result.band.label,
                      style: _zone.copyWith(fontWeight: FontWeight.w700)),
                  Text('Nota ${_decimal(result.grade)}', style: _zone),
                  Text(goal, style: _zone),
                ]),
          ),
        ]);
      }),
    );
  }
}

class _RepBarChart extends StatelessWidget {
  final List<({int index, double angle})> reps;
  final double reference;

  const _RepBarChart({
    required this.reps,
    required this.reference,
  });

  @override
  Widget build(BuildContext context) {
    final maxRep =
        reps.fold<double>(0, (m, r) => math.max(m, r.angle));
    final maxY = math.max(reference, maxRep) * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 14,
              height: 2,
              color: const Color(0xFF137C9D),
            ),
            const SizedBox(width: 6),
            Text(
              'Referência: ${_degrees(reference)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF137C9D),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 168,
          child: CustomPaint(
            painter: _RepBarChartPainter(
              reps: reps,
              reference: reference,
              maxY: maxY <= 0 ? 1 : maxY,
            ),
          ),
        ),
      ],
    );
  }
}

class _RepBarChartPainter extends CustomPainter {
  final List<({int index, double angle})> reps;
  final double reference;
  final double maxY;

  const _RepBarChartPainter({
    required this.reps,
    required this.reference,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double topPad = 22;
    const double bottomPad = 24;
    const double sidePad = 8;
    final chartH = math.max(10.0, size.height - topPad - bottomPad);
    final chartW = math.max(10.0, size.width - sidePad * 2);
    final baseY = topPad + chartH;

    // Eixo base
    canvas.drawLine(
      Offset(sidePad, baseY),
      Offset(size.width - sidePad, baseY),
      Paint()
        ..color = _Fig.cardBorder
        ..strokeWidth = 1,
    );

    // Barras por repetição
    final slotW = chartW / reps.length;
    final barW = math.min(44.0, slotW * 0.56);

    for (var i = 0; i < reps.length; i++) {
      final rep = reps[i];
      final band = mobilityBand(rep.angle, reference);
      final barColor = switch (band) {
        MobilityBand.adequada => _Fig.green,
        MobilityBand.reduzida => _Fig.amber,
        MobilityBand.limitada => _Fig.red,
      };
      final barH = (rep.angle / maxY).clamp(0.0, 1.0) * chartH;
      final cx = sidePad + slotW * (i + 0.5);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, baseY - barH, barW, barH),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = barColor);

      // Valor acima da barra
      _drawText(
        canvas,
        _degrees(rep.angle),
        Offset(cx, baseY - barH - 16),
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      );

      // Rótulo no eixo X
      _drawText(
        canvas,
        'Rep ${rep.index}',
        Offset(cx, baseY + 6),
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _Fig.text,
        ),
      );
    }

    // Linha tracejada da referência
    final refY = baseY - (reference / maxY).clamp(0.0, 1.0) * chartH;
    final dashPaint = Paint()
      ..color = const Color(0xFF137C9D)
      ..strokeWidth = 1.6;
    const double dashW = 6;
    const double gapW = 4;
    double x = sidePad;
    while (x < size.width - sidePad) {
      final x2 = math.min(x + dashW, size.width - sidePad);
      canvas.drawLine(Offset(x, refY), Offset(x2, refY), dashPaint);
      x += dashW + gapW;
    }
  }

  void _drawText(Canvas canvas, String text, Offset centerTop, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(centerTop.dx - tp.width / 2, centerTop.dy));
  }

  @override
  bool shouldRepaint(covariant _RepBarChartPainter old) =>
      old.reps != reps || old.reference != reference || old.maxY != maxY;
}
