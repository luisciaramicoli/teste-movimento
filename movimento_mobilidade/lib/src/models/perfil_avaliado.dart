import 'mobility_score.dart';

/// Dados do avaliado: cabeçalho da tela de resultado, referência e meta.
///
/// Os campos exibidos são opcionais; o que não for informado aparece como "--".
/// A biblioteca não calcula esses dados (a nota vem de [MobilityScore]).
class PerfilAvaliado {
  /// Idade em anos.
  final int? idade;

  /// Peso em quilos.
  final double? pesoKg;

  /// Alcance em centímetros.
  final double? alcanceCm;

  /// Texto do alcance exibido no lugar de [alcanceCm] (ex.: `">24"`).
  final String? alcanceTexto;

  /// Classificação do alcance exibida na etiqueta (ex.: "Ruim", "Bom").
  final String? alcanceClassificacao;

  /// Referência de amplitude do perfil (sexo e idade). Se `null`, a avaliação
  /// usa [MobilityReference.illustrative].
  final MobilityReference? referencia;

  /// Duração da Jornada em meses, usada na meta.
  final int jornadaMeses;

  const PerfilAvaliado({
    this.idade,
    this.pesoKg,
    this.alcanceCm,
    this.alcanceTexto,
    this.alcanceClassificacao,
    this.referencia,
    this.jornadaMeses = 3,
  }) : assert(jornadaMeses > 0);
}
