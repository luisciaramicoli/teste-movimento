import time
import math
import numpy as np

# -------------------------------------------------------------
# 1. SIMULAÇÃO DO ERRO DE PROJEÇÃO 2D vs 3D (FORSHORTENING)
# -------------------------------------------------------------
def simulate_projection_error():
    """
    Simula uma articulação tridimensional (ex: Cotovelo ou Joelho)
    onde o braço superior está fixo e o antebraço se move com ângulo real theta_real.
    Se o plano do membro sofrer uma rotação fora do plano (out-of-plane angle phi),
    calculamos o erro induzido ao projetar no plano 2D (MoveNet) vs cálculo 3D (BlazePose com Z).
    """
    angles_to_test = [45.0, 60.0, 90.0, 120.0, 150.0]
    out_of_plane_rotations = [0.0, 10.0, 20.0, 30.0, 45.0, 60.0]  # graus fora do plano da câmera
    
    results = {}
    
    for phi_deg in out_of_plane_rotations:
        phi = math.radians(phi_deg)
        errors = []
        
        for theta_deg in angles_to_test:
            theta = math.radians(theta_deg)
            
            # Vértice na origem (0, 0, 0)
            vertex = np.array([0.0, 0.0, 0.0])
            
            # Vetor u (ex: braço ao longo do eixo Y negativo)
            u_3d = np.array([0.0, -1.0, 0.0])
            
            # Vetor v (antebraço) com ângulo theta no plano do membro,
            # mas rotacionado fora do plano da câmera por um ângulo phi em torno do eixo Y
            # No plano local: [sin(theta), -cos(theta), 0]
            # Rotacionado em Y por phi:
            vx = math.sin(theta) * math.cos(phi)
            vy = -math.cos(theta)
            vz = math.sin(theta) * math.sin(phi)
            v_3d = np.array([vx, vy, vz])
            
            # 1. Ângulo real 3D (BlazePose com Z):
            cos_3d = np.dot(u_3d, v_3d) / (np.linalg.norm(u_3d) * np.linalg.norm(v_3d))
            theta_3d = math.degrees(math.acos(np.clip(cos_3d, -1.0, 1.0)))
            
            # 2. Ângulo projetado 2D (MoveNet sem Z, apenas X e Y):
            u_2d = u_3d[:2]
            v_2d = v_3d[:2]
            cos_2d = np.dot(u_2d, v_2d) / (np.linalg.norm(u_2d) * np.linalg.norm(v_2d))
            theta_2d = math.degrees(math.acos(np.clip(cos_2d, -1.0, 1.0)))
            
            err = abs(theta_2d - theta_deg)
            errors.append(err)
            
        mae = float(np.mean(errors))
        max_err = float(np.max(errors))
        results[phi_deg] = {"mae": mae, "max_err": max_err}
        
    return results

# -------------------------------------------------------------
# 2. IMPLEMENTAÇÃO DO ONE EURO FILTER PARA KEYPOINTS E ÂNGULOS
# -------------------------------------------------------------
class OneEuroFilter:
    def __init__(self, t0, x0, dx0=0.0, min_cutoff=1.0, beta=0.007, d_cutoff=1.0):
        self.min_cutoff = float(min_cutoff)
        self.beta = float(beta)
        self.d_cutoff = float(d_cutoff)
        self.x_prev = float(x0)
        self.dx_prev = float(dx0)
        self.t_prev = float(t0)

    def _smoothing_factor(self, t_e, cutoff):
        r = 2 * math.pi * cutoff * t_e
        return r / (r + 1)

    def _exponential_smoothing(self, a, x, x_prev):
        return a * x + (1 - a) * x_prev

    def filter(self, t, x):
        t_e = t - self.t_prev
        if t_e <= 0.0:
            return self.x_prev
        
        # Derivada estimada da posição
        a_d = self._smoothing_factor(t_e, self.d_cutoff)
        dx = (x - self.x_prev) / t_e
        dx_hat = self._exponential_smoothing(a_d, dx, self.dx_prev)
        
        # Frequência de corte adaptativa (aumenta com a velocidade do movimento)
        cutoff = self.min_cutoff + self.beta * abs(dx_hat)
        a = self._smoothing_factor(t_e, cutoff)
        x_hat = self._exponential_smoothing(a, x, self.x_prev)
        
        self.x_prev = x_hat
        self.dx_prev = dx_hat
        self.t_prev = t
        return x_hat

