# Rastreamento de Articulações Corporais, Análise de Ângulos (ROM) e Contador de Repetições

Este projeto realiza a detecção das principais articulações do corpo humano via câmera ou vídeo em tempo real, calcula instantaneamente os ângulos anatômicos alcançados pelo usuário, monitora a **Amplitude de Movimento (ROM - Range of Motion)**, conta repetições de exercícios físicos de forma inteligente com máquina de estados por histerese, calcula a cadência e fases concêntrica/excêntrica e, ao final da sessão, gera automaticamente um painel gráfico completo com a evolução temporal e biomecânica.

Inspirado nos conceitos do repositório [vision-demos](https://github.com/jeremyipark/vision-demos).

---

## 🎯 Articulações Monitoradas

- **Cotovelos (Esquerdo e Direito)**: Ângulo formado por `Ombro -> Cotovelo -> Punho` (Extensão e Flexão).
- **Ombros (Esquerdo e Direito)**: Ângulo formado por `Quadril -> Ombro -> Cotovelo` (Elevação e Abdução).
- **Joelhos (Esquerdo e Direito)**: Ângulo formado por `Quadril -> Joelho -> Tornozelo` (Extensão e Flexão).
- **Quadril (Esquerdo e Direito)**: Ângulo formado por `Ombro -> Quadril -> Joelho` (Flexão e Extensão).

---

## ⚡ Recursos Adicionados (vision-demos)

1. **Contador Inteligente de Repetições com Histerese**:
   - Máquina de estados (`START` $\rightarrow$ `IN_PROGRESS` $\rightarrow$ `PEAK` $\rightarrow$ `RETURNING` $\rightarrow$ `COMPLETED`).
   - Evita falso-positivos causados por oscilações ou tremores de câmera.
   - Modos disponíveis:
     - **Livre (`free`)**: Medição contínua de mobilidade sem contagem de repetições.
     - **Agachamento (`squat`)**: Valida profundidade do joelho ($\le 95^\circ$) e extensão completa.
     - **Rosca Bíceps (`curl`)**: Valida flexão máxima no cotovelo ($\le 55^\circ$) e retorno controlado.
     - **Barra Fixa / Puxada (`chin_up`)**: Inspirado no demo chin-ups do vision-demos.
2. **Cronometragem de Fases do Movimento**:
   - Duração da fase **Concêntrica** (subida/esforço) vs **Excêntrica** (descida/controle).
   - Cálculo dinâmico de **Cadência (RPM - Repetições por minuto)**.
3. **Trilha de Movimento Visual ("Comet Trail")**:
   - Rastro translúcido das articulações em movimento com efeito de desvanecimento suave (*fade-out*), permitindo avaliar a trajetória, estabilidade e simetria do movimento no espaço.
4. **Feedback Postural e Barra de Amplitude**:
   - Barra de progresso visual de 0% a 100% da amplitude exigida.
   - Mensagens dinâmicas na tela (*"Desça mais"*, *"Boa amplitude! ✅"*, *"Excelente repetição! 🔥"*).
5. **Relatório Gráfico Expandido**:
   - Painel adicional no gráfico final exibindo o tempo de cada repetição e o ritmo do treino.

---

## 📦 Instalação

Recomenda-se o uso de um ambiente virtual Python:

```bash
# 1. Criar ambiente virtual
python3 -m venv venv

# 2. Ativar o ambiente virtual
# No Linux/macOS:
source venv/bin/activate
# No Windows:
# venv\Scripts\activate

# 3. Instalar as dependências
pip install -r requirements.txt
```

---

## 🚀 Como Executar

### 1. Monitoramento com Webcam em Tempo Real
```bash
# Modo livre (apenas ângulos e amplitudes)
python3 main.py

# Modo Agachamento com contagem de repetições
python3 main.py --exercise squat

# Modo Rosca Bíceps
python3 main.py --exercise curl

# Modo Barra Fixa / Puxada
python3 main.py --exercise chin_up
```

Se desejar usar outra webcam conectada (ex: índice 1 ou 2):
```bash
python3 main.py --camera 1 --exercise squat
```

### 2. Monitoramento a partir de um Vídeo Gravado
```bash
python3 main.py --video caminho/do/video.mp4 --exercise squat --export-csv historico.csv
```

### 3. Opções de Linha de Comando
```bash
python3 main.py --help
# Opções:
#   --camera INT            Índice da webcam (padrão: 0)
#   --video PATH            Vídeo de entrada gravado
#   --exercise CHOICE       free, squat, curl, chin_up (padrão: free)
#   --no-trail              Desativa a trilha visual de cometa
#   --output-graph PATH     Nome da imagem gerada (padrão: relatorio_angulos.png)
#   --export-csv PATH       Exporta série temporal completa para CSV
#   --confidence FLOAT      Confiança mínima de detecção (padrão: 0.5)
#   --headless              Executa sem abrir janela OpenCV
```

### 4. Demonstração / Teste Rápido (Sem Câmera)
Para testar a pipeline completa com dados sintéticos e gerar o relatório com 5 repetições e cadência:

```bash
python3 demo_simulation.py
```

---

## 🎮 Controles Durante a Execução

Na janela do vídeo:
- **`Q` ou `ESC`**: Encerra a sessão, calcula as estatísticas e gera automaticamente o relatório gráfico.
- **`M`**: Alterna dinamicamente entre os modos de exercício (`Livre` $\rightarrow$ `Agachamento` $\rightarrow$ `Rosca` $\rightarrow$ `Barra Fixa`).
- **`T`**: Liga / Desliga a trilha visual de cometa (*Comet Trail*).
- **`R`**: Reseta os recordes de amplitude e zera o contador de repetições.

---

## 📊 Relatório Gráfico Gerado

Ao finalizar a sessão, o arquivo `relatorio_angulos.png` é salvo em alta definição contendo:
1. **Evolução Angular - Membros Superiores**: Gráficos temporais de cotovelos e ombros.
2. **Evolução Angular - Membros Inferiores**: Gráficos temporais de joelhos e quadris.
3. **Amplitude de Movimento Alcançada (ROM)**: Gráfico de barras horizontais comparando o ângulo mínimo vs máximo de cada articulação.
4. **Análise Biomecânica de Repetições** (quando ativo): Gráfico de barras com a decomposição do tempo concêntrico vs excêntrico por repetição e a cadência média.

---

## 📁 Estrutura dos Arquivos

- [`main.py`](file:///home/luis/teste-movimento/main.py): Ponto de entrada da aplicação.
- [`pose_detector.py`](file:///home/luis/teste-movimento/pose_detector.py): Mapeamento de articulações e cálculos trigonométricos de ângulos com MediaPipe Pose.
- [`tracker.py`](file:///home/luis/teste-movimento/tracker.py): Gerenciamento da série temporal, cálculo de amplitudes (mín, máx, média) e exportação CSV.
- [`rep_counter.py`](file:///home/luis/teste-movimento/rep_counter.py): Contador inteligente de repetições com máquina de estados, tempos concêntrico/excêntrico e cadência.
- [`motion_trail.py`](file:///home/luis/teste-movimento/motion_trail.py): Renderização do efeito visual Comet Trail (rastro translúcido das articulações).
- [`visualizer.py`](file:///home/luis/teste-movimento/visualizer.py): Renderização do HUD em tempo real e geração dos gráficos com Matplotlib.
- [`demo_simulation.py`](file:///home/luis/teste-movimento/demo_simulation.py): Simulação biomecânica para testes rápidos.
- [`test_system.py`](file:///home/luis/teste-movimento/test_system.py): Testes unitários para validar a geometria, máquina de estados e renderização.
- [`requirements.txt`](file:///home/luis/teste-movimento/requirements.txt): Lista de dependências.