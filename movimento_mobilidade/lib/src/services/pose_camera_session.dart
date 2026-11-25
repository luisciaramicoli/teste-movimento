import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/joint_angle.dart';
import 'native_pose_service.dart';
import 'pose_detector_service.dart';

/// Encapsula câmera + Google ML Kit Pose Detection e entrega, a cada quadro,
/// os landmarks e ângulos já extraídos (coordenadas em pixels da tela).
class PoseCameraSession {
  final PoseDetectorService poseService = PoseDetectorService();
  final NativePoseService native = NativePoseService();
  final void Function(ExtractedPoseData? pose) onPose;
  final Size Function() screenSize;

  /// Quadro sem pessoa ainda não repassado a [onPose] (tolerância a falhas curtas).
  final void Function()? onEmptyFrame;

  CameraController? controller;
  List<CameraDescription> cameras = [];
  int _index = 0;
  bool _processing = false;
  bool _disposed = false;
  bool paused = false;
  bool _usedNative = false;

  /// 'LEFT'/'RIGHT' em perfil (só esse lado é usado); null de frente.
  String? onlySide;

  // Instrumentação de desempenho (média móvel por janela de 2 s).
  int _tConvert = 0, _tMl = 0, _tPost = 0, _nStats = 0, _statsStart = 0;
  int _lastMs = 0;

  /// Latência (ms) da última inferência e FPS médio de processamento.
  int latencyMs = 0;
  double fps = 0;
  int _fpsWindowStart = 0;
  int _fpsCount = 0;
  int _emptyFrames = 0;
  int _srcW = 720;
  int _srcH = 480;
  Uint8List? _buffer;

  PoseCameraSession(
      {required this.onPose, required this.screenSize, this.onEmptyFrame});

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  bool get isFront =>
      cameras.isNotEmpty &&
      cameras[_index].lensDirection == CameraLensDirection.front;

