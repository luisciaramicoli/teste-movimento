// Passa os pontos de um vídeo pelo código de análise da biblioteca.
//
// Uso (os trechos são em segundos, no tempo do vídeo):
//   flutter test tool/replay_video_test.dart \
//     --dart-define=LANDMARKS=/caminho/pontos.json \
//     --dart-define=ABDUCTION=3-17 --dart-define=SQUAT=19-25
// CAMERA=front (padrão do app) ou back. Os pontos devem vir de uma imagem sem
// espelhamento, como a que a câmera do aparelho entrega.
//
// Não reproduz a trava de enquadramento da tela: o trecho informado faz esse
// papel. O enquadramento é só relatado.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';
import 'package:movimento_mobilidade/src/models/joint_angle.dart';
import 'package:movimento_mobilidade/src/services/framing_checker.dart';
import 'package:movimento_mobilidade/src/services/pose_detector_service.dart';
import 'package:movimento_mobilidade/src/services/rep_tracker.dart';

const _path = String.fromEnvironment('LANDMARKS');
const _front = String.fromEnvironment('CAMERA', defaultValue: 'front') != 'back';
const _segments = [
  String.fromEnvironment('ABDUCTION'),
  String.fromEnvironment('SQUAT'),
];

/// Elevação do braço (ombro→cotovelo) em relação à vertical da imagem.
/// Não faz parte da biblioteca; serve só de comparação.
double? _armFromVertical(ExtractedPoseData pose, String side) {
  final s = pose.landmarks['${side}_SHOULDER'];
  final e = pose.landmarks['${side}_ELBOW'];
  if (s == null || e == null) return null;
  return atan2((e.x - s.x).abs(), e.y - s.y) * 180 / pi;
}

void main() {
  test('replay de vídeo', () {
    if (_path.isEmpty) {
      markTestSkipped('informe --dart-define=LANDMARKS=...');
      return;
    }
    final data = jsonDecode(File(_path).readAsStringSync()) as Map;
    final size = Size((data['width'] as num).toDouble(),
        (data['height'] as num).toDouble());
    final results = <MovementResult>[];
    print('câmera simulada: ${_front ? 'frontal' : 'traseira'}');

    for (var m = 0; m < kProtocolMovements.length; m++) {
      if (_segments[m].isEmpty) continue;
      final spec = kProtocolMovements[m];
      final limits = _segments[m].split('-').map(double.parse).toList();
      var now = 0.0;
      final service = PoseDetectorService(clock: () => now);
      final tracker = RepTracker(spec);
      final framing = <String, int>{};
      final arm = <String, List<double>>{'LEFT': [], 'RIGHT': []};
      final peaks = <String>[];
      double? best;
      var bestAt = 0.0;

      for (final frame in data['frames'] as List) {
        now = ((frame as Map)['t'] as num).toDouble();
        if (now < limits[0] || now > limits[1]) continue;
        final raw = (frame['p'] as List).cast<num>();
        if (raw.isEmpty) {
          tracker.discardFrame();
          continue;
        }
        final pose = Pose(landmarks: {
          for (var i = 0; i * 4 < raw.length; i++)
            PoseLandmarkType.values[i]: PoseLandmark(
                type: PoseLandmarkType.values[i],
                x: raw[i * 4] * size.width,
                y: raw[i * 4 + 1] * size.height,
                z: raw[i * 4 + 2] * size.width,
                likelihood: raw[i * 4 + 3].toDouble()),
        });
        final extracted = service.extractAnglesFromPose(pose,
            inputImageSize: size,
            screenSize: size,
            isFrontCamera: _front,
            onlySide: spec.view == CaptureView.frontal ? null : 'RIGHT');
        final status = FramingChecker.evaluate(extracted, size, spec.view);
        framing.update(status.issue?.name ?? 'ok', (v) => v + 1,
            ifAbsent: () => 1);
        for (final side in arm.keys) {
          final value = _armFromVertical(extracted, side);
          if (value != null) arm[side]!.add(value);
        }
        final angles = {
          for (final e in extracted.angles.entries)
            if (e.value.isValid && e.value.angle != null)
              e.key: e.value.angle!
        };
        final driver = tracker.driver(angles);
        if (driver != null &&
            (best == null ||
                (tracker.isAbduction ? driver > best : driver < best))) {
          best = driver;
          bestAt = now;
        }
        if (tracker.update(angles, now)) {
          peaks.add('rep ${tracker.reps.length} concluída em '
              '${now.toStringAsFixed(2)} s: ${tracker.reps.last.angles}\n'
              '      em repouso: ${tracker.reps.last.restAngles}');
        }
      }

      final result = tracker.toResult();
      results.add(result);
      print('\n== ${spec.title} (${limits[0]}–${limits[1]} s)');
      print('repetições: ${result.reps.length} de ${spec.repetitions}; '
          'quadros ${result.processedFrames}, '
          'descartados ${result.discardedFrames}');
      peaks.forEach(print);
      print('médias: ${result.averages}');
      print('ângulo condutor extremo: $best em ${bestAt.toStringAsFixed(2)} s');
      print('enquadramento (quadros): $framing');
      if (spec.view == CaptureView.frontal) {
        for (final e in arm.entries) {
          if (e.value.isNotEmpty) {
            print('braço ${e.key} em relação à vertical: '
                'mín ${e.value.reduce(min).toStringAsFixed(1)}°, '
                'máx ${e.value.reduce(max).toStringAsFixed(1)}°');
          }
        }
      }
    }

    final record = AssessmentRecord(
        id: 'replay',
        createdAt: DateTime(2026),
        volunteerCode: 'V00',
        testNumber: 1,
        movements: results);
    print('\n== análise');
    for (final j in record.analysis.joints) {
      print('${j.joint.label}: ${j.angle}° (reps ${j.repAngles}) '
          'nota ${j.grade.toStringAsFixed(1)}');
    }
    print('score: ${record.analysis.score}; '
        'faltam: ${record.analysis.missing.map((j) => j.label).toList()}');
  });
}
