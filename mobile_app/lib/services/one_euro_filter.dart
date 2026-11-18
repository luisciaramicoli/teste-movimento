import 'dart:math';

/// Implementação do One Euro Filter (Casiez et al., CHI 2012)
/// Filtro passa-baixas adaptativo de primeira ordem ideal para rastreamento de juntas humanas:
/// - Em repouso (baixa velocidade): reduz o corte para eliminar o tremor/jitter de alta frequência.
/// - Em movimento rápido (alta velocidade): eleva o corte para eliminar atraso perceptível (zero-lag).
class OneEuroFilter {
  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _xPrev;
  double? _dxPrev;
  double? _tPrev;

  OneEuroFilter({
    this.minCutoff = 0.8,
    this.beta = 0.01,
    this.dCutoff = 1.0,
  });

  double _alpha(double te, double cutoff) {
    final tau = 1.0 / (2 * pi * cutoff);
    return 1.0 / (1.0 + tau / te);
  }

  double filter(double x, double timestamp) {
    if (_tPrev == null) {
      _xPrev = x;
      _dxPrev = 0.0;
      _tPrev = timestamp;
      return x;
    }

    final te = timestamp - _tPrev!;
    if (te <= 0.0) return _xPrev!;

    // 1. Estima derivada (velocidade angular ou espacial)
    final ad = _alpha(te, dCutoff);
    final dx = (x - _xPrev!) / te;
    final dxHat = ad * dx + (1.0 - ad) * (_dxPrev ?? 0.0);

    // 2. Frequência de corte dinâmica proporcional à velocidade
    final cutoff = minCutoff + beta * dxHat.abs();
    final a = _alpha(te, cutoff);
    final xHat = a * x + (1.0 - a) * _xPrev!;

    _xPrev = xHat;
    _dxPrev = dxHat;
    _tPrev = timestamp;

    return xHat;
  }

  void reset() {
    _xPrev = null;
    _dxPrev = null;
    _tPrev = null;
  }
}

