import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/joint_angle.dart';
import '../theme/app_theme.dart';

/// Sobreposição técnica: esqueleto em linha fina, valores angulares das
/// articulações avaliadas e moldura de enquadramento. Sem brilhos nem sombras.
class AssessmentOverlayPainter extends CustomPainter {
  final ExtractedPoseData? pose;
  final List<String> trackedJoints;
  final bool framingOk;

  /// Cor de alerta atual (âmbar/vermelho) usada na moldura quando fora do enquadramento.
  final Color alertColor;

  /// 0..1 — pulso da moldura de alerta.
  final double pulse;

  const AssessmentOverlayPainter({
    required this.pose,
    required this.trackedJoints,
    required this.framingOk,
    this.alertColor = AppColors.warn,
    this.pulse = 1,
  });

  static const List<List<String>> _bones = [
    ['LEFT_SHOULDER', 'RIGHT_SHOULDER'],
    ['LEFT_HIP', 'RIGHT_HIP'],
    ['LEFT_SHOULDER', 'LEFT_HIP'],
    ['RIGHT_SHOULDER', 'RIGHT_HIP'],
    ['LEFT_SHOULDER', 'LEFT_ELBOW'],
    ['LEFT_ELBOW', 'LEFT_WRIST'],
    ['RIGHT_SHOULDER', 'RIGHT_ELBOW'],
    ['RIGHT_ELBOW', 'RIGHT_WRIST'],
    ['LEFT_HIP', 'LEFT_KNEE'],
    ['LEFT_KNEE', 'LEFT_ANKLE'],
    ['LEFT_ANKLE', 'LEFT_FOOT_INDEX'],
    ['RIGHT_HIP', 'RIGHT_KNEE'],
    ['RIGHT_KNEE', 'RIGHT_ANKLE'],
    ['RIGHT_ANKLE', 'RIGHT_FOOT_INDEX'],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _paintFrame(canvas, size);
    final p = pose;
    if (p == null) return;

    final color = framingOk ? AppColors.ok : alertColor;
    // Contorno escuro por baixo para o esqueleto aparecer sobre fundos claros.
    final outline = Paint()
      ..color = const Color(0xCC000000)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    for (final paint in [outline, line]) {
      for (final b in _bones) {
        final a = p.landmarks[b[0]];
        final c = p.landmarks[b[1]];
        if (a != null && c != null) {
          canvas.drawLine(Offset(a.x, a.y), Offset(c.x, c.y), paint);
        }
      }
    }
    final dotBorder = Paint()..color = const Color(0xCC000000);
    final dot = Paint()..color = Colors.white;
    for (final pt in p.landmarks.values) {
      canvas.drawCircle(Offset(pt.x, pt.y), 6, dotBorder);
      canvas.drawCircle(Offset(pt.x, pt.y), 4, dot);
    }

    _paintLabels(canvas, size, p);
  }

