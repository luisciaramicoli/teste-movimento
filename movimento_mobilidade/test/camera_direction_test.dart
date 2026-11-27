import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';
import 'package:movimento_mobilidade/src/models/joint_angle.dart';
import 'package:movimento_mobilidade/src/services/framing_checker.dart';
import 'package:movimento_mobilidade/src/services/pose_detector_service.dart';
import 'package:movimento_mobilidade/src/services/protocol_service.dart';

const _size = Size(480, 720);

/// Pose na imagem que a câmera entrega, sem espelhamento.
Pose _pose(Map<PoseLandmarkType, (double, double, double)> points) =>
    Pose(landmarks: {
      for (final e in points.entries)
        e.key: PoseLandmark(
            type: e.key,
            x: e.value.$1,
            y: e.value.$2,
            z: e.value.$3,
            likelihood: 0.95),
    });

/// Perfil em pé. Quem olha para a direita da imagem mostra o lado direito; o
/// lado próximo da câmera tem z menor.
Pose _profile({required bool facingRight}) {
  final dir = facingRight ? 1.0 : -1.0;
  final leftZ = facingRight ? 40.0 : -40.0;
  (double, double, double) at(double dx, double y, bool left) =>
      (240 + dx * dir, y, left ? leftZ : -leftZ);
  return _pose({
    PoseLandmarkType.nose: (240 + 30 * dir, 120, 0),
    PoseLandmarkType.leftShoulder: at(0, 180, true),
    PoseLandmarkType.rightShoulder: at(2, 180, false),
    PoseLandmarkType.leftHip: at(-4, 360, true),
    PoseLandmarkType.rightHip: at(-2, 360, false),
    PoseLandmarkType.leftKnee: at(0, 480, true),
    PoseLandmarkType.rightKnee: at(2, 480, false),
    PoseLandmarkType.leftAnkle: at(-4, 600, true),
    PoseLandmarkType.rightAnkle: at(-2, 600, false),
    PoseLandmarkType.leftHeel: at(-14, 615, true),
    PoseLandmarkType.rightHeel: at(-12, 615, false),
    PoseLandmarkType.leftFootIndex: at(34, 620, true),
    PoseLandmarkType.rightFootIndex: at(36, 620, false),
  });
}

/// De frente, com o centro do corpo em [centerX] na imagem da câmera.
Pose _frontal(double centerX) {
  // A esquerda anatômica da pessoa fica à direita da imagem da câmera.
  (double, double, double) at(double dx, double y) => (centerX + dx, y, 0);
  return _pose({
    PoseLandmarkType.nose: at(0, 120),
    PoseLandmarkType.leftShoulder: at(60, 190),
    PoseLandmarkType.rightShoulder: at(-60, 190),
    PoseLandmarkType.leftElbow: at(75, 280),
    PoseLandmarkType.rightElbow: at(-75, 280),
    PoseLandmarkType.leftWrist: at(80, 360),
    PoseLandmarkType.rightWrist: at(-80, 360),
    PoseLandmarkType.leftHip: at(35, 360),
    PoseLandmarkType.rightHip: at(-35, 360),
    PoseLandmarkType.leftKnee: at(35, 480),
    PoseLandmarkType.rightKnee: at(-35, 480),
    PoseLandmarkType.leftAnkle: at(35, 600),
    PoseLandmarkType.rightAnkle: at(-35, 600),
    PoseLandmarkType.leftHeel: at(35, 615),
    PoseLandmarkType.rightHeel: at(-35, 615),
  });
}

ExtractedPoseData _extract(Pose pose,
        {required bool front, String? onlySide}) =>
    PoseDetectorService().extractAnglesFromPose(pose,
        inputImageSize: _size,
        screenSize: _size,
        isFrontCamera: front,
        onlySide: onlySide);

void main() {
  for (final front in [true, false]) {
    final camera = front ? 'frontal' : 'traseira';

    group('câmera $camera', () {
      for (final facingRight in [true, false]) {
        final shown = facingRight ? 'RIGHT' : 'LEFT';
        test('perfil mostrando o lado $shown', () {
          final pose = _extract(_profile(facingRight: facingRight),
              front: front, onlySide: 'RIGHT');
          expect(pose.visibleSide, shown);

          final framing =
              FramingChecker.evaluate(pose, _size, CaptureView.profileRight);
          if (facingRight) {
            expect(framing.issue, isNull, reason: framing.message);
            expect(pose.angles['joelho_dir']!.isValid, isTrue);
            expect(pose.angles['joelho_esq']!.isValid, isFalse);
          } else {
            expect(framing.issue, FramingIssue.wrongOrientation);
            expect(framing.message, 'Mostre o lado direito.');
          }
        });
      }

      // À esquerda na imagem da câmera = pessoa deslocada para a direita dela,
      // então deve ir para a esquerda; vale para as duas câmeras.
      for (final (centerX, direction) in [
        (110.0, 'esquerda'),
        (370.0, 'direita'),
      ]) {
        test('descentralizado em x=$centerX: pede para ir à $direction', () {
          final pose = _extract(_frontal(centerX), front: front);

          final framing =
              FramingChecker.evaluate(pose, _size, CaptureView.frontal);
          expect(framing.issue, FramingIssue.offCenter);
          expect(framing.message, 'Vá para a $direction.');

          final positioning =
              ProtocolService().evaluatePositioning(pose, _size, 0);
          expect(positioning.horizontalMessage.toLowerCase(),
              contains(direction));
        });
      }
    });
  }
}
