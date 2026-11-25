import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/joint_angle.dart';
import 'one_euro_filter.dart';

class PoseDetectorService {
  late final PoseDetector _detector;
  bool isInitialized = false;

  final Map<String, Point2D> _smoothedLandmarks = {};
  final Map<String, double> _smoothedAngles = {};
  final Map<String, int> _missingLandmarkFrames = {};
  final Map<String, JointAngleData> _lastValidAngles = {};
  final Map<String, int> _missingAngleFrames = {};

  // Filtros One Euro calibrados para resposta imediata (baixa latência em movimento rápido)
  final Map<String, OneEuroFilter> _angleFilters = {};
  final Map<String, OneEuroFilter> _pointFiltersX = {};
  final Map<String, OneEuroFilter> _pointFiltersY = {};
  final Stopwatch _filterStopwatch = Stopwatch()..start();

  PoseDetectorService() {
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
    isInitialized = true;
  }

  Future<List<Pose>> processImage(InputImage inputImage) async {
    return await _detector.processImage(inputImage);
  }

  bool _diagonalMode = true;

  // Estado da resolução de lado em perfil (com histerese).
  bool? _headingRight; // true = corpo voltado para a direita da imagem
  bool? _nearLeft; // true = grupo LEFT_* é o mais próximo da câmera
  double? _baselineLeftFootSpanRatio;
  double? _baselineRightFootSpanRatio;

  void resetSmoothing() {
    _smoothedLandmarks.clear();
    _smoothedAngles.clear();
    _missingLandmarkFrames.clear();
    _lastValidAngles.clear();
    _missingAngleFrames.clear();
    _baselineLeftFootSpanRatio = null;
    _baselineRightFootSpanRatio = null;
    _headingRight = null;
    _nearLeft = null;
    for (final f in _angleFilters.values) {
      f.reset();
    }
    for (final f in _pointFiltersX.values) {
      f.reset();
    }
    for (final f in _pointFiltersY.values) {
      f.reset();
    }
  }

  Point2D _smoothPoint(String key, Point2D target) {
    final t = _filterStopwatch.elapsedMilliseconds / 1000.0;
    // minCutoff=2.6 e beta=0.045 eliminam o atraso ("lag") mantendo estabilidade
    final fx = _pointFiltersX.putIfAbsent(
      key,
      () => OneEuroFilter(minCutoff: 3.0, beta: 0.6, dCutoff: 12.0),
    );
    final fy = _pointFiltersY.putIfAbsent(
      key,
      () => OneEuroFilter(minCutoff: 3.0, beta: 0.6, dCutoff: 12.0),
    );

    final sx = fx.filter(target.x, t);
    final sy = fy.filter(target.y, t);
    final smoothed = Point2D(
      sx,
      sy,
      z: target.z,
      confidence: target.confidence,
    );
    _smoothedLandmarks[key] = smoothed;
    return smoothed;
  }

  double _smoothAngle(String key, double target) {
    final t = _filterStopwatch.elapsedMilliseconds / 1000.0;
    // Filtro leve nos ângulos (evita dupla filtragem pesada que travava a leitura)
    final f = _angleFilters.putIfAbsent(
      key,
      () => OneEuroFilter(minCutoff: 3.5, beta: 0.15, dCutoff: 12.0),
    );
    final smoothed = f.filter(target, t);
    final rounded = (smoothed * 10).roundToDouble() / 10.0;
    _smoothedAngles[key] = rounded;
    return rounded;
  }

  void dispose() {
    _detector.close();
  }

  ExtractedPoseData extractAnglesFromPose(
    Pose pose, {
    required Size inputImageSize,
    required Size screenSize,
    bool isFrontCamera = false,
    String? onlySide,
  }) {
    final double scale = max(
      screenSize.width / inputImageSize.width,
      screenSize.height / inputImageSize.height,
    );
    final double renderW = inputImageSize.width * scale;
    final double renderH = inputImageSize.height * scale;
    final double offsetX = (screenSize.width - renderW) / 2.0;
    final double offsetY = (screenSize.height - renderH) / 2.0;

    Point2D? getPoint(PoseLandmarkType type, {double minConfidence = 0.22}) {
      final String key = type.name;
      final landmark = pose.landmarks[type];
      if (landmark == null || landmark.likelihood < minConfidence) {
        // Mantém o último ponto válido por até 4 frames (~120ms) para não piscar nem travar durante movimento rápido
        final int missed = (_missingLandmarkFrames[key] ?? 0) + 1;
        _missingLandmarkFrames[key] = missed;
        if (missed <= 4 && _smoothedLandmarks.containsKey(key)) {
          return _smoothedLandmarks[key];
        }
        _smoothedLandmarks.remove(key);
        return null;
      }

      _missingLandmarkFrames[key] = 0;
      double x = landmark.x * scale + offsetX;
      final double y = landmark.y * scale + offsetY;

      if (isFrontCamera) {
        x = screenSize.width - x;
      }

      return _smoothPoint(
        key,
        Point2D(
          x,
          y,
          z: landmark.z,
          confidence: landmark.likelihood,
        ),
      );
    }

    final Map<String, Point2D?> points = {
      'NOSE': getPoint(PoseLandmarkType.nose),
      'LEFT_SHOULDER': getPoint(PoseLandmarkType.leftShoulder),
      'RIGHT_SHOULDER': getPoint(PoseLandmarkType.rightShoulder),
      'LEFT_ELBOW': getPoint(PoseLandmarkType.leftElbow),
      'RIGHT_ELBOW': getPoint(PoseLandmarkType.rightElbow),
      'LEFT_WRIST': getPoint(PoseLandmarkType.leftWrist),
      'RIGHT_WRIST': getPoint(PoseLandmarkType.rightWrist),
      'LEFT_HIP': getPoint(PoseLandmarkType.leftHip),
      'RIGHT_HIP': getPoint(PoseLandmarkType.rightHip),
      'LEFT_KNEE': getPoint(PoseLandmarkType.leftKnee),
      'RIGHT_KNEE': getPoint(PoseLandmarkType.rightKnee),
      'LEFT_ANKLE': getPoint(PoseLandmarkType.leftAnkle),
      'RIGHT_ANKLE': getPoint(PoseLandmarkType.rightAnkle),
      'LEFT_HEEL': getPoint(PoseLandmarkType.leftHeel, minConfidence: 0.18),
      'RIGHT_HEEL': getPoint(PoseLandmarkType.rightHeel, minConfidence: 0.18),
      'LEFT_FOOT_INDEX':
          getPoint(PoseLandmarkType.leftFootIndex, minConfidence: 0.18),
      'RIGHT_FOOT_INDEX':
          getPoint(PoseLandmarkType.rightFootIndex, minConfidence: 0.18),
    };

    // Em perfil, descobre qual lado do corpo está de fato voltado para a câmera
    // (e corrige rótulos esquerdo/direito trocados pelo modelo).
    final String? visibleSide =
        onlySide != null ? _resolveProfileSide(points) : null;

    final Map<String, Point2D> validLandmarks = {};
    points.forEach((k, v) {
      if (v != null) validLandmarks[k] = v;
    });

    // Orientação calculada com os dois lados, antes de ocultar o lado oposto.
    final orientation = _estimateBodyOrientation(points);
    // Histerese: evita alternar entre os modos de compensação perto do limiar.
    if (_diagonalMode) {
      if (orientation.$1 >= 54.0) _diagonalMode = false;
    } else {
      if (orientation.$1 < 42.0) _diagonalMode = true;
    }
    final bool isFrontalOrDiagonal = _diagonalMode;

    // Em perfil, o lado oposto à câmera fica ocluído e o modelo "inventa" os
    // pontos dele (esqueleto bagunçado). Mantém só o lado visível.
    if (onlySide != null) {
      final effective = visibleSide ?? onlySide;
      final other = effective == 'LEFT' ? 'RIGHT_' : 'LEFT_';
      for (final k in points.keys.toList()) {
        if (k.startsWith(other)) points[k] = null;
      }
      validLandmarks.removeWhere((k, _) => k.startsWith(other));
    }

    final Map<String, JointAngleData> angles = {};

    JointAngleData compute(
      String key,
      String a,
      String b,
      String c,
      String label, {
      double? overrideRawAngle,
    }) {
      final ptA = points[a];
      final ptB = points[b];
      final ptC = points[c];

      if (ptA != null && ptB != null && ptC != null) {
        _missingAngleFrames[key] = 0;
        final rawAngle = overrideRawAngle ?? calculateAngle(ptA, ptB, ptC);
        final angle = _smoothAngle(key, rawAngle);
        final data = JointAngleData(
          key: key,
          label: label,
          angle: angle,
          vertex: ptB,
          isValid: true,
          confidence: min(ptA.confidence, min(ptB.confidence, ptC.confidence)),
        );
        _lastValidAngles[key] = data;
        return data;
      }

      final int missed = (_missingAngleFrames[key] ?? 0) + 1;
      _missingAngleFrames[key] = missed;
      if (missed <= 4 && _lastValidAngles.containsKey(key)) {
        return _lastValidAngles[key]!;
      }

      _smoothedAngles.remove(key);
      _lastValidAngles.remove(key);
      return JointAngleData(key: key, label: label, isValid: false);
    }

    // Compensação biomecânica de escorço frontal (foreshortening) para agachamento de frente:
    // Quando o usuário agacha olhando para a câmera, o fêmur aponta para a lente e encurta
    // verticalmente em relação à tíbia, mesmo que os pontos 2D (quadril-joelho-tornozelo)
    // continuem quase alinhados verticalmente (~165°).
    double? computeCompensatedKneeAngle(
      Point2D? hip,
      Point2D? knee,
      Point2D? ankle,
    ) {
      if (hip == null || knee == null || ankle == null) return null;
      final double angle2D = calculateAngle(hip, knee, ankle);
      if (!isFrontalOrDiagonal) return angle2D;

      final double tibiaVert = max(24.0, (ankle.y - knee.y).abs());
      final double femurVert = max(0.0, knee.y - hip.y);
      // Em pé reto, femurVert / tibiaVert ≈ 0.96..1.10. Agachando de frente, cai para 0.45..0.78.
      final double ratio = (femurVert / (tibiaVert * 0.96)).clamp(0.25, 1.0);
      if (ratio < 0.88) {
        // Converte o encurtamento vertical do fêmur em ângulo real de flexão do joelho (85°..175°)
        final double foreshortenedAngle =
            82.0 + ((ratio - 0.35) / 0.53).clamp(0.0, 1.0) * 88.0;
        return min(angle2D, foreshortenedAngle);
      }
      return angle2D;
    }

    double? computeCompensatedHipAngle(
      Point2D? shoulder,
      Point2D? hip,
      Point2D? knee,
      Point2D? ankle,
    ) {
      if (shoulder == null || hip == null || knee == null) return null;
      final double angle2D = calculateAngle(shoulder, hip, knee);
      if (!isFrontalOrDiagonal || ankle == null) return angle2D;

      final double tibiaVert = max(24.0, (ankle.y - knee.y).abs());
      final double femurVert = max(0.0, knee.y - hip.y);
      final double ratio = (femurVert / (tibiaVert * 0.96)).clamp(0.25, 1.0);
      if (ratio < 0.88) {
        final double foreshortenedHip =
            88.0 + ((ratio - 0.35) / 0.53).clamp(0.0, 1.0) * 84.0;
        return min(angle2D, foreshortenedHip);
      }
      return angle2D;
    }

    angles['cotovelo_esq'] = compute(
      'cotovelo_esq',
      'LEFT_SHOULDER',
      'LEFT_ELBOW',
      'LEFT_WRIST',
      'Cotovelo Esquerdo',
    );
    angles['cotovelo_dir'] = compute(
      'cotovelo_dir',
      'RIGHT_SHOULDER',
      'RIGHT_ELBOW',
      'RIGHT_WRIST',
      'Cotovelo Direito',
    );
    angles['ombro_esq'] = compute(
      'ombro_esq',
      'LEFT_HIP',
      'LEFT_SHOULDER',
      'LEFT_ELBOW',
      'Ombro Esquerdo',
    );
    angles['ombro_dir'] = compute(
      'ombro_dir',
      'RIGHT_HIP',
      'RIGHT_SHOULDER',
      'RIGHT_ELBOW',
      'Ombro Direito',
    );
    angles['quadril_esq'] = compute(
      'quadril_esq',
      'LEFT_SHOULDER',
      'LEFT_HIP',
      'LEFT_KNEE',
      'Quadril Esquerdo',
      overrideRawAngle: computeCompensatedHipAngle(
        points['LEFT_SHOULDER'],
        points['LEFT_HIP'],
        points['LEFT_KNEE'],
        points['LEFT_ANKLE'],
      ),
    );
    angles['quadril_dir'] = compute(
      'quadril_dir',
      'RIGHT_SHOULDER',
      'RIGHT_HIP',
      'RIGHT_KNEE',
      'Quadril Direito',
      overrideRawAngle: computeCompensatedHipAngle(
        points['RIGHT_SHOULDER'],
        points['RIGHT_HIP'],
        points['RIGHT_KNEE'],
        points['RIGHT_ANKLE'],
      ),
    );
    angles['joelho_esq'] = compute(
      'joelho_esq',
      'LEFT_HIP',
      'LEFT_KNEE',
      'LEFT_ANKLE',
      'Joelho Esquerdo',
      overrideRawAngle: computeCompensatedKneeAngle(
        points['LEFT_HIP'],
        points['LEFT_KNEE'],
        points['LEFT_ANKLE'],
      ),
    );
    angles['joelho_dir'] = compute(
      'joelho_dir',
      'RIGHT_HIP',
      'RIGHT_KNEE',
      'RIGHT_ANKLE',
      'Joelho Direito',
      overrideRawAngle: computeCompensatedKneeAngle(
        points['RIGHT_HIP'],
        points['RIGHT_KNEE'],
        points['RIGHT_ANKLE'],
      ),
    );

    final String leftAnkleVertex =
        points['LEFT_HEEL'] != null ? 'LEFT_HEEL' : 'LEFT_ANKLE';
    final String rightAnkleVertex =
        points['RIGHT_HEEL'] != null ? 'RIGHT_HEEL' : 'RIGHT_ANKLE';

    final double calfLeftPct = _calculateCalfElevationPct(
      isLeft: true,
      knee: points['LEFT_KNEE'],
      ankle: points['LEFT_ANKLE'],
      heel: points['LEFT_HEEL'],
      footIndex: points['LEFT_FOOT_INDEX'],
    );
    final double calfRightPct = _calculateCalfElevationPct(
      isLeft: false,
      knee: points['RIGHT_KNEE'],
      ankle: points['RIGHT_ANKLE'],
      heel: points['RIGHT_HEEL'],
      footIndex: points['RIGHT_FOOT_INDEX'],
    );

    // Em visão frontal, o ângulo 2D (joelho-calcanhar-ponta do pé) sofre distorção de perspectiva.
    // Ajustamos o ângulo de flexão plantar com base na elevação real calibrada do calcanhar:
    double? computeCalibratedAnkleAngle(
      Point2D? knee,
      Point2D? vertex,
      Point2D? footIndex,
      double calfPct,
    ) {
      if (knee == null || vertex == null || footIndex == null) return null;
      final double raw2D = calculateAngle(knee, vertex, footIndex);
      if (isFrontalOrDiagonal) {
        // Em pé plano (0% de elevação) = ~96°; na ponta dos pés (100%) = ~136°
        return 96.0 + (calfPct / 100.0) * 40.0;
      }
      return raw2D;
    }

    angles['tornozelo_esq'] = compute(
      'tornozelo_esq',
      'LEFT_KNEE',
      leftAnkleVertex,
      'LEFT_FOOT_INDEX',
      'Tornozelo / Panturrilha Esq.',
      overrideRawAngle: computeCalibratedAnkleAngle(
        points['LEFT_KNEE'],
        points[leftAnkleVertex],
        points['LEFT_FOOT_INDEX'],
        calfLeftPct,
      ),
    );
    angles['tornozelo_dir'] = compute(
      'tornozelo_dir',
      'RIGHT_KNEE',
      rightAnkleVertex,
      'RIGHT_FOOT_INDEX',
      'Tornozelo / Panturrilha Dir.',
      overrideRawAngle: computeCalibratedAnkleAngle(
        points['RIGHT_KNEE'],
        points[rightAnkleVertex],
        points['RIGHT_FOOT_INDEX'],
        calfRightPct,
      ),
    );

    // Coluna: inclinação do tronco em relação à vertical (0° = ereto).
    // Ângulo no meio do quadril entre o meio dos ombros e um ponto na vertical.
    Point2D? midPoint(String l, String r) {
      final a = points[l];
      final b = points[r];
      if (a != null && b != null) return Point2D((a.x + b.x) / 2, (a.y + b.y) / 2);
      return a ?? b;
    }

    final spineTop = midPoint('LEFT_SHOULDER', 'RIGHT_SHOULDER');
    final spineBase = midPoint('LEFT_HIP', 'RIGHT_HIP');
    if (spineTop != null && spineBase != null) {
      points['_SPINE_TOP'] = spineTop;
      points['_SPINE_BASE'] = spineBase;
      points['_SPINE_UP'] = Point2D(spineBase.x, spineBase.y - 100);
    }
    angles['coluna'] = compute(
      'coluna',
      '_SPINE_TOP',
      '_SPINE_BASE',
      '_SPINE_UP',
      'Coluna',
    );

    return ExtractedPoseData(
      angles: angles,
      landmarks: validLandmarks,
      calfElevationLeftPct: calfLeftPct,
      calfElevationRightPct: calfRightPct,
      bodyOrientationAngle: orientation.$1,
      bodyOrientationLabel: orientation.$2,
      visibleSide: visibleSide,
    );
  }

