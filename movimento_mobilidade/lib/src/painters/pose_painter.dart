import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/joint_angle.dart';
import '../models/protocol_models.dart';

class _BadgeLayoutItem {
  final String key;
  final Offset vertex;
  final TextPainter textPainter;
  final Color statusColor;
  final double width;
  final double height;
  final bool isLeftSide;
  double left;
  double top;

  _BadgeLayoutItem({
    required this.key,
    required this.vertex,
    required this.textPainter,
    required this.statusColor,
    required this.width,
    required this.height,
    required this.isLeftSide,
    required this.left,
    required this.top,
  });

  Rect get rect => Rect.fromLTWH(left, top, width, height);
}

class PosePainter extends CustomPainter {
  final Map<String, JointAngleData> anglesData;
  final Map<String, Point2D> landmarks;
  final String activeExercise;
  final bool showAngles;
  final bool showSkeleton;
  final ProtocolStage protocolStage;
  final PositioningAssessment? positioningAssessment;
  final ProtocolPosture? activePosture;
  final Map<String, JointMatchFeedback> jointFeedbacks;
  final double holdProgress;
  final double evaluationWindowProgress;
  final double postureAccuracyPct;
  final double animationTimeSec;

  // Cache estático da geometria da máscara Gov.br para evitar Path.combine e computeMetrics a cada frame
  static Size? _cachedSize;
  static Rect? _cachedFramingRect;
  static RRect? _cachedFramingRRect;
  static Path? _cachedMaskPath;
  static PathMetric? _cachedBorderMetric;
  static double _cachedBorderLength = 0.0;

  PosePainter({
    required this.anglesData,
    this.landmarks = const {},
    this.activeExercise = 'free',
    this.showAngles = true,
    this.showSkeleton = true,
    this.protocolStage = ProtocolStage.freeRom,
    this.positioningAssessment,
    this.activePosture,
    this.jointFeedbacks = const {},
    this.holdProgress = 0.0,
    this.evaluationWindowProgress = 0.0,
    this.postureAccuracyPct = 0.0,
    this.animationTimeSec = 0.0,
  });

  static void _ensureGeometryCache(Size size) {
    if (_cachedSize == size && _cachedMaskPath != null) return;
    _cachedSize = size;
    final rect = Rect.fromLTWH(
      size.width * 0.06,
      size.height * 0.19,
      size.width * 0.88,
      size.height * 0.69,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(32.0));
    final fullScreenPath = Path()..addRect(Offset.zero & size);
    final holePath = Path()..addRRect(rrect);

    _cachedFramingRect = rect;
    _cachedFramingRRect = rrect;
    _cachedMaskPath = Path.combine(
      PathOperation.difference,
      fullScreenPath,
      holePath,
    );

    final metrics = holePath.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      _cachedBorderMetric = metrics.first;
      _cachedBorderLength = _cachedBorderMetric!.length;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureGeometryCache(size);

    // 1. Máscara vazada estilo Gov.br (usando Path em cache de custo zero)
    if (protocolStage == ProtocolStage.positioning ||
        protocolStage == ProtocolStage.postureReplication) {
      _drawGovStyleCutoutAndFrame(canvas, size);
    }

    // 2. Silhueta-guia limpa e translúcida ao fundo (sem poluir o esqueleto do usuário)
    if (protocolStage == ProtocolStage.postureReplication &&
        activePosture != null) {
      _drawCleanGuideSilhouette(canvas, size, activePosture!);
    }

    // 3. Desenhar conexões ósseas do esqueleto do usuário
    if (showSkeleton) {
      _drawSkeleton(canvas);
    }

    // 4. Desenhar badges de ângulos com posicionamento externo inteligente e anticolisão
    // Na etapa de posicionamento inicial, oculta os badges numéricos para manter a tela 100% limpa
    if (showAngles && protocolStage != ProtocolStage.positioning) {
      _drawNonOverlappingJointBadges(canvas, size);
    }
  }

