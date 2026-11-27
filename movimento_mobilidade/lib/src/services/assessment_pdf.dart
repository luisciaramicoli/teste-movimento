import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/assessment_models.dart';
import '../models/mobility_score.dart';
import '../models/perfil_avaliado.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Cores do relatório: as mesmas do tema e da tela de resultado.
final _header = PdfColor.fromInt(AppColors.header.value);
final _card = PdfColor.fromInt(ResultColors.card.value);
final _cardBorder = PdfColor.fromInt(ResultColors.cardBorder.value);
final _track = PdfColor.fromInt(ResultColors.track.value);
final _text = PdfColor.fromInt(ResultColors.text.value);
final _muted = PdfColor.fromInt(AppColors.textSecondary.value);
final _badge = PdfColor.fromInt(ResultColors.badgeBg.value);
final _teal = PdfColor.fromInt(ResultColors.badgeScore.value);
final _green = PdfColor.fromInt(ResultColors.green.value);
final _amber = PdfColor.fromInt(ResultColors.amber.value);
final _red = PdfColor.fromInt(ResultColors.red.value);
// Âmbar a 22% sobre branco, como no alerta da tela.
const _amberSoft = PdfColor.fromInt(0xFFFCEED6);

const double _radius = 14;

/// Ícone de cada articulação, com os mesmos ajustes da tela: o joelho é
/// espelhado, e o quadril tem uma sobra à direita na arte original.
const Map<MobilityJoint, ({String file, bool flip, double cropRight})> _icons = {
  MobilityJoint.ombroDir: (file: 'icone_ombro_dir', flip: false, cropRight: 0),
  MobilityJoint.ombroEsq: (file: 'icone_ombro_esq', flip: false, cropRight: 0),
  MobilityJoint.quadril: (file: 'icone_quadril', flip: false, cropRight: 0.07),
  MobilityJoint.joelho: (file: 'icone_joelho', flip: true, cropRight: 0),
  MobilityJoint.tornozelo: (file: 'icone_tornozelo', flip: false, cropRight: 0),
};

/// As imagens não são distribuídas no repositório: sem elas, o relatório sai
/// sem ícones.
Future<Map<MobilityJoint, pw.ImageProvider>> _loadIcons() async {
  final images = <MobilityJoint, pw.ImageProvider>{};
  for (final entry in _icons.entries) {
    try {
      final data = await rootBundle.load(
          'packages/movimento_mobilidade/assets/images/${entry.value.file}.png');
      images[entry.key] = _blackToAlpha(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          entry.value.cropRight);
    } catch (_) {}
  }
  return images;
}

/// Mesma regra da tela: o brilho do pixel vira a opacidade, então o fundo preto
/// da arte fica transparente.
pw.ImageProvider _blackToAlpha(Uint8List png, double cropRight) {
  var art = img.decodePng(png)!.convert(numChannels: 4);
  if (cropRight > 0) {
    art = img.copyCrop(art,
        x: 0,
        y: 0,
        width: (art.width * (1 - cropRight)).round(),
        height: art.height);
  }
  for (final pixel in art) {
    final brightness =
        0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;
    pixel.a = (4 * brightness).clamp(0, 255);
  }
  return pw.MemoryImage(img.encodePng(art));
}

PdfColor _bandColor(MobilityBand band) => switch (band) {
      MobilityBand.adequada => _green,
      MobilityBand.reduzida => _amber,
      MobilityBand.limitada => _red,
    };

pw.BoxDecoration _box(PdfColor color, {PdfColor? border}) => pw.BoxDecoration(
      color: color,
      border: border == null ? null : pw.Border.all(color: border, width: 0.8),
      borderRadius: pw.BorderRadius.circular(_radius),
    );

