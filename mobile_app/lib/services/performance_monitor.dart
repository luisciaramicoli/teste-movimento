/// Mede FPS de inferência e latência captura→ângulo (RNF01/RNF02).
/// Latência = tempo entre a chegada do frame e a publicação do ângulo.
class PerformanceMonitor {
  final List<int> _latenciesMs = [];
  int? _firstMs;
  int? _lastMs;

  void record({required int captureMs, required int displayMs}) {
    _firstMs ??= displayMs;
    _lastMs = displayMs;
    _latenciesMs.add(displayMs - captureMs);
  }

  void reset() {
    _latenciesMs.clear();
    _firstMs = null;
    _lastMs = null;
  }

  int get frames => _latenciesMs.length;

  double get avgFps {
    if (_firstMs == null || _lastMs == null || frames < 2) return 0.0;
    final span = _lastMs! - _firstMs!;
    return span <= 0 ? 0.0 : (frames - 1) * 1000.0 / span;
  }

  double get avgLatencyMs => _latenciesMs.isEmpty
      ? 0.0
      : _latenciesMs.reduce((a, b) => a + b) / _latenciesMs.length;

  int get maxLatencyMs =>
      _latenciesMs.isEmpty ? 0 : _latenciesMs.reduce((a, b) => a > b ? a : b);

  String get summary => frames < 2
      ? 'Desempenho: sem dados'
      : 'Desempenho: ${avgFps.toStringAsFixed(1)} FPS · '
          'latência média ${avgLatencyMs.toStringAsFixed(0)} ms '
          '(máx. $maxLatencyMs ms)';
}
