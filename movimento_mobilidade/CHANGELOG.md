# Histórico de mudanças

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado

- Relatório em PDF da avaliação, salvo pelo seletor de documentos do Android.
- Pré-aquecimento da câmera e do modelo de pose em `inicializar()`.
- Documentação em `doc/` e este histórico.

### Alterado

- A referência padrão passa a ser única para todos os perfis, com ombros pela
  média ponderada de Gill et al. (2020) e quadril, joelho e tornozelo por Endo et
  al. (2020). Avaliações salvas mantêm a referência gravada nelas.
- A tela de resultado deixa de exibir o alcance. Os campos continuam em
  `PerfilAvaliado`.

## [1.0.0]

Versão declarada no `pubspec.yaml`.

### Adicionado

- Biblioteca `movimento_mobilidade`, com o fluxo de avaliação por abdução de
  ombro e agachamento.
- Pose com MediaPipe nativo e ML Kit como alternativa.
- Score de mobilidade com faixas, meta e assimetria.
- Histórico local, exportação em CSV e identificação anônima do voluntário.
- Avisos de enquadramento por voz.
