# Teste Movimento · avaliação de mobilidade pela câmera

Projeto Integrador III (Sistemas Inteligentes, Fatec Pompeia), em parceria
acadêmica com a Movement. Versão candidata à apresentação: **1.0.1+2003**, tag
`v1.0.1-rc1`. Ela é a base dos testes finais e da defesa.

> Protótipo acadêmico. Não é instrumento clínico. A precisão em relação ao
> goniômetro, o desempenho da versão atual e a usabilidade ainda não foram
> medidos.

## Componentes

| Pasta | Conteúdo |
| --- | --- |
| [`mobile_app/`](mobile_app/README.md) | App Android integrado: perfil, avaliação, histórico e cópia do CSV |
| [`movimento_mobilidade/`](movimento_mobilidade/README.md) | Biblioteca: câmera, pose, ângulos, repetições, resultado, PDF e CSV |

O [protótipo em Python](PROTOTIPO_PYTHON.md) é uma etapa anterior e não integra a
versão candidata.

## Vídeo de demonstração

O link do vídeo (3 min 42 s) está na ficha de desenvolvimento entregue à
disciplina. A demonstração do app vai de cerca de 2:52 a 3:35.

**O vídeo mostra uma versão anterior à candidata.** Nela, a tela inicial se chama
"App host", há avisos de enquadramento em texto e o resultado exibe
"Alcance >24 cm / Ruim". **Esse alcance não foi medido:** eram valores fixos no
código do app de exemplo. A candidata não os envia nem os exibe.

## Instruções de acesso e execução

Requisitos: Flutter 3.24.5 (versão usada na verificação), Android SDK e aparelho
com Android 7.0 (API 24) ou superior, com câmera.

```bash
git clone https://github.com/luisciaramicoli/teste-movimento.git
cd teste-movimento
git checkout v1.0.1-rc1
# copie antes as imagens da biblioteca (veja abaixo)
cd mobile_app
flutter pub get
flutter run --release          # instala no aparelho conectado
flutter build apk --release    # gera build/app/outputs/flutter-apk/app-release.apk
```

