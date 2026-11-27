import 'joint_angle.dart';

enum ProtocolStage {
  positioning,
  postureReplication,
  completed,
  freeRom,
}

class AngleTargetRange {
  final String jointKey;
  final String label;
  final double targetAngle;
  final double tolerance;

  const AngleTargetRange({
    required this.jointKey,
    required this.label,
    required this.targetAngle,
    this.tolerance = 18.0,
  });

  double get minAngle => targetAngle - tolerance;
  double get maxAngle => targetAngle + tolerance;

  bool isWithinRange(double angle) =>
      angle >= minAngle && angle <= maxAngle;

  /// Retorna pontuação de 0.0 a 1.0 para quão próximo o ângulo está do alvo
  double scoreForAngle(double angle) {
    final diff = (angle - targetAngle).abs();
    if (diff <= tolerance) return 1.0;
    final excess = diff - tolerance;
    return (1.0 - (excess / 45.0)).clamp(0.0, 1.0);
  }
}

class ProtocolPosture {
  final String id;
  final String title;
  final String shortCommand;
  final String focusSummary;
  final String badge;
  final String instruction;
  final String recommendedView;
  final String gifAssetPath;
  final Map<String, AngleTargetRange> targetAngles;
  final double? minCalfElevationPct;
  final double holdDurationSeconds;
  final double evaluationWindowSeconds;

  /// Coordenadas normalizadas (x: 0..1, y: 0..1) da pose inicial (neutra)
  /// para animar o movimento até a pose-alvo na tela.
  final Map<String, Point2D> startLandmarksNormalized;

  /// Coordenadas normalizadas (x: 0..1, y: 0..1) da pose-alvo dentro da moldura
  final Map<String, Point2D> guideLandmarksNormalized;

  const ProtocolPosture({
    required this.id,
    required this.title,
    required this.shortCommand,
    this.focusSummary = '',
    required this.badge,
    required this.instruction,
    required this.recommendedView,
    required this.gifAssetPath,
    required this.targetAngles,
    required this.startLandmarksNormalized,
    required this.guideLandmarksNormalized,
    this.minCalfElevationPct,
    this.holdDurationSeconds = 2.2,
    this.evaluationWindowSeconds = 8.0,
  });
}

class PositioningAssessment {
  final bool isDistanceGood;
  final String distanceStatus; // 'too_far', 'too_close', 'optimal', 'no_person'
  final String distanceMessage;
  final double bodyHeightRatio;

  final bool isCentered;
  final double horizontalOffset; // -0.5 a +0.5 (0 = centro)
  final String horizontalMessage;

  final bool isAngleGood;
  final double trunkTiltDeg;
  final double bodyOrientationAngle;
  final String bodyOrientationLabel;
  final String angleMessage;

  final bool areAllPointsVisible;
  final List<String> missingParts;
  final String visibilityMessage;

  final double holdProgress; // 0.0 a 1.0

  const PositioningAssessment({
    required this.isDistanceGood,
    required this.distanceStatus,
    required this.distanceMessage,
    required this.bodyHeightRatio,
    required this.isCentered,
    required this.horizontalOffset,
    required this.horizontalMessage,
    required this.isAngleGood,
    required this.trunkTiltDeg,
    required this.bodyOrientationAngle,
    required this.bodyOrientationLabel,
    required this.angleMessage,
    required this.areAllPointsVisible,
    required this.missingParts,
    required this.visibilityMessage,
    this.holdProgress = 0.0,
  });

  bool get isAllGood =>
      isDistanceGood && isCentered && isAngleGood && areAllPointsVisible;

  String get primaryGuidance {
    if (!areAllPointsVisible) return visibilityMessage;
    if (!isDistanceGood) return distanceMessage;
    if (!isCentered) return horizontalMessage;
    if (!isAngleGood) return angleMessage;
    return 'Posição perfeita! Mantenha-se parado para iniciar...';
  }

  factory PositioningAssessment.empty() {
    return const PositioningAssessment(
      isDistanceGood: false,
      distanceStatus: 'no_person',
      distanceMessage: 'Posicione-se em frente à câmera',
      bodyHeightRatio: 0.0,
      isCentered: false,
      horizontalOffset: 0.0,
      horizontalMessage: 'Centralize-se na moldura',
      isAngleGood: false,
      trunkTiltDeg: 0.0,
      bodyOrientationAngle: 0.0,
      bodyOrientationLabel: '--',
      angleMessage: 'Aguardando detecção postural',
      areAllPointsVisible: false,
      missingParts: ['Corpo inteiro'],
      visibilityMessage:
          'Afaste-se para mostrar da cabeça aos pés (incluindo calcanhares)',
      holdProgress: 0.0,
    );
  }
}

class JointMatchFeedback {
  final String jointKey;
  final String label;
  final double? currentAngle;
  final double targetAngle;
  final double tolerance;
  final bool isMatched;
  final String adjustmentHint;

  const JointMatchFeedback({
    required this.jointKey,
    required this.label,
    required this.currentAngle,
    required this.targetAngle,
    required this.tolerance,
    required this.isMatched,
    required this.adjustmentHint,
  });
}

/// Representa uma falta de mobilidade, restrição articular ou assimetria detectada no protocolo
class MobilityDeficitItem {
  final String postureId;
  final String postureTitle;
  final String jointKey;
  final String jointLabel;
  final double achievedValue;
  final double targetValue;
  final String unit; // '°' ou '%'
  final String severity; // 'Moderada/Severa' ou 'Leve' ou 'Assimetria'
  final String description;

  const MobilityDeficitItem({
    required this.postureId,
    required this.postureTitle,
    required this.jointKey,
    required this.jointLabel,
    required this.achievedValue,
    required this.targetValue,
    this.unit = '°',
    required this.severity,
    required this.description,
  });
}

class PostureEvaluationResult {
  final String postureId;
  final String postureTitle;
  final String gifAssetPath;
  final double accuracyScorePct;
  final Map<String, double> capturedAngles;
  final Map<String, AngleTargetRange> targetAngles;
  final double maxCalfElevationPct;
  final double maxCalfLeftPct;
  final double maxCalfRightPct;
  final double completionTimeSec;
  final bool completedByIdealHold;
  final String mobilityStatus; // 'Plena', 'Parcial', 'Restrição de Mobilidade'
  final List<MobilityDeficitItem> deficits;

  const PostureEvaluationResult({
    required this.postureId,
    required this.postureTitle,
    required this.gifAssetPath,
    required this.accuracyScorePct,
    required this.capturedAngles,
    required this.targetAngles,
    required this.maxCalfElevationPct,
    this.maxCalfLeftPct = 0.0,
    this.maxCalfRightPct = 0.0,
    required this.completionTimeSec,
    this.completedByIdealHold = true,
    required this.mobilityStatus,
    this.deficits = const [],
  });
}

/// Valores devolvidos pelo protocolo de posturas.
class ProtocolSessionResult {
  /// Posturas avaliadas, com ângulos, status e restrições.
  final List<PostureEvaluationResult> postures;

  /// Motor(es) de pose que processaram os quadros.
  final String engine;

  const ProtocolSessionResult({required this.postures, required this.engine});

  /// Média, de 0 a 100, da proximidade dos ângulos-alvo; 0 sem posturas.
  double get score => averageAccuracy(postures);

  List<MobilityDeficitItem> get deficits =>
      [for (final p in postures) ...p.deficits];

  static double averageAccuracy(List<PostureEvaluationResult> postures) =>
      postures.isEmpty
          ? 0
          : postures.fold<double>(0, (s, p) => s + p.accuracyScorePct) /
              postures.length;
}