  /// Retorna null em caso de sucesso, ou a mensagem de erro.
  Future<String?> start() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) return 'Nenhuma câmera disponível neste dispositivo.';
      final front = cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
      _index = front >= 0 ? front : 0;
      await _open();
      if (Platform.isAndroid) {
        final ok = await native.init(model: 'lite');
        debugPrint('PERF native=${ok ? native.delegate : 'indisponível (ML Kit)'}');
      }
      return null;
    } catch (e) {
      return 'Não foi possível acessar a câmera: $e';
    }
  }

  Future<void> _open() async {
    controller = CameraController(
      cameras[_index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    await controller!.initialize();
    try {
      await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    await controller!.startImageStream(_onFrame);
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) return;
    final old = controller;
    controller = null;
    try {
      await old?.stopImageStream();
    } catch (_) {}
    await old?.dispose();
    _index = (_index + 1) % cameras.length;
    poseService.resetSmoothing();
    await _open();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || paused || _disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < 5) return;
    _lastMs = now;
    _processing = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final tConv = DateTime.now().millisecondsSinceEpoch;
      final rotNow = input.metadata?.rotation;
      final rotatedNow = rotNow == InputImageRotation.rotation90deg ||
          rotNow == InputImageRotation.rotation270deg;
      final List<Pose> poses;
      final rotSize = rotatedNow
          ? Size(_srcH.toDouble(), _srcW.toDouble())
          : Size(_srcW.toDouble(), _srcH.toDouble());
      _usedNative = native.ready &&
          Platform.isAndroid &&
          (image.planes.length == 3 ||
              (image.planes.length == 1 && input.bytes != null));
      if (_usedNative && image.planes.length == 3) {
        poses = await native.detectYuv(
          image.planes[0].bytes,
          image.planes[1].bytes,
          image.planes[2].bytes,
          _srcW,
          _srcH,
          image.planes[0].bytesPerRow,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel ?? 1,
          rotNow?.rawValue ?? 0,
          rotSize,
        );
      } else if (_usedNative) {
        poses = await native.detect(
          input.bytes!,
          _srcW,
          _srcH,
          rotNow?.rawValue ?? 0,
          rotSize,
        );
      } else {
        poses = await poseService.processImage(input);
      }
      if (_disposed) return;
      final done = DateTime.now().millisecondsSinceEpoch;
      _tConvert += tConv - now;
      _tMl += done - tConv;
      latencyMs = done - now;
      _fpsCount++;
      if (done - _fpsWindowStart >= 1000) {
        fps = _fpsCount * 1000 / (done - _fpsWindowStart);
        _fpsCount = 0;
        _fpsWindowStart = done;
      }
      if (poses.isEmpty) {
        if (++_emptyFrames > 6) {
          poseService.resetSmoothing();
          onPose(null);
        } else {
          onEmptyFrame?.call();
        }
        return;
      }
      _emptyFrames = 0;
      final rot = input.metadata?.rotation;
      final rotated = rot == InputImageRotation.rotation90deg ||
          rot == InputImageRotation.rotation270deg;
      final size = rotated
          ? Size(_srcH.toDouble(), _srcW.toDouble())
          : Size(_srcW.toDouble(), _srcH.toDouble());
      onPose(poseService.extractAnglesFromPose(
        poses.first,
        inputImageSize: size,
        screenSize: screenSize(),
        isFrontCamera: isFront,
        onlySide: onlySide,
      ));
      _tPost += DateTime.now().millisecondsSinceEpoch - done;
      if (++_nStats >= 30) {
        final span = done - _statsStart;
        debugPrint('PERF ${_usedNative ? 'MEDIAPIPE' : 'MLKIT'} planes=${image.planes.length} fps=${(_nStats * 1000 / span).toStringAsFixed(1)} '
            'convert=${(_tConvert / _nStats).toStringAsFixed(1)}ms '
            'mlkit=${(_tMl / _nStats).toStringAsFixed(1)}ms '
            'post=${(_tPost / _nStats).toStringAsFixed(1)}ms');
        _tConvert = _tMl = _tPost = _nStats = 0;
        _statsStart = done;
      }
    } catch (e) {
      debugPrint('Erro ao processar quadro: $e');
    } finally {
      _processing = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final c = controller;
    if (c == null) return null;
    final camera = cameras[_index];
    final sensor = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else if (Platform.isAndroid) {
      var comp = _orientations[c.value.deviceOrientation];
      if (comp != null) {
        comp = camera.lensDirection == CameraLensDirection.front
            ? (sensor + comp) % 360
            : (sensor - comp + 360) % 360;
        rotation = InputImageRotationValue.fromRawValue(comp);
      }
    }
    rotation ??= InputImageRotationValue.fromRawValue(sensor) ??
        InputImageRotation.rotation0deg;

    _srcW = image.width;
    _srcH = image.height;

    if (!Platform.isAndroid) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(_srcW.toDouble(), _srcH.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes[0].bytes;
    } else {
      final total = image.planes.fold<int>(0, (s, p) => s + p.bytes.length);
      if (_buffer == null || _buffer!.length != total) _buffer = Uint8List(total);
      var offset = 0;
      for (final p in image.planes) {
        _buffer!.setRange(offset, offset + p.bytes.length, p.bytes);
        offset += p.bytes.length;
      }
      bytes = _buffer!;
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(_srcW.toDouble(), _srcH.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  /// Pré-visualização alinhada às coordenadas do ML Kit (mesmo tratamento do app anterior).
  Widget buildPreview(Size screen) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final ps = c.value.previewSize;
    final w = ps != null ? ps.height : 480.0;
    final h = ps != null ? ps.width : 720.0;
    Widget preview = SizedBox(width: w, height: h, child: CameraPreview(c));
    return ClipRect(
      child: SizedBox(
        width: screen.width,
        height: screen.height,
        child: FittedBox(fit: BoxFit.cover, child: preview),
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    final c = controller;
    controller = null;
    try {
      await c?.stopImageStream();
    } catch (_) {}
    await c?.dispose();
    poseService.dispose();
    native.dispose();
  }
}
