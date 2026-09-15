import 'package:flutter/material.dart';
import '../models/joint_angle.dart';

class PosePainter extends CustomPainter {
  final Map<String, JointAngleData> anglesData;
  final Map<String, Point2D> landmarks;
  final String activeExercise;
  final bool showAngles;
  final bool showSkeleton;

  PosePainter({
    required this.anglesData,
    this.landmarks = const {},
    this.activeExercise = 'free',
    this.showAngles = true,
    this.showSkeleton = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Desenhar conexões ósseas do esqueleto
    if (showSkeleton) {
      _drawSkeleton(canvas);
    }

    // 2. Desenhar círculos e badges de ângulos nas articulações
    if (showAngles) {
      _drawJointBadges(canvas);
    }
  }

  void _drawSkeleton(Canvas canvas) {
    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.85)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final torsoPaint = Paint()
      ..color = const Color(0xFF00B0FF).withOpacity(0.65)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    Point2D? getLandmarkPoint(String key) {
      if (landmarks.containsKey(key)) return landmarks[key];
      switch (key) {
        case 'LEFT_SHOULDER': return anglesData['ombro_esq']?.vertex;
        case 'RIGHT_SHOULDER': return anglesData['ombro_dir']?.vertex;
        case 'LEFT_ELBOW': return anglesData['cotovelo_esq']?.vertex;
        case 'RIGHT_ELBOW': return anglesData['cotovelo_dir']?.vertex;
        case 'LEFT_HIP': return anglesData['quadril_esq']?.vertex;
        case 'RIGHT_HIP': return anglesData['quadril_dir']?.vertex;
        case 'LEFT_KNEE': return anglesData['joelho_esq']?.vertex;
        case 'RIGHT_KNEE': return anglesData['joelho_dir']?.vertex;
        default: return null;
      }
    }

    void drawLineBetween(String keyA, String keyB, [Paint? customPaint]) {
      final ptA = getLandmarkPoint(keyA);
      final ptB = getLandmarkPoint(keyB);
      if (ptA != null && ptB != null) {
        canvas.drawLine(
          Offset(ptA.x, ptA.y),
          Offset(ptB.x, ptB.y),
          customPaint ?? bonePaint,
        );
      }
    }

    // Cabeça e pescoço
    final nose = landmarks['NOSE'];
    final lShoulder = getLandmarkPoint('LEFT_SHOULDER');
    final rShoulder = getLandmarkPoint('RIGHT_SHOULDER');
    if (nose != null && lShoulder != null && rShoulder != null) {
      final midShoulder = Offset((lShoulder.x + rShoulder.x) / 2, (lShoulder.y + rShoulder.y) / 2);
      canvas.drawLine(Offset(nose.x, nose.y), midShoulder, torsoPaint);
    }

    // Clavícula / Ombros
    drawLineBetween('LEFT_SHOULDER', 'RIGHT_SHOULDER', bonePaint);

    // Braço esquerdo: Ombro -> Cotovelo -> Pulso
    drawLineBetween('LEFT_SHOULDER', 'LEFT_ELBOW', bonePaint);
    drawLineBetween('LEFT_ELBOW', 'LEFT_WRIST', bonePaint);

    // Braço direito: Ombro -> Cotovelo -> Pulso
    drawLineBetween('RIGHT_SHOULDER', 'RIGHT_ELBOW', bonePaint);
    drawLineBetween('RIGHT_ELBOW', 'RIGHT_WRIST', bonePaint);

    // Tronco
    drawLineBetween('LEFT_SHOULDER', 'LEFT_HIP', torsoPaint);
    drawLineBetween('RIGHT_SHOULDER', 'RIGHT_HIP', torsoPaint);
    drawLineBetween('LEFT_HIP', 'RIGHT_HIP', torsoPaint);

    // Perna esquerda: Quadril -> Joelho -> Tornozelo
    drawLineBetween('LEFT_HIP', 'LEFT_KNEE', bonePaint);
    drawLineBetween('LEFT_KNEE', 'LEFT_ANKLE', bonePaint);

    // Perna direita: Quadril -> Joelho -> Tornozelo
    drawLineBetween('RIGHT_HIP', 'RIGHT_KNEE', bonePaint);
    drawLineBetween('RIGHT_KNEE', 'RIGHT_ANKLE', bonePaint);
  }

