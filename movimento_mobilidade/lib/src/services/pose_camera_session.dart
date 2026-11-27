import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/joint_angle.dart';
import 'native_pose_service.dart';
import 'pose_detector_service.dart';

/// Encapsula câmera + detecção de pose (MediaPipe nativo no Android com fallback
/// para Google ML Kit) e entrega, a cada quadro, landmarks e ângulos em pixels
/// da tela.
class PoseCameraSession {
  static const String _defaultNativeModel = 'lite';
  static const int _minFrameIntervalMs = 5;
  static const int _maxEmptyFramesBeforeReset = 6;
  static const int _perfLogWindowFrames = 30;
  static const double _defaultPreviewWidth = 480.0;
  static const double _defaultPreviewHeight = 720.0;

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static List<CameraDescription>? _cachedCameras;
  static Future<List<CameraDescription>>? _camerasFuture;

  /// Carrega e armazena em cache a lista de câmeras disponíveis.
  static Future<List<CameraDescription>> loadCameras({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedCameras != null &&
        _cachedCameras!.isNotEmpty) {
      return _cachedCameras!;
    }
    if (!forceRefresh && _camerasFuture != null) {
      return _camerasFuture!;
    }

    final future = availableCameras();
    _camerasFuture = future;
    try {
      final result = await future;
      if (result.isNotEmpty) {
        _cachedCameras = result;
      }
      return result;
    } finally {
      if (identical(_camerasFuture, future)) {
        _camerasFuture = null;
      }
    }
  }

  /// Pré-aquece de forma não bloqueante a descoberta de câmeras e o modelo
  /// nativo de pose no Android.
  static void prewarm() {
    unawaited(
      loadCameras().catchError((_) => const <CameraDescription>[]),
    );
    if (Platform.isAndroid) {
      unawaited(
        NativePoseService.prewarm(model: _defaultNativeModel)
            .catchError((_) => false),
      );
    }
  }

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
  bool _switching = false;
  bool _nativeInitPending = false;
  bool paused = false;
  bool _usedNative = false;

  /// Repassado a [PoseDetectorService.extractAnglesFromPose].
  final bool compensatePerspective;

  /// 'LEFT'/'RIGHT' em perfil (só esse lado é usado); null de frente.
  String? onlySide;

  // Instrumentação de desempenho (média móvel por janela de quadros).
  int _tConvert = 0, _tInference = 0, _tPost = 0, _nStats = 0, _statsStart = 0;
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

  PoseCameraSession({
    required this.onPose,
    required this.screenSize,
    this.onEmptyFrame,
    this.compensatePerspective = false,
  });

  /// Nome do motor que processou o quadro mais recente. Dentro de [onPose],
  /// refere-se à pose recebida.
  String get lastEngine =>
      engineLabel(usedNative: _usedNative, delegate: native.delegate);

  static String engineLabel(
          {required bool usedNative, required String delegate}) =>
      usedNative
          ? 'MediaPipe Pose Landmarker $_defaultNativeModel ($delegate)'
          : 'ML Kit Pose Detection (base)';

  bool get isFront =>
      cameras.isNotEmpty &&
      cameras[_index].lensDirection == CameraLensDirection.front;

  bool get isPreviewReady =>
      !_disposed && controller != null && controller!.value.isInitialized;

  /// Inicia câmera e pipeline de pose. Retorna `null` em caso de sucesso, ou a
  /// mensagem de erro.
  ///
  /// [onPreviewReady] é chamado imediatamente após `controller.initialize()`,
  /// antes de configurar orientação, iniciar stream de imagem ou aguardar o
  /// carregamento do modelo de pose.
  Future<String?> start({VoidCallback? onPreviewReady}) async {
    final clock = Stopwatch()..start();
    try {
      _startNativeInitIfNeeded(clock);

      cameras = await loadCameras();
      if (_disposed) return null;
      if (cameras.isEmpty) {
        return 'Nenhuma câmera disponível neste dispositivo.';
      }

      final front = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _index = front >= 0 ? front : 0;

      await _open(onPreviewReady: () {
        debugPrint('PERF camera=${clock.elapsedMilliseconds}ms');
        if (!_disposed) onPreviewReady?.call();
      });
      return null;
    } catch (e) {
      return 'Não foi possível acessar a câmera: $e';
    }
  }

  void _startNativeInitIfNeeded(Stopwatch clock) {
    if (!Platform.isAndroid) return;
    _nativeInitPending = true;
    unawaited(
      native.init(model: _defaultNativeModel).then((ok) {
        _nativeInitPending = false;
        debugPrint(
          'PERF native=${ok ? native.delegate : 'indisponível (ML Kit)'} '
          'pronto=${clock.elapsedMilliseconds}ms',
        );
      }).catchError((_) {
        _nativeInitPending = false;
      }),
    );
  }

