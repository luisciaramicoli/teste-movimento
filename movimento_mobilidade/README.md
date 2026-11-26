# movimento_mobilidade

Biblioteca Flutter (plugin Android) de avaliação de mobilidade por visão
computacional. O app que a usa chama **uma função**; a biblioteca abre as telas,
usa a câmera para medir os ângulos das articulações durante dois movimentos e
**devolve os ângulos medidos** como um objeto Dart.

- [Como funciona](#como-funciona)
- [Instalação](#instalação)
- [Como chamar](#como-chamar)
- [Dados retornados](#dados-retornados)
- [Outras funções](#outras-funções)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Limitações conhecidas](#limitações-conhecidas)

## Como funciona

`iniciarAvaliacao` abre um fluxo de telas por cima do app que a chamou:

| # | Tela | O que acontece |
| --- | --- | --- |
| 1 | **Como funciona?** | Instruções (tripé, roupa, posição). Botão **Iniciar**. |
| 2 | **Passo 1 / 2** — abdução de ombro | Foto de demonstração em cima e câmera ao vivo embaixo. |
| 3 | **Passo 2 / 2** — agachamento (perfil direito) | Mesmo layout, com a foto do agachamento. |
| 4 | **Resultado** | Uma barra de ângulo por articulação, botões **Refazer** e **Relatório**. |

Em cada passo (telas 2 e 3), tudo é automático:

1. **Enquadramento:** um detector de pose (MediaPipe nativo, com ML Kit como
   alternativa) acompanha o corpo. A biblioteca avisa, por texto e por voz, se a
   pessoa não foi detectada, está longe, perto, cortada ou descentralizada.
2. **Trava:** depois de ~1,5 s com o corpo bem enquadrado, a captura começa
   ("GRAVANDO").
3. **Repetições:** são contadas por histerese sobre um ângulo de referência —
   abdução: média dos dois ombros (conta ao passar de 70° e voltar abaixo de 45°);
   agachamento: joelho direito (conta ao ficar abaixo de 130° e voltar acima de 155°).
   Em cada repetição é guardado o ângulo de todas as articulações avaliadas **no
   instante do pico**.
4. **Fim do passo:** com 3 repetições o passo termina e o próximo começa sozinho.
   Ao concluir os dois, a avaliação é salva no histórico local do aparelho e
   devolvida a quem chamou.

A seta de voltar fecha todo o
fluxo; durante os passos 1 e 2 ela pede confirmação antes, porque os dados da
avaliação em andamento ainda não foram salvos.

As telas usam um tema próprio (header preto, botões em pílula, cards brancos) e
**não herdam o tema do app** que as chama.

## Instalação

No `pubspec.yaml` do app que vai usar a biblioteca:

```yaml
dependencies:
  movimento_mobilidade:
    path: ../movimento_mobilidade     # ou, em repositório git:
    # git:
    #   url: https://exemplo.com/movimento_mobilidade.git
```

Requisitos:

- Flutter com Dart `>=3.0.0 <4.0.0`.
- Android com `minSdk 24`. A biblioteca ainda não suporta iOS.
- A permissão `CAMERA` já é declarada pela biblioteca (manifest do plugin). O
  pedido em tempo de execução é feito pelo plugin de câmera na primeira abertura.
- Os modelos do MediaPipe (`pose_landmarker_lite.task` e `_full.task`) e as imagens
  vão dentro da biblioteca; o app não precisa copiar nenhum arquivo.

## Como chamar

Inicialize uma vez no `main` e depois chame a avaliação de qualquer lugar que
tenha um `BuildContext`:

```dart
import 'package:flutter/material.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MovimentoMobilidade.inicializar();   // configura a câmera (Camera2)
  runApp(const MeuApp());
}

Future<void> avaliar(BuildContext context) async {
  final AssessmentRecord? avaliacao = await MovimentoMobilidade.iniciarAvaliacao(
    context,
    voluntario: 'V01',        // identifica quem está sendo avaliado
    mostrarResultado: true,     // false = volta direto ao app, sem a tela 4
  );

  if (avaliacao == null) {
    // O usuário saiu antes de concluir os dois movimentos.
    return;
  }

  final ombroDir = avaliacao.movement('abducao_ombro')?.averages['ombro_dir'];
  print('Ombro direito: $ombroDir°');
}
```

### Parâmetros de `iniciarAvaliacao`

| Parâmetro | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `context` | `BuildContext` | — | Usado para empilhar as telas no `Navigator` do app. |
| `voluntario` | `String` | `'V00'` | Código anônimo do voluntário (V01, V02…); nomes lançam `ArgumentError`. Vai para o histórico e para o CSV. O número do teste é sequencial por voluntário (1, 2, 3…). |
| `mostrarResultado` | `bool` | `true` | Se `false`, a tela de resultado não aparece e o fluxo fecha logo após o segundo movimento. |
| `perfil` | `PerfilAvaliado?` | `null` | Idade, peso e alcance do cabeçalho, referência do score e duração da Jornada. Campos exibidos não informados aparecem como `--`. |

`PerfilAvaliado` tem os campos opcionais `idade` (`int`), `pesoKg` (`double`),
`alcanceCm` (`double`), `alcanceTexto` (`String`, exibido no lugar de
`alcanceCm`, ex.: `">24"`) e `alcanceClassificacao` (`String`, ex.: `"Ruim"`),
além de `sexo` (`Sexo?`), `referencia` (`MobilityReference?`) e `jornadaMeses`
(`int`, padrão 3).
A nota não é informada pelo app: é calculada pela biblioteca.

```dart
await MovimentoMobilidade.iniciarAvaliacao(
  context,
  voluntario: 'V01',
  perfil: const PerfilAvaliado(
      idade: 25, pesoKg: 80, alcanceCm: 24, alcanceClassificacao: 'Ruim'),
);
```

### Quando o `Future` completa

O `Future` só completa quando **todo o fluxo é fechado**: o usuário sai pela
seta de voltar, ou termina a avaliação e fecha a tela de resultado (ou, com
`mostrarResultado: false`, assim que o segundo movimento termina). O valor é:

- a **última avaliação concluída** no fluxo, ou
- `null` se nenhuma foi concluída (o usuário saiu antes do fim).

Se o usuário tocar em **Refazer**, uma nova avaliação (teste nº + 1) começa dentro
do mesmo fluxo, e o retorno será a mais recente.

## Dados retornados

O retorno é um `AssessmentRecord`. Todos os tipos abaixo são exportados por
`package:movimento_mobilidade/movimento_mobilidade.dart`.

```text
AssessmentRecord
├── id             String      identificador único
├── createdAt      DateTime    data e hora da avaliação
├── volunteerCode  String      o `voluntario` informado
├── testNumber     int         nº do teste deste voluntário (1, 2, 3…)
├── engine         String      motor de pose usado (informativo)
└── movements      List<MovementResult>   um por movimento, na ordem do protocolo
    ├── movementId   String    'abducao_ombro' | 'agachamento_perfil_dir'
    ├── spec         MovementSpec?   título, vista da câmera, articulações
    ├── reps         List<RepMeasurement>   uma por repetição concluída
    │   ├── index    int                       1, 2, 3
    │   └── angles   Map<String, double>       ângulo (°) por articulação no pico
    ├── averages     Map<String, double>   média por articulação (1 casa decimal)
    └── deviations   Map<String, double>   desvio padrão amostral (precisa de 2+ reps)
```

Métodos úteis: `record.movement('abducao_ombro')` devolve o `MovementResult`
daquele movimento (ou `null`); `record.toJson()` / `AssessmentRecord.fromJson(...)`
serializam a avaliação.

### Movimentos e articulações

| `movementId` | Movimento | Vista | Chaves de articulação medidas |
| --- | --- | --- | --- |
| `abducao_ombro` | Abdução de ombro | Frontal | `ombro_esq`, `ombro_dir`, `quadril_esq`, `quadril_dir`, `joelho_esq`, `joelho_dir`, `tornozelo_esq`, `tornozelo_dir` |
| `agachamento_perfil_dir` | Agachamento, perfil direito | Lado direito para a câmera | `ombro_dir`, `quadril_dir`, `joelho_dir`, `tornozelo_dir`, `coluna` |

`jointLabel('ombro_dir')` devolve o nome legível ("Ombro direito"). Os ângulos
são em graus e calculados a partir dos pontos do corpo detectados. Exemplos:
ombro = quadril–ombro–cotovelo; joelho = quadril–joelho–tornozelo (180° = perna
esticada); quadril = ombro–quadril–joelho; tornozelo = joelho–tornozelo–ponta do
pé. A **coluna** é a inclinação do tronco em relação à vertical (0° = tronco
ereto), medida entre o meio dos ombros e o meio dos quadris.

As médias e desvios consideram só as repetições com leitura válida da
articulação; uma chave pode faltar em `averages` se nenhuma leitura foi válida.

### Exemplo de leitura

```dart
for (final mov in avaliacao.movements) {
  print(mov.spec?.title);                      // "Abdução de ombro"
  for (final e in mov.averages.entries) {
    final dp = mov.deviations[e.key];          // pode ser null com 1 repetição
    print('  ${jointLabel(e.key)}: ${e.value}° (DP ${dp ?? '-'})');
  }
  for (final rep in mov.reps) {
    print('  repetição ${rep.index}: ${rep.angles}');
  }
}
```

### Exemplo de retorno (resumido)

```text
AssessmentRecord(volunteerCode: V01, testNumber: 1)
  abducao_ombro
    reps:     R1 {ombro_dir: 98, ombro_esq: 101, joelho_dir: 176, ...}
              R2 {...}  R3 {...}
    averages: {ombro_dir: 99.3, ombro_esq: 100.7, joelho_dir: 175.8, ...}
  agachamento_perfil_dir
    reps:     R1 {quadril_dir: 78, joelho_dir: 96, tornozelo_dir: 72, ombro_dir: 80}
    averages: {quadril_dir: 79.0, joelho_dir: 97.3, ...}
```

### CSV

`MovimentoMobilidade.exportarCsv(avaliacao)` devolve um texto CSV com uma linha por
repetição e articulação, mais uma linha `media` por articulação:

```csv
data_hora,voluntario,teste,movimento,repeticao,lado,articulacao,angulo_graus,confianca,rom_min,rom_max,quadros_processados,quadros_descartados
2026-11-24T09:12:03.120,V01,1,Abdução de ombro,1,direito,ombro,95.0,0.80,20.0,95.0,150,3
```

Linhas `media` não têm confiança nem ROM. Os valores do exemplo são ilustrativos.

## Outras funções

| Função | Descrição |
| --- | --- |
| `MovimentoMobilidade.inicializar()` | Configura a câmera. Chamar uma vez, no `main`, antes de `iniciarAvaliacao`. |
| `MovimentoMobilidade.iniciarAvaliacao(context, ...)` | Fluxo completo. Retorna `Future<AssessmentRecord?>`. |
| `MovimentoMobilidade.telaResultado(record, {perfil})` | `Widget` da tela de resultado de uma avaliação existente (somente leitura, sem "Refazer"). Use com `Navigator.push`. |
| `MovimentoMobilidade.historico()` | `Future<List<AssessmentRecord>>` com as avaliações salvas no aparelho, da mais recente para a mais antiga. |
| `MovimentoMobilidade.exportarCsv(record)` | `String` CSV de uma avaliação. |

O histórico é guardado em `SharedPreferences` do app host (chave
`assessment_history_v1`); limpar os dados do app apaga o histórico.

```dart
// Mostrar uma avaliação antiga
final todas = await MovimentoMobilidade.historico();
if (todas.isNotEmpty) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovimentoMobilidade.telaResultado(todas.first)));
}
```

### Sobre a tela de resultado

No topo, o seletor **Última avaliação** lista as avaliações salvas do mesmo
voluntário e troca a que está na tela (aparece só quando há mais de uma). Logo
abaixo, dois cartões: score atual (inteiro), idade e peso, e o alcance com sua
classificação. Depois, o resumo `Score 9 (8,7)` e a meta, e uma barra para cada
uma das 5 articulações, com faixa, nota e meta em graus. A barra cheia equivale
à referência.

### Score de Mobilidade

`MobilityScore.fromRecord(avaliacao)` calcula:

| Linha | Amplitude medida |
| --- | --- |
| Ombro direito / esquerdo | abdução (frontal) |
| Quadril, Joelho | flexão no agachamento: `180° − ângulo interno` |
| Tornozelo | dorsiflexão no agachamento: ângulo em pé − ângulo no ponto mais baixo |

- **Faixa:** Adequada a partir de 90% da referência (R); Reduzida de 75% a 90%;
  Limitada abaixo de 75%.
- **Nota:** 10 em R ou acima; linear de 8 a 10 (90–100%), 4 a 8 (75–90%) e 0 a 4
  (50–75%); 0 abaixo de 50%.
- **Score:** média simples das 5 notas. Se faltar alguma medida, não há score.
- **Meta:** +10% de R a cada 3 meses para quem está abaixo de R, sem passar de R,
  com teto de +15% por Jornada (a confirmar).
- **Assimetria:** alerta nos ombros com diferença de pelo menos 15% (sobre o lado
  maior) e 10°. Não altera o score.

**As referências padrão são provisórias** (`MobilityReference.forProfile`):

| Articulação | Referência |
| --- | --- |
| Ombros | Média de abdução ativa por sexo, faixa etária e lado ([Gill et al., 2020](https://doi.org/10.1186/s12891-020-03665-9), CC BY 4.0). Sem sexo ou idade, ou abaixo de 20 anos: 150° (ilustrativo). |
| Quadril, joelho | 124,6° e 125,2°: médias do lado direito no ponto mais profundo ([Endo et al., 2020](https://doi.org/10.1589/jpts.32.391)), para todos os perfis. |
| Tornozelo | 35° (ilustrativo). |

Limitações: R é uma **média**, não a amplitude completa. O estudo de
agachamento tem só 9 homens de 18,3 anos, feito com braços elevados, e mede o
quadril em relação à pelve; o app mede em relação ao tronco. O estudo do ombro
usou inclinômetro. Para usar outros valores, passe `PerfilAvaliado.referencia`.
A usada fica gravada em cada avaliação. Avaliações antigas não têm o ângulo do
tornozelo em pé e ficam sem score. A flexão e a dorsiflexão ainda não foram
validadas contra goniômetro.

## Estrutura do projeto

```text
movimento_mobilidade/
├── lib/
│   ├── movimento_mobilidade.dart   API pública (MovimentoMobilidade + tipos exportados)
│   └── src/
│       ├── flow.dart               fluxo de telas e rotas compartilhadas
│       ├── views/                  telas (como funciona, passos, resultado)
│       ├── models/                 AssessmentRecord, MovementResult, ângulos
│       ├── services/               câmera, pose, contagem de repetições, CSV, histórico
│       ├── painters/               esqueleto e moldura sobre a câmera
│       └── theme/                  tema visual da biblioteca
├── android/                        plugin Kotlin (MediaPipe Pose Landmarker) e modelos .task
├── assets/images/                  fotos de demonstração e tripé
├── third_party/google_mlkit_pose_detection   cópia local do plugin ML Kit
└── test/                           testes unitários
```

Rodar os testes: `flutter test` dentro de `movimento_mobilidade/`. O app em
`mobile_app/` é um exemplo mínimo de uso da biblioteca.

## Limitações conhecidas

- **Só Android.** Não há implementação para iOS.
- **MediaPipe e emulador `x86_64`:** a lib nativa do MediaPipe 0.10.14 não existe
  para `x86_64`. Nesse emulador a pose cai automaticamente para o ML Kit (o log mostra
  `native=indisponível (ML Kit)`). Para o caminho principal, use um aparelho real
  ou um emulador arm64.
- **Câmera do emulador:** as câmeras padrão do emulador não mostram uma pessoa, então
  a tela fica em "Pessoa não detectada". Configure a webcam do computador na câmera
  do AVD ou teste em um aparelho.
- **Protocolo fixo:** são dois movimentos (abdução de ombro e agachamento, lado
  direito), 3 repetições cada. Ainda não é configurável pela API.
- **Voluntário padrão:** sem informar `voluntario`, os testes são gravados como `V00`.
- **Privacidade:** para o APK final não pedir internet nem microfone, o app host deve
  remover essas permissões no manifest de release (veja
  `mobile_app/android/app/src/release/AndroidManifest.xml`).
- **Imagens:** as fotos e os ícones não são distribuídos neste repositório. Coloque os
  arquivos em `assets/images/`; sem eles, as telas ficam sem as imagens.
