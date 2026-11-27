/// Funções utilitárias de arredondamento e formatação de números/datas em pt-BR.
library;

/// Arredonda [value] para 1 casa decimal.
double roundToTenths(double value) => (value * 10).roundToDouble() / 10;

/// Formata com 1 casa decimal usando vírgula (ex.: `8,7`).
String formatDecimalPtBr(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');

/// Formata ângulo em graus com até 1 casa decimal (ex.: `"120°"`, `"132,7°"`).
String formatDegreesPtBr(double value) =>
    '${formatDecimalPtBr(value).replaceAll(RegExp(r',0$'), '')}°';

/// Formata o score no padrão `"9 (8,7)"`: inteiro arredondado e detalhe.
String formatScoreText(double value) =>
    '${value.round()} (${formatDecimalPtBr(value)})';

/// Formata data no padrão brasileiro `dd/MM/aaaa`.
String formatDatePtBr(DateTime date) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year}';
}

/// Formata número opcional de forma compacta (`"--"`, `"70"`, `"70.5"`).
String formatCompactNumber(num? value) {
  if (value == null) return '--';
  return value % 1 == 0 ? '${value.toInt()}' : value.toStringAsFixed(1);
}
