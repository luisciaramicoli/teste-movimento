# Rastreamento de Articulações Corporais e Análise de Amplitude de Movimento (ROM)

Este projeto realiza a detecção das principais articulações do corpo humano via câmera ou vídeo em tempo real, calcula instantaneamente os ângulos anatômicos alcançados pelo usuário, monitora a **Amplitude de Movimento (ROM - Range of Motion)** e, ao final da sessão, gera automaticamente um painel gráfico com a evolução temporal e os recordes angulares.

---

## 🎯 Articulações Monitoradas

- **Cotovelos (Esquerdo e Direito)**: Ângulo formado por `Ombro -> Cotovelo -> Punho` (Extensão e Flexão).
- **Ombros (Esquerdo e Direito)**: Ângulo formado por `Quadril -> Ombro -> Cotovelo` (Elevação e Abdução).
- **Joelhos (Esquerdo e Direito)**: Ângulo formado por `Quadril -> Joelho -> Tornozelo` (Extensão e Flexão).
- **Quadril (Esquerdo e Direito)**: Ângulo formado por `Ombro -> Quadril -> Joelho` (Flexão e Extensão).

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
Para iniciar a captura pela webcam padrão (câmera 0):

```bash
python3 main.py
```

Se desejar usar outra webcam conectada (ex: índice 1 ou 2):
```bash
python3 main.py --camera 1
```

### 2. Monitoramento a partir de um Vídeo Gravado
Se você já possui uma gravação de um exercício ou teste de mobilidade:

```bash
python3 main.py --video caminho/do/video.mp4
```

### 3. Opções Avançadas e Exportação de Dados

```bash
# Definir nome do arquivo do gráfico de saída e exportar série temporal para CSV:
python3 main.py --output-graph meu_relatorio.png --export-csv historico_angulos.csv
```

### 4. Demonstração / Teste Rápido (Sem necessidade de câmera)
Para testar a pipeline visual e a geração dos gráficos imediatamente com dados simulados:

```bash
python3 demo_simulation.py
```

---

## 🎮 Controles Durante a Execução

Na janela do vídeo:
- **`Q` ou `ESC`**: Encerra a sessão, calcula as estatísticas e gera automaticamente o relatório gráfico.
- **`R`**: Reseta os recordes de ângulos mínimos e máximos da sessão atual (útil para reiniciar um exercício sem reiniciar o programa).

---

## 📊 Relatório Gráfico Gerado

Ao finalizar a sessão, o arquivo `relatorio_angulos.png` é salvo e exibido na tela contendo:
1. **Evolução Angular - Membros Superiores**: Gráfico de linha mostrando a variação dos ângulos dos cotovelos e ombros em função do tempo.
2. **Evolução Angular - Membros Inferiores**: Gráfico de linha mostrando a variação dos ângulos dos joelhos e quadris.
3. **Amplitude de Movimento Alcançada (ROM)**: Gráfico de barras horizontais comparando o ângulo mínimo vs o ângulo máximo alcançado por cada articulação, destacando o delta angular ($\Delta = \text{Máximo} - \text{Mínimo}$).

---

## 📁 Estrutura dos Arquivos

- [`main.py`](file:///home/luis/teste-movimento/main.py): Ponto de entrada da aplicação.
- [`pose_detector.py`](file:///home/luis/teste-movimento/pose_detector.py): Mapeamento de articulações e cálculos trigonométricos de ângulos com MediaPipe Pose.
- [`tracker.py`](file:///home/luis/teste-movimento/tracker.py): Gerenciamento da série temporal, cálculo de amplitudes (mín, máx, média) e exportação CSV.
- [`visualizer.py`](file:///home/luis/teste-movimento/visualizer.py): Renderização do HUD em tempo real e geração dos gráficos com Matplotlib.
- [`demo_simulation.py`](file:///home/luis/teste-movimento/demo_simulation.py): Simulação biomecânica para testes rápidos.
- [`test_system.py`](file:///home/luis/teste-movimento/test_system.py): Testes unitários para validar a geometria e a renderização.
- [`requirements.txt`](file:///home/luis/teste-movimento/requirements.txt): Lista de dependências.