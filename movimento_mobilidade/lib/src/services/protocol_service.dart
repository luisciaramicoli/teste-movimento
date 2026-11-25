import 'dart:math';
import 'package:flutter/material.dart';
import '../models/joint_angle.dart';
import '../models/protocol_models.dart';

const Map<String, Point2D> kNeutralGuideLandmarks = {
  'NOSE': Point2D(0.50, 0.14),
  'LEFT_SHOULDER': Point2D(0.39, 0.25),
  'RIGHT_SHOULDER': Point2D(0.61, 0.25),
  'LEFT_ELBOW': Point2D(0.36, 0.39),
  'RIGHT_ELBOW': Point2D(0.64, 0.39),
  'LEFT_WRIST': Point2D(0.35, 0.52),
  'RIGHT_WRIST': Point2D(0.65, 0.52),
  'LEFT_HIP': Point2D(0.43, 0.52),
  'RIGHT_HIP': Point2D(0.57, 0.52),
  'LEFT_KNEE': Point2D(0.43, 0.71),
  'RIGHT_KNEE': Point2D(0.57, 0.71),
  'LEFT_ANKLE': Point2D(0.43, 0.88),
  'RIGHT_ANKLE': Point2D(0.57, 0.88),
  'LEFT_HEEL': Point2D(0.44, 0.91),
  'RIGHT_HEEL': Point2D(0.56, 0.91),
  'LEFT_FOOT_INDEX': Point2D(0.40, 0.92),
  'RIGHT_FOOT_INDEX': Point2D(0.60, 0.92),
};

/// Posturas de avaliação do protocolo biomecânico com GIFs animados e detecção de faltas de mobilidade.
final List<ProtocolPosture> kDefaultProtocolPostures = [
  const ProtocolPosture(
    id: 'ortostatica',
    title: '1. Posição Neutra (Ortostática)',
    shortCommand: 'FIQUE RETO COM BRAÇOS ABAIXADOS',
    focusSummary: 'FOCO: COLUNA RETA + BRAÇOS AO LADO DO TRONCO + PÉS NO CHÃO',
    badge: 'POSTURA 1/5',
    instruction:
        'Fique em pé, corpo ereto, braços relaxados colados ao lado do tronco e calcanhares apoiados no chão.',
    recommendedView: 'Frontal (0°–30°)',
    gifAssetPath: 'assets/gifs/ortostatica.gif',
    holdDurationSeconds: 2.2,
    evaluationWindowSeconds: 8.0,
    targetAngles: {
      'ombro_esq': AngleTargetRange(
        jointKey: 'ombro_esq',
        label: 'Ombro Esq.',
        targetAngle: 20.0,
        tolerance: 18.0,
      ),
      'ombro_dir': AngleTargetRange(
        jointKey: 'ombro_dir',
        label: 'Ombro Dir.',
        targetAngle: 20.0,
        tolerance: 18.0,
      ),
      'cotovelo_esq': AngleTargetRange(
        jointKey: 'cotovelo_esq',
        label: 'Cotovelo Esq.',
        targetAngle: 168.0,
        tolerance: 20.0,
      ),
      'cotovelo_dir': AngleTargetRange(
        jointKey: 'cotovelo_dir',
        label: 'Cotovelo Dir.',
        targetAngle: 168.0,
        tolerance: 20.0,
      ),
      'quadril_esq': AngleTargetRange(
        jointKey: 'quadril_esq',
        label: 'Quadril Esq.',
        targetAngle: 172.0,
        tolerance: 15.0,
      ),
      'quadril_dir': AngleTargetRange(
        jointKey: 'quadril_dir',
        label: 'Quadril Dir.',
        targetAngle: 172.0,
        tolerance: 15.0,
      ),
      'joelho_esq': AngleTargetRange(
        jointKey: 'joelho_esq',
        label: 'Joelho Esq.',
        targetAngle: 174.0,
        tolerance: 14.0,
      ),
      'joelho_dir': AngleTargetRange(
        jointKey: 'joelho_dir',
        label: 'Joelho Dir.',
        targetAngle: 174.0,
        tolerance: 14.0,
      ),
    },
    startLandmarksNormalized: {
      'NOSE': Point2D(0.50, 0.14),
      'LEFT_SHOULDER': Point2D(0.39, 0.25),
      'RIGHT_SHOULDER': Point2D(0.61, 0.25),
      'LEFT_ELBOW': Point2D(0.30, 0.37),
      'RIGHT_ELBOW': Point2D(0.70, 0.37),
      'LEFT_WRIST': Point2D(0.27, 0.49),
      'RIGHT_WRIST': Point2D(0.73, 0.49),
      'LEFT_HIP': Point2D(0.43, 0.52),
      'RIGHT_HIP': Point2D(0.57, 0.52),
      'LEFT_KNEE': Point2D(0.43, 0.71),
      'RIGHT_KNEE': Point2D(0.57, 0.71),
      'LEFT_ANKLE': Point2D(0.43, 0.88),
      'RIGHT_ANKLE': Point2D(0.57, 0.88),
      'LEFT_HEEL': Point2D(0.44, 0.91),
      'RIGHT_HEEL': Point2D(0.56, 0.91),
      'LEFT_FOOT_INDEX': Point2D(0.40, 0.92),
      'RIGHT_FOOT_INDEX': Point2D(0.60, 0.92),
    },
    guideLandmarksNormalized: kNeutralGuideLandmarks,
  ),
  const ProtocolPosture(
    id: 'bracos_t',
    title: '2. Abdução de Ombros (Braços em T)',
    shortCommand: 'ABRA OS BRAÇOS PARA OS LADOS EM "T" (90°)',
    focusSummary: 'FOCO: OMBROS A 90° ABERTOS PARA OS LADOS (NÃO À FRENTE)',
    badge: 'POSTURA 2/5',
    instruction:
        'Abra os dois braços LATERALMENTE (para os lados, formando um "T") até a altura dos ombros (90°) com cotovelos estendidos.',
    recommendedView: 'Frontal (0°–30°)',
    gifAssetPath: 'assets/gifs/bracos_t.gif',
    holdDurationSeconds: 2.2,
    evaluationWindowSeconds: 8.0,
    targetAngles: {
      'ombro_esq': AngleTargetRange(
        jointKey: 'ombro_esq',
        label: 'Ombro Esq.',
        targetAngle: 90.0,
        tolerance: 18.0,
      ),
      'ombro_dir': AngleTargetRange(
        jointKey: 'ombro_dir',
        label: 'Ombro Dir.',
        targetAngle: 90.0,
        tolerance: 18.0,
      ),
      'cotovelo_esq': AngleTargetRange(
        jointKey: 'cotovelo_esq',
        label: 'Cotovelo Esq.',
        targetAngle: 170.0,
        tolerance: 18.0,
      ),
      'cotovelo_dir': AngleTargetRange(
        jointKey: 'cotovelo_dir',
        label: 'Cotovelo Dir.',
        targetAngle: 170.0,
        tolerance: 18.0,
      ),
      'joelho_esq': AngleTargetRange(
        jointKey: 'joelho_esq',
        label: 'Joelho Esq.',
        targetAngle: 172.0,
        tolerance: 15.0,
      ),
      'joelho_dir': AngleTargetRange(
        jointKey: 'joelho_dir',
        label: 'Joelho Dir.',
        targetAngle: 172.0,
        tolerance: 15.0,
      ),
    },
    startLandmarksNormalized: kNeutralGuideLandmarks,
    guideLandmarksNormalized: {
      'NOSE': Point2D(0.50, 0.14),
      'LEFT_SHOULDER': Point2D(0.39, 0.25),
      'RIGHT_SHOULDER': Point2D(0.61, 0.25),
      'LEFT_ELBOW': Point2D(0.22, 0.25),
      'RIGHT_ELBOW': Point2D(0.78, 0.25),
      'LEFT_WRIST': Point2D(0.06, 0.25),
      'RIGHT_WRIST': Point2D(0.94, 0.25),
      'LEFT_HIP': Point2D(0.43, 0.52),
      'RIGHT_HIP': Point2D(0.57, 0.52),
      'LEFT_KNEE': Point2D(0.43, 0.71),
      'RIGHT_KNEE': Point2D(0.57, 0.71),
      'LEFT_ANKLE': Point2D(0.43, 0.88),
      'RIGHT_ANKLE': Point2D(0.57, 0.88),
      'LEFT_HEEL': Point2D(0.44, 0.91),
      'RIGHT_HEEL': Point2D(0.56, 0.91),
      'LEFT_FOOT_INDEX': Point2D(0.40, 0.92),
      'RIGHT_FOOT_INDEX': Point2D(0.60, 0.92),
    },
  ),
  const ProtocolPosture(
    id: 'elevacao_panturrilha',
    title: '3. Elevação de Panturrilha (Ponta dos Pés)',
    shortCommand: 'SUBA NA PONTA DOS PÉS! ↑',
    focusSummary: 'FOCO: PANTURRILHA E SUBIDA DO CALCANHAR (PONTA DOS PÉS)',
    badge: 'POSTURA 3/5',
    instruction:
        'Suba na ponta dos pés retirando os dois calcanhares do chão ao máximo! Mantenha os joelhos estendidos.',
    recommendedView: 'Diagonal ou Perfil (25°–85°)',
    gifAssetPath: 'assets/gifs/elevacao_panturrilha.gif',
    holdDurationSeconds: 2.2,
    evaluationWindowSeconds: 8.0,
    minCalfElevationPct: 22.0,
    targetAngles: {
      'tornozelo_esq': AngleTargetRange(
        jointKey: 'tornozelo_esq',
        label: 'Tornozelo/Panturrilha Esq.',
        targetAngle: 132.0,
        tolerance: 24.0,
      ),
      'tornozelo_dir': AngleTargetRange(
        jointKey: 'tornozelo_dir',
        label: 'Tornozelo/Panturrilha Dir.',
        targetAngle: 132.0,
        tolerance: 24.0,
      ),
      'joelho_esq': AngleTargetRange(
        jointKey: 'joelho_esq',
        label: 'Joelho Esq.',
        targetAngle: 170.0,
        tolerance: 16.0,
      ),
      'joelho_dir': AngleTargetRange(
        jointKey: 'joelho_dir',
        label: 'Joelho Dir.',
        targetAngle: 170.0,
        tolerance: 16.0,
      ),
    },
    startLandmarksNormalized: kNeutralGuideLandmarks,
    guideLandmarksNormalized: {
      'NOSE': Point2D(0.50, 0.09),
      'LEFT_SHOULDER': Point2D(0.40, 0.20),
      'RIGHT_SHOULDER': Point2D(0.60, 0.20),
      'LEFT_ELBOW': Point2D(0.33, 0.33),
      'RIGHT_ELBOW': Point2D(0.67, 0.33),
      'LEFT_WRIST': Point2D(0.39, 0.43),
      'RIGHT_WRIST': Point2D(0.61, 0.43),
      'LEFT_HIP': Point2D(0.43, 0.47),
      'RIGHT_HIP': Point2D(0.57, 0.47),
      'LEFT_KNEE': Point2D(0.43, 0.66),
      'RIGHT_KNEE': Point2D(0.57, 0.66),
      'LEFT_ANKLE': Point2D(0.43, 0.81),
      'RIGHT_ANKLE': Point2D(0.57, 0.81),
      'LEFT_HEEL': Point2D(0.45, 0.83),
      'RIGHT_HEEL': Point2D(0.55, 0.83),
      'LEFT_FOOT_INDEX': Point2D(0.40, 0.92),
      'RIGHT_FOOT_INDEX': Point2D(0.60, 0.92),
    },
  ),
  const ProtocolPosture(
    id: 'agachamento_iso',
    title: '4. Agachamento Isométrico (90°–110°)',
    shortCommand: 'AGACHE COM OS BRAÇOS PARA A FRENTE ↓',
    focusSummary: 'FOCO: JOELHOS/QUADRIL A 100° + BRAÇOS ESTENDIDOS À FRENTE',
    badge: 'POSTURA 4/5',
    instruction:
        'Estenda os dois braços PARA A FRENTE (na linha dos ombros) e flexione os joelhos e o quadril como se fosse sentar em uma cadeira.',
    recommendedView: 'Diagonal ou Frontal',
    gifAssetPath: 'assets/gifs/agachamento_iso.gif',
    holdDurationSeconds: 2.2,
    evaluationWindowSeconds: 8.0,
    targetAngles: {
      'joelho_esq': AngleTargetRange(
        jointKey: 'joelho_esq',
        label: 'Joelho Esq.',
        targetAngle: 105.0,
        tolerance: 20.0,
      ),
      'joelho_dir': AngleTargetRange(
        jointKey: 'joelho_dir',
        label: 'Joelho Dir.',
        targetAngle: 105.0,
        tolerance: 20.0,
      ),
      'quadril_esq': AngleTargetRange(
        jointKey: 'quadril_esq',
        label: 'Quadril Esq.',
        targetAngle: 105.0,
        tolerance: 22.0,
      ),
      'quadril_dir': AngleTargetRange(
        jointKey: 'quadril_dir',
        label: 'Quadril Dir.',
        targetAngle: 105.0,
        tolerance: 22.0,
      ),
      'ombro_esq': AngleTargetRange(
        jointKey: 'ombro_esq',
        label: 'Ombro Esq.',
        targetAngle: 85.0,
        tolerance: 25.0,
      ),
      'ombro_dir': AngleTargetRange(
        jointKey: 'ombro_dir',
        label: 'Ombro Dir.',
        targetAngle: 85.0,
        tolerance: 25.0,
      ),
    },
    startLandmarksNormalized: kNeutralGuideLandmarks,
    guideLandmarksNormalized: {
      // Braços estendidos PARA A FRENTE (alinhados com os ombros na visão frontal)
      'NOSE': Point2D(0.50, 0.25),
      'LEFT_SHOULDER': Point2D(0.39, 0.36),
      'RIGHT_SHOULDER': Point2D(0.61, 0.36),
      'LEFT_ELBOW': Point2D(0.38, 0.38),
      'RIGHT_ELBOW': Point2D(0.62, 0.38),
      'LEFT_WRIST': Point2D(0.38, 0.35),
      'RIGHT_WRIST': Point2D(0.62, 0.35),
      'LEFT_HIP': Point2D(0.43, 0.62),
      'RIGHT_HIP': Point2D(0.57, 0.62),
      'LEFT_KNEE': Point2D(0.36, 0.75),
      'RIGHT_KNEE': Point2D(0.64, 0.75),
      'LEFT_ANKLE': Point2D(0.43, 0.89),
      'RIGHT_ANKLE': Point2D(0.57, 0.89),
      'LEFT_HEEL': Point2D(0.45, 0.91),
      'RIGHT_HEEL': Point2D(0.55, 0.91),
      'LEFT_FOOT_INDEX': Point2D(0.39, 0.92),
      'RIGHT_FOOT_INDEX': Point2D(0.61, 0.92),
    },
  ),
  const ProtocolPosture(
    id: 'duplo_biceps',
    title: '5. Braços em "W" (90° / 90°)',
    shortCommand: 'ELEVE OS BRAÇOS EM "W" (90°/90°)',
    focusSummary: 'FOCO: OMBROS A 90° + COTOVELOS DOBRADOS A 90° PARA CIMA',
    badge: 'POSTURA 5/5',
    instruction:
        'Abra os ombros a 90° para os lados e dobre os dois cotovelos a 90° com as mãos apontando para o teto (em formato de "W").',
    recommendedView: 'Frontal (0°–30°)',
    gifAssetPath: 'assets/gifs/duplo_biceps.gif',
    holdDurationSeconds: 2.2,
    evaluationWindowSeconds: 8.0,
    targetAngles: {
      'ombro_esq': AngleTargetRange(
        jointKey: 'ombro_esq',
        label: 'Ombro Esq.',
        targetAngle: 90.0,
        tolerance: 18.0,
      ),
      'ombro_dir': AngleTargetRange(
        jointKey: 'ombro_dir',
        label: 'Ombro Dir.',
        targetAngle: 90.0,
        tolerance: 18.0,
      ),
      'cotovelo_esq': AngleTargetRange(
        jointKey: 'cotovelo_esq',
        label: 'Cotovelo Esq.',
        targetAngle: 90.0,
        tolerance: 18.0,
      ),
      'cotovelo_dir': AngleTargetRange(
        jointKey: 'cotovelo_dir',
        label: 'Cotovelo Dir.',
        targetAngle: 90.0,
        tolerance: 18.0,
      ),
      'joelho_esq': AngleTargetRange(
        jointKey: 'joelho_esq',
        label: 'Joelho Esq.',
        targetAngle: 172.0,
        tolerance: 15.0,
      ),
      'joelho_dir': AngleTargetRange(
        jointKey: 'joelho_dir',
        label: 'Joelho Dir.',
        targetAngle: 172.0,
        tolerance: 15.0,
      ),
    },
    startLandmarksNormalized: kNeutralGuideLandmarks,
    guideLandmarksNormalized: {
      'NOSE': Point2D(0.50, 0.14),
      'LEFT_SHOULDER': Point2D(0.39, 0.25),
      'RIGHT_SHOULDER': Point2D(0.61, 0.25),
      'LEFT_ELBOW': Point2D(0.22, 0.25),
      'RIGHT_ELBOW': Point2D(0.78, 0.25),
      'LEFT_WRIST': Point2D(0.22, 0.11),
      'RIGHT_WRIST': Point2D(0.78, 0.11),
      'LEFT_HIP': Point2D(0.43, 0.52),
      'RIGHT_HIP': Point2D(0.57, 0.52),
      'LEFT_KNEE': Point2D(0.43, 0.71),
      'RIGHT_KNEE': Point2D(0.57, 0.71),
      'LEFT_ANKLE': Point2D(0.43, 0.88),
      'RIGHT_ANKLE': Point2D(0.57, 0.88),
      'LEFT_HEEL': Point2D(0.44, 0.91),
      'RIGHT_HEEL': Point2D(0.56, 0.91),
      'LEFT_FOOT_INDEX': Point2D(0.40, 0.92),
      'RIGHT_FOOT_INDEX': Point2D(0.60, 0.92),
    },
  ),
];

