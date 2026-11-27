import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movimento_mobilidade/src/painters/assessment_overlay_painter.dart';

const _canvas = Size(360, 330);
const _size = Size(34, 17);

void _expectReadable(List<Rect> places, {Size canvas = _canvas}) {
  for (var i = 0; i < places.length; i++) {
    final r = places[i];
    expect(
        r.left >= 0 &&
            r.top >= 0 &&
            r.right <= canvas.width &&
            r.bottom <= canvas.height,
        isTrue,
        reason: 'rótulo $i fora da área: $r');
    for (var j = i + 1; j < places.length; j++) {
      expect(r.overlaps(places[j]), isFalse,
          reason: 'rótulos $i e $j sobrepostos: $r e ${places[j]}');
    }
  }
}

List<Rect> _place(List<Offset> vertices, {Size size = _size}) =>
    AssessmentOverlayPainter.placeLabels(
        vertices, List.filled(vertices.length, size), _canvas);

void main() {
  test('perfil: quadril e coluna no mesmo ponto ficam separados', () {
    const hip = Offset(200, 180);
    _expectReadable(
        _place(const [Offset(190, 90), hip, Offset(160, 220), hip],
            size: const Size(80, 17)));
  });

  test('de frente: lados próximos vão um para cada lado do corpo', () {
    // Como na gravação: quadris a menos de um rótulo de distância.
    final places = _place(const [Offset(170, 180), Offset(196, 180)]);
    _expectReadable(places);
    expect(places[0].right, lessThan(170));
    expect(places[1].left, greaterThan(196));
  });

  test('sem conflito, o rótulo fica à direita do ponto', () {
    final place = _place(const [Offset(100, 100)]).single;
    expect(place.topLeft, const Offset(110, 90));
  });

  test('junto à borda direita, vai para a esquerda sem cobrir o ponto', () {
    final place = _place(const [Offset(350, 100)]).single;
    expect(place.right, lessThan(350));
  });

  test('pontos amontoados nos cantos continuam legíveis e dentro da área', () {
    for (final corner in const [
      Offset(0, 0),
      Offset(360, 330),
      Offset(358, 4),
    ]) {
      _expectReadable(_place(List.filled(5, corner)));
    }
  });

  test('o texto identifica coluna e quadril quando aparecem juntos', () {
    const label = AssessmentOverlayPainter.labelText;
    expect(label('coluna', 5.4), 'Coluna 5°');
    expect(label('quadril_dir', 170.2, nameHip: true), 'Quadril 170°');
    expect(label('quadril_dir', 170.2), '170°');
    expect(label('joelho_dir', 78, nameHip: true), '78°');
  });
}