**Imagens:** não são distribuídas neste repositório. A equipe precisa copiá-las
para `movimento_mobilidade/assets/`, conforme a
[lista de arquivos](movimento_mobilidade/README.md#imagens). Sem elas, o clone
não reproduz a interface da versão candidata. Para obtê-las, fale com a equipe.

O APK de release é assinado com a chave de depuração do Android: serve para
teste e apresentação, não para publicação em loja.

## Fluxo principal

1. Informar o código do voluntário (`V01`), o peso, a idade (opcional) e a meta
   da jornada (1, 3 ou 6 meses). Nomes são recusados.
2. Ler "Como funciona" e tocar em **Iniciar**.
3. Posicionar o celular fixo, com o corpo inteiro no quadro (protocolo: cerca de
   2,5 m, na altura do quadril).
4. Passo 1/2: de frente, três abduções de ombro, levando os braços acima da
   cabeça.
5. Passo 2/2: com o lado direito para a câmera, três agachamentos.
6. Ver o resultado e gerar o relatório em PDF.
7. Voltar à tela inicial, abrir a avaliação no histórico ou copiar o CSV.

Antes de gravar ou avaliar qualquer pessoa, obtenha o consentimento.

## Funcionalidades reais, simulações e valores calculados

| Tipo | Itens |
| --- | --- |
| Processados a partir da câmera | Pontos do corpo, ângulos, enquadramento, contagem de repetições, média e desvio-padrão. A precisão não foi validada. |
| Funções do software | Histórico local, CSV, PDF, voz, recusa de nomes |
| Calculados por regra, sem validação | Score de 0 a 10, faixas, alerta de assimetria. A **meta** é uma projeção, não um resultado nem uma previsão validada. |
| Digitados pelo usuário | Código, peso, idade e duração da jornada |
| Ilustrativos | Imagens de demonstração dos movimentos e silhueta de posicionamento |
| Dados sintéticos | Testes automatizados da suíte |
| Somente no vídeo (versão anterior) | "Alcance >24 cm / Ruim", valor fixo |

O app de exemplo não tem modo de simulação. A biblioteca ainda contém o protocolo
de câmera de 5 posturas, que o app não abre.

## Verificação da candidata (27/11/2026)

| Verificação | Resultado |
| --- | --- |
| `flutter analyze` no app e na biblioteca | Sem apontamentos |
| `flutter test` na biblioteca (o app não tem testes próprios) | 80 de 80, com dados sintéticos e testes de interface no computador |
| Build do APK de release | Concluído, 210,3 MB |
| Permissões do APK | Sem `INTERNET` e sem `RECORD_AUDIO` |
| Emulador Android 17 (x86_64), modo avião | Abre, mostra as instruções, liga a câmera virtual, pede confirmação para encerrar e recusa um nome; nenhuma `FATAL EXCEPTION` |

No emulador não há pessoa na câmera e o MediaPipe não existe para `x86_64` (é
usado o ML Kit). Por isso, **o fluxo completo da candidata, com contagem,
resultado, histórico, PDF e CSV, ainda não foi demonstrado em aparelho.**

## Dependências

| Dependência | Uso |
| --- | --- |
| MediaPipe Tasks (Pose Landmarker `lite`, modelo incluído) | Motor de pose principal no Android |
| Google ML Kit Pose Detection (cópia em `third_party/`) | Reserva |
| `camera`, `camera_android` | Captura |
| `flutter_tts` | Avisos por voz; depende do mecanismo de voz do aparelho |
| `shared_preferences` | Histórico local |
| `pdf`, `image` | Relatório em PDF |
| `fl_chart` | Gráficos |

Versões em [`movimento_mobilidade/pubspec.yaml`](movimento_mobilidade/pubspec.yaml)
e nos arquivos `pubspec.lock`. O APK ainda declara, entre outras, as permissões
`ACCESS_NETWORK_STATE`, `READ_EXTERNAL_STORAGE`, `FOREGROUND_SERVICE` e
`RECEIVE_BOOT_COMPLETED`; falta revisar se são necessárias.

## Limitações

- Sem ensaios com goniômetro, de repetibilidade, estabilidade, FPS, latência ou
  descarte de quadros.
- Ângulos estimados em imagem 2D: câmera, roupa e iluminação afetam o resultado.
- As referências do score vêm de estudos com amostras e métodos diferentes; idade
  e sexo não mudam a referência padrão.
- Protocolo fixo: dois movimentos, três repetições, agachamento pelo lado direito.
- Os requisitos preveem abdução até 180°, houve decisão de ir até os ombros e o
  app pede os braços acima da cabeça. Falta confirmar com a parceira.
- Score e meta estavam fora do escopo dos requisitos iniciais.
- Os avisos de enquadramento são por voz e destaque visual; o requisito RF06
  precisa ser revisto.
- Antes da correção de 27/11, o agachamento com a câmera traseira registrava o
  lado esquerdo como direito.
- Sem usuários externos nem aceite da parceira registrados.
- A biblioteca não suporta iOS como plataforma validada.

## Trabalho futuro

1. Executar o fluxo completo da candidata em aparelho, com consentimento, e
   gravar a demonstração.
2. Confirmar abdução, score, meta e PDF com a Movement e atualizar os requisitos.
3. Ensaios de desempenho, estabilidade e repetibilidade com goniômetro.
4. Teste de usabilidade a 2,5 m.
5. Revisar permissões e assinar com chave própria.
6. Integração ao Movement Arch (fora do escopo atual).

## Documentação técnica

[API](movimento_mobilidade/doc/api.md) ·
[Medição e score](movimento_mobilidade/doc/medicao.md) ·
[Arquitetura](movimento_mobilidade/doc/arquitetura.md) ·
[Histórico de mudanças](movimento_mobilidade/CHANGELOG.md)
