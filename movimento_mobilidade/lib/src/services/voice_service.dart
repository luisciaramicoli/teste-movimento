import 'package:flutter_tts/flutter_tts.dart';

/// Instruções por voz (TTS) em português. Falhas de TTS nunca interrompem a avaliação.
class VoiceService {
  final FlutterTts _tts = FlutterTts();
  bool enabled = true;
  bool _ready = false;
  bool _speaking = false;
  String? _pending;

  bool get isSpeaking => _speaking;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.5);
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(_onDone);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _onDone());
    } catch (_) {}
  }

  void _onDone() {
    _speaking = false;
    final next = _pending;
    _pending = null;
    if (next != null && enabled) speak(next);
  }

  /// Fala [text]. Com [interrupt] corta a fala atual; sem ele, espera a fala
  /// atual terminar (só a mensagem mais recente fica na fila).
  Future<void> speak(String text, {bool interrupt = true}) async {
    if (!enabled) return;
    try {
      await _init();
      if (_speaking && !interrupt) {
        _pending = text;
        return;
      }
      _pending = null;
      if (_speaking) await _tts.stop();
      _speaking = true;
      await _tts.speak(text);
    } catch (_) {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    _pending = null;
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
