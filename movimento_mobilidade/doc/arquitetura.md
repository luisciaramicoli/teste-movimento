# Arquitetura

Para quem mantém a biblioteca. Para integrá-la, veja o [README](../README.md).

## Estrutura

```text
movimento_mobilidade/
├── lib/
│   ├── movimento_mobilidade.dart   API pública
│   └── src/
│       ├── flow.dart               estado e rotas do fluxo de avaliação
│       ├── models/                 dados, score e referências
│       ├── services/               câmera, pose, regras, persistência e exportação
│       ├── views/                  telas
│       ├── painters/               desenho sobre a câmera
│       ├── theme/                  tema visual
│       └── utils/                  CSV e formatação pt-BR
├── android/                        plugin Kotlin e modelos .task
├── assets/                         imagens e GIFs (não versionados)
├── third_party/                    cópia local do google_mlkit_pose_detection
├── test/                           testes
└── doc/                            documentação
```

## Os dois fluxos

O pacote tem dois fluxos que compartilham a sessão de câmera e pose
(`PoseCameraSession`) e os modelos de ângulo (`joint_angle.dart`), mas têm regras
e telas próprias. Toda a análise fica nos modelos e serviços; telas, PDF e app
só exibem os valores. A diferença no cálculo é `compensatePerspective`, ligado
apenas no protocolo de câmera.

| | Avaliação | Protocolo de câmera |
| --- | --- | --- |
| Telas | `how_it_works_screen`, `assessment_screen`, `result_screen` | `camera_screen`, `report_screen` |
| Câmera | `pose_camera_session` | `pose_camera_session` |
| Regras | `framing_checker`, `rep_tracker`, `mobility_score` | `protocol_service`, `rep_counter_service` |
| Overlay | `assessment_overlay_painter` | `pose_painter` |
| Exportação | `assessment_csv`, `assessment_pdf` | `session_csv_exporter` |
| Outros | `assessment_history_store`, `voice_service` | `performance_monitor` |

Uma mudança em `PoseCameraSession`, `PoseDetectorService` ou `joint_angle.dart`
afeta os dois.

`motion_trail_service.dart` não é usado por nenhuma tela; hoje só os testes o
importam.

## Fluxo de dados da avaliação

```text
Câmera (YUV420)
  └─► PoseCameraSession
        ├─► NativePoseService ──canal "movimento/pose"──► MediaPipe (Kotlin)
        └─► PoseDetectorService.processImage (ML Kit, reserva)
              │
              ▼
        PoseDetectorService.extractAnglesFromPose   filtros e ângulos
              ▼
        FramingChecker ──► RepTracker ──► MovementResult
              ▼
        AssessmentRecord ──► AssessmentHistoryStore (SharedPreferences)
              ├─► MobilityScore ──► ResultScreen ──► PDF ──canal "movimento/relatorio"
              └─► AssessmentCsv
```

`NativePoseService` converte a saída do MediaPipe para o tipo `Pose` do ML Kit.
Assim, o restante do processamento é o mesmo para os dois motores.

A sessão processa um quadro por vez e descarta os que chegam enquanto está
ocupada. Enquanto o modelo nativo carrega, os quadros também são ignorados.

### Navegação

As rotas do fluxo usam o mesmo nome (`kFlowRoute`), o que permite que
`exitFlow` feche todas de uma vez. Crie telas novas do fluxo com `flowRoute`,
que também aplica o tema. `AvaliacaoFluxo` leva o estado entre as telas e guarda
o resultado devolvido por `iniciarAvaliacao`.

### Câmera frontal e traseira

Com a câmera frontal, as coordenadas são espelhadas
(`ExtractedPoseData.mirrored`). Tudo que depende de esquerda ou direita **na
imagem**, como o lado em perfil e os pedidos de centralização, deve considerar
esse campo. As chaves `_esq` e `_dir` são sempre os lados da pessoa.

## Plugin Android

O plugin é `MovimentoMobilidadePlugin` (`com.testemovimento.mobilidade`).

### Canal `movimento/pose`

| Método | Argumentos | Retorno |
| --- | --- | --- |
| `init` | `model`: `lite` ou `full` | Delegate usado: `GPU` ou `CPU` |
| `detect` | `bytes` (NV21), `width`, `height`, `rotation` | `Float64List` |
| `detectYuv` | `y`, `u`, `v`, `width`, `height`, `yStride`, `uvStride`, `uvPixelStride`, `rotation` | `Float64List` |
| `dispose` | nenhum | `null` |

O retorno tem quatro valores por ponto: `x`, `y`, `z` e visibilidade, com
coordenadas normalizadas na imagem já rotacionada. A lista vem vazia sem pessoa
detectada ou antes de o modelo estar pronto. Os erros usam os códigos `INIT` e
`DETECT`.

- O fluxo de avaliação usa o modelo `lite`. O `full` também é empacotado.
- A GPU é tentada primeiro; emuladores e falhas de GPU usam a CPU.
- A imagem é reduzida à metade da largura e da altura antes da inferência.
- A inferência roda em uma thread separada.
- O modelo continua carregado entre sessões; `NativePoseService.releaseNative()`
  o libera.