# -------------------------------------------------------------
# 3. BENCHMARK DE TREMOR E ESTABILIDADE TEMPORAL (JITTER) EM 100 FRAMES
# -------------------------------------------------------------
def simulate_jitter_and_filters():
    np.random.seed(42)
    n_frames = 100
    fps = 30.0
    dt = 1.0 / fps
    
    # Pose estática: Joelho a 90.0°
    # Quadril (100, 50), Joelho (100, 150), Tornozelo (200, 150)
    # Ruído gaussiano típico de detecção de landmarks no MoveNet/BlazePose (desvio padrão de 1.5 pixels)
    noise_sigma = 1.5
    
    raw_angles = []
    ema_angles = []
    one_euro_angles = []
    
    # EMA setup (semelhante ao usado atualmente no app)
    ema_current = None
    
    # One Euro Filter setup
    oe_filter = None
    
    for i in range(n_frames):
        t = i * dt
        
        # Pontos com ruído de jitter
        hip = np.array([100.0 + np.random.normal(0, noise_sigma), 50.0 + np.random.normal(0, noise_sigma)])
        knee = np.array([100.0 + np.random.normal(0, noise_sigma), 150.0 + np.random.normal(0, noise_sigma)])
        ankle = np.array([200.0 + np.random.normal(0, noise_sigma), 150.0 + np.random.normal(0, noise_sigma)])
        
        # Ângulo no joelho
        u = hip - knee
        v = ankle - knee
        cos_ang = np.dot(u, v) / (np.linalg.norm(u) * np.linalg.norm(v))
        angle_raw = math.degrees(math.acos(np.clip(cos_ang, -1.0, 1.0)))
        raw_angles.append(angle_raw)
        
        # 1. Filtro Exponencial Atual (EMA adaptativo)
        if ema_current is None:
            ema_current = angle_raw
        else:
            diff = abs(angle_raw - ema_current)
            alpha = 0.85 if diff > 25.0 else (0.70 if diff > 8.0 else 0.50)
            ema_current = ema_current + alpha * (angle_raw - ema_current)
        ema_angles.append(ema_current)
        
        # 2. One Euro Filter
        if oe_filter is None:
            oe_filter = OneEuroFilter(t, angle_raw, min_cutoff=0.8, beta=0.01)
            one_euro_angles.append(angle_raw)
        else:
            one_euro_angles.append(oe_filter.filter(t, angle_raw))
            
    raw_angles = np.array(raw_angles)
    ema_angles = np.array(ema_angles)
    one_euro_angles = np.array(one_euro_angles)
    
    return {
        "raw": {
            "std": float(np.std(raw_angles)),
            "peak_to_peak": float(np.max(raw_angles) - np.min(raw_angles)),
            "mean": float(np.mean(raw_angles))
        },
        "ema": {
            "std": float(np.std(ema_angles)),
            "peak_to_peak": float(np.max(ema_angles) - np.min(ema_angles)),
            "mean": float(np.mean(ema_angles))
        },
        "one_euro": {
            "std": float(np.std(one_euro_angles)),
            "peak_to_peak": float(np.max(one_euro_angles) - np.min(one_euro_angles)),
            "mean": float(np.mean(one_euro_angles))
        }
    }

# -------------------------------------------------------------
# 4. COMPARAÇÃO DE MODELO: MOVENET LIGHTNING VS THUNDER
# -------------------------------------------------------------
def benchmark_movenet_models():
    results = {}
    try:
        import tflite_runtime.interpreter as tflite
    except ImportError:
        try:
            import tensorflow.lite as tflite
        except ImportError:
            tflite = None
            
    models = {
        "MoveNet Lightning": {
            "path": "mobile_app/assets/models/movenet_lightning.tflite",
            "input_size": (192, 192),
            "points": 17,
            "has_z": False
        },
        "MoveNet Thunder": {
            "path": "movenet_thunder.tflite",
            "input_size": (256, 256),
            "points": 17,
            "has_z": False
        }
    }
    
    for name, info in models.items():
        import os
        size_mb = os.path.getsize(info["path"]) / (1024 * 1024)
        info["size_mb"] = round(size_mb, 2)
        
        # Se TFLite estiver disponível no python, faz medição sintética de CPU
        if tflite is not None:
            try:
                interpreter = tflite.Interpreter(model_path=info["path"])
                interpreter.allocate_tensors()
                input_details = interpreter.get_input_details()
                output_details = interpreter.get_output_details()
                
                # Aquecimento
                dummy = np.zeros(input_details[0]['shape'], dtype=np.int32 if input_details[0]['dtype'] == np.int32 else np.uint8)
                interpreter.set_tensor(input_details[0]['index'], dummy)
                for _ in range(5):
                    interpreter.invoke()
                    
                # Benchmark 20 iterações
                times = []
                for _ in range(20):
                    t0 = time.perf_counter()
                    interpreter.set_tensor(input_details[0]['index'], dummy)
                    interpreter.invoke()
                    times.append((time.perf_counter() - t0) * 1000)
                info["cpu_latency_ms"] = round(float(np.mean(times)), 2)
            except Exception as e:
                info["cpu_latency_ms"] = f"Erro: {e}"
        results[name] = info
        
    return results

if __name__ == "__main__":
    print("--- 1. ERRO DE PROJEÇÃO 2D vs 3D (FORSHORTENING) ---")
    proj = simulate_projection_error()
    for phi, val in proj.items():
        print(f"Rotação Fora do Plano: {phi:4.1f}° | MAE: {val['mae']:5.2f}° | Erro Máx: {val['max_err']:5.2f}°")
        
    print("\n--- 2. BENCHMARK DE JITTER (TREMOR EM 100 QUADROS ESTÁTICOS) ---")
    jit = simulate_jitter_and_filters()
    for ftype, val in jit.items():
        print(f"Filtro: {ftype:10s} | Desvio Padrão (sigma): {val['std']:4.2f}° | Amplitude Pico-a-Pico: {val['peak_to_peak']:4.2f}°")
        
    print("\n--- 3. COMPARATIVO MOVENET LIGHTNING vs THUNDER ---")
    models = benchmark_movenet_models()
    for name, info in models.items():
        print(f"{name}: Tamanho: {info['size_mb']} MB | Res: {info['input_size']} | Pontos: {info['points']} | Latência CPU: {info.get('cpu_latency_ms', 'N/A')} ms")