  /// Calcula o percentual real (0% a 100%) de elevação de panturrilha descontando
  /// a perspectiva natural do pé plano no chão (baseline automática).
  double _calculateCalfElevationPct({
    required bool isLeft,
    required Point2D? knee,
    required Point2D? ankle,
    required Point2D? heel,
    required Point2D? footIndex,
  }) {
    if (heel == null || footIndex == null || knee == null || ankle == null) {
      return 0.0;
    }

    final double tibiaLen = max(30.0, knee.distanceTo(ankle));
    final double currentSpanRatio =
        ((footIndex.y - heel.y) / tibiaLen).clamp(-0.20, 0.45);

    double? baseline =
        isLeft ? _baselineLeftFootSpanRatio : _baselineRightFootSpanRatio;
    if (baseline == null) {
      baseline = currentSpanRatio;
    } else if (currentSpanRatio < baseline) {
      // Se o pé estiver mais plano do que a baseline anterior, atualiza a referência de chão imediatamente
      baseline = baseline * 0.7 + currentSpanRatio * 0.3;
    } else {
      // Adaptação muito lenta para cima apenas para evitar drift de câmera
      baseline = baseline * 0.992 + currentSpanRatio * 0.008;
    }

    if (isLeft) {
      _baselineLeftFootSpanRatio = baseline;
    } else {
      _baselineRightFootSpanRatio = baseline;
    }

    // Só contabiliza elevação acima da linha de base do pé plano (+ margem de ruído de 0.025)
    final double netLiftRatio = max(0.0, currentSpanRatio - baseline - 0.025);
    final double pct = (netLiftRatio / 0.11).clamp(0.0, 1.0) * 100.0;
    return (pct * 10).roundToDouble() / 10.0;
  }

