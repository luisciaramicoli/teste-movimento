import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/joint_angle.dart';

class PoseDetectorService {
  late final PoseDetector _detector;
  bool isInitialized = false;

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

  void dispose() {
    _detector.close();
  }

  /// Converte os marcos anatômicos do Google ML Kit em coordenadas 2D e calcula os ângulos.
  Map<String, JointAngleData> extractAnglesFromPose(
    Pose pose,
    Size imageSize,
    Size widgetSize, {
    bool isFrontCamera = false,
  }) {
    Point2D? getPoint(PoseLandmarkType type) {
      final landmark = pose.landmarks[type];
      if (landmark == null) return null;

      // Escala para as dimensões do widget na tela
      final scaleX = widgetSize.width / imageSize.width;
      final scaleY = widgetSize.height / imageSize.height;

      double x = landmark.x * scaleX;
      if (isFrontCamera) {
        // Espelhamento horizontal para câmera frontal
        x = widgetSize.width - x;
      }
      final y = landmark.y * scaleY;

      return Point2D(x, y);
    }

    final Map<String, Point2D?> points = {
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

    final Map<String, JointAngleData> angles = {};

    JointAngleData compute(String key, String a, String b, String c, String label) {
      final ptA = points[a];
      final ptB = points[b];
      final ptC = points[c];

      if (ptA != null && ptB != null && ptC != null) {
        final angle = calculateAngle(ptA, ptB, ptC);
        return JointAngleData(
          key: key,
          label: label,
          angle: angle,
          vertex: ptB,
          isValid: true,
        );
      }
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

    return angles;
  }

  /// Gera dados sintéticos de pose para o modo demonstração/teste (sem câmera física)
  Map<String, JointAngleData> generateSyntheticAngles(double timeSec) {
    // Simula ciclo de agachamento de 2.5s
    final squatCycle = sin(2 * pi * 0.4 * timeSec);
    final joelhoAngle = double.parse((125.0 - 45.0 * squatCycle).toStringAsFixed(1));
    final quadrilAngle = double.parse((135.0 - 40.0 * squatCycle).toStringAsFixed(1));

    final armCycle = sin(2 * pi * 0.2 * timeSec);
    final cotoveloAngle = double.parse((110.0 + 40.0 * armCycle).toStringAsFixed(1));
    final ombroAngle = double.parse((85.0 + 35.0 * armCycle).toStringAsFixed(1));

    return {
      'cotovelo_esq': JointAngleData(
        key: 'cotovelo_esq',
        label: 'Cotovelo Esquerdo',
        angle: cotoveloAngle,
        vertex: const Point2D(120, 260),
        isValid: true,
      ),
      'cotovelo_dir': JointAngleData(
        key: 'cotovelo_dir',
        label: 'Cotovelo Direito',
        angle: cotoveloAngle,
        vertex: const Point2D(280, 260),
        isValid: true,
      ),
      'ombro_esq': JointAngleData(
        key: 'ombro_esq',
        label: 'Ombro Esquerdo',
        angle: ombroAngle,
        vertex: const Point2D(140, 200),
        isValid: true,
      ),
      'ombro_dir': JointAngleData(
        key: 'ombro_dir',
        label: 'Ombro Direito',
        angle: ombroAngle,
        vertex: const Point2D(260, 200),
        isValid: true,
      ),
      'quadril_esq': JointAngleData(
        key: 'quadril_esq',
        label: 'Quadril Esquerdo',
        angle: quadrilAngle,
        vertex: const Point2D(160, 380),
        isValid: true,
      ),
      'quadril_dir': JointAngleData(
        key: 'quadril_dir',
        label: 'Quadril Direito',
        angle: quadrilAngle,
        vertex: const Point2D(240, 380),
        isValid: true,
      ),
      'joelho_esq': JointAngleData(
        key: 'joelho_esq',
        label: 'Joelho Esquerdo',
        angle: joelhoAngle,
        vertex: const Point2D(150, 490),
        isValid: true,
      ),
      'joelho_dir': JointAngleData(
        key: 'joelho_dir',
        label: 'Joelho Direito',
        angle: joelhoAngle,
        vertex: const Point2D(250, 490),
        isValid: true,
      ),
    };
  }
}