class ProtocolService {
  final List<ProtocolPosture> postures;
  ProtocolStage stage;
  int currentPostureIndex = 0;

  // Tela preta de 5 segundos com GIF em tela cheia antes de cada postura
  final bool enablePostureIntro;
  static const double postureIntroDurationSec = 5.0;
  bool isShowingPostureIntro = false;
  double postureIntroRemainingSeconds = 5.0;
  double postureIntroProgress = 0.0;
  double? _postureIntroStartSec;

  PositioningAssessment currentPositioning = PositioningAssessment.empty();
  Map<String, JointMatchFeedback> currentJointFeedbacks = {};
  double currentPostureAccuracyPct = 0.0;
  double currentPostureHoldProgress = 0.0;
  double currentEvaluationWindowProgress = 0.0;
  double remainingEvaluationSeconds = 8.0;

  final List<PostureEvaluationResult> completedPostures = [];

  double? _positioningGoodStartSec;
  double? _postureHoldStartSec;
  double? _postureAttemptStartSec;

  final Map<String, double> _bestAnglesInCurrentPosture = {};
  double _bestAccuracyInCurrentPosture = 0.0;
  double _bestCalfLeftInCurrentPosture = 0.0;
  double _bestCalfRightInCurrentPosture = 0.0;

  static const double positioningHoldRequiredSec = 2.0;

