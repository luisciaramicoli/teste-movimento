import 'mobility_score.dart';
import 'reference_norms.dart';

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

  /// Sexo, usado com a [idade] (a do início da Jornada) para a referência.
  final Sexo? sexo;

  /// Referência de amplitude própria. Se `null`, a avaliação usa
  /// [MobilityReference.forProfile] com [idade] e [sexo].
  final MobilityReference? referencia;

  /// Duração da Jornada em meses, usada na meta.
  final int jornadaMeses;

  const PerfilAvaliado({
    this.idade,
    this.sexo,
    this.pesoKg,
    this.alcanceCm,
    this.alcanceTexto,
    this.alcanceClassificacao,
    this.referencia,
    this.jornadaMeses = 3,
  }) : assert(jornadaMeses > 0);
}
