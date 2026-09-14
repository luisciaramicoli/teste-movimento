#!/usr/bin/env python3
"""
demo_simulation.py
Script de demonstração que simula o movimento de uma pessoa fazendo agachamentos,
atualizando o rastreador de amplitude, o contador inteligente de repetições com tempos
concêntrico/excêntrico e gerando o gráfico final completo automaticamente.
"""

import numpy as np

from tracker import AngleTracker
from rep_counter import ExerciseRepCounter
from visualizer import generate_rom_report_graph
from pose_detector import JOINT_DEFINITIONS


def run_simulation(duration_sec: float = 12.0, output_image: str = "relatorio_angulos.png"):
    print(f"Iniciando simulação biomecânica com contagem de repetições por {duration_sec:.1f}s...")

    tracker = AngleTracker({k: v[3] for k, v in JOINT_DEFINITIONS.items()})
    rep_counter = ExerciseRepCounter(exercise_name="squat")

    fps = 30
    total_frames = int(duration_sec * fps)

    for frame_idx in range(total_frames):
        t = frame_idx / fps

        # Simula movimentos fisiológicos realistas:
        # Agachamentos com ciclo de aprox. 2.5s cada repetição
        # Joelhos vão de ~165° (em pé) até ~85° (pico de agachamento)
        squat_cycle = np.sin(2 * np.pi * 0.4 * t)
        joelho_val = 125.0 - 45.0 * squat_cycle
        quadril_val = 135.0 - 40.0 * squat_cycle

        # Cotovelos e ombros em movimento natural
        cotovelo_e = 110.0 + 40.0 * np.sin(2 * np.pi * 0.2 * t)
        cotovelo_d = 110.0 + 35.0 * np.cos(2 * np.pi * 0.2 * t)
        ombro_e = 85.0 + 35.0 * np.sin(2 * np.pi * 0.2 * t)
        ombro_d = 85.0 + 30.0 * np.cos(2 * np.pi * 0.2 * t)

        mock_frame_data = {
            "cotovelo_esq": {"angle": round(float(cotovelo_e), 1), "valid": True},
            "cotovelo_dir": {"angle": round(float(cotovelo_d), 1), "valid": True},
            "ombro_esq": {"angle": round(float(ombro_e), 1), "valid": True},
            "ombro_dir": {"angle": round(float(ombro_d), 1), "valid": True},
            "joelho_esq": {"angle": round(float(joelho_val), 1), "valid": True},
            "joelho_dir": {"angle": round(float(joelho_val + 2.0), 1), "valid": True},
            "quadril_esq": {"angle": round(float(quadril_val), 1), "valid": True},
            "quadril_dir": {"angle": round(float(quadril_val + 2.0), 1), "valid": True},
        }

        tracker.update(mock_frame_data, timestamp=t)
        completed_rep = rep_counter.update(mock_frame_data, timestamp=t)
        if completed_rep:
            print(f" -> [REP {completed_rep.rep_number}] Duração: {completed_rep.total_duration:.2f}s (Concêntrico: {completed_rep.concentric_duration:.2f}s | Excêntrico: {completed_rep.eccentric_duration:.2f}s) | {completed_rep.feedback}")

    print("\nSimulação concluída! Gerando relatório gráfico final com análise de repetições...")
    saved_path = generate_rom_report_graph(
        tracker,
        output_image_path=output_image,
        show_plot=False,
        rep_counter=rep_counter,
    )
    print(f"Gráfico salvo com sucesso em: {saved_path}")

    # Exibe resumo de amplitudes no terminal
    print("\n" + "=" * 65)
    print("      RESUMO ESTATÍSTICO DA SIMULAÇÃO (ROM)")
    print("=" * 65)
    print(f"{'Articulação':<22} | {'Mínimo':>8} | {'Máximo':>8} | {'ROM (Δ)':>8} | {'Média':>8}")
    print("-" * 65)
    for key, data in tracker.get_all_summaries().items():
        print(f"{data['label']:<22} | {data['min']:>7.1f}° | {data['max']:>7.1f}° | {data['rom']:>7.1f}° | {data['avg']:>7.1f}°")
    print("=" * 65)

    # Exibe resumo das repetições
    print("\n" + "=" * 65)
    print(f"      RESUMO DE REPETIÇÕES ({rep_counter.config.display_name.upper()})")
    print("=" * 65)
    print(f" Total de Repetições: {rep_counter.rep_count}")
    print(f" Cadência: {rep_counter.cadence_rpm:.1f} RPM")
    print(f" Tempo Médio por Rep: {rep_counter.average_rep_duration:.2f}s")
    print("-" * 65)
    print(f"{'Rep':<5} | {'Concêntrico':>12} | {'Excêntrico':>12} | {'Total':>8} | {'Feedback':<20}")
    print("-" * 65)
    for r in rep_counter.reps_history:
        print(f"{r.rep_number:<5} | {r.concentric_duration:>11.2f}s | {r.eccentric_duration:>11.2f}s | {r.total_duration:>7.2f}s | {r.feedback}")
    print("=" * 65 + "\n")


if __name__ == "__main__":
    run_simulation()