  ProtocolService({
    List<ProtocolPosture>? customPostures,
    this.stage = ProtocolStage.positioning,
    this.enablePostureIntro = false,
  }) : postures = customPostures ?? kDefaultProtocolPostures {
    if (stage == ProtocolStage.postureReplication && enablePostureIntro) {
      _startPostureIntro();
    }
  }

  ProtocolPosture get currentPosture =>
      postures[currentPostureIndex.clamp(0, postures.length - 1)];

  List<MobilityDeficitItem> get allDetectedDeficits =>
      completedPostures.expand((p) => p.deficits).toList();

  void _startPostureIntro() {
    if (!enablePostureIntro) {
      isShowingPostureIntro = false;
      postureIntroRemainingSeconds = 0.0;
      postureIntroProgress = 1.0;
      _postureIntroStartSec = null;
      return;
    }
    isShowingPostureIntro = true;
    postureIntroRemainingSeconds = postureIntroDurationSec;
    postureIntroProgress = 0.0;
    _postureIntroStartSec = null;
  }

  /// Permite pular os 5s da tela preta ou reabrir a demonstração em tela cheia
  void skipPostureIntro() {
    isShowingPostureIntro = false;
    postureIntroRemainingSeconds = 0.0;
    postureIntroProgress = 1.0;
    _postureIntroStartSec = null;
    _postureAttemptStartSec = null;
  }

  void replayPostureIntro() {
    isShowingPostureIntro = true;
    postureIntroRemainingSeconds = postureIntroDurationSec;
    postureIntroProgress = 0.0;
    _postureIntroStartSec = null;
    _postureAttemptStartSec = null;
    _postureHoldStartSec = null;
  }

  /// Atualiza o cronômetro de 5 segundos da tela preta de demonstração (retorna true quando termina os 5s)
  bool updateIntroTimer(double timestampSec) {
    if (stage != ProtocolStage.postureReplication || !isShowingPostureIntro) {
      return false;
    }
    _postureIntroStartSec ??= timestampSec;
    final elapsed = max(0.0, timestampSec - _postureIntroStartSec!);
    postureIntroProgress = (elapsed / postureIntroDurationSec).clamp(0.0, 1.0);
    postureIntroRemainingSeconds = max(0.0, postureIntroDurationSec - elapsed);

    if (elapsed >= postureIntroDurationSec) {
      isShowingPostureIntro = false;
      _postureIntroStartSec = null;
      _postureAttemptStartSec = null;
      return true;
    }
    return false;
  }

  void _resetCurrentPostureAttemptTrackers() {
    _postureHoldStartSec = null;
    _postureAttemptStartSec = null;
    currentPostureHoldProgress = 0.0;
    currentEvaluationWindowProgress = 0.0;
    remainingEvaluationSeconds = currentPosture.evaluationWindowSeconds;
    _bestAnglesInCurrentPosture.clear();
    _bestAccuracyInCurrentPosture = 0.0;
    _bestCalfLeftInCurrentPosture = 0.0;
    _bestCalfRightInCurrentPosture = 0.0;
    _startPostureIntro();
  }

  void reset() {
    stage = ProtocolStage.positioning;
    currentPostureIndex = 0;
    currentPositioning = PositioningAssessment.empty();
    currentJointFeedbacks = {};
    currentPostureAccuracyPct = 0.0;
    completedPostures.clear();
    _positioningGoodStartSec = null;
    _resetCurrentPostureAttemptTrackers();
    isShowingPostureIntro = false;
  }

  void skipToPostureReplication() {
    stage = ProtocolStage.postureReplication;
    _resetCurrentPostureAttemptTrackers();
  }

  void toggleFreeRomMode() {
    if (stage == ProtocolStage.freeRom) {
      stage = ProtocolStage.positioning;
      _positioningGoodStartSec = null;
      isShowingPostureIntro = false;
    } else {
      stage = ProtocolStage.freeRom;
      isShowingPostureIntro = false;
    }
  }

  void nextPosture({double? timestampSec, bool recordCurrentIfStarted = true}) {
    if (recordCurrentIfStarted &&
        stage == ProtocolStage.postureReplication &&
        !isShowingPostureIntro &&
        _bestAnglesInCurrentPosture.isNotEmpty &&
        !completedPostures.any((p) => p.postureId == currentPosture.id)) {
      _recordPostureEvaluation(
        timestampSec ?? 0.0,
        completedByIdealHold: false,
      );
    }

    if (currentPostureIndex < postures.length - 1) {
      currentPostureIndex++;
      stage = ProtocolStage.postureReplication;
      _resetCurrentPostureAttemptTrackers();
    } else {
      stage = ProtocolStage.completed;
      _resetCurrentPostureAttemptTrackers();
      isShowingPostureIntro = false;
    }
  }

