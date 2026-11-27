import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:movimento_mobilidade/src/models/joint_angle.dart';
import 'package:movimento_mobilidade/src/services/pose_detector_service.dart';

/// Pessoa de frente com o fêmur curto na imagem, mas quadril, joelho e
/// tornozelo quase alinhados: o caso em que a heurística troca o ângulo.
const _points = <PoseLandmarkType, (double, double)>{
  PoseLandmarkType.leftShoulder: (160, 200),
  PoseLandmarkType.rightShoulder: (320, 200),
  PoseLandmarkType.leftElbow: (120, 280),
  PoseLandmarkType.rightElbow: (360, 280),
  PoseLandmarkType.leftHip: (200, 400),
  PoseLandmarkType.rightHip: (280, 400),
  PoseLandmarkType.leftKnee: (195, 460),
  PoseLandmarkType.rightKnee: (285, 460),
  PoseLandmarkType.leftAnkle: (200, 600),
  PoseLandmarkType.rightAnkle: (280, 600),
  PoseLandmarkType.leftHeel: (205, 615),
  PoseLandmarkType.rightHeel: (275, 615),
  PoseLandmarkType.leftFootIndex: (170, 630),
  PoseLandmarkType.rightFootIndex: (310, 630),
};

final _pose = Pose(landmarks: {
  for (final e in _points.entries)
    e.key: PoseLandmark(
        type: e.key, x: e.value.$1, y: e.value.$2, z: 0, likelihood: 0.9),
});

double _measured(PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c) {
  Point2D p(PoseLandmarkType t) => Point2D(_points[t]!.$1, _points[t]!.$2);
  return calculateAngle(p(a), p(b), p(c));
}

void main() {
  const size = Size(480, 720);

  test('por padrão, os ângulos devolvidos são os medidos na imagem', () {
    final angles = PoseDetectorService()
        .extractAnglesFromPose(_pose, inputImageSize: size, screenSize: size)
        .angles;
    final expected = {
      'quadril_dir': _measured(PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
      'joelho_dir': _measured(PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
      'tornozelo_dir': _measured(PoseLandmarkType.rightKnee,
          PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex),
    };
    for (final e in expected.entries) {
      expect(angles[e.key]!.angle, closeTo(e.value, 0.11), reason: e.key);
    }
  });

  test('a compensação só altera os ângulos quando pedida', () {
    final angles = PoseDetectorService()
        .extractAnglesFromPose(_pose,
            inputImageSize: size,
            screenSize: size,
            compensatePerspective: true)
        .angles;
    final measured = _measured(PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    expect(angles['quadril_dir']!.angle, lessThan(measured - 30));
  });
}
