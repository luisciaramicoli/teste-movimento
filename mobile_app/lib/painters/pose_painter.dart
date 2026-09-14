import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/joint_angle.dart';
import '../services/motion_trail_service.dart';

class PosePainter extends CustomPainter {
  final Map<String, JointAngleData> anglesData;
  final MotionTrailService motionTrail;
  final bool showAngles;
  final bool showSkeleton;

  PosePainter({
    required this.anglesData,
    required this.motionTrail,
    this.showAngles = true,
    this.showSkeleton = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Desenhar trilhas de cometa (Comet Trail)
    if (motionTrail.enabled) {
      _drawMotionTrails(canvas);
    }

    // 2. Desenhar conexões ósseas do esqueleto
    if (showSkeleton) {
      _drawSkeleton(canvas);
    }

    // 3. Desenhar círculos e badges de ângulos nas articulações
    if (showAngles) {
      _drawJointBadges(canvas);
    }
  }

  void _drawMotionTrails(Canvas canvas) {
    for (final entry in motionTrail.trails.entries) {
      final name = entry.key;
      final points = entry.value.toList();
      if (points.length < 2) continue;

      final baseColor = motionTrail.jointColors[name] ?? Colors.cyanAccent;

      for (int i = 1; i < points.length; i++) {
        final p1 = Offset(points[i - 1].x, points[i - 1].y);
        final p2 = Offset(points[i].x, points[i].y);

        final alpha = (i / points.length).clamp(0.1, 0.85);
        final strokeWidth = (4.0 * (i / points.length)).clamp(1.0, 4.0);

        final paint = Paint()
          ..color = baseColor.withOpacity(alpha)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  void _drawSkeleton(Canvas canvas) {
    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.75)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    void drawBone(String keyA, String keyB) {
      final dataA = anglesData[keyA];
      final dataB = anglesData[keyB];
      if (dataA != null && dataA.isValid && dataB != null && dataB.isValid) {
        if (dataA.vertex != null && dataB.vertex != null) {
          canvas.drawLine(
            Offset(dataA.vertex!.x, dataA.vertex!.y),
            Offset(dataB.vertex!.x, dataB.vertex!.y),
            bonePaint,
          );
        }
      }
    }

    // Conexões dos membros
    drawBone('ombro_esq', 'ombro_dir');
    drawBone('ombro_esq', 'cotovelo_esq');
    drawBone('ombro_dir', 'cotovelo_dir');
    drawBone('ombro_esq', 'quadril_esq');
    drawBone('ombro_dir', 'quadril_dir');
    drawBone('quadril_esq', 'quadril_dir');
    drawBone('quadril_esq', 'joelho_esq');
    drawBone('quadril_dir', 'joelho_dir');
  }

  void _drawJointBadges(Canvas canvas) {
    final jointCirclePaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.fill;

    final jointOuterPaint = Paint()
      ..color = const Color(0xFFFF9100)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final badgeBgPaint = Paint()
      ..color = const Color(0xDD1E1E1E)
      ..style = PaintingStyle.fill;

    final badgeBorderPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    anglesData.forEach((key, data) {
      if (!data.isValid || data.angle == null || data.vertex == null) return;

      final vOffset = Offset(data.vertex!.x, data.vertex!.y);

      // Círculo no ponto articular
      canvas.drawCircle(vOffset, 6.0, jointCirclePaint);
      canvas.drawCircle(vOffset, 8.0, jointOuterPaint);

      // Texto do ângulo em graus
      final textSpan = TextSpan(
        text: '${data.angle!.round()}°',
        style: const TextStyle(
          color: Color(0xFF00FF7F),
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgePadding = const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0);
      final badgeW = textPainter.width + badgePadding.horizontal;
      final badgeH = textPainter.height + badgePadding.vertical;

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(vOffset.dx + 10, vOffset.dy - badgeH / 2, badgeW, badgeH),
        const Radius.circular(4.0),
      );

      canvas.drawRRect(badgeRect, badgeBgPaint);
      canvas.drawRRect(badgeRect, badgeBorderPaint);

      textPainter.paint(
        canvas,
        Offset(vOffset.dx + 10 + badgePadding.left, vOffset.dy - textPainter.height / 2),
      );
    });
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) => true;
}