  void _drawJointBadges(Canvas canvas) {
    // 1. Desenhar círculos em todos os marcos disponíveis
    final landmarkDotPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    final landmarkInnerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    landmarks.forEach((key, pt) {
      final offset = Offset(pt.x, pt.y);
      canvas.drawCircle(offset, 4.0, landmarkDotPaint);
      canvas.drawCircle(offset, 2.0, landmarkInnerDotPaint);
    });

    // 2. Badges com valores em graus nos vértices angulares
    final jointCirclePaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.fill;

    final jointOuterPaint = Paint()
      ..color = const Color(0xFFFF9100)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final badgeBgPaint = Paint()
      ..color = const Color(0xE6101418)
      ..style = PaintingStyle.fill;

    final badgeBorderPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Determina quais articulações são o foco principal do exercício atual
    Set<String> priorityJoints = {};
    if (activeExercise == 'squat') {
      priorityJoints = {'joelho_esq', 'joelho_dir', 'quadril_esq', 'quadril_dir'};
    } else if (activeExercise == 'curl' || activeExercise == 'bicep_curl') {
      priorityJoints = {'cotovelo_esq', 'cotovelo_dir'};
    } else if (activeExercise == 'chin_up') {
      priorityJoints = {'cotovelo_esq', 'cotovelo_dir', 'ombro_esq', 'ombro_dir'};
    }

    anglesData.forEach((key, data) {
      if (!data.isValid || data.angle == null || data.vertex == null) return;

      final isPriority = priorityJoints.isEmpty || priorityJoints.contains(key);
      final vOffset = Offset(data.vertex!.x, data.vertex!.y);

      // Círculo no ponto articular
      canvas.drawCircle(vOffset, isPriority ? 6.5 : 4.5, isPriority ? jointCirclePaint : landmarkDotPaint);
      canvas.drawCircle(vOffset, isPriority ? 9.0 : 6.0, jointOuterPaint);

      // Se for um exercício específico e a articulação não for foco, omite o badge numérico para não poluir
      if (priorityJoints.isNotEmpty && !isPriority) return;

      // Texto do ângulo em graus (reutiliza TextPainter em cache)
      final int angleInt = data.angle!.round();
      final textPainter = _getTextPainter(angleInt, isPriority);

      const badgePadding = EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0);
      final badgeW = textPainter.width + badgePadding.horizontal;
      final badgeH = textPainter.height + badgePadding.vertical;

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(vOffset.dx + 8, vOffset.dy - badgeH / 2, badgeW, badgeH),
        const Radius.circular(4.0),
      );

      canvas.drawRRect(badgeRect, badgeBgPaint);
      canvas.drawRRect(badgeRect, isPriority ? badgeBorderPaint : (Paint()..color = Colors.white24..style = PaintingStyle.stroke));

      textPainter.paint(
        canvas,
        Offset(vOffset.dx + 8 + badgePadding.left, vOffset.dy - textPainter.height / 2),
      );
    });
  }

  static final Map<int, TextPainter> _priorityTextPainters = {};
  static final Map<int, TextPainter> _normalTextPainters = {};

  static TextPainter _getTextPainter(int angle, bool isPriority) {
    final cache = isPriority ? _priorityTextPainters : _normalTextPainters;
    return cache.putIfAbsent(angle, () {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$angle°',
          style: TextStyle(
            color: isPriority ? const Color(0xFF00FF7F) : Colors.white70,
            fontSize: isPriority ? 12.0 : 10.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      return textPainter;
    });
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) => true;
}