  void previousPosture() {
    if (currentPostureIndex > 0) {
      currentPostureIndex--;
      stage = ProtocolStage.postureReplication;
      completedPostures.removeWhere((p) => p.postureId == currentPosture.id);
      _resetCurrentPostureAttemptTrackers();
    }
  }

  /// Atualiza o protocolo com o quadro de pose atual e retorna true se houve transição de etapa/postura.
  bool update(
    ExtractedPoseData? poseData,
    Size screenSize,
    double timestampSec,
  ) {
    // Se estiver exibindo a tela preta de 5 segundos com o GIF antes da postura, avança apenas o timer de introdução
    if (stage == ProtocolStage.postureReplication && isShowingPostureIntro) {
      return updateIntroTimer(timestampSec);
    }

    if (poseData == null || poseData.landmarks.isEmpty) {
      _positioningGoodStartSec = null;
      _postureHoldStartSec = null;
      currentPositioning = PositioningAssessment.empty();
      currentPostureAccuracyPct = 0.0;
      currentPostureHoldProgress = 0.0;
      return false;
    }

    final assessment = evaluatePositioning(
      poseData,
      screenSize,
      timestampSec,
    );
    currentPositioning = assessment;

    if (stage == ProtocolStage.positioning) {
      if (assessment.isAllGood) {
        _positioningGoodStartSec ??= timestampSec;
        final held = timestampSec - _positioningGoodStartSec!;
        final progress = (held / positioningHoldRequiredSec).clamp(0.0, 1.0);
        currentPositioning = PositioningAssessment(
          isDistanceGood: assessment.isDistanceGood,
          distanceStatus: assessment.distanceStatus,
          distanceMessage: assessment.distanceMessage,
          bodyHeightRatio: assessment.bodyHeightRatio,
          isCentered: assessment.isCentered,
          horizontalOffset: assessment.horizontalOffset,
          horizontalMessage: assessment.horizontalMessage,
          isAngleGood: assessment.isAngleGood,
          trunkTiltDeg: assessment.trunkTiltDeg,
          bodyOrientationAngle: assessment.bodyOrientationAngle,
          bodyOrientationLabel: assessment.bodyOrientationLabel,
          angleMessage: assessment.angleMessage,
          areAllPointsVisible: assessment.areAllPointsVisible,
          missingParts: assessment.missingParts,
          visibilityMessage: assessment.visibilityMessage,
          holdProgress: progress,
        );

        if (progress >= 1.0) {
          stage = ProtocolStage.postureReplication;
          _positioningGoodStartSec = null;
          _resetCurrentPostureAttemptTrackers();
          return true;
        }
      } else {
        _positioningGoodStartSec = null;
      }
      return false;
    } else if (stage == ProtocolStage.postureReplication) {
      return _evaluateCurrentPosture(poseData, timestampSec);
    }

    return false;
  }