  void _drawGovStyleCutoutAndFrame(Canvas canvas, Size size) {
    final rect = _cachedFramingRect!;
    final rrect = _cachedFramingRRect!;

    canvas.drawPath(
      _cachedMaskPath!,
      Paint()
        ..color = Colors.black.withOpacity(0.45)
        ..style = PaintingStyle.fill,
    );

    Color frameColor = const Color(0xFF00E5FF);
    if (protocolStage == ProtocolStage.positioning) {
      final pos = positioningAssessment;
      if (pos != null) {
        if (pos.isAllGood) {
          frameColor = const Color(0xFF00E676);
        } else if (pos.areAllPointsVisible &&
            (pos.isDistanceGood || pos.isCentered)) {
          frameColor = const Color(0xFFFFD700);
        } else {
          frameColor = const Color(0xFFFF3B30);
        }
      }
    } else if (protocolStage == ProtocolStage.postureReplication) {
      if (holdProgress > 0.01) {
        frameColor = const Color(0xFF00E676);
      } else if (postureAccuracyPct >= 55.0) {
        frameColor = const Color(0xFFFFD700);
      } else {
        frameColor = const Color(0xFF00E5FF);
      }
    }

    final floorY = rect.top + rect.height * 0.92;
    canvas.drawLine(
      Offset(rect.left + 30, floorY),
      Offset(rect.right - 30, floorY),
      Paint()
        ..color = frameColor.withOpacity(0.45)
        ..strokeWidth = 2.5,
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = frameColor.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0,
    );

    final double ringProg =
        holdProgress > 0.02 ? holdProgress : evaluationWindowProgress;
    final Color ringColor = holdProgress > 0.02
        ? const Color(0xFF00FF7F)
        : const Color(0xFFFFD700);

    if (ringProg > 0.01 && _cachedBorderMetric != null) {
      final Path extract = _cachedBorderMetric!.extractPath(
        0.0,
        _cachedBorderLength * ringProg.clamp(0.0, 1.0),
      );
      canvas.drawPath(
        extract,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Desenha o modelo de referência como uma silhueta translúcida suave ao fundo,
  /// sem bolinhas brancas nem halos pretos que antes brigavam com o esqueleto real do usuário.
  void _drawCleanGuideSilhouette(
    Canvas canvas,
    Size size,
    ProtocolPosture posture,
  ) {
    final rect = _cachedFramingRect!;
    final targetMap = posture.guideLandmarksNormalized;
    if (targetMap.isEmpty) return;

    Offset? toScreenTarget(String key) {
      final norm = targetMap[key];
      if (norm == null) return null;
      return Offset(
        rect.left + norm.x * rect.width,
        rect.top + norm.y * rect.height,
      );
    }

    bool isLimbMatched(String? jointKey) {
      if (jointKey == null) return false;
      return jointFeedbacks[jointKey]?.isMatched ?? false;
    }

    void drawGuideBone(String a, String b, [String? relatedJointKey]) {
      final ptA = toScreenTarget(a);
      final ptB = toScreenTarget(b);
      if (ptA != null && ptB != null) {
        final matched = isLimbMatched(relatedJointKey);
        final coreColor = matched
            ? const Color(0xFF00E676).withOpacity(0.32)
            : const Color(0xFFFFEA00).withOpacity(0.38);

        canvas.drawLine(
          ptA,
          ptB,
          Paint()
            ..color = coreColor
            ..strokeWidth = 12.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final nose = toScreenTarget('NOSE');
    final lShT = toScreenTarget('LEFT_SHOULDER');
    final rShT = toScreenTarget('RIGHT_SHOULDER');
    if (nose != null) {
      if (lShT != null && rShT != null) {
        final midShoulder = Offset(
          (lShT.dx + rShT.dx) / 2,
          (lShT.dy + rShT.dy) / 2,
        );
        canvas.drawLine(
          nose,
          midShoulder,
          Paint()
            ..color = const Color(0xFFFFEA00).withOpacity(0.32)
            ..strokeWidth = 10.0
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(
        nose,
        24.0,
        Paint()
          ..color = const Color(0xFFFFEA00).withOpacity(0.38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0,
      );
    }

    drawGuideBone('LEFT_SHOULDER', 'RIGHT_SHOULDER');
    drawGuideBone('LEFT_SHOULDER', 'LEFT_ELBOW', 'ombro_esq');
    drawGuideBone('LEFT_ELBOW', 'LEFT_WRIST', 'cotovelo_esq');
    drawGuideBone('RIGHT_SHOULDER', 'RIGHT_ELBOW', 'ombro_dir');
    drawGuideBone('RIGHT_ELBOW', 'RIGHT_WRIST', 'cotovelo_dir');
    drawGuideBone('LEFT_SHOULDER', 'LEFT_HIP', 'quadril_esq');
    drawGuideBone('RIGHT_SHOULDER', 'RIGHT_HIP', 'quadril_dir');
    drawGuideBone('LEFT_HIP', 'RIGHT_HIP');
    drawGuideBone('LEFT_HIP', 'LEFT_KNEE', 'quadril_esq');
    drawGuideBone('LEFT_KNEE', 'LEFT_ANKLE', 'joelho_esq');
    drawGuideBone('RIGHT_HIP', 'RIGHT_KNEE', 'quadril_dir');
    drawGuideBone('RIGHT_KNEE', 'RIGHT_ANKLE', 'joelho_dir');
    drawGuideBone('LEFT_ANKLE', 'LEFT_HEEL', 'tornozelo_esq');
    drawGuideBone('LEFT_HEEL', 'LEFT_FOOT_INDEX', 'tornozelo_esq');
    drawGuideBone('RIGHT_ANKLE', 'RIGHT_HEEL', 'tornozelo_dir');
    drawGuideBone('RIGHT_HEEL', 'RIGHT_FOOT_INDEX', 'tornozelo_dir');
  }

  void _drawSkeleton(Canvas canvas) {
    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final torsoPaint = Paint()
      ..color = const Color(0xFFE51937)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final footPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    Point2D? getLandmarkPoint(String key) {
      if (landmarks.containsKey(key)) return landmarks[key];
      switch (key) {
        case 'LEFT_SHOULDER':
          return anglesData['ombro_esq']?.vertex;
        case 'RIGHT_SHOULDER':
          return anglesData['ombro_dir']?.vertex;
        case 'LEFT_ELBOW':
          return anglesData['cotovelo_esq']?.vertex;
        case 'RIGHT_ELBOW':
          return anglesData['cotovelo_dir']?.vertex;
        case 'LEFT_HIP':
          return anglesData['quadril_esq']?.vertex;
        case 'RIGHT_HIP':
          return anglesData['quadril_dir']?.vertex;
        case 'LEFT_KNEE':
          return anglesData['joelho_esq']?.vertex;
        case 'RIGHT_KNEE':
          return anglesData['joelho_dir']?.vertex;
        default:
          return null;
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

    final nose = landmarks['NOSE'];
    final lShoulder = getLandmarkPoint('LEFT_SHOULDER');
    final rShoulder = getLandmarkPoint('RIGHT_SHOULDER');
    if (nose != null && lShoulder != null && rShoulder != null) {
      final midShoulder = Offset(
        (lShoulder.x + rShoulder.x) / 2,
        (lShoulder.y + rShoulder.y) / 2,
      );
      canvas.drawLine(Offset(nose.x, nose.y), midShoulder, torsoPaint);
    }

    drawLineBetween('LEFT_SHOULDER', 'RIGHT_SHOULDER', bonePaint);
    drawLineBetween('LEFT_SHOULDER', 'LEFT_ELBOW', bonePaint);
    drawLineBetween('LEFT_ELBOW', 'LEFT_WRIST', bonePaint);
    drawLineBetween('RIGHT_SHOULDER', 'RIGHT_ELBOW', bonePaint);
    drawLineBetween('RIGHT_ELBOW', 'RIGHT_WRIST', bonePaint);
    drawLineBetween('LEFT_SHOULDER', 'LEFT_HIP', torsoPaint);
    drawLineBetween('RIGHT_SHOULDER', 'RIGHT_HIP', torsoPaint);
    drawLineBetween('LEFT_HIP', 'RIGHT_HIP', torsoPaint);
    drawLineBetween('LEFT_HIP', 'LEFT_KNEE', bonePaint);
    drawLineBetween('LEFT_KNEE', 'LEFT_ANKLE', bonePaint);
    drawLineBetween('RIGHT_HIP', 'RIGHT_KNEE', bonePaint);
    drawLineBetween('RIGHT_KNEE', 'RIGHT_ANKLE', bonePaint);

    drawLineBetween('LEFT_ANKLE', 'LEFT_HEEL', footPaint);
    drawLineBetween('LEFT_HEEL', 'LEFT_FOOT_INDEX', footPaint);
    drawLineBetween('LEFT_ANKLE', 'LEFT_FOOT_INDEX', footPaint);

    drawLineBetween('RIGHT_ANKLE', 'RIGHT_HEEL', footPaint);
    drawLineBetween('RIGHT_HEEL', 'RIGHT_FOOT_INDEX', footPaint);
    drawLineBetween('RIGHT_ANKLE', 'RIGHT_FOOT_INDEX', footPaint);

    // Pontos das articulações discretos e nítidos
    final landmarkDotPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    final heelDotPaint = Paint()
      ..color = const Color(0xFFFF4081)
      ..style = PaintingStyle.fill;
    final innerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    landmarks.forEach((key, pt) {
      final offset = Offset(pt.x, pt.y);
      final isHeelOrFoot = key.contains('HEEL') || key.contains('FOOT_INDEX');
      canvas.drawCircle(
        offset,
        isHeelOrFoot ? 5.5 : 4.0,
        isHeelOrFoot ? heelDotPaint : landmarkDotPaint,
      );
      canvas.drawCircle(offset, 2.0, innerDot);
    });
  }

  /// Posiciona os badges do lado esquerdo para FORA à esquerda, os do lado direito para FORA à direita,
  /// e aplica separação vertical automática para que NENHUM item jamais se sobreponha!
  void _drawNonOverlappingJointBadges(Canvas canvas, Size size) {
    Set<String> priorityJoints = {};
    if (protocolStage == ProtocolStage.postureReplication &&
        activePosture != null) {
      priorityJoints = activePosture!.targetAngles.keys.toSet();
    }

    final List<_BadgeLayoutItem> leftBadges = [];
    final List<_BadgeLayoutItem> rightBadges = [];

    const badgePadding = EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.5);
    final double centerX = size.width * 0.5;

    anglesData.forEach((key, data) {
      if (!data.isValid || data.angle == null || data.vertex == null) return;
      final isPriority = priorityJoints.isEmpty || priorityJoints.contains(key);
      if (priorityJoints.isNotEmpty && !isPriority) return;

      final vOffset = Offset(data.vertex!.x, data.vertex!.y);
      final feedback = jointFeedbacks[key];
      final bool isMatched = feedback == null || feedback.isMatched;
      final Color statusColor =
          isMatched ? const Color(0xFF00E676) : const Color(0xFFFF9100);

      // Desenha o círculo sobre o vértice da articulação
      canvas.drawCircle(
        vOffset,
        7.5,
        Paint()
          ..color = statusColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        vOffset,
        9.0,
        Paint()
          ..color = Colors.black87
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke,
      );

      final int angleInt = data.angle!.round();
      final textPainter = _getTextPainter(angleInt, true, isMatched);
      final double badgeW = textPainter.width + badgePadding.horizontal;
      final double badgeH = textPainter.height + badgePadding.vertical;

      final bool placeOnLeft = vOffset.dx < centerX;
      final double initialLeft = placeOnLeft
          ? (vOffset.dx - badgeW - 18.0).clamp(6.0, size.width - badgeW - 6.0)
          : (vOffset.dx + 18.0).clamp(6.0, size.width - badgeW - 6.0);
      final double initialTop = (vOffset.dy - badgeH / 2.0)
          .clamp(size.height * 0.16, size.height * 0.88);

      final item = _BadgeLayoutItem(
        key: key,
        vertex: vOffset,
        textPainter: textPainter,
        statusColor: statusColor,
        width: badgeW,
        height: badgeH,
        isLeftSide: placeOnLeft,
        left: initialLeft,
        top: initialTop,
      );

      if (placeOnLeft) {
        leftBadges.add(item);
      } else {
        rightBadges.add(item);
      }
    });

    // Resolve colisões verticais em cada coluna lateral
    void resolveColumnOverlaps(List<_BadgeLayoutItem> list) {
      if (list.length <= 1) return;
      list.sort((a, b) => a.top.compareTo(b.top));
      const double minGap = 6.0;
      for (int i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final curr = list[i];
        final double minAllowedTop = prev.top + prev.height + minGap;
        if (curr.top < minAllowedTop) {
          curr.top = minAllowedTop;
        }
      }
    }

    resolveColumnOverlaps(leftBadges);
    resolveColumnOverlaps(rightBadges);

    final badgeBgPaint = Paint()
      ..color = const Color(0xEB0E1218)
      ..style = PaintingStyle.fill;

    void drawBadgeList(List<_BadgeLayoutItem> list) {
      for (final item in list) {
        final Rect rect = item.rect;
        final Offset anchorPt = item.isLeftSide
            ? Offset(rect.right, rect.center.dy)
            : Offset(rect.left, rect.center.dy);

        // Linha guia conectando a etiqueta até a articulação exata
        canvas.drawLine(
          item.vertex,
          anchorPt,
          Paint()
            ..color = item.statusColor.withOpacity(0.75)
            ..strokeWidth = 1.8,
        );

        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(7.0));
        canvas.drawRRect(rrect, badgeBgPaint);
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = item.statusColor
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );

        item.textPainter.paint(
          canvas,
          Offset(
            item.left + badgePadding.left,
            item.top + badgePadding.top,
          ),
        );
      }
    }

    drawBadgeList(leftBadges);
    drawBadgeList(rightBadges);
  }

  static final Map<int, TextPainter> _matchedPriorityTextPainters = {};
  static final Map<int, TextPainter> _unmatchedPriorityTextPainters = {};
  static final Map<int, TextPainter> _normalTextPainters = {};

  static TextPainter _getTextPainter(
    int angle,
    bool isPriority,
    bool isMatched,
  ) {
    final cache = !isPriority
        ? _normalTextPainters
        : (isMatched
            ? _matchedPriorityTextPainters
            : _unmatchedPriorityTextPainters);

    return cache.putIfAbsent(angle, () {
      final Color textColor = !isPriority
          ? Colors.white70
          : (isMatched ? const Color(0xFF00FF7F) : const Color(0xFFFFD54F));
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$angle°',
          style: TextStyle(
            color: textColor,
            fontSize: isPriority ? 14.0 : 11.0,
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
  bool shouldRepaint(covariant PosePainter oldDelegate) =>
      oldDelegate.anglesData != anglesData ||
      oldDelegate.landmarks != landmarks ||
      oldDelegate.protocolStage != protocolStage ||
      oldDelegate.positioningAssessment != positioningAssessment ||
      oldDelegate.activePosture != activePosture ||
      oldDelegate.jointFeedbacks != jointFeedbacks ||
      oldDelegate.holdProgress != holdProgress ||
      oldDelegate.evaluationWindowProgress != evaluationWindowProgress ||
      oldDelegate.postureAccuracyPct != postureAccuracyPct ||
      oldDelegate.showAngles != showAngles ||
      oldDelegate.showSkeleton != showSkeleton;
}
