# movimento_mobilidade

Biblioteca Flutter (plugin Android) de avaliação de mobilidade por visão
computacional. O app chama uma função; a biblioteca abre as telas, mede os
ângulos das articulações pela câmera em dois movimentos, calcula um score de
0 a 10 e devolve o resultado como um objeto Dart.

> **Aviso:** as medidas são estimativas feitas a partir de imagem 2D. A flexão e
> a dorsiflexão ainda não foram validadas contra goniômetro. Leia as
> [limitações](#limitações-conhecidas) antes de interpretar os resultados.

## Documentação

| Documento | Conteúdo |
| --- | --- |
| Este README | Instalação, uso básico e limitações |
| [Referência da API](doc/api.md) | Funções, parâmetros, tipos retornados e CSV |
| [Medição e score](doc/medicao.md) | Ângulos, repetições, enquadramento, nota, meta e referências |
| [Arquitetura](doc/arquitetura.md) | Estrutura do código, fluxo de dados, canais nativos e testes |
| [Histórico de mudanças](CHANGELOG.md) | O que mudou em cada versão |

## Recursos

- Fluxo guiado em quatro telas, com orientação e avisos por voz (pt-BR).
- Pose com MediaPipe nativo (GPU ou CPU) e ML Kit como alternativa.
- Contagem automática de 3 repetições por movimento.
- Score de mobilidade, faixa por articulação, meta e alerta de assimetria entre
  os ombros.
- Histórico local por voluntário, relatório em PDF e exportação em CSV.
- Voluntários identificados apenas por código (`V01`, `V02`…).

## Requisitos

| Item | Versão |
| --- | --- |
| Dart | `>=3.0.0 <4.0.0` |
| Flutter | `>=3.10.0` (mínimo declarado no `pubspec.yaml`) |
| Android | `minSdk 24`; o plugin compila com `compileSdk 36` |
| iOS | Não suportado |

## Instalação

No `pubspec.yaml` do app:

```yaml
dependencies:
  movimento_mobilidade:
    path: ../movimento_mobilidade
```

A biblioteca fica em uma subpasta do repositório. Para usá-la como dependência
Git, informe `path` e uma `ref` que a contenha:

```yaml
dependencies:
  movimento_mobilidade:
    git:
      url: https://github.com/luisciaramicoli/teste-movimento.git
      path: movimento_mobilidade
      ref: <branch, tag ou commit>
```

### Imagens

As imagens **não são distribuídas no repositório**. Antes de gerar o app, copie
os arquivos para a biblioteca. Por isso, prefira a dependência por `path`: uma
dependência Git chega sem as imagens.

| Pasta | Arquivos | Usados em |
| --- | --- | --- |
| `assets/images/` | `tripe.png`, `abducao.png`, `agachamento.png` | Instruções e passos |
| `assets/images/` | `boneco_ombro.png`, `icone_ombro_dir.png`, `icone_ombro_esq.png`, `icone_quadril.png`, `icone_joelho.png`, `icone_tornozelo.png` | Resultado |
| `assets/gifs/` | `ortostatica.gif`, `bracos_t.gif`, `elevacao_panturrilha.gif`, `agachamento_iso.gif`, `duplo_biceps.gif` | Protocolo de câmera (5 posturas) |

Os modelos do MediaPipe já vêm na biblioteca.

### Permissões

A biblioteca declara a permissão `CAMERA`; o pedido em tempo de execução é feito
pelo plugin de câmera. As dependências podem acrescentar `INTERNET` e
`RECORD_AUDIO`, que o fluxo de avaliação não usa. Para removê-las do APK de
release, crie `android/app/src/release/AndroidManifest.xml` no app:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
</manifest>
```

Se o seu app usa internet ou microfone, não remova a permissão correspondente.

## Uso

```dart
import 'package:flutter/material.dart';
import 'package:movimento_mobilidade/movimento_mobilidade.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MovimentoMobilidade.inicializar();
  runApp(const MeuApp());
}

/// Chame de qualquer tela que esteja abaixo de um `Navigator`.
Future<void> avaliar(BuildContext context) async {
  final avaliacao = await MovimentoMobilidade.iniciarAvaliacao(
    context,
    voluntario: 'V01',
    perfil: const PerfilAvaliado(idade: 25, pesoKg: 80),
  );
  if (avaliacao == null) return; // saiu antes de concluir

  final score = MobilityScore.fromRecord(avaliacao).score; // null se faltar medida
  final ombro = avaliacao.movement('abducao_ombro')?.averages['ombro_dir'];
  debugPrint('Score: $score | Ombro direito: $ombro°');
}
```

`voluntario` aceita só códigos no formato `V` mais 2 ou 3 dígitos. Qualquer outro
texto, como um nome, lança `ArgumentError`.

O app de exemplo está em [`../mobile_app`](../mobile_app).

## Fluxo da avaliação

| # | Tela | O que acontece |
| --- | --- | --- |
| 1 | Como funciona? | Instruções e botão **Iniciar** |
| 2 | Passo 1 / 2 | Abdução de ombro, de frente |
| 3 | Passo 2 / 2 | Agachamento, lado direito para a câmera |
| 4 | Resultado | Score, barras por articulação, **Refazer** e **Relatório** (PDF) |

Nos passos 2 e 3, a captura começa depois de cerca de 1,5 s com o corpo bem
enquadrado. Após 3 repetições, o passo seguinte começa sozinho. Sair durante a
captura pede confirmação e descarta a avaliação.

As telas usam um tema próprio, sem herdar o tema do app.

## Privacidade e dados

- O histórico fica no aparelho, em `SharedPreferences`, na chave
  `assessment_history_v1`. Ele guarda código do voluntário, ângulos e, se
  informados, idade, peso e duração da Jornada.
- O código da biblioteca não envia dados pela rede.
- O PDF e o CSV saem do app somente por ação do usuário ou do app que integra a
  biblioteca. O PDF inclui idade e peso, quando informados.

## Limitações conhecidas

**Medição**

- Os ângulos vêm de pontos estimados em imagem 2D; posição da câmera, roupa e
  iluminação afetam o resultado.
- As referências padrão do score são médias de estudos com amostras e métodos
  diferentes dos da biblioteca. Veja
  [Referências](doc/medicao.md#referências-padrão).
- Idade e sexo não mudam a referência padrão.
- O protocolo é fixo: 2 movimentos, 3 repetições, agachamento pelo lado direito.

**Plataforma**

- Só Android.
- A biblioteca nativa do MediaPipe 0.10.14 não existe para `x86_64`. Em
  emuladores dessa arquitetura, é usado o ML Kit (o log mostra
  `native=indisponível (ML Kit)`).
- As câmeras virtuais do emulador não mostram uma pessoa. Use a webcam do
  computador na câmera do AVD ou um aparelho real.

**Comportamentos que exigem atenção**

- `AssessmentRecord.engine` não indica o motor usado: as avaliações gravadas
  pelo fluxo recebem sempre o valor padrão, que cita o ML Kit.
- Se o histórico salvo não puder ser lido, `historico()` devolve uma lista vazia,
  e a avaliação seguinte **substitui o histórico anterior**.
- `iniciarCameraProtocolo` troca para **dados simulados** quando não há câmera ou
  ela falha ao abrir. Veja o
  [protocolo de câmera](doc/api.md#protocolo-de-câmera-5-posturas).

## Desenvolvimento

```bash
cd movimento_mobilidade
flutter pub get
flutter analyze
flutter test
```

Veja a [arquitetura](doc/arquitetura.md) antes de alterar o código.
