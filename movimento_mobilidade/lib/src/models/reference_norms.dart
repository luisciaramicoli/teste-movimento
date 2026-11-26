/// Dados publicados usados como referência (R) do score de Mobilidade.
library;

enum Sexo {
  masculino('Masculino'),
  feminino('Feminino');

  final String label;
  const Sexo(this.label);
}

/// Média de abdução ativa de um grupo, em graus.
class ShoulderNorm {
  final double right;
  final double left;
  const ShoulderNorm(this.right, this.left);
}

/// Uma faixa etária: vale de [minAge] até a faixa seguinte.
class _AgeBand {
  final int minAge;
  final ShoulderNorm male;
  final ShoulderNorm female;
  const _AgeBand(this.minAge, this.male, this.female);
}

/// Gill et al., 2020, BMC Musculoskeletal Disorders 21:676, Tabela 2
/// (doi:10.1186/s12891-020-03665-9, CC BY 4.0). Abdução ativa em pé, medida com
/// inclinômetro, em pessoas sem histórico de dor ou rigidez no ombro nem de
/// artrite reumatoide. Cada linha: (direito, esquerdo).
const List<_AgeBand> _shoulderBands = [
  _AgeBand(20, ShoulderNorm(158.4, 158.8), ShoulderNorm(156.4, 156.0)),
  _AgeBand(25, ShoulderNorm(154.1, 153.4), ShoulderNorm(157.3, 155.2)),
  _AgeBand(30, ShoulderNorm(157.0, 156.1), ShoulderNorm(156.0, 155.9)),
  _AgeBand(35, ShoulderNorm(155.1, 153.4), ShoulderNorm(158.8, 156.4)),
  _AgeBand(40, ShoulderNorm(154.9, 151.6), ShoulderNorm(154.9, 152.5)),
  _AgeBand(45, ShoulderNorm(154.5, 152.4), ShoulderNorm(151.1, 148.5)),
  _AgeBand(50, ShoulderNorm(158.1, 154.6), ShoulderNorm(151.4, 149.3)),
  _AgeBand(55, ShoulderNorm(148.6, 146.5), ShoulderNorm(149.6, 146.2)),
  _AgeBand(60, ShoulderNorm(145.9, 145.0), ShoulderNorm(138.8, 138.2)),
  _AgeBand(65, ShoulderNorm(137.5, 135.7), ShoulderNorm(142.6, 140.5)),
  _AgeBand(70, ShoulderNorm(137.2, 134.8), ShoulderNorm(132.7, 131.8)),
  _AgeBand(75, ShoulderNorm(136.4, 134.2), ShoulderNorm(133.3, 127.8)),
  _AgeBand(80, ShoulderNorm(130.5, 125.0), ShoulderNorm(120.9, 115.0)),
  _AgeBand(85, ShoulderNorm(118.9, 119.7), ShoulderNorm(119.5, 118.9)),
];

/// Média do grupo de mesmo sexo e idade, ou null abaixo de 20 anos (o estudo
/// não cobre).
ShoulderNorm? shoulderNorm(int age, Sexo sex) {
  _AgeBand? match;
  for (final band in _shoulderBands) {
    if (age >= band.minAge) match = band;
  }
  if (match == null) return null;
  return sex == Sexo.masculino ? match.male : match.female;
}

/// Endo, Miura e Sakamoto, 2020, J Phys Ther Sci 32(6):391–394
/// (doi:10.1589/jpts.32.391): flexão do lado direito no ponto mais profundo,
/// em vídeo 2D. Amostra de só 9 homens de 18,3 anos; por isso o valor é o mesmo
/// para todos os perfis. O estudo mede o quadril em relação à pelve, e o app,
/// em relação ao tronco.
const double kSquatHipFlexionNorm = 124.6;
const double kSquatKneeFlexionNorm = 125.2;
