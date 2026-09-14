#!/usr/bin/env python3
"""
demo_simulation.py
Script de demonstração que simula o movimento de uma pessoa fazendo exercícios (ex: flexão de braço e agachamento),
atualizando o rastreador de amplitude angular e gerando o gráfico final automaticamente.
Útil para testar a pipeline visual e a geração de relatórios mesmo sem webcam conectada.
"""

import time
import numpy as np

from tracker import AngleTracker
from visualizer import generate_rom_report_graph
from pose_detector import JOINT_DEFINITIONS


def run_simulation(duration_sec: float = 10.0, output_image: str = "relatorio_angulos.png"):
    print(f"Iniciando simulação biomecânica por {duration_sec:.1f} segundos...")

    tracker = AngleTracker({k: v[3] for k, v in JOINT_DEFINITIONS.items()})

    fps = 30
    total_frames = int(duration_sec * fps)

    for frame_idx in range(total_frames):
        t = frame_idx / fps

        # Simula movimentos fisiológicos realistas:
        # 1. Cotovelo Esquerdo / Direito (flexão de 45° até 165°)
        cotovelo_e = 105.0 + 60.0 * np.sin(2 * np.pi * 0.4 * t)
        cotovelo_d = 105.0 + 55.0 * np.cos(2 * np.pi * 0.4 * t)

        # 2. Ombro Esquerdo / Direito (elevação/abdução de 30° até 150°)
        ombro_e = 90.0 + 60.0 * np.sin(2 * np.pi * 0.25 * t)
        ombro_d = 90.0 + 55.0 * np.cos(2 * np.pi * 0.25 * t)

        # 3. Joelho Esquerdo / Direito (agachamento: flexão de 60° a 170°)
        joelho_e = 115.0 + 55.0 * np.sin(2 * np.pi * 0.3 * t)
        joelho_d = 115.0 + 50.0 * np.cos(2 * np.pi * 0.3 * t)

        # 4. Quadril Esquerdo / Direito (90° a 165°)
        quadril_e = 130.0 + 35.0 * np.sin(2 * np.pi * 0.3 * t)
        quadril_d = 130.0 + 30.0 * np.cos(2 * np.pi * 0.3 * t)

        mock_frame_data = {
            "cotovelo_esq": {"angle": round(float(cotovelo_e), 1), "valid": True},
            "cotovelo_dir": {"angle": round(float(cotovelo_d), 1), "valid": True},
            "ombro_esq": {"angle": round(float(ombro_e), 1), "valid": True},
            "ombro_dir": {"angle": round(float(ombro_d), 1), "valid": True},
            "joelho_esq": {"angle": round(float(joelho_e), 1), "valid": True},
            "joelho_dir": {"angle": round(float(joelho_d), 1), "valid": True},
            "quadril_esq": {"angle": round(float(quadril_e), 1), "valid": True},
            "quadril_dir": {"angle": round(float(quadril_d), 1), "valid": True},
        }

        tracker.update(mock_frame_data, timestamp=t)

    print("Simulação concluída! Gerando relatório gráfico final...")
    saved_path = generate_rom_report_graph(
        tracker, output_image_path=output_image, show_plot=False
    )
    print(f"Gráfico salvo com sucesso em: {saved_path}")

    # Exibe resumo no terminal
    print("\n" + "=" * 65)
    print("      RESUMO ESTATÍSTICO DA SIMULAÇÃO (ROM)")
    print("=" * 65)
    print(f"{'Articulação':<22} | {'Mínimo':>8} | {'Máximo':>8} | {'ROM (Δ)':>8} | {'Média':>8}")
    print("-" * 65)
    for key, data in tracker.get_all_summaries().items():
        print(f"{data['label']:<22} | {data['min']:>7.1f}° | {data['max']:>7.1f}° | {data['rom']:>7.1f}° | {data['avg']:>7.1f}°")
    print("=" * 65 + "\n")


if __name__ == "__main__":
    run_simulation()

