# movimento_mobilidade

Biblioteca Flutter de avaliação de mobilidade por visão computacional para
Android e iOS. A biblioteca abre o fluxo guiado, captura a imagem da câmera,
mede os ângulos das articulações em dois movimentos e devolve as medidas e a
análise ao app.

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
- Detecção de pose com MediaPipe nativo e ML Kit no Android, e ML Kit no iOS.
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
| Android | `minSdk 24` e `compileSdk 36` |
| iOS | iOS 15.5 ou superior (requisito do ML Kit), com Xcode e CocoaPods para compilar |

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

### Android

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

### iOS

Configure o deployment target do app para iOS 15.5 ou superior no Xcode e
no `ios/Podfile` (`platform :ios, '15.5'` se usar a versão mínima). Adicione
uma descrição de uso da câmera ao `ios/Runner/Info.plist` do app:

```xml
<key>NSCameraUsageDescription</key>
<string>A câmera é usada para medir os movimentos na avaliação de mobilidade.</string>
```

Valide a captura em um iPhone físico. A exportação do PDF pelo botão
**Relatório** depende de um canal nativo implementado apenas no Android nesta
versão. O CSV é devolvido ao app como texto pela API Dart.

## Uso

### O que o app fornece

Chame `MovimentoMobilidade.inicializar()` uma vez no `main`, depois de
`WidgetsFlutterBinding.ensureInitialized()`. A partir de uma tela do app,
chame `MovimentoMobilidade.iniciarAvaliacao` com os seguintes parâmetros.

| Parâmetro | Obrigatório? | O que passar |
| --- | --- | --- |
| `context` | Sim | Um `BuildContext` abaixo de um `Navigator`, como o de uma tela dentro de um `MaterialApp`. |
| `voluntario` | Não | Código anônimo com `V` e 2 ou 3 dígitos, como `V01` ou `V123`. O padrão é `V00`. A biblioteca remove espaços nas pontas, converte para maiúsculas e lança `ArgumentError` para um código inválido. |
| `perfil` | Não | Um `PerfilAvaliado` com os dados opcionais descritos abaixo. Pode ser omitido por inteiro. |
| `mostrarResultado` | Não | O padrão `true` abre a tela de resultado da biblioteca. Use `false` para voltar ao app após concluir os dois movimentos e apresentar o resultado no próprio app. |

Em `PerfilAvaliado`, `idade` é um `int` em anos e `pesoKg` é um `double` em
quilogramas. Ambos são usados para exibição e ficam disponíveis no registro.
`jornadaMeses` é um `int` positivo, com padrão de 3 meses, usado no cálculo
da meta. `referencia` aceita um `MobilityReference` com as amplitudes de
referência em graus para o score. Ao omitir esse campo, vale a referência padrão.

O AlcanceM ficou fora do fluxo. Deixe `alcanceCm`, `alcanceTexto` e
`alcanceClassificacao` sem preencher. A biblioteca captura as imagens e calcula
os ângulos durante a avaliação.

### O que a biblioteca devolve

`iniciarAvaliacao` devolve um `Future<AssessmentRecord?>` que completa quando
o fluxo fecha. Se nenhuma avaliação tiver sido concluída, o retorno é `null`.
Se o usuário concluir mais de uma avaliação com **Refazer**, o retorno contém a
última concluída. Cada avaliação concluída entra no histórico local.

| Campo ou método | Conteúdo |
| --- | --- |
| `id`, `createdAt`, `volunteerCode`, `testNumber` | Identificador, data e hora, código normalizado e número do teste por voluntário. |
| `idade`, `pesoKg`, `jornadaMeses`, `engine`, `reference` | Dados do perfil registrados, motor de pose usado e referência aplicada. |
| `movements` | Abdução de ombro (`abducao_ombro`) e agachamento de perfil direito (`agachamento_perfil_dir`), com ângulos geométricos em graus por repetição, médias e desvios padrão disponíveis. |
| `analysis` | Score de 0 a 10, amplitudes em graus, faixas, notas e metas por articulação, medidas ausentes e assimetria entre os ombros quando calculável. O score é `null` se faltar alguma das cinco medidas. Use `analysis.joints` para exibir as amplitudes da tela de resultado. |
| `toResultJson()` | `Map<String, dynamic>` com medidas e análise, incluindo as metas para a duração da Jornada. Use `jsonEncode` se precisar de texto JSON. |
| `MovimentoMobilidade.exportarCsv(avaliacao)` | `String` com o CSV da avaliação, com linhas por repetição e articulação e linhas de média. |

### Exemplo de integração

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

  final analise = avaliacao.analysis; // calculada pela biblioteca
  debugPrint('Score: ${analise.score}'); // null se faltar medida
  for (final item in analise.joints) {
    debugPrint('${item.joint.label}: ${item.angle}° (${item.band.label})');
  }

  final json = avaliacao.toResultJson(); // mapa serializável em JSON
  debugPrint('${json['analysis']}');
}
```

O app de exemplo está em [`../mobile_app`](../mobile_app). A
[referência da API](doc/api.md) detalha os campos de retorno, o histórico e o
fluxo independente de cinco posturas (`iniciarCameraProtocolo`).

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
- Dados do histórico que não podem ser lidos não aparecem na lista, mas são
  preservados quando outra avaliação é salva.
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

- No Android, a biblioteca nativa do MediaPipe 0.10.14 não existe para
  `x86_64`. Em emuladores dessa arquitetura, é usado o ML Kit (o log mostra
  `native=indisponível (ML Kit)`).
- As câmeras virtuais do emulador não mostram uma pessoa. Use a webcam do
  computador na câmera do AVD ou um aparelho real.

## Desenvolvimento

```bash
cd movimento_mobilidade
flutter pub get
flutter analyze
flutter test
```

Veja a [arquitetura](doc/arquitetura.md) antes de alterar o código.