  void _paintLabels(Canvas canvas, Size size, ExtractedPoseData pose) {
    final visible = [
      for (final key in trackedJoints)
        if (pose.angles[key] case final d?)
          if (d.isValid && d.angle != null && d.vertex != null) d
    ];
    // No perfil, quadril e coluna usam o mesmo ponto: o nome os distingue.
    final named = visible.any((d) => d.key == 'coluna');
    final painters = [
      for (final d in visible)
        TextPainter(
          text: TextSpan(
            text: labelText(d.key, d.angle!, nameHip: named),
            style: const TextStyle(
                color: Color(0xFF5CE1FF),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black, blurRadius: 3)]),
          ),
          textDirection: TextDirection.ltr,
        )..layout()
    ];
    final places = placeLabels(
      [for (final d in visible) Offset(d.vertex!.x, d.vertex!.y)],
      [for (final t in painters) t.size],
      size,
    );
    for (var i = 0; i < painters.length; i++) {
      painters[i].paint(canvas, places[i].topLeft);
    }
  }

  /// Texto do rótulo. A coluna sempre leva o nome; o quadril, quando a coluna
  /// também é exibida ([nameHip]).
  static String labelText(String key, double angle, {bool nameHip = false}) {
    final value = '${angle.round()}°';
    if (key == 'coluna') return 'Coluna $value';
    if (nameHip && key.startsWith('quadril')) return 'Quadril $value';
    return value;
  }

  /// Posiciona um rótulo para cada vértice, sem sobrepor outro e dentro de
  /// [canvas]. Tenta à direita do ponto, depois à esquerda e, por fim, desce ou
  /// sobe. Os pontos mais à direita são posicionados primeiro, para que num par
  /// próximo o da esquerda vá para o lado de fora.
  @visibleForTesting
  static List<Rect> placeLabels(
      List<Offset> vertices, List<Size> sizes, Size canvas) {
    const gap = 10.0;
    const spacing = 2.0;
    final order = List<int>.generate(vertices.length, (i) => i)
      ..sort((a, b) {
        final byX = vertices[b].dx.compareTo(vertices[a].dx);
        return byX != 0 ? byX : a.compareTo(b);
      });
    final result = List<Rect>.filled(vertices.length, Rect.zero);
    final placed = <Rect>[];

    Rect inside(Offset at, Size s) => Offset(
          at.dx.clamp(0.0, math.max(0.0, canvas.width - s.width)),
          at.dy.clamp(0.0, math.max(0.0, canvas.height - s.height)),
        ) &
        s;

    for (final i in order) {
      final v = vertices[i];
      final s = sizes[i];
      final right = v.dx + gap;
      final left = v.dx - gap - s.width;
      // Sem espaço à direita, tenta antes a esquerda, para não cobrir o ponto.
      final sides =
          right + s.width <= canvas.width ? [right, left] : [left, right];
      Rect? chosen;
      for (var step = 0; chosen == null && step <= vertices.length; step++) {
        final shift = step * (s.height + spacing);
        for (final dy in step == 0 ? [0.0] : [shift, -shift]) {
          for (final x in sides) {
            final candidate = inside(Offset(x, v.dy - gap + dy), s);
            if (chosen == null &&
                !placed.any((r) => r.overlaps(candidate.inflate(spacing / 2)))) {
              chosen = candidate;
            }
          }
        }
      }
      result[i] = chosen ?? inside(Offset(v.dx + gap, v.dy - gap), s);
      placed.add(result[i]);
    }
    return result;
  }

  void _paintFrame(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(size.width * 0.05, size.height * 0.07,
        size.width * 0.95, size.height * 0.93);

    // Borda arredondada acompanhando o cartão da câmera: verde quando correto,
    // vermelha e pulsante (suave) quando há algo a corrigir.
    final border = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height).deflate(2),
        const Radius.circular(22));
    if (framingOk) {
      canvas.drawRRect(
          border,
          Paint()
            ..color = AppColors.ok
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    } else {
      canvas.drawRRect(
          border,
          Paint()
            ..color = alertColor.withOpacity(0.35 + 0.5 * pulse)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }

    final paint = Paint()
      ..color = framingOk ? AppColors.ok : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 34.0;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * len, 0), paint);
      canvas.drawLine(o, o + Offset(0, dy * len), paint);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomLeft, 1, -1);
    corner(r.bottomRight, -1, -1);

    // Silhueta-guia: onde a cabeça e os pés devem ficar quando não há ninguém
    // corretamente enquadrado.
    if (!framingOk && pose == null) {
      final g = Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      final cx = size.width / 2;
      final top = size.height * 0.14;
      final bottom = size.height * 0.86;
      canvas.drawCircle(Offset(cx, top + size.height * 0.04), size.height * 0.04, g);
      canvas.drawLine(Offset(cx, top + size.height * 0.08), Offset(cx, size.height * 0.52), g);
      canvas.drawLine(Offset(cx - size.width * 0.18, size.height * 0.30),
          Offset(cx + size.width * 0.18, size.height * 0.30), g);
      canvas.drawLine(Offset(cx, size.height * 0.52), Offset(cx - size.width * 0.09, bottom), g);
      canvas.drawLine(Offset(cx, size.height * 0.52), Offset(cx + size.width * 0.09, bottom), g);
    }
  }

  @override
  bool shouldRepaint(covariant AssessmentOverlayPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.framingOk != framingOk ||
      oldDelegate.alertColor != alertColor ||
      oldDelegate.pulse != pulse ||
      oldDelegate.trackedJoints != trackedJoints;
}