pw.TextStyle _style(double size, {PdfColor? color, bool bold = false}) =>
    pw.TextStyle(
        fontSize: size,
        color: color ?? _text,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

Future<Uint8List> buildAssessmentPdf(
    AssessmentRecord record, PerfilAvaliado profile) async {
  final result = record.analysis;
  final months = profile.jornadaMeses;
  final icons = await _loadIcons();
  final asymmetry = result.shoulderAsymmetry;
  final doc = pw.Document(title: 'Relatório de mobilidade');

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 26),
    footer: (context) => pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
          'Voluntário ${record.volunteerCode}  ·  Teste ${record.testNumber}'
          '  ·  Página ${context.pageNumber} de ${context.pagesCount}',
          style: _style(8, color: _muted)),
    ),
    build: (_) => [
      _titleBar(record),
      pw.SizedBox(height: 12),
      _scoreCard(result, months, profile),
      pw.SizedBox(height: 14),
      for (final joint in MobilityJoint.values) ...[
        _jointCard(joint, result.joint(joint), record.reference.of(joint),
            months, icons[joint]),
        pw.SizedBox(height: 7),
        if (joint == MobilityJoint.ombroEsq &&
            asymmetry != null &&
            asymmetry.alert) ...[
          _asymmetryAlert(asymmetry),
          pw.SizedBox(height: 7),
        ],
      ],
      pw.SizedBox(height: 4),
      pw.Text(
          'Os ângulos são a amplitude média das repetições (quadril e joelho: '
          'flexão; tornozelo: dorsiflexão). DP: desvio-padrão das repetições '
          'com medida válida. A barra cheia equivale à referência.',
          style: _style(8, color: _muted)),
      if (result.reference.note case final note?) ...[
        pw.SizedBox(height: 4),
        pw.Text(note, style: _style(8, color: _muted)),
      ],
    ],
  ));
  return doc.save();
}

/// Faixa preta com o título, como o cabeçalho das telas.
pw.Widget _titleBar(AssessmentRecord record) {
  final date = record.createdAt.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return pw.Container(
    decoration: _box(_header),
    padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Mobilidade', style: _style(22, color: PdfColors.white)),
            pw.SizedBox(height: 2),
            pw.Text('Relatório de avaliação',
                style: _style(10, color: PdfColors.grey400)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
                'Voluntário ${record.volunteerCode}   |   Teste ${record.testNumber}',
                style: _style(11, color: PdfColors.white, bold: true)),
            pw.SizedBox(height: 4),
            pw.Text(
                '${formatDatePtBr(date)} às ${pad(date.hour)}:${pad(date.minute)}',
                style: _style(10, color: PdfColors.grey400)),
          ],
        ),
      ],
    ),
  );
}

/// Selo da nota, meta da Jornada e dados do avaliado.
pw.Widget _scoreCard(MobilityScore result, int months, PerfilAvaliado profile) {
  final score = result.score;
  final goal = result.goalScore(months);

  pw.Widget info(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _style(9, color: _muted)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: _style(13, bold: true)),
        ],
      );

  return pw.Container(
    decoration: _box(_card, border: _cardBorder),
    padding: const pw.EdgeInsets.all(12),
    child: pw.Row(children: [
      pw.Container(
        width: 92,
        padding: const pw.EdgeInsets.symmetric(vertical: 9),
        decoration: _box(_badge),
        child: pw.Column(children: [
          pw.Text(score == null ? '--' : formatDecimalPtBr(score),
              style: _style(30, color: _teal, bold: true)),
          pw.Text('de 10', style: _style(9)),
        ]),
      ),
      pw.SizedBox(width: 16),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(score == null ? 'Score indisponível' : 'Score atual',
                style: _style(15, bold: true)),
            pw.SizedBox(height: 4),
            if (goal != null)
              pw.Text(
                  'Meta em $months ${months == 1 ? "mês" : "meses"}: '
                  '${formatDecimalPtBr(goal)} / 10',
                  style: _style(11, color: _teal, bold: true))
            else
              pw.Text(
                  'Falta medir: ${result.missing.map((j) => j.label).join(', ')}.',
                  style: _style(9, color: _muted)),
          ],
        ),
      ),
      if (profile.idade != null) ...[
        info('Idade', '${profile.idade} anos'),
        pw.SizedBox(width: 22),
      ],
      if (profile.pesoKg != null) ...[
        info('Peso',
            '${formatCompactNumber(profile.pesoKg).replaceAll('.', ',')} kg'),
        pw.SizedBox(width: 6),
      ],
    ]),
  );
}