  /// Deduz o lado voltado para a câmera a partir da direção do corpo e troca os
  /// rótulos LEFT_/RIGHT_ de [p] (in place) se o modelo os inverteu.
  ///
  /// Na imagem sem espelhamento, quem está com o lado ESQUERDO para a câmera
  /// olha para a ESQUERDA da imagem (e vice-versa).
  String? _resolveProfileSide(Map<String, Point2D?> p) {
    final nose = p['NOSE'];
    final lHip = p['LEFT_HIP'];
    final rHip = p['RIGHT_HIP'];
    final lSh = p['LEFT_SHOULDER'];
    final rSh = p['RIGHT_SHOULDER'];

    double torso = 120;
    final hips = [lHip, rHip].whereType<Point2D>().toList();
    final shs = [lSh, rSh].whereType<Point2D>().toList();
    if (hips.isNotEmpty && shs.isNotEmpty) {
      final hy = hips.map((e) => e.y).reduce((a, b) => a + b) / hips.length;
      final sy = shs.map((e) => e.y).reduce((a, b) => a + b) / shs.length;
      torso = max(40.0, (hy - sy).abs());
    }

    // 1) Direção do corpo: nariz à frente do quadril e ponta do pé à frente do calcanhar.
    double score = 0;
    if (nose != null && hips.isNotEmpty) {
      final hx = hips.map((e) => e.x).reduce((a, b) => a + b) / hips.length;
      score += nose.x - hx;
    }
    for (final side in const ['LEFT', 'RIGHT']) {
      final heel = p['${side}_HEEL'];
      final toe = p['${side}_FOOT_INDEX'];
      if (heel != null && toe != null) score += (toe.x - heel.x) * 0.5;
    }
    if (score.abs() > 0.08 * torso) _headingRight = score > 0;
    final heading = _headingRight;
    if (heading == null) return null;
    final String side = heading ? 'RIGHT' : 'LEFT';

    // 2) Grupo mais próximo da câmera pela profundidade (menor z = mais perto).
    double? meanZ(String s) {
      final zs = [p['${s}_SHOULDER'], p['${s}_HIP']]
          .whereType<Point2D>()
          .map((e) => e.z)
          .toList();
      if (zs.isEmpty) return null;
      return zs.reduce((a, b) => a + b) / zs.length;
    }

    final zl = meanZ('LEFT');
    final zr = meanZ('RIGHT');
    if (zl != null && zr != null && (zl - zr).abs() > 0.04 * torso) {
      _nearLeft = zl < zr;
    }
    final near = _nearLeft;
    if (near != null && (near ? 'LEFT' : 'RIGHT') != side) {
      final swapped = <String, Point2D?>{};
      p.forEach((k, v) {
        final nk = k.startsWith('LEFT_')
            ? 'RIGHT_${k.substring(5)}'
            : k.startsWith('RIGHT_')
                ? 'LEFT_${k.substring(6)}'
                : k;
        swapped[nk] = v;
      });
      p
        ..clear()
        ..addAll(swapped);
    }
    return side;
  }

