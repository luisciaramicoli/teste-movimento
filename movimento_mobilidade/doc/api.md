# Referência da API

Tudo o que está aqui é exportado por:

```dart
import 'package:movimento_mobilidade/movimento_mobilidade.dart';
```

Não importe arquivos de `lib/src/`: eles podem mudar sem aviso.

- [`MovimentoMobilidade`](#movimentomobilidade)
- [`PerfilAvaliado`](#perfilavaliado)
- [Dados retornados](#dados-retornados)
- [Score](#score)
- [CSV](#csv)
- [Relatório PDF](#relatório-pdf)
- [Protocolo de câmera (5 posturas)](#protocolo-de-câmera-5-posturas)
- [Utilitários](#utilitários)

## `MovimentoMobilidade`

Ponto de entrada. Todos os membros são estáticos.

| Membro | Retorno | Descrição |
| --- | --- | --- |
| `inicializar()` | `Future<void>` | Seleciona a implementação Camera2 e começa, sem bloquear, a carregar a lista de câmeras e o modelo de pose. Chame uma vez no `main`, antes de abrir telas. |
| `iniciarAvaliacao(context, …)` | `Future<AssessmentRecord?>` | Abre o fluxo de avaliação. |
| `telaResultado(avaliacao, {perfil})` | `Widget` | Tela de resultado de uma avaliação salva, sem **Refazer**. |
| `historico()` | `Future<List<AssessmentRecord>>` | Avaliações deste aparelho, de todos os voluntários, da mais recente para a mais antiga. |
| `exportarCsv(avaliacao)` | `String` | CSV de uma avaliação. |
| `iniciarCameraProtocolo(context, …)` | `Future<ProtocolSessionResult?>` | Abre o [protocolo de 5 posturas](#protocolo-de-câmera-5-posturas). |

### `iniciarAvaliacao`

| Parâmetro | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `context` | `BuildContext` | obrigatório | Precisa estar abaixo de um `Navigator`. |
| `voluntario` | `String` | `'V00'` | Código `V` mais 2 ou 3 dígitos. Espaços nas pontas são removidos e o `v` vira maiúsculo. |
| `mostrarResultado` | `bool` | `true` | Com `false`, o fluxo fecha ao fim do segundo movimento. |
| `perfil` | `PerfilAvaliado?` | `null` | Dados do avaliado, referência própria e duração da Jornada. |

**Erros:** lança `ArgumentError` se `voluntario` não for um código válido. A
mensagem não repete o valor recebido, que pode ser um nome. Falhas de câmera
aparecem na própria tela, sem exceção para quem chamou.

**Quando o `Future` completa:** quando o fluxo é fechado. O valor é a última
avaliação concluída nele, ou `null` se nenhuma foi concluída. **Refazer** inicia
outro teste no mesmo fluxo; se for concluído, ele passa a ser o retorno.

Cada avaliação concluída é salva no histórico antes de o resultado aparecer. O
número do teste é sequencial por voluntário.

### Exibir uma avaliação antiga

```dart
final todas = await MovimentoMobilidade.historico();
if (!context.mounted || todas.isEmpty) return;
await Navigator.of(context).push(MaterialPageRoute<void>(
  builder: (_) => MovimentoMobilidade.telaResultado(todas.first),
));
```

Na tela de resultado, o seletor no topo alterna entre as avaliações do mesmo
voluntário. O ícone de gráfico de cada articulação mostra repetições, desvio
padrão, estudo de referência e evolução no histórico.

Idade, peso e Jornada gravados na avaliação têm prioridade. O `perfil` de
`telaResultado` preenche apenas o que faltar na avaliação inicial. A referência
do score é sempre a gravada na avaliação; `perfil.referencia` não a altera aqui.

Um registro ilegível fica fora de `historico()`, mas continua gravado, e o número
do teste dele não é reutilizado.

A biblioteca não oferece função pública para apagar o histórico. Limpar os dados
do app apaga tudo.

## `PerfilAvaliado`

Todos os campos são opcionais.

| Campo | Tipo | Efeito |
| --- | --- | --- |
| `idade` | `int?` | Exibida no resultado e no PDF; gravada na avaliação. |
| `pesoKg` | `double?` | Exibido no resultado e no PDF; gravado na avaliação. |
| `referencia` | `MobilityReference?` | Substitui a referência padrão do score; gravada na avaliação. |
| `jornadaMeses` | `int` | Duração usada na meta. Padrão `3`; deve ser maior que zero. Gravada na avaliação. |
| `sexo` | `Sexo?` | Aceito, mas hoje não altera telas, score nem referência. |
| `alcanceCm`, `alcanceTexto`, `alcanceClassificacao` | `double?`, `String?`, `String?` | Aceitos, mas hoje não são exibidos nem gravados. |

Exemplo com referência própria (os valores são só ilustrativos):

```dart
const perfil = PerfilAvaliado(
  idade: 40,
  jornadaMeses: 6,
  referencia: MobilityReference(
    ombroDir: 160,
    ombroEsq: 160,
    quadril: 120,
    joelho: 130,
    tornozelo: 30,
    note: 'Referência definida pela minha equipe.',
  ),
);
```

## Dados retornados

```text
AssessmentRecord
├── id             String             identificador único
├── createdAt      DateTime           data e hora local
├── volunteerCode  String             código normalizado
├── testNumber     int                nº do teste deste voluntário
├── idade          int?
├── pesoKg         double?
├── jornadaMeses   int?
├── engine         String             motor(es) de pose usados na medição
├── reference      MobilityReference  referência usada no score
└── movements      List<MovementResult>
    ├── movementId       String       'abducao_ombro' | 'agachamento_perfil_dir'
    ├── spec             MovementSpec?
    ├── reps             List<RepMeasurement>
    │   ├── index        int
    │   ├── angles       Map<String, double>  ângulos no pico
    │   ├── minAngles    Map<String, double>  mínimos do ciclo
    │   ├── maxAngles    Map<String, double>  máximos do ciclo
    │   ├── confidences  Map<String, double>  confiança no pico
    │   └── restAngles   Map<String, double>  posição inicial (mediana)
    ├── averages         Map<String, double>  média, 1 casa decimal
    ├── deviations       Map<String, double>  desvio padrão amostral
    ├── processedFrames  int?
    └── discardedFrames  int?
```

> **Atenção:** `angles` e `averages` guardam o **ângulo geométrico** (joelho
> esticado ≈ 180°), não a amplitude de flexão. Para amplitudes comparáveis com a
> tela, use [`mobilityAngles`](#score).

- `engine` traz, por exemplo, `MediaPipe Pose Landmarker lite (GPU)` ou
  `ML Kit Pose Detection (base)`; se os dois foram usados, os nomes vêm
  unidos por ` + `. Sem a informação, vale `AssessmentRecord.unknownEngine`.
  Isso inclui avaliações de versões anteriores, que gravavam um texto fixo.
- Uma articulação sem leitura válida não aparece no mapa.
- `deviations` exige pelo menos 2 repetições com leitura.
- Avaliações antigas podem ter mapas vazios e campos `null`.
- `record.movement(id)` devolve o movimento ou `null`.
- `record.analysis` devolve a [análise completa](#score).
- `record.toResultJson()` devolve, em tipos JSON, os campos acima, as médias e os
  desvios por movimento e a análise em `analysis`.
- `toJson()` e `AssessmentRecord.fromJson()` serializam só as medidas, que é o
  que o histórico guarda. Na leitura,
  um código inválido vira `SEM_CODIGO`; um registro sem `reference` recebe
  `MobilityReference.illustrative`.

### Movimentos e chaves

| `movementId` | Vista | Chaves |
| --- | --- | --- |
| `abducao_ombro` | Frontal | `ombro_esq`, `ombro_dir`, `quadril_esq`, `quadril_dir`, `joelho_esq`, `joelho_dir`, `tornozelo_esq`, `tornozelo_dir` |
| `agachamento_perfil_dir` | Lado direito | `ombro_dir`, `quadril_dir`, `joelho_dir`, `tornozelo_dir`, `coluna` |

`kProtocolMovements` lista as definições (`MovementSpec`): `id`, `title`,
`viewLabel`, `view` (`CaptureView`), `instruction`, `voiceGuide`, `repetitions`
e `joints`. `jointLabel('ombro_dir')` devolve `Ombro direito`.

### Leitura das repetições

```dart
for (final movimento in avaliacao.movements) {
  debugPrint(movimento.spec?.title);
  for (final media in movimento.averages.entries) {
    final desvio = movimento.deviations[media.key]; // pode ser null
    debugPrint('${jointLabel(media.key)}: ${media.value}° (DP ${desvio ?? '-'})');
  }
}
```

## Score

As regras de cálculo estão em [Medição e score](medicao.md).

```dart
final resultado = avaliacao.analysis; // MobilityScore.fromRecord(avaliacao)

if (resultado.score == null) {
  debugPrint('Falta medir: ${resultado.missing.map((j) => j.label).join(', ')}');
} else {
  debugPrint('Score: ${resultado.score}');
  debugPrint('Meta em 3 meses: ${resultado.goalScore(3)}');
}

for (final item in resultado.joints) {
  debugPrint('${item.joint.label}: ${item.angle}° de ${item.reference}° '
      '(${item.band.label}, nota ${item.grade})');
}

if (resultado.shoulderAsymmetry?.alert ?? false) {
  debugPrint('Assimetria entre os ombros');
}
```

| Símbolo | Descrição |
| --- | --- |
| `MobilityScore.fromRecord(record)` | Score com a referência gravada na avaliação. |
| `MobilityScore.fromAngles(angles, {reference})` | Score a partir de amplitudes em graus. |
| `score` | `double?` de 0 a 10, sem arredondar; `null` se faltar uma das 5 medidas. |
| `goalScore(meses)` | Score simulado ao atingir a meta; `null` nas mesmas condições. |
| `toJson(months: n)` | Análise completa em tipos JSON. |
| `joints`, `joint(j)`, `missing` | Articulações medidas, busca de uma delas e lista das ausentes. |
| `JointScore` | `angle`, `repAngles`, `deviation` (`null` com menos de 2 repetições), `reference`, `percent`, `grade`, `band`, `atReference`, `goalAngle(meses)`. |
| `MobilityJoint` | `ombroDir`, `ombroEsq`, `quadril`, `joelho`, `tornozelo`. |
| `MobilityBand` | `adequada`, `reduzida`, `limitada`. |
| `MobilityReference` | Referência por articulação. Constantes `standard` e `illustrative`. |
| `ShoulderAsymmetry` | `degrees`, `percent`, `alert`. |
| `mobilityAngles(record)` | Amplitude média por `MobilityJoint`. |
| `mobilityJointReps(record, joint)` | Amplitude de cada repetição: `(index, angle)`. |
| `mobilityGrade`, `mobilityBand`, `mobilityGoalAngle` | Funções de cálculo isoladas. |
| `kGoalGainPerMonth`, `kGoalMaxGain` | Constantes da meta. |

`MobilityReference.forProfile` existe por compatibilidade e devolve sempre
`standard`. `shoulderNorm(idade, sexo)` consulta a média de abdução por grupo
(`ShoulderNorm`, ou `null` abaixo de 20 anos), mas **não é usada pelo score**.

## CSV

`exportarCsv` gera uma linha por repetição e articulação e, ao fim de cada
movimento, uma linha `media` por articulação. O separador é a vírgula, o decimal
é o ponto e as linhas terminam em `\n`. A função só devolve o texto: salvar ou
compartilhar fica por conta do app.

| Coluna | Conteúdo |
| --- | --- |
| `data_hora` | ISO 8601 |
| `voluntario` | Código, ou `SEM_CODIGO` |
| `teste` | Número do teste |
| `movimento` | Título do movimento |
| `repeticao` | Número da repetição ou `media` |
| `lado` | `direito`, `esquerdo` ou `n/a` |
| `articulacao` | Chave sem o lado, como `ombro` ou `coluna` |
| `angulo_graus` | Ângulo geométrico, 1 casa decimal |
| `confianca` | 2 casas decimais; vazia se ausente e nas linhas `media` |
| `rom_min`, `rom_max` | Extremos do ciclo; vazios nas linhas `media` |
| `quadros_processados`, `quadros_descartados` | Totais do movimento, repetidos em suas linhas |

Valores ilustrativos:

```csv
data_hora,voluntario,teste,movimento,repeticao,lado,articulacao,angulo_graus,confianca,rom_min,rom_max,quadros_processados,quadros_descartados
2026-11-24T09:12:03.120,V01,1,Abdução de ombro,1,direito,ombro,95.0,0.80,20.0,95.0,150,3
```

## Relatório PDF

O botão **Relatório** gera um PDF A4 da avaliação selecionada e abre o seletor
de destino do Android. O visual segue a tela de resultado: cabeçalho preto, selo
do score, um cartão por articulação com ícone, faixa colorida e barra em relação
à referência.

O arquivo traz código, teste, data, idade e peso (se houver), score e meta. Para
cada articulação: amplitude média, faixa, nota, desvio padrão, referência e meta
em graus. Inclui o alerta de assimetria, quando houver, e a nota da referência.
Sem os [ícones](../README.md#imagens), o PDF é gerado sem eles. Não há função
pública para gerar o PDF por código.

Nome sugerido: `Mobilidade-<código>-teste-<n>.pdf`.

## Protocolo de câmera (5 posturas)

```dart
final sessao = await MovimentoMobilidade.iniciarCameraProtocolo(
  context,
  perfil: const PerfilAvaliado(idade: 25, pesoKg: 80),
);
if (sessao == null) return; // nenhuma postura foi avaliada
debugPrint('Proximidade média: ${sessao.score}%');
for (final restricao in sessao.deficits) {
  debugPrint(restricao.description);
}
```

É um fluxo **independente** da avaliação principal, com posturas estáticas:
posição neutra, braços em T, elevação de panturrilha, agachamento isométrico e
braços em W. Ao final, mostra um relatório com abas de mobilidade, amplitude e
evolução dos ângulos na sessão.

O retorno chega quando o fluxo é fechado e se refere à última sessão finalizada
com pelo menos uma postura avaliada; caso contrário, é `null`.

| Tipo | Campos |
| --- | --- |
| `ProtocolSessionResult` | `score` (0 a 100), `postures`, `deficits`, `engine` |
| `PostureEvaluationResult` | `postureId`, `postureTitle`, `accuracyScorePct`, `capturedAngles`, `targetAngles`, `maxCalfElevationPct`, `maxCalfLeftPct`, `maxCalfRightPct`, `completionTimeSec`, `completedByIdealHold`, `mobilityStatus`, `deficits` |
| `MobilityDeficitItem` | `postureId`, `jointKey`, `jointLabel`, `achievedValue`, `targetValue`, `unit`, `severity`, `description` |
| `AngleTargetRange` | `jointKey`, `label`, `targetAngle`, `tolerance` |

| Aspecto | Avaliação (`iniciarAvaliacao`) | Protocolo de câmera |
| --- | --- | --- |
| Motor de pose | MediaPipe, com ML Kit de reserva | MediaPipe, com ML Kit de reserva |
| Ângulos | Medidos na imagem | Com compensação de perspectiva |
| Retorno | `AssessmentRecord?` | `ProtocolSessionResult?` |
| Histórico | Salva | Não salva |
| Pontuação | 0 a 10, por amplitude | 0 a 100%, por proximidade dos ângulos-alvo |
| CSV | `exportarCsv` | Copiado para a área de transferência, no relatório |
| Perfil | Ver [`PerfilAvaliado`](#perfilavaliado) | Exibe idade e peso no relatório |

> **Compensação de perspectiva:** nas vistas frontal e diagonal, este protocolo
> substitui os ângulos de quadril, joelho e tornozelo por **estimativas** com
> constantes fixas, das quais os ângulos-alvo dependem. Elas não foram
> validadas. Não use esses valores como medidas articulares.

O CSV deste fluxo tem outro esquema: `data_hora, voluntario, movimento, lado,
articulacao, angulo, confianca, rom_min, rom_max`. A coluna `confianca` fica
vazia, e `rom_min` e `rom_max` consideram a sessão inteira.

**Falha de câmera:** sem câmera, sem permissão ou com erro ao abrir ou trocar de
câmera, a tela mostra "Câmera indisponível", com **Tentar novamente** e
**Voltar**. Nada é medido nesse estado.

As telas `CameraScreen` e `ReportScreen` também são exportadas. Para abrir o
protocolo, prefira `iniciarCameraProtocolo`, que aplica o tema. `ReportScreen`
exige tipos que não são exportados (como `JointAngleTracker`) e, na prática, é
de uso interno.

## Utilitários

| Símbolo | Descrição |
| --- | --- |
| `VolunteerCode.isValid(texto)` | Valida um código antes de chamar o fluxo. |
| `VolunteerCode.normalize(texto)` | Remove espaços nas pontas e usa maiúsculas. |
| `VolunteerCode.sanitize(texto)` | Código normalizado, ou `VolunteerCode.unknown` (`SEM_CODIGO`). |
| `stdDev(valores)` | Desvio padrão amostral; `0` com menos de 2 valores. |
| `Sexo` | `masculino`, `feminino`. |
