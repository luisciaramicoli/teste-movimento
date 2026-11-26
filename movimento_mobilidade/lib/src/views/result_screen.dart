import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flow.dart';
import '../models/assessment_models.dart';
import '../models/mobility_score.dart';
import '../models/perfil_avaliado.dart';
import '../services/assessment_csv.dart';
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

/// Score no formato "9 (8,7)": inteiro e, entre parênteses, o detalhe.
String _scoreText(double v) => '${v.round()} (${_decimal(v)})';

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

  PerfilAvaliado get _perfil =>
      widget.perfil ?? widget.fluxo?.perfil ?? const PerfilAvaliado();

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
      rows.add(_JointRow(spec: spec, result: joint, months: months));
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
                const SizedBox(height: 10),
                _scoreSummary(result, months),
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

  /// Score e meta; explica quando o score não pode ser calculado.
  Widget _scoreSummary(MobilityScore result, int months) {
    final score = result.score;
    final goal = result.goalScore(months);
    const strong = TextStyle(
        fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black);
    const small = TextStyle(fontSize: 12, color: _Fig.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: _Fig.card,
          border: Border.all(color: _Fig.cardBorder),
          borderRadius: BorderRadius.circular(_Fig.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (score == null || goal == null) ...[
          const Text('Score indisponível', style: strong),
          const SizedBox(height: 4),
          Text(
              'Sem medida válida de: '
              '${result.missing.map((j) => j.label).join(', ')}.',
              style: small),
        ] else
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Score ${_scoreText(score)}', style: strong),
                Text(
                    'Meta $months ${months == 1 ? 'mês' : 'meses'}: '
                    '${_scoreText(goal)}',
                    style: strong),
              ]),
        if (result.reference.provisional) ...[
          const SizedBox(height: 6),
          Text(
              'Referências provisórias. '
              '${result.reference.note ?? 'Valores ilustrativos.'}',
              style: small),
        ],
      ]),
    );
  }

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

    BoxDecoration box() => BoxDecoration(
        color: _Fig.card,
        border: Border.all(color: _Fig.cardBorder),
        borderRadius: BorderRadius.circular(_Fig.radius));

    final profile = Container(
      height: 109,
      decoration: box(),
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
        Positioned(
          left: 83,
          top: 22.5,
          child: CustomPaint(
              size: const Size(15, 26),
              painter: _PointerPainter(const Color(0xFFB0CDD9))),
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
        Positioned(
            left: 46,
            top: 19,
            width: 33,
            height: 30,
            child: Center(child: Text('/10', style: scoreGrey))),
        Positioned(
            left: 13,
            top: 47,
            width: 67,
            height: 30,
            child: Center(child: Text('Atual', style: scoreGrey))),
        const Positioned(left: 151, top: 13, child: Text('Idade', style: small)),
        Positioned(
            left: 151,
            top: 30,
            child: Text(p.idade == null ? '--' : '${p.idade} anos', style: value)),
        const Positioned(left: 151, top: 59, child: Text('Peso', style: small)),
        Positioned(
            left: 151,
            top: 76,
            child: Text(p.pesoKg == null ? '--' : '${n(p.pesoKg)}kg',
                style: value)),
      ]),
    );

    final reach = Container(
      height: 109,
      decoration: box(),
      child: Stack(children: [
        const Positioned(
            top: 13,
            left: 0,
            right: 0,
            child: Center(child: Text('Alcance', style: small))),
        Positioned(
            top: 35,
            left: 0,
            right: 0,
            child: Center(
                child: Text(p.alcanceTexto ?? n(p.alcanceCm),
                    style: const TextStyle(
                        fontSize: 24,
                        height: 28 / 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.black)))),
        const Positioned(
            top: 67,
            left: 0,
            right: 0,
            child: Center(
                child: Text('cm',
                    style: TextStyle(
                        fontSize: 8, height: 9 / 8, color: _Fig.text)))),
        if (p.alcanceClassificacao != null)
          Positioned(
            top: 81,
            left: 7,
            right: 7,
            child: Container(
              height: 21,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0x6BE86969),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(p.alcanceClassificacao!,
                  style: const TextStyle(
                      fontSize: 12,
                      height: 15 / 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.05,
                      color: Color(0xFF913939))),
            ),
          ),
      ]),
    );

    return Row(children: [
      Expanded(flex: 229, child: profile),
      const SizedBox(width: 5),
      Expanded(flex: 102, child: reach),
    ]);
  }

  Widget _buttons() {
    final fluxo = widget.fluxo;
    Widget pill(
        {required Color bg,
        required Color fg,
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
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(42)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: iconSize, color: fg),
            const SizedBox(width: 10),
            Text(text,
                style: TextStyle(
                    fontSize: 16,
                    height: 15 / 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: fg)),
          ]),
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
          fg: const Color(0xFF777777),
          icon: Icons.picture_as_pdf,
          iconSize: 15,
          text: 'Relatório',
          onTap: () async {
            await Clipboard.setData(
                ClipboardData(text: AssessmentCsv.build(_record)));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Relatório (CSV) copiado.')));
            }
          },
        ),
      ],
    );
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
  const _JointRow(
      {required this.spec, required this.result, required this.months});

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
          // Botão de gráfico (46x26, borda B9B9B9).
          Positioned(
            right: 6,
            top: 6,
            width: 46,
            height: 26,
            child: Container(
              decoration: BoxDecoration(
                  border: Border.all(color: _Fig.cardBorder),
                  borderRadius: BorderRadius.circular(31)),
              child: const Icon(Icons.bar_chart, size: 18, color: _Fig.cardBorder),
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