  Future<void> _open({VoidCallback? onPreviewReady}) async {
    final nextController = CameraController(
      cameras[_index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    controller = nextController;

    await nextController.initialize();
    if (_disposed || !identical(controller, nextController)) {
      await _safeDisposeController(nextController);
      return;
    }

    onPreviewReady?.call();

    try {
      await nextController.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}

    if (_disposed || !identical(controller, nextController)) return;
    await nextController.startImageStream(_onFrame);
  }

  Future<void> switchCamera({VoidCallback? onPreviewReady}) async {
    if (cameras.length < 2 || _switching || _disposed) return;
    _switching = true;
    try {
      final old = controller;
      controller = null;
      await _safeDisposeController(old);
      if (_disposed) return;

      _index = (_index + 1) % cameras.length;
      poseService.resetSmoothing();
      await _open(onPreviewReady: onPreviewReady);
    } finally {
      _switching = false;
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || paused || _disposed) return;
    if (_nativeInitPending) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < _minFrameIntervalMs) return;
    _lastMs = now;
    _processing = true;

    try {
      final rotation = _computeRotation();
      if (rotation == null) return;

      _srcW = image.width;
      _srcH = image.height;
      final rotatedSize = _rotatedSize(rotation);

      final bool useNativeYuv =
          Platform.isAndroid && native.ready && image.planes.length == 3;

      final List<Pose> poses;
      final int tConv;
      if (useNativeYuv) {
        _usedNative = true;
        tConv = DateTime.now().millisecondsSinceEpoch;
        poses = await native.detectYuv(
          image.planes[0].bytes,
          image.planes[1].bytes,
          image.planes[2].bytes,
          _srcW,
          _srcH,
          image.planes[0].bytesPerRow,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel ?? 1,
          rotation.rawValue,
          rotatedSize,
        );
      } else {
        final input = _toInputImage(image, rotation);
        tConv = DateTime.now().millisecondsSinceEpoch;
        _usedNative = Platform.isAndroid &&
            native.ready &&
            image.planes.length == 1 &&
            input.bytes != null;
        if (_usedNative) {
          poses = await native.detect(
            input.bytes!,
            _srcW,
            _srcH,
            rotation.rawValue,
            rotatedSize,
          );
        } else {
          poses = await poseService.processImage(input);
        }
      }

      if (_disposed) return;
      final done = DateTime.now().millisecondsSinceEpoch;
      _updateTimings(now, tConv, done);

      if (poses.isEmpty) {
        _handleEmptyFrame();
        return;
      }

      _emptyFrames = 0;
      onPose(
        poseService.extractAnglesFromPose(
          poses.first,
          inputImageSize: rotatedSize,
          screenSize: screenSize(),
          isFrontCamera: isFront,
          onlySide: onlySide,
          compensatePerspective: compensatePerspective,
        ),
      );
      _tPost += DateTime.now().millisecondsSinceEpoch - done;
      _maybeLogPerf(image.planes.length, done);
    } catch (e) {
      debugPrint('Erro ao processar quadro: $e');
    } finally {
      _processing = false;
    }
  }

  void _updateTimings(int startMs, int convMs, int doneMs) {
    _tConvert += convMs - startMs;
    _tInference += doneMs - convMs;
    latencyMs = doneMs - startMs;
    _fpsCount++;
    if (doneMs - _fpsWindowStart >= 1000) {
      fps = _fpsCount * 1000 / (doneMs - _fpsWindowStart);
      _fpsCount = 0;
      _fpsWindowStart = doneMs;
    }
  }

  void _handleEmptyFrame() {
    if (++_emptyFrames > _maxEmptyFramesBeforeReset) {
      poseService.resetSmoothing();
      onPose(null);
    } else {
      onEmptyFrame?.call();
    }
  }

  void _maybeLogPerf(int planes, int doneMs) {
    if (++_nStats < _perfLogWindowFrames) return;
    final span = doneMs - _statsStart;
    if (span > 0) {
      debugPrint(
        'PERF ${_usedNative ? 'MEDIAPIPE' : 'MLKIT'} planes=$planes '
        'fps=${(_nStats * 1000 / span).toStringAsFixed(1)} '
        'convert=${(_tConvert / _nStats).toStringAsFixed(1)}ms '
        'inferencia=${(_tInference / _nStats).toStringAsFixed(1)}ms '
        'post=${(_tPost / _nStats).toStringAsFixed(1)}ms',
      );
    }
    _tConvert = _tInference = _tPost = _nStats = 0;
    _statsStart = doneMs;
  }

  InputImageRotation? _computeRotation() {
    final c = controller;
    if (c == null || cameras.isEmpty) return null;
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
    return rotation ??
        InputImageRotationValue.fromRawValue(sensor) ??
        InputImageRotation.rotation0deg;
  }

  Size _rotatedSize(InputImageRotation rotation) {
    final rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    return rotated
        ? Size(_srcH.toDouble(), _srcW.toDouble())
        : Size(_srcW.toDouble(), _srcH.toDouble());
  }

  InputImage _toInputImage(CameraImage image, InputImageRotation rotation) {
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

    final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes[0].bytes;
    } else {
      final total = image.planes.fold<int>(0, (s, p) => s + p.bytes.length);
      if (_buffer == null || _buffer!.length != total) {
        _buffer = Uint8List(total);
      }
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

  /// Pré-visualização alinhada às coordenadas do detector de pose.
  Widget buildPreview(Size screen) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final ps = c.value.previewSize;
    final w = ps != null ? ps.height : _defaultPreviewWidth;
    final h = ps != null ? ps.width : _defaultPreviewHeight;
    return ClipRect(
      child: SizedBox(
        width: screen.width,
        height: screen.height,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: w, height: h, child: CameraPreview(c)),
        ),
      ),
    );
  }

  Future<void> _safeDisposeController(CameraController? c) async {
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
      }
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    final c = controller;
    controller = null;
    await _safeDisposeController(c);
    poseService.dispose();
    await native.dispose();
  }
}