  /// Avalia se o usuário está a uma boa distância, centralizado, alinhado e com corpo + calcanhares visíveis.
  PositioningAssessment evaluatePositioning(
    ExtractedPoseData poseData,
    Size screenSize,
    double timestampSec,
  ) {
    final lm = poseData.landmarks;
    final double w = max(1.0, screenSize.width);
    final double h = max(1.0, screenSize.height);

    final bool hasHeadAndTorso = lm.containsKey('NOSE') &&
        lm.containsKey('LEFT_SHOULDER') &&
        lm.containsKey('RIGHT_SHOULDER') &&
        lm.containsKey('LEFT_HIP') &&
        lm.containsKey('RIGHT_HIP');

    final bool hasArms = lm.containsKey('LEFT_ELBOW') &&
        lm.containsKey('RIGHT_ELBOW') &&
        lm.containsKey('LEFT_WRIST') &&
        lm.containsKey('RIGHT_WRIST');

    final bool hasLegs = lm.containsKey('LEFT_KNEE') &&
        lm.containsKey('RIGHT_KNEE') &&
        lm.containsKey('LEFT_ANKLE') &&
        lm.containsKey('RIGHT_ANKLE');

    final bool hasFeetAndHeels =
        (lm.containsKey('LEFT_HEEL') || lm.containsKey('LEFT_FOOT_INDEX')) &&
            (lm.containsKey('RIGHT_HEEL') || lm.containsKey('RIGHT_FOOT_INDEX'));

    final List<String> missing = [];
    if (!hasHeadAndTorso) missing.add('Cabeça/Tronco');
    if (!hasArms) missing.add('Braços');
    if (!hasLegs) missing.add('Joelhos/Tornozelos');
    if (!hasFeetAndHeels) missing.add('Calcanhares/Pés');

    final bool areAllVisible = missing.isEmpty;
    final String visibilityMsg = areAllVisible
        ? 'Corpo inteiro e calcanhares visíveis ✅'
        : 'Enquadre na câmera: ${missing.join(", ")}';

    double minY = h;
    double maxY = 0.0;
    for (final pt in lm.values) {
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    final nose = lm['NOSE'];
    final lShoulder = lm['LEFT_SHOULDER'];
    final rShoulder = lm['RIGHT_SHOULDER'];
    if (nose != null && lShoulder != null && rShoulder != null) {
      final midShoulderY = (lShoulder.y + rShoulder.y) / 2.0;
      final headTopEstimate = nose.y - (midShoulderY - nose.y) * 0.65;
      if (headTopEstimate < minY) minY = headTopEstimate;
    }

    final double bodySpanPx = max(0.0, maxY - minY);
    final double bodyHeightRatio = (bodySpanPx / h).clamp(0.0, 1.0);

    final bool clippedTop = minY < h * 0.03;
    final bool clippedBottom = maxY > h * 0.94;

    bool isDistanceGood = false;
    String distanceStatus = 'optimal';
    String distanceMsg = 'Distância ideal da câmera ✅';

    if (!hasLegs ||
        !hasFeetAndHeels ||
        clippedBottom ||
        clippedTop ||
        bodyHeightRatio > 0.89) {
      isDistanceGood = false;
      distanceStatus = 'too_close';
      distanceMsg = 'Muito perto! Afaste-se para mostrar dos pés à cabeça';
    } else if (bodyHeightRatio < 0.44) {
      isDistanceGood = false;
      distanceStatus = 'too_far';
      distanceMsg = 'Muito longe! Aproxime-se um pouco da câmera';
    } else {
      isDistanceGood = true;
      distanceStatus = 'optimal';
      distanceMsg =
          'Distância ideal (${(bodyHeightRatio * 100).round()}% do quadro) ✅';
    }

    double centerXNorm = 0.5;
    final lHip = lm['LEFT_HIP'];
    final rHip = lm['RIGHT_HIP'];
    if (lShoulder != null && rShoulder != null && lHip != null && rHip != null) {
      final midX = (lShoulder.x + rShoulder.x + lHip.x + rHip.x) / 4.0;
      centerXNorm = (midX / w).clamp(0.0, 1.0);
    } else if (nose != null) {
      centerXNorm = (nose.x / w).clamp(0.0, 1.0);
    }

    final double horizOffset = centerXNorm - 0.5;
    bool isCentered = true;
    String horizMsg = 'Centralizado no quadro ✅';

    if (horizOffset < -0.18) {
      isCentered = false;
      horizMsg = 'Mova-se um pouco para a DIREITA ->';
    } else if (horizOffset > 0.18) {
      isCentered = false;
      horizMsg = '<- Mova-se um pouco para a ESQUERDA';
    }

    double trunkTiltDeg = 0.0;
    if (lShoulder != null && rShoulder != null && lHip != null && rHip != null) {
      final midShoulderX = (lShoulder.x + rShoulder.x) / 2.0;
      final midShoulderY = (lShoulder.y + rShoulder.y) / 2.0;
      final midHipX = (lHip.x + rHip.x) / 2.0;
      final midHipY = (lHip.y + rHip.y) / 2.0;

      final dx = (midShoulderX - midHipX).abs();
      final dy = max(1.0, (midHipY - midShoulderY).abs());
      trunkTiltDeg = atan2(dx, dy) * 180.0 / pi;
    }

    final double orientationAngle = poseData.bodyOrientationAngle;
    final String orientationLabel = poseData.bodyOrientationLabel;

    bool isAngleGood = trunkTiltDeg <= 16.0;
    String angleMsg = isAngleGood
        ? 'Angulação OK: $orientationLabel (${orientationAngle.round()}°) ✅'
        : 'Alinhe a coluna verticalmente (inclinação: ${trunkTiltDeg.round()}°)';

    return PositioningAssessment(
      isDistanceGood: isDistanceGood,
      distanceStatus: distanceStatus,
      distanceMessage: distanceMsg,
      bodyHeightRatio: bodyHeightRatio,
      isCentered: isCentered,
      horizontalOffset: horizOffset,
      horizontalMessage: horizMsg,
      isAngleGood: isAngleGood,
      trunkTiltDeg: trunkTiltDeg,
      bodyOrientationAngle: orientationAngle,
      bodyOrientationLabel: orientationLabel,
      angleMessage: angleMsg,
      areAllPointsVisible: areAllVisible,
      missingParts: missing,
      visibilityMessage: visibilityMsg,
      holdProgress: 0.0,
    );
  }

  bool _evaluateCurrentPosture(ExtractedPoseData poseData, double timestampSec) {
    final posture = currentPosture;
    _postureAttemptStartSec ??= timestampSec;

    final double attemptElapsed = max(0.0, timestampSec - _postureAttemptStartSec!);
    currentEvaluationWindowProgress =
        (attemptElapsed / posture.evaluationWindowSeconds).clamp(0.0, 1.0);
    remainingEvaluationSeconds =
        max(0.0, posture.evaluationWindowSeconds - attemptElapsed);

    final Map<String, JointMatchFeedback> feedbacks = {};
    double totalScore = 0.0;
    int criteriaCount = 0;

    // Atualiza todas as articulações visíveis no melhor esforço da postura
    poseData.angles.forEach((jointKey, jointData) {
      if (jointData.isValid && jointData.angle != null) {
        final double angle = jointData.angle!;
        final targetRange = posture.targetAngles[jointKey];
        if (targetRange != null) {
          final prevBest = _bestAnglesInCurrentPosture[jointKey];
          if (prevBest == null ||
              (angle - targetRange.targetAngle).abs() <
                  (prevBest - targetRange.targetAngle).abs()) {
            _bestAnglesInCurrentPosture[jointKey] = angle;
          }
        } else {
          _bestAnglesInCurrentPosture[jointKey] = angle;
        }
      }
    });

    if (poseData.calfElevationLeftPct > _bestCalfLeftInCurrentPosture) {
      _bestCalfLeftInCurrentPosture = poseData.calfElevationLeftPct;
    }
    if (poseData.calfElevationRightPct > _bestCalfRightInCurrentPosture) {
      _bestCalfRightInCurrentPosture = poseData.calfElevationRightPct;
    }

    posture.targetAngles.forEach((jointKey, targetRange) {
      criteriaCount++;
      final jointData = poseData.angles[jointKey];
      final double? angle =
          (jointData != null && jointData.isValid) ? jointData.angle : null;

      if (angle == null) {
        feedbacks[jointKey] = JointMatchFeedback(
          jointKey: jointKey,
          label: targetRange.label,
          currentAngle: null,
          targetAngle: targetRange.targetAngle,
          tolerance: targetRange.tolerance,
          isMatched: false,
          adjustmentHint: 'Articulação oculta',
        );
      } else {
        final matched = targetRange.isWithinRange(angle);
        final score = targetRange.scoreForAngle(angle);
        totalScore += score;

        String hint = 'Alinhado ✅';
        if (!matched) {
          final diff = (targetRange.targetAngle - angle).round();
          if (diff > 0) {
            hint =
                'Abra/Estenda +$diff° (Alvo: ${targetRange.targetAngle.round()}°)';
          } else {
            hint =
                'Flexione/Feche $diff° (Alvo: ${targetRange.targetAngle.round()}°)';
          }
        }

        feedbacks[jointKey] = JointMatchFeedback(
          jointKey: jointKey,
          label: targetRange.label,
          currentAngle: angle,
          targetAngle: targetRange.targetAngle,
          tolerance: targetRange.tolerance,
          isMatched: matched,
          adjustmentHint: hint,
        );
      }
    });

    if (posture.minCalfElevationPct != null) {
      criteriaCount++;
      final minCalf = posture.minCalfElevationPct!;
      final currentCalf = poseData.maxCalfElevationPct;
      final calfScore = (currentCalf / minCalf).clamp(0.0, 1.0);
      totalScore += calfScore;
    }

    currentJointFeedbacks = feedbacks;
    final double accuracy =
        criteriaCount > 0 ? (totalScore / criteriaCount) * 100.0 : 0.0;
    currentPostureAccuracyPct = double.parse(accuracy.toStringAsFixed(1));
    if (currentPostureAccuracyPct > _bestAccuracyInCurrentPosture) {
      _bestAccuracyInCurrentPosture = currentPostureAccuracyPct;
    }

    // Só considera "Mobilidade Plena" imediata se a média for >= 78% E nenhuma articulação-alvo tiver restrição importante
    final bool anySevereJointDeficit = feedbacks.values.any((fb) {
      if (fb.currentAngle == null) return true;
      return (fb.currentAngle! - fb.targetAngle).abs() > fb.tolerance * 1.2;
    });
    final bool calfOk = posture.minCalfElevationPct == null ||
        poseData.maxCalfElevationPct >= posture.minCalfElevationPct!;

    final bool isPostureMatched =
        currentPostureAccuracyPct >= 78.0 && !anySevereJointDeficit && calfOk;

    if (isPostureMatched) {
      _postureHoldStartSec ??= timestampSec;
      final held = timestampSec - _postureHoldStartSec!;
      currentPostureHoldProgress =
          (held / posture.holdDurationSeconds).clamp(0.0, 1.0);

      if (currentPostureHoldProgress >= 1.0) {
        _recordPostureEvaluation(timestampSec, completedByIdealHold: true);
        nextPosture(timestampSec: timestampSec, recordCurrentIfStarted: false);
        return true;
      }
    } else {
      _postureHoldStartSec = null;
      currentPostureHoldProgress = 0.0;
    }

    // Se a janela de avaliação de mobilidade (ex: 8 segundos) terminou e o usuário
    // não atingiu 100% da pose ideal, registra o limite funcional alcançado e detecta
    // as faltas de mobilidade automaticamente, avançando para a próxima postura!
    if (currentEvaluationWindowProgress >= 1.0) {
      _recordPostureEvaluation(timestampSec, completedByIdealHold: false);
      nextPosture(timestampSec: timestampSec, recordCurrentIfStarted: false);
      return true;
    }

    return false;
  }

  void _recordPostureEvaluation(
    double timestampSec, {
    required bool completedByIdealHold,
  }) {
    final posture = currentPosture;
    final captured = Map<String, double>.from(_bestAnglesInCurrentPosture);
    final maxCalf = max(_bestCalfLeftInCurrentPosture, _bestCalfRightInCurrentPosture);

    final deficits = _analyzeMobilityDeficitsForPosture(
      posture: posture,
      bestAngles: captured,
      maxCalfLeft: _bestCalfLeftInCurrentPosture,
      maxCalfRight: _bestCalfRightInCurrentPosture,
    );

    String mobilityStatus;
    if (deficits.isEmpty && _bestAccuracyInCurrentPosture >= 72.0) {
      mobilityStatus = 'Mobilidade Plena';
    } else if (deficits.any((d) => d.severity == 'Moderada/Severa') ||
        _bestAccuracyInCurrentPosture < 52.0) {
      mobilityStatus = 'Restrição de Mobilidade';
    } else {
      mobilityStatus = 'Mobilidade Parcial';
    }

    completedPostures.removeWhere((p) => p.postureId == posture.id);
    completedPostures.add(
      PostureEvaluationResult(
        postureId: posture.id,
        postureTitle: posture.title,
        gifAssetPath: posture.gifAssetPath,
        accuracyScorePct: _bestAccuracyInCurrentPosture,
        capturedAngles: captured,
        targetAngles: posture.targetAngles,
        maxCalfElevationPct: maxCalf,
        maxCalfLeftPct: _bestCalfLeftInCurrentPosture,
        maxCalfRightPct: _bestCalfRightInCurrentPosture,
        completionTimeSec: timestampSec,
        completedByIdealHold: completedByIdealHold,
        mobilityStatus: mobilityStatus,
        deficits: deficits,
      ),
    );
  }

  /// Analisa os melhores ângulos atingidos pelo usuário na postura e identifica faltas de mobilidade e assimetrias
  List<MobilityDeficitItem> _analyzeMobilityDeficitsForPosture({
    required ProtocolPosture posture,
    required Map<String, double> bestAngles,
    required double maxCalfLeft,
    required double maxCalfRight,
  }) {
    final List<MobilityDeficitItem> deficits = [];

    posture.targetAngles.forEach((jointKey, targetRange) {
      final achieved = bestAngles[jointKey];
      if (achieved == null) return;

      final diff = (achieved - targetRange.targetAngle).abs();
      if (diff <= targetRange.tolerance) return; // Dentro da faixa esperada!

      final double deficitDeg = diff - targetRange.tolerance;
      final String severity =
          deficitDeg >= 16.0 ? 'Moderada/Severa' : 'Leve';

      String clinicalExplanation = '';
      if (posture.id == 'bracos_t' && jointKey.startsWith('ombro')) {
        if (achieved < targetRange.minAngle) {
          clinicalExplanation =
              'Falta de mobilidade em abdução glenoumeral (${targetRange.label} elevou apenas até ${achieved.round()}° de 90° esperados).';
        } else {
          clinicalExplanation =
              'Hiperabdução / compensação escapular acima da linha de 90° (${achieved.round()}°).';
        }
      } else if (posture.id == 'agachamento_iso' &&
          jointKey.startsWith('joelho')) {
        if (achieved > targetRange.maxAngle) {
          clinicalExplanation =
              'Falta de mobilidade na flexão de cadeia inferior (${targetRange.label} desceu apenas até ${achieved.round()}°, esperado ≤ ${targetRange.maxAngle.round()}°). Sugere restrição de joelho, quadril ou dorsiflexão do tornozelo.';
        } else {
          clinicalExplanation =
              'Flexão profunda além da faixa isométrica alvo (${achieved.round()}°).';
        }
      } else if (posture.id == 'agachamento_iso' &&
          jointKey.startsWith('quadril')) {
        if (achieved > targetRange.maxAngle) {
          clinicalExplanation =
              'Redução de mobilidade de flexão do quadril no agachamento (${achieved.round()}° vs alvo ${targetRange.targetAngle.round()}°).';
        } else {
          clinicalExplanation =
              'Inclinação anterior excessiva do tronco no agachamento (${achieved.round()}°), compensando falta de dorsiflexão do tornozelo.';
        }
      } else if (posture.id == 'duplo_biceps') {
        if (jointKey.startsWith('ombro') && achieved < targetRange.minAngle) {
          clinicalExplanation =
              'Restrição de elevação e rotação externa do ombro na postura em W (${achieved.round()}° vs 90°).';
        } else if (jointKey.startsWith('cotovelo')) {
          clinicalExplanation =
              'Desvio de controle/flexão do cotovelo na postura em W (${achieved.round()}° vs 90°).';
        }
      } else if (jointKey.startsWith('cotovelo') &&
          targetRange.targetAngle >= 160 &&
          achieved < targetRange.minAngle) {
        clinicalExplanation =
            'Déficit de extensão completa do ${targetRange.label} (atingiu ${achieved.round()}° vs extensão de ${targetRange.targetAngle.round()}°).';
      } else if (jointKey.startsWith('joelho') &&
          targetRange.targetAngle >= 165 &&
          achieved < targetRange.minAngle) {
        clinicalExplanation =
            'Flexo residual de joelho / falta de extensão total (${achieved.round()}° vs ${targetRange.targetAngle.round()}°).';
      }

      if (clinicalExplanation.isEmpty) {
        clinicalExplanation =
            'Amplitude atingida de ${achieved.round()}° ficou fora da faixa funcional esperada (${targetRange.minAngle.round()}°–${targetRange.maxAngle.round()}°).';
      }

      deficits.add(
        MobilityDeficitItem(
          postureId: posture.id,
          postureTitle: posture.title,
          jointKey: jointKey,
          jointLabel: targetRange.label,
          achievedValue: achieved,
          targetValue: targetRange.targetAngle,
          unit: '°',
          severity: severity,
          description: clinicalExplanation,
        ),
      );
    });

    // Avaliação específica de elevação de panturrilha / plantiflexão
    if (posture.minCalfElevationPct != null) {
      final minCalf = posture.minCalfElevationPct!;
      final maxCalf = max(maxCalfLeft, maxCalfRight);
      if (maxCalf < minCalf) {
        final severity = maxCalf < 12.0 ? 'Moderada/Severa' : 'Leve';
        deficits.add(
          MobilityDeficitItem(
            postureId: posture.id,
            postureTitle: posture.title,
            jointKey: 'panturrilha',
            jointLabel: 'Panturrilha / Flexão Plantar',
            achievedValue: maxCalf,
            targetValue: minCalf,
            unit: '%',
            severity: severity,
            description:
                'Déficit de elevação do calcanhar na ponta dos pés (atingiu ${maxCalf.round()}%, esperado ≥ ${minCalf.round()}%). Indica redução de amplitude de plantiflexão do tornozelo ou força do tríceps sural.',
          ),
        );
      }

      if ((maxCalfLeft - maxCalfRight).abs() >= 10.0) {
        deficits.add(
          MobilityDeficitItem(
            postureId: posture.id,
            postureTitle: posture.title,
            jointKey: 'assimetria_panturrilha',
            jointLabel: 'Assimetria de Panturrilha (Esq x Dir)',
            achievedValue: maxCalfLeft,
            targetValue: maxCalfRight,
            unit: '%',
            severity: 'Assimetria',
            description:
                'Diferença acentuada na subida do calcanhar: Esquerdo ${maxCalfLeft.round()}% vs Direito ${maxCalfRight.round()}%.',
          ),
        );
      }
    }

    // Verificação de assimetria bilateral de ombros e joelhos na postura
    final ombroE = bestAngles['ombro_esq'];
    final ombroD = bestAngles['ombro_dir'];
    if (ombroE != null &&
        ombroD != null &&
        posture.targetAngles.containsKey('ombro_esq') &&
        (ombroE - ombroD).abs() >= 16.0) {
      deficits.add(
        MobilityDeficitItem(
          postureId: posture.id,
          postureTitle: posture.title,
          jointKey: 'assimetria_ombros',
          jointLabel: 'Assimetria de Ombros (Esq x Dir)',
          achievedValue: ombroE,
          targetValue: ombroD,
          unit: '°',
          severity: 'Assimetria',
          description:
              'Assimetria bilateral importante entre Ombro Esquerdo (${ombroE.round()}°) e Ombro Direito (${ombroD.round()}°).',
        ),
      );
    }

    final joelhoE = bestAngles['joelho_esq'];
    final joelhoD = bestAngles['joelho_dir'];
    if (joelhoE != null &&
        joelhoD != null &&
        posture.targetAngles.containsKey('joelho_esq') &&
        (joelhoE - joelhoD).abs() >= 15.0) {
      deficits.add(
        MobilityDeficitItem(
          postureId: posture.id,
          postureTitle: posture.title,
          jointKey: 'assimetria_joelhos',
          jointLabel: 'Assimetria de Joelhos (Esq x Dir)',
          achievedValue: joelhoE,
          targetValue: joelhoD,
          unit: '°',
          severity: 'Assimetria',
          description:
              'Descarga de peso ou flexão assimétrica entre Joelho Esquerdo (${joelhoE.round()}°) e Direito (${joelhoD.round()}°).',
        ),
      );
    }

    return deficits;
  }
}
