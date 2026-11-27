# App de exemplo — movimento_mobilidade

App Flutter mínimo que usa a biblioteca
[`movimento_mobilidade`](../movimento_mobilidade/README.md). A câmera, a detecção
de pose, as medidas e as telas da avaliação ficam na biblioteca.

A análise principal é feita pelo **MediaPipe Pose Landmarker**. O Google ML Kit é
usado só como reserva, quando o MediaPipe não está disponível.

## O que o app faz

- Pede o código do voluntário (`V01`, `V02`…), o peso, a idade (opcional) e a
  duração da Jornada.
- Abre a avaliação com `iniciarAvaliacao`.
- Mostra o valor devolvido pela chamada: score, articulações e motor de pose.
- Lista o histórico, abre o resultado de uma avaliação e copia o CSV.

O app não calcula nada: toda a análise vem pronta da biblioteca.

Todo o código do app está em `lib/main.dart`.

## Como executar

É preciso um aparelho Android com Android 7.0 ou superior (API 24). A biblioteca
não suporta iOS. Antes, copie as
[imagens da biblioteca](../movimento_mobilidade/README.md#imagens).

```bash
cd mobile_app
flutter pub get
flutter run
```
