import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/joint_angle.dart';

class PoseDetectorService {
  late final PoseDetector _detector;
  bool isInitialized = false;

  final Map<String, Point2D> _smoothedLandmarks = {};
  final Map<String, double> _smoothedAngles = {};

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

  void resetSmoothing() {
    _smoothedLandmarks.clear();
    _smoothedAngles.clear();
  }

  Point2D _smoothPoint(String key, Point2D target) {
    final prev = _smoothedLandmarks[key];
    if (prev == null) {
      _smoothedLandmarks[key] = target;
      return target;
    }
    final dist = prev.distanceTo(target);
    // Filtro passa-baixas adaptativo: suaviza micro-vibrações (ruído)
    // e acompanha movimentos rápidos sem latência perceptível
    final double alpha = dist > 40.0 ? 0.85 : (dist > 15.0 ? 0.70 : 0.50);
    final double sx = prev.x + alpha * (target.x - prev.x);
    final double sy = prev.y + alpha * (target.y - prev.y);
    final smoothed = Point2D(sx, sy);
    _smoothedLandmarks[key] = smoothed;
    return smoothed;
  }

  double _smoothAngle(String key, double target) {
    final prev = _smoothedAngles[key];
    if (prev == null) {
      _smoothedAngles[key] = target;
      return target;
    }
    final diff = (target - prev).abs();
    final double alpha = diff > 25.0 ? 0.85 : (diff > 8.0 ? 0.70 : 0.50);
    final double smoothed = prev + alpha * (target - prev);
    final rounded = double.parse(smoothed.toStringAsFixed(1));
    _smoothedAngles[key] = rounded;
    return rounded;
  }

  void dispose() {
    _detector.close();
  }

  /// Converte os marcos anatômicos do Google ML Kit em coordenadas 2D e calcula os ângulos.
  ExtractedPoseData extractAnglesFromPose(
    Pose pose, {
    required Size inputImageSize,
    required Size screenSize,
    bool isFrontCamera = false,
  }) {
    final double scale = max(
      screenSize.width / inputImageSize.width,
      screenSize.height / inputImageSize.height,
    );
    final double renderW = inputImageSize.width * scale;
    final double renderH = inputImageSize.height * scale;
    final double offsetX = (screenSize.width - renderW) / 2.0;
    final double offsetY = (screenSize.height - renderH) / 2.0;

    Point2D? getPoint(PoseLandmarkType type) {
      final landmark = pose.landmarks[type];
      if (landmark == null || landmark.likelihood < 0.30) {
        _smoothedLandmarks.remove(type.name);
        return null;
      }

      // Coordenadas já alinhadas com o frame de exibição pelo ML Kit
      final double imgX = landmark.x;
      final double imgY = landmark.y;

      final double x = imgX * scale + offsetX;
      final double y = imgY * scale + offsetY;

      return _smoothPoint(type.name, Point2D(x, y));
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
    };

    final Map<String, Point2D> validLandmarks = {};
    points.forEach((k, v) {
      if (v != null) validLandmarks[k] = v;
    });

    final Map<String, JointAngleData> angles = {};

    JointAngleData compute(String key, String a, String b, String c, String label) {
      final ptA = points[a];
      final ptB = points[b];
      final ptC = points[c];

      if (ptA != null && ptB != null && ptC != null) {
        final rawAngle = calculateAngle(ptA, ptB, ptC);
        final angle = _smoothAngle(key, rawAngle);
        return JointAngleData(
          key: key,
          label: label,
          angle: angle,
          vertex: ptB,
          isValid: true,
        );
      }
      _smoothedAngles.remove(key);
      return JointAngleData(key: key, label: label, isValid: false);
    }

    angles['cotovelo_esq'] = compute('cotovelo_esq', 'LEFT_SHOULDER', 'LEFT_ELBOW', 'LEFT_WRIST', 'Cotovelo Esquerdo');
    angles['cotovelo_dir'] = compute('cotovelo_dir', 'RIGHT_SHOULDER', 'RIGHT_ELBOW', 'RIGHT_WRIST', 'Cotovelo Direito');
    angles['ombro_esq'] = compute('ombro_esq', 'LEFT_HIP', 'LEFT_SHOULDER', 'LEFT_ELBOW', 'Ombro Esquerdo');
    angles['ombro_dir'] = compute('ombro_dir', 'RIGHT_HIP', 'RIGHT_SHOULDER', 'RIGHT_ELBOW', 'Ombro Direito');
    angles['quadril_esq'] = compute('quadril_esq', 'LEFT_SHOULDER', 'LEFT_HIP', 'LEFT_KNEE', 'Quadril Esquerdo');
    angles['quadril_dir'] = compute('quadril_dir', 'RIGHT_SHOULDER', 'RIGHT_HIP', 'RIGHT_KNEE', 'Quadril Direito');
    angles['joelho_esq'] = compute('joelho_esq', 'LEFT_HIP', 'LEFT_KNEE', 'LEFT_ANKLE', 'Joelho Esquerdo');
    angles['joelho_dir'] = compute('joelho_dir', 'RIGHT_HIP', 'RIGHT_KNEE', 'RIGHT_ANKLE', 'Joelho Direito');

    return ExtractedPoseData(angles: angles, landmarks: validLandmarks);
  }

  /// Gera dados sintéticos de pose para o modo demonstração/teste (sem câmera física)
  ExtractedPoseData generateSyntheticAngles(double timeSec, Size screenSize) {
    // Simula ciclo de agachamento de 2.5s
    final squatCycle = sin(2 * pi * 0.4 * timeSec);
    final joelhoAngle = double.parse((125.0 - 45.0 * squatCycle).toStringAsFixed(1));
    final quadrilAngle = double.parse((135.0 - 40.0 * squatCycle).toStringAsFixed(1));

    final armCycle = sin(2 * pi * 0.2 * timeSec);
    final cotoveloAngle = double.parse((110.0 + 40.0 * armCycle).toStringAsFixed(1));
    final ombroAngle = double.parse((85.0 + 35.0 * armCycle).toStringAsFixed(1));

    final double cx = screenSize.width / 2.0;
    final double cy = screenSize.height / 2.0;

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
      'LEFT_ANKLE': Point2D(cx - 50, cy + 230),
      'RIGHT_ANKLE': Point2D(cx + 50, cy + 230),
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
    };

    return ExtractedPoseData(angles: angles, landmarks: landmarks);
  }
}