- Os arquivos `.task` não podem ser comprimidos (`noCompress 'task'`).

### Canal `movimento/relatorio`

Implementado em `ReportExport.kt`. O método `salvarPdf` recebe `nome` e `bytes`,
abre o seletor de documentos do Android e devolve `true` se salvar ou `false` se
a operação for cancelada. Aceita uma exportação por vez. Erros: `UNAVAILABLE`,
`CREATE_PDF` e `WRITE_PDF`.

## Persistência

`AssessmentHistoryStore` grava a lista completa em JSON na chave
`assessment_history_v1` do `SharedPreferences`.

Ao mudar o formato:

1. Faça `fromJson` aceitar registros antigos, com valores padrão.
2. Não invente medidas que o registro antigo não tem.
3. Mantenha a referência gravada em cada avaliação.
4. Adicione um teste de leitura do formato anterior.

A leitura é feita registro a registro. As gravações trabalham sobre o JSON
original, sem passar pelo modelo, e por isso não apagam o que não pode ser lido:

- um registro ilegível fica fora de `loadAll`, mas continua na lista gravada;
- se o conteúdo não for uma lista JSON, ele é copiado para
  `assessment_history_v1_backup_<microssegundos>` antes de ser substituído.

Não há recuperação automática dessas cópias. Mantenha essa garantia em novas
operações de escrita: não regrave a lista a partir do resultado de `loadAll`.

## Dependências

| Pacote | Uso |
| --- | --- |
| `camera`, `camera_android`, `camera_platform_interface` | Câmera (Camera2) |
| `google_mlkit_pose_detection` (em `third_party/`) | Pose com ML Kit e tipos `Pose` |
| `com.google.mediapipe:tasks-vision:0.10.14` | Pose nativa |
| `shared_preferences` | Histórico |
| `flutter_tts` | Voz |
| `pdf`, `image` | Relatório; `image` torna transparente o fundo dos ícones |
| `fl_chart` | Gráficos do relatório do protocolo de câmera |

## Testes

```bash
flutter analyze
flutter test
```

| Arquivo | Cobertura principal |
| --- | --- |
| `assessment_test.dart` | Enquadramento, repetições, histórico, CSV e privacidade |
| `mobility_score_test.dart` | Nota, faixas, meta, assimetria e referências |
| `report_export_test.dart` | Envio do PDF ao canal nativo |
| `csv_export_test.dart` | CSV do protocolo de câmera, código e desempenho |
| `unit_test.dart` | Ângulos, protocolo de 5 posturas e filtros |
| `history_store_test.dart` | Preservação de histórico ilegível |
| `engine_test.dart` | Identificação do motor de pose |
| `camera_screen_test.dart` | Falha de câmera no protocolo de 5 posturas |
| `overlay_labels_test.dart` | Rótulos de ângulos sem sobreposição |
| `camera_direction_test.dart` | Lado do corpo e direção pedida com as câmeras frontal e traseira |
| `measured_angles_test.dart` | Ângulos medidos e compensação só quando pedida |
| `result_payload_test.dart` | Análise devolvida e JSON de resultado |
| `protocol_result_test.dart` | Valores devolvidos pelo protocolo de posturas |

Os testes são em Dart. Câmera, MediaPipe, voz e a gravação nativa do PDF
precisam ser verificados em um aparelho Android.

## Replay de vídeo

`tool/` passa um vídeo pelo código de análise, sem o aparelho. Requer um Python
com `mediapipe` e `opencv-python`.

```bash
python tool/extract_landmarks.py video.mp4 /caminho/pontos.json
flutter test tool/replay_video_test.dart \
  --dart-define=LANDMARKS=/caminho/pontos.json \
  --dart-define=ABDUCTION=3-17 --dart-define=SQUAT=19-25
```

Use `--mirrored` na extração se o vídeo estiver espelhado, e
`--dart-define=CAMERA=back` para simular a câmera traseira (o padrão é a
frontal).

Os resultados não são idênticos aos do aparelho: a versão do MediaPipe, o
processamento da imagem e os quadros analisados podem diferir, e a trava de
enquadramento da tela não é reproduzida. O replay mostra o que o código calcula;
**não valida** os ângulos, o que exige uma medição independente.

## Relatório PDF

`assessment_pdf.dart` repete o visual da tela de resultado e usa as cores de
`app_theme.dart`. Ele só exibe valores de `record.analysis`. A fonte é a
Helvetica padrão, que não tem Unicode completo: evite símbolos como `≥` ou `—`
no texto do relatório.

## Convenções

- Identificadores da API de entrada são em português (`iniciarAvaliacao`); os
  modelos usam principalmente nomes em inglês (`AssessmentRecord`).
- Textos de tela e documentação são em pt-BR.
- Documente membros públicos com comentários `///`.
- Voluntários são identificados só por código. Não registre nomes ou contatos em
  dados, logs ou mensagens de erro.
- Ao mudar API, limites de medição ou referências, atualize `doc/` e o
  `CHANGELOG.md` no mesmo commit.
