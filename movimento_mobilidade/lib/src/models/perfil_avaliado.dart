/// Dados do avaliado exibidos no cabeçalho da tela de resultado.
///
/// Todos os campos são opcionais; o que não for informado aparece como "--".
/// A biblioteca não calcula esses valores: eles vêm de quem a chama.
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

  /// Nota atual de 0 a 10.
  final double? nota;

  const PerfilAvaliado({
    this.idade,
    this.pesoKg,
    this.alcanceCm,
    this.alcanceTexto,
    this.alcanceClassificacao,
    this.nota,
  });
}
