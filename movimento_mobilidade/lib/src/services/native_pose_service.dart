import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Ponte para o MediaPipe Pose Landmarker nativo (Android).
/// Devolve o mesmo tipo [Pose] do ML Kit para reaproveitar todo o pipeline.
class NativePoseService {
  static const MethodChannel _channel = MethodChannel('movimento/pose');
  static const String _methodInit = 'init';
  static const String _methodDetect = 'detect';
  static const String _methodDetectYuv = 'detectYuv';
  static const String _methodDispose = 'dispose';
  static const int _valuesPerLandmark = 4;

  static String? _loadedModel;
  static String _loadedDelegate = '';
  static Future<bool>? _inFlightInit;
  static String? _inFlightModel;

  bool ready = false;
  String delegate = '';

  /// Pré-carrega o landmarker nativo em segundo plano no Android para reutilização
  /// entre sessões sem recriar o modelo.
  static Future<bool> prewarm({String model = 'lite'}) async {
    if (!Platform.isAndroid) return false;
    if (_loadedModel == model) return true;
    if (_inFlightInit != null && _inFlightModel == model) {
      return _inFlightInit!;
    }

    _inFlightModel = model;
    final future = _initializeNative(model);
    _inFlightInit = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightInit, future)) {
        _inFlightInit = null;
        _inFlightModel = null;
      }
    }
  }

  static Future<bool> _initializeNative(String model) async {
    try {
      final usedDelegate =
          await _channel.invokeMethod<String>(_methodInit, {'model': model}) ??
              '';
      _loadedModel = model;
      _loadedDelegate = usedDelegate;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Libera explicitamente o landmarker nativo mantido em memória.
  static Future<void> releaseNative() async {
    try {
      await _channel.invokeMethod<void>(_methodDispose);
    } catch (_) {}
    _loadedModel = null;
    _loadedDelegate = '';
  }

  /// [model]: `'lite'` (mais rápido) ou `'full'` (mais preciso).
  Future<bool> init({String model = 'full'}) async {
    final ok = await prewarm(model: model);
    ready = ok;
    delegate = ok ? _loadedDelegate : '';
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
    final result = await _channel.invokeMethod<Float64List>(_methodDetect, {
      'bytes': nv21,
      'width': width,
      'height': height,
      'rotation': rotation,
    });
    return _toPoses(result, rotatedSize);
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
    final result = await _channel.invokeMethod<Float64List>(_methodDetectYuv, {
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
    return _toPoses(result, rotatedSize);
  }

  List<Pose> _toPoses(Float64List? raw, Size rotatedSize) {
    if (raw == null || raw.isEmpty) return const [];
    const types = PoseLandmarkType.values;
    final count = raw.length ~/ _valuesPerLandmark;
    final landmarks = <PoseLandmarkType, PoseLandmark>{};
    for (var i = 0; i < count && i < types.length; i++) {
      final base = i * _valuesPerLandmark;
      landmarks[types[i]] = PoseLandmark(
        type: types[i],
        x: raw[base] * rotatedSize.width,
        y: raw[base + 1] * rotatedSize.height,
        z: raw[base + 2] * rotatedSize.width,
        likelihood: raw[base + 3],
      );
    }
    return [Pose(landmarks: landmarks)];
  }

  /// Encerra o uso desta instância. Por padrão mantém o landmarker nativo
  /// aquecido para reutilização em sessões seguintes.
  Future<void> dispose({bool releaseNative = false}) async {
    ready = false;
    delegate = '';
    if (releaseNative) {
      await NativePoseService.releaseNative();
    }
  }
}