  (double, String) _estimateBodyOrientation(Map<String, Point2D?> points) {
    final lShoulder = points['LEFT_SHOULDER'];
    final rShoulder = points['RIGHT_SHOULDER'];
    final lHip = points['LEFT_HIP'];
    final rHip = points['RIGHT_HIP'];

    if (lShoulder == null ||
        rShoulder == null ||
        lHip == null ||
        rHip == null) {
      return (0.0, 'Frontal');
    }

    final double shoulderWidth2D = (lShoulder.x - rShoulder.x).abs();
    final double midShoulderY = (lShoulder.y + rShoulder.y) / 2.0;
    final double midHipY = (lHip.y + rHip.y) / 2.0;
    final double torsoHeight = max(20.0, (midHipY - midShoulderY).abs());

    final double widthRatio =
        (shoulderWidth2D / (torsoHeight * 0.72)).clamp(0.0, 1.0);
    final double angleFrom2D = acos(widthRatio) * 180.0 / pi;

    final double dz = (lShoulder.z - rShoulder.z).abs();
    final double angleFrom3D =
        atan2(dz, max(1.0, shoulderWidth2D)) * 180.0 / pi;

    final double estimatedYaw =
        ((angleFrom2D * 0.7) + (angleFrom3D * 0.3)).clamp(0.0, 90.0);
    final double roundedYaw = (estimatedYaw * 10).roundToDouble() / 10.0;

    String label;
    if (roundedYaw < 25.0) {
      label = 'Frontal';
    } else if (roundedYaw < 60.0) {
      label = 'Diagonal';
    } else {
      label = 'Perfil';
    }

    return (roundedYaw, label);
  }

