# Teste Movimento Mobile (Flutter)

Aplicativo móvel em **Flutter** para celulares (Android e iOS) que realiza a identificação das articulações do corpo humano via câmera em tempo real, mede instantaneamente os ângulos articulares alcançados, monitora a Amplitude de Movimento (ROM), conta repetições de exercícios físicos com máquina de estados por histerese, exibe trilhas de movimento (*Comet Trail*) e gera relatórios com gráficos interativos usando a biblioteca **`fl_chart`**.

Inspirado nos conceitos de visão computacional do [vision-demos](https://github.com/jeremyipark/vision-demos).

---

## 📱 Recursos do Aplicativo

- **Rastreamento On-Device em Tempo Real**: Utiliza **Google ML Kit Pose Detection** (BlazePose), executando a inferência de inteligência artificial de forma 100% local no celular (sem consumo de internet e com alta taxa de quadros por segundo).
- **Cálculo Angular Anatômico**: Mede cotovelos, ombros, quadris e joelhos (membros bilaterais).
- **Contador Inteligente de Repetições**:
  - Máquina de estados por histerese que elimina contagens falsas.
  - Modos disponíveis: **Agachamento** (`Squat`), **Rosca Bíceps** (`Arm Curl`), **Barra Fixa** (`Chin-up`) e **Modo Livre**.
  - Decomposição precisa do tempo de cada repetição: **Fase Concêntrica** (subida) vs **Fase Excêntrica** (descida).
  - Cálculo de **Cadência** em Repetições por Minuto (RPM).
- **Feedback Postural e Barra de Amplitude**: Mensagens em tempo real na tela (*"Desça mais"*, *"Boa amplitude! ✅"*, *"Ritmo perfeito! 🔥"*) e barra de progresso visual de 0% a 100%.
- **Trilha de Movimento ("Comet Trail")**: Efeito visual translúcido desenhando o trajeto dos pulsos e joelhos no espaço.
- **Relatório Interativo com `fl_chart`**:
  - Gráfico de barras de Amplitude de Movimento (Mínimo vs Máximo atingido e delta $\Delta$).
  - Gráfico de linhas com a evolução temporal dos ângulos.
  - Gráfico de decomposição de tempo por repetição.
- **Modo Demonstração Embutido**: Permite testar todo o aplicativo, interface, gráficos e contadores sem câmera (ideal para testes em emuladores).

---

## 🛠️ Pré-requisitos

1. **Flutter SDK** instalado (versão 3.0 ou superior):
   - Verifique com: `flutter doctor`
2. **Android Studio** ou **VS Code** com extensão Flutter instalada.
3. Dispositivo físico com Android 7.0+ (API 24+) ou iOS 12.0+, ou um emulador Android/iOS.

---

## 🚀 Como Executar

### 1. Entrar na pasta do app
```bash
cd mobile_app
```

### 2. Baixar as dependências do Flutter
```bash
flutter pub get
```

### 3. Executar no celular ou emulador
```bash
flutter run
```

---

## ⚙️ Permissões de Câmera

As configurações de permissão já foram pré-configuradas nos arquivos da plataforma:

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" />
<uses-feature android:name="android.hardware.camera.autofocus" />
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Este aplicativo requer acesso à câmera para rastrear as articulações corporais e medir os ângulos dos seus exercícios em tempo real.</string>
```

---

## 📁 Estrutura do Código

```text
mobile_app/
├── lib/
│   ├── main.dart                          # Inicialização do app e tela inicial
│   ├── models/
│   │   ├── joint_angle.dart               # Modelos de geometria, cálculo de ângulos e tracker
│   │   └── exercise_preset.dart           # Configurações de exercícios e modelo RepInfo
│   ├── services/
│   │   ├── pose_detector_service.dart     # Integração Google ML Kit Pose e dados sintéticos
│   │   ├── rep_counter_service.dart       # Máquina de estados para repetições e cadência
│   │   └── motion_trail_service.dart      # Histórico de coordenadas para o Comet Trail
│   ├── painters/
│   │   └── pose_painter.dart              # CustomPainter: esqueleto, badges e trilhas
│   └── views/
│       ├── camera_screen.dart             # Tela da câmera ao vivo, overlay HUD e controles
│       └── report_screen.dart             # Relatório final com abas e gráficos fl_chart
├── test/
│   └── unit_test.dart                     # Testes unitários para cálculo angular e repetições
└── pubspec.yaml                           # Gerenciador de dependências do Flutter
```

