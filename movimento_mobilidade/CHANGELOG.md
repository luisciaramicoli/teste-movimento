# Histórico de mudanças

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado

- Relatório em PDF da avaliação, salvo pelo seletor de documentos do Android,
  com o visual da tela de resultado, meta por articulação e alerta de assimetria.
- Pré-aquecimento da câmera e do modelo de pose em `inicializar()`.
- Documentação em `doc/` e este histórico.
- Ferramenta de replay de vídeo em `tool/`, para conferir a análise fora do
  aparelho.
- `AssessmentRecord.analysis` e `toResultJson()`, com a análise completa;
  `JointScore.repAngles` e `deviation`; `MobilityScore.toJson()`.
- `iniciarCameraProtocolo` devolve `ProtocolSessionResult`.

### Alterado

- A referência padrão passa a ser única para todos os perfis, com ombros pela
  média ponderada de Gill et al. (2020) e quadril, joelho e tornozelo por Endo et
  al. (2020). Avaliações salvas mantêm a referência gravada nelas.
- A tela de resultado deixa de exibir o alcance. Os campos continuam em
  `PerfilAvaliado`.
- O protocolo de câmera usa a mesma sessão da avaliação: MediaPipe, com ML Kit
  de reserva. Os ângulos-alvo e a compensação não foram recalibrados para o
  MediaPipe.
- Sem informação do motor, `AssessmentRecord.engine` passa a ser `Não informado`.

### Corrigido

- Na câmera da avaliação, os ângulos da coluna e do quadril eram desenhados no
  mesmo lugar e formavam números impossíveis, como `952°`. Os rótulos não se
  sobrepõem mais, e quadril e coluna aparecem com o nome no perfil.
- Com a câmera traseira, o agachamento de perfil rejeitava o lado direito e
  aceitava o esquerdo, registrando-o como direito. Medidas de agachamento feitas
  antes com essa câmera são do lado esquerdo. Os pedidos para ir à direita ou à
  esquerda também saíam invertidos.
- Na avaliação, os ângulos de quadril, joelho e tornozelo da abdução passam a ser
  os medidos, em vez de estimativas com constantes fixas. Isso altera esses
  valores em relação a avaliações anteriores; o score não os usa.
- Removidos os percentis atribuídos a Endo et al. (2020), que não existem no
  artigo, assim como `SquatStudyRow.percentiles`.
- Um registro ilegível não esconde mais o histórico, e salvar uma avaliação não
  apaga dados que não puderam ser lidos.
- `AssessmentRecord.engine` passa a registrar o motor que processou a medição.
  O texto fixo gravado por versões anteriores, que citava o ML Kit em toda
  avaliação, é lido como `Não informado`.
- Quando a câmera falta ou falha, o protocolo de câmera mostra um erro, com
  opção de tentar novamente.

### Removido

- Dependência `permission_handler`, que não era usada.
- Botão "Modo Espelho" do protocolo de câmera, que invertia só a imagem.
- Modo de simulação do protocolo de câmera, com os dados sintéticos e os
  parâmetros `simulationMode` e `initialSimulationMode`.

## [1.0.0]

Versão declarada no `pubspec.yaml`.

### Adicionado

- Biblioteca `movimento_mobilidade`, com o fluxo de avaliação por abdução de
  ombro e agachamento.
- Pose com MediaPipe nativo e ML Kit como alternativa.
- Score de mobilidade com faixas, meta e assimetria.
- Histórico local, exportação em CSV e identificação anônima do voluntário.
- Avisos de enquadramento por voz.