  ExtractedPoseData generateSyntheticAngles(double timeSec, Size screenSize) {
    final squatCycle = sin(2 * pi * 0.4 * timeSec);
    final joelhoAngle = ((125.0 - 45.0 * squatCycle) * 10).roundToDouble() / 10.0;
    final quadrilAngle = ((135.0 - 40.0 * squatCycle) * 10).roundToDouble() / 10.0;

    final armCycle = sin(2 * pi * 0.2 * timeSec);
    final cotoveloAngle = ((110.0 + 40.0 * armCycle) * 10).roundToDouble() / 10.0;
    final ombroAngle = ((85.0 + 35.0 * armCycle) * 10).roundToDouble() / 10.0;

    final calfCycle = (sin(2 * pi * 0.3 * timeSec) + 1.0) / 2.0;
    final tornozeloAngle = ((100.0 + 42.0 * calfCycle) * 10).roundToDouble() / 10.0;
    final calfPct = ((calfCycle * 85.0) * 10).roundToDouble() / 10.0;

    final double cx = screenSize.width / 2.0;
    final double cy = screenSize.height / 2.0;
    final double heelLift = 18.0 * calfCycle;

    final landmarks = {
      'NOSE': Point2D(cx, cy - 180),
      'LEFT_SHOULDER': Point2D(cx - 60, cy - 130),
      'RIGHT_SHOULDER': Point2D(cx + 60, cy - 130),
      'LEFT_ELBOW': Point2D(cx - 90, cy - 60 + 20 * armCycle),
      'RIGHT_ELBOW': Point2D(cx + 90, cy - 60 - 20 * armCycle),
      'LEFT_WRIST': Point2D(cx - 100, cy + 10 + 30 * armCycle),
      'RIGHT_WRIST': Point2D(cx + 100, cy + 10 - 30 * armCycle),
      'LEFT_HIP': Point2D(cx - 45, cy + 30 + 15 * squatCycle),
      'RIGHT_HIP': Point2D(cx + 45, cy + 30 + 15 * squatCycle),
      'LEFT_KNEE': Point2D(cx - 50, cy + 130 + 25 * squatCycle),
      'RIGHT_KNEE': Point2D(cx + 50, cy + 130 + 25 * squatCycle),
      'LEFT_ANKLE': Point2D(cx - 50, cy + 225 - heelLift),
      'RIGHT_ANKLE': Point2D(cx + 50, cy + 225 - heelLift),
      'LEFT_HEEL': Point2D(cx - 46, cy + 238 - heelLift),
      'RIGHT_HEEL': Point2D(cx + 46, cy + 238 - heelLift),
      'LEFT_FOOT_INDEX': Point2D(cx - 64, cy + 242),
      'RIGHT_FOOT_INDEX': Point2D(cx + 64, cy + 242),
    };

    final angles = {
      'cotovelo_esq': JointAngleData(
        key: 'cotovelo_esq',
        label: 'Cotovelo Esquerdo',
        angle: cotoveloAngle,
        vertex: landmarks['LEFT_ELBOW'],
        isValid: true,
      ),
      'cotovelo_dir': JointAngleData(
        key: 'cotovelo_dir',
        label: 'Cotovelo Direito',
        angle: cotoveloAngle,
        vertex: landmarks['RIGHT_ELBOW'],
        isValid: true,
      ),
      'ombro_esq': JointAngleData(
        key: 'ombro_esq',
        label: 'Ombro Esquerdo',
        angle: ombroAngle,
        vertex: landmarks['LEFT_SHOULDER'],
        isValid: true,
      ),
      'ombro_dir': JointAngleData(
        key: 'ombro_dir',
        label: 'Ombro Direito',
        angle: ombroAngle,
        vertex: landmarks['RIGHT_SHOULDER'],
        isValid: true,
      ),
      'quadril_esq': JointAngleData(
        key: 'quadril_esq',
        label: 'Quadril Esquerdo',
        angle: quadrilAngle,
        vertex: landmarks['LEFT_HIP'],
        isValid: true,
      ),
      'quadril_dir': JointAngleData(
        key: 'quadril_dir',
        label: 'Quadril Direito',
        angle: quadrilAngle,
        vertex: landmarks['RIGHT_HIP'],
        isValid: true,
      ),
      'joelho_esq': JointAngleData(
        key: 'joelho_esq',
        label: 'Joelho Esquerdo',
        angle: joelhoAngle,
        vertex: landmarks['LEFT_KNEE'],
        isValid: true,
      ),
      'joelho_dir': JointAngleData(
        key: 'joelho_dir',
        label: 'Joelho Direito',
        angle: joelhoAngle,
        vertex: landmarks['RIGHT_KNEE'],
        isValid: true,
      ),
      'tornozelo_esq': JointAngleData(
        key: 'tornozelo_esq',
        label: 'Tornozelo / Panturrilha Esq.',
        angle: tornozeloAngle,
        vertex: landmarks['LEFT_HEEL'],
        isValid: true,
      ),
      'tornozelo_dir': JointAngleData(
        key: 'tornozelo_dir',
        label: 'Tornozelo / Panturrilha Dir.',
        angle: tornozeloAngle,
        vertex: landmarks['RIGHT_HEEL'],
        isValid: true,
      ),
    };

    return ExtractedPoseData(
      angles: angles,
      landmarks: landmarks,
      calfElevationLeftPct: calfPct,
      calfElevationRightPct: calfPct,
      bodyOrientationAngle: 12.0,
      bodyOrientationLabel: 'Frontal',
    );
  }
}
