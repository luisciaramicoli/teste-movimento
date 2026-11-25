/// Identificação anônima do voluntário (RF10): somente códigos V01, V02...
/// Nomes e contatos são recusados.
class VolunteerCode {
  static const String unknown = 'SEM_CODIGO';
  static final RegExp _pattern = RegExp(r'^V\d{2,3}$');

  static String normalize(String code) => code.trim().toUpperCase();

  static bool isValid(String code) => _pattern.hasMatch(normalize(code));

  /// Para registros antigos: o que não for código nunca é reexibido nem exportado.
  static String sanitize(String code) =>
      isValid(code) ? normalize(code) : unknown;
}
