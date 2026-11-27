/// Utilitários compartilhados para serialização CSV e normalização de chaves articulares.
library;

final RegExp _sideSuffixPattern = RegExp(r'_(esq|dir)$');

/// Retorna o lado anatômico legível para exportação (`esquerdo`, `direito` ou `n/a`).
String jointSideLabel(String jointKey) {
  if (jointKey.endsWith('_esq')) return 'esquerdo';
  if (jointKey.endsWith('_dir')) return 'direito';
  return 'n/a';
}

/// Remove o sufixo `_esq` / `_dir` da chave da articulação.
String jointBaseKey(String jointKey) =>
    jointKey.replaceAll(_sideSuffixPattern, '');

/// Escapa uma célula CSV segundo a RFC 4180 quando contém separadores ou aspas.
String escapeCsvCell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