pw.Widget _icon(MobilityJoint joint, pw.ImageProvider? image) {
  const double size = 38;
  if (image == null) return pw.SizedBox(width: 0, height: size);
  final style = _icons[joint]!;
  pw.Widget art = pw.SizedBox(
      width: size,
      height: size,
      child: pw.Image(image, fit: pw.BoxFit.contain));
  if (style.flip) {
    art = pw.Transform(
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      alignment: pw.Alignment.center,
      child: art,
    );
  }
  return pw.Padding(padding: const pw.EdgeInsets.only(right: 10), child: art);
}

/// Barra proporcional à referência, com o marcador da tela de resultado.
pw.Widget _bar(double fraction, PdfColor color) {
  const parts = 1000;
  final filled = (fraction.clamp(0.0, 1.0) * parts).round();
  return pw.SizedBox(
    height: 12,
    child: pw.Row(children: [
      if (filled > 0)
        pw.Expanded(flex: filled, child: pw.Container(height: 6, color: color)),
      pw.Container(
          width: 4,
          height: 12,
          decoration: pw.BoxDecoration(
              color: color, borderRadius: pw.BorderRadius.circular(2))),
      if (filled < parts)
        pw.Expanded(
            flex: parts - filled,
            child: pw.Container(height: 6, color: _track)),
    ]),
  );
}

pw.Widget _jointCard(MobilityJoint joint, JointScore? measured,
    double reference, int months, pw.ImageProvider? icon) {
  final color = measured == null ? _cardBorder : _bandColor(measured.band);
  final deviation = measured?.deviation;

  pw.Widget detail(String label, String value) => pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$label ', style: _style(9, color: _muted)),
          pw.TextSpan(text: value, style: _style(9, bold: true)),
        ]),
      );

  return pw.Container(
    decoration: _box(_card),
    padding: const pw.EdgeInsets.fromLTRB(12, 8, 14, 9),
    child: pw.Column(children: [
      pw.Row(children: [
        _icon(joint, icon),
        pw.Expanded(child: pw.Text(joint.label, style: _style(13, bold: true))),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration:
              pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(9)),
          child: pw.Text(measured?.band.label ?? 'Sem medida',
              style: _style(9, bold: true)),
        ),
        pw.SizedBox(width: 12),
        pw.SizedBox(
          width: 70,
          child: pw.Text(
              measured == null ? '--' : formatDegreesPtBr(measured.angle),
              textAlign: pw.TextAlign.right,
              style: _style(19, bold: true)),
        ),
      ]),
      pw.SizedBox(height: 5),
      _bar(measured == null ? 0 : measured.angle / reference, color),
      pw.SizedBox(height: 5),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          detail(
              'Nota',
              measured == null ? '--' : formatDecimalPtBr(measured.grade)),
          detail(
              'DP', deviation == null ? '--' : formatDegreesPtBr(deviation)),
          detail('Referência', formatDegreesPtBr(reference)),
          detail(
              'Meta',
              measured == null
                  ? '--'
                  : measured.atReference
                      ? 'manter'
                      : formatDegreesPtBr(measured.goalAngle(months))),
        ],
      ),
    ]),
  );
}

pw.Widget _asymmetryAlert(ShoulderAsymmetry asymmetry) => pw.Container(
      width: double.infinity,
      decoration: _box(_amberSoft, border: _amber),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: pw.Text(
          'Atenção: diferença de ${asymmetry.percent.round()}% entre os ombros.',
          style: _style(10, bold: true)),
    );
