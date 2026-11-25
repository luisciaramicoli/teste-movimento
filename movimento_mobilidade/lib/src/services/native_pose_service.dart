import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Ponte para o MediaPipe Pose Landmarker nativo (Android, delegate de GPU).
/// Devolve o mesmo tipo [Pose] do ML Kit para reaproveitar todo o pipeline.
class NativePoseService {
  static const _channel = MethodChannel('movimento/pose');

  bool ready = false;
  String delegate = '';

  /// [model]: 'lite' (mais rápido) ou 'full' (mais preciso).
  Future<bool> init({String model = 'full'}) async {
    try {
      delegate = await _channel.invokeMethod<String>('init', {'model': model}) ?? '';
      ready = true;
    } catch (_) {
      ready = false;
    }
    return ready;
  }

  /// Retorna lista vazia quando não há pessoa. Coordenadas em pixels da imagem
  /// já rotacionada ([rotatedSize]).
  Future<List<Pose>> detect(
    Uint8List nv21,
    int width,
    int height,
    int rotation,
    Size rotatedSize,
  ) async {
    final r = await _channel.invokeMethod<Float64List>('detect', {
      'bytes': nv21,
      'width': width,
      'height': height,
      'rotation': rotation,
    });
    return _toPoses(r, rotatedSize);
  }

  List<Pose> _toPoses(Float64List? r, Size rotatedSize) {
    if (r == null || r.isEmpty) return const [];
    final types = PoseLandmarkType.values;
    final n = r.length ~/ 4;
    final map = <PoseLandmarkType, PoseLandmark>{};
    for (var i = 0; i < n && i < types.length; i++) {
      map[types[i]] = PoseLandmark(
        type: types[i],
        x: r[i * 4] * rotatedSize.width,
        y: r[i * 4 + 1] * rotatedSize.height,
        z: r[i * 4 + 2] * rotatedSize.width,
        likelihood: r[i * 4 + 3],
      );
    }
    return [Pose(landmarks: map)];
  }

  /// Quadro YUV_420_888 com 3 planos (Y, U, V) e seus strides.
  Future<List<Pose>> detectYuv(
    Uint8List y,
    Uint8List u,
    Uint8List v,
    int width,
    int height,
    int yStride,
    int uvStride,
    int uvPixelStride,
    int rotation,
    Size rotatedSize,
  ) async {
    final r = await _channel.invokeMethod<Float64List>('detectYuv', {
      'y': y,
      'u': u,
      'v': v,
      'width': width,
      'height': height,
      'yStride': yStride,
      'uvStride': uvStride,
      'uvPixelStride': uvPixelStride,
      'rotation': rotation,
    });
    return _toPoses(r, rotatedSize);
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {}
    ready = false;
  }
}
