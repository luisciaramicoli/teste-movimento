"""
visualizer.py
Módulo responsável pela renderização visual em tempo real sobre os frames de vídeo (HUD/OpenCV)
e pela geração e salvamento do relatório gráfico final com Matplotlib, integrando feedback
de postura, contador de repetições e trilha de movimento.
"""

from typing import Dict, Optional, Tuple
import os
os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib_cache")

import cv2
import numpy as np
import matplotlib
import matplotlib.pyplot as plt

from tracker import AngleTracker
from rep_counter import ExerciseRepCounter


def draw_hud(
    frame: np.ndarray,
    angles_data: Dict[str, Dict],
    tracker: AngleTracker,
    fps: float = 0.0,
    rep_counter: Optional[ExerciseRepCounter] = None,
    trail_enabled: bool = False,
) -> np.ndarray:
    """
    Desenha os ângulos sobre as articulações no corpo e exibe painéis laterais (HUD)
    com os ângulos atuais, amplitudes, contador de repetições e feedback postural.
    """
    h, w, _ = frame.shape
    overlay = frame.copy()

    # 1. Desenhar anotações diretamente sobre as articulações no corpo
    for joint_key, data in angles_data.items():
        if not data.get("valid") or data.get("angle") is None:
            continue

        vertex = data["vertex_px"]
        angle = data["angle"]

        if vertex is not None:
            vx, vy = vertex
            # Círculo de destaque na articulação
            cv2.circle(frame, (vx, vy), 8, (0, 255, 255), -1)
            cv2.circle(frame, (vx, vy), 11, (0, 165, 255), 2)

            # Texto do ângulo com fundo semi-transparente para legibilidade
            text = f"{int(round(angle))}°"
            (tw, th), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2)
            tx, ty = vx + 12, vy - 10

            # Garantir que o texto não saia da tela
            tx = max(10, min(tx, w - tw - 10))
            ty = max(th + 10, min(ty, h - 10))

            cv2.rectangle(
                frame,
                (tx - 3, ty - th - 3),
                (tx + tw + 3, ty + baseline + 1),
                (20, 20, 20),
                -1,
            )
            cv2.putText(
                frame,
                text,
                (tx, ty),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )

    # 2. Painel lateral esquerdo (HUD Angular)
    panel_w = 340
    panel_h = 285
    cv2.rectangle(overlay, (10, 10), (10 + panel_w, 10 + panel_h), (25, 25, 25), -1)

    # 3. Painel de Exercício / Repetições (Canto Superior Direito) caso ativo
    is_exercise_mode = rep_counter is not None and rep_counter.config.name != "free"
    ex_panel_w = 340
    ex_panel_h = 160
    ex_x1 = w - ex_panel_w - 10
    ex_y1 = 10

    if is_exercise_mode:
        cv2.rectangle(overlay, (ex_x1, ex_y1), (ex_x1 + ex_panel_w, ex_y1 + ex_panel_h), (25, 25, 25), -1)

    alpha = 0.68
    cv2.addWeighted(overlay, alpha, frame, 1 - alpha, 0, frame)

    # Bordas dos painéis
    cv2.rectangle(frame, (10, 10), (10 + panel_w, 10 + panel_h), (80, 80, 80), 1)
    if is_exercise_mode:
        cv2.rectangle(frame, (ex_x1, ex_y1), (ex_x1 + ex_panel_w, ex_y1 + ex_panel_h), (80, 80, 80), 1)

    # --- Conteúdo do Painel Esquerdo (Ângulos) ---
    cv2.putText(
        frame,
        "MONITORAMENTO ANGULAR",
        (20, 35),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.52,
        (0, 220, 255),
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        f"FPS: {fps:.1f}",
        (260, 35),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (180, 180, 180),
        1,
        cv2.LINE_AA,
    )

    cv2.putText(
        frame,
        "Articulacao          Atual   Min   Max   ROM",
        (20, 58),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.38,
        (200, 200, 200),
        1,
        cv2.LINE_AA,
    )
    cv2.line(frame, (20, 65), (10 + panel_w - 10, 65), (100, 100, 100), 1)

    row_y = 85
    labels_abbrev = {
        "cotovelo_esq": "Cotovelo E.",
        "cotovelo_dir": "Cotovelo D.",
        "ombro_esq": "Ombro E.",
        "ombro_dir": "Ombro D.",
        "quadril_esq": "Quadril E.",
        "quadril_dir": "Quadril D.",
        "joelho_esq": "Joelho E.",
        "joelho_dir": "Joelho D.",
    }

    summaries = tracker.get_all_summaries()

    for key, name in labels_abbrev.items():
        summary = summaries.get(key, {})
        curr = f"{int(round(summary['current']))}°" if summary.get("current") is not None else "--"
        min_v = f"{int(round(summary['min']))}°" if summary.get("min") is not None else "--"
        max_v = f"{int(round(summary['max']))}°" if summary.get("max") is not None else "--"
        rom_v = f"{int(round(summary['rom']))}°" if summary.get("rom") is not None else "--"

        color = (255, 255, 255) if summary.get("current") is not None else (120, 120, 120)
        line_text = f"{name:<13} {curr:>5} {min_v:>5} {max_v:>5} {rom_v:>5}"

        cv2.putText(
            frame,
            line_text,
            (20, row_y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.36,
            color,
            1,
            cv2.LINE_AA,
        )
        row_y += 24

    # --- Conteúdo do Painel Direito (Exercício, Repetições e Feedback) ---
    if is_exercise_mode and rep_counter is not None:
        # Título do exercício
        cv2.putText(
            frame,
            rep_counter.config.display_name.upper(),
            (ex_x1 + 15, ex_y1 + 25),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.50,
            (255, 215, 0),
            2,
            cv2.LINE_AA,
        )

        # Contador de repetições em destaque
        cv2.putText(
            frame,
            f"REPS: {rep_counter.rep_count}",
            (ex_x1 + 15, ex_y1 + 65),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.95,
            (0, 255, 128),
            3,
            cv2.LINE_AA,
        )

        # Cadência (RPM) e tempo médio
        cadence_str = f"{rep_counter.cadence_rpm:.1f} RPM" if rep_counter.cadence_rpm > 0 else "-- RPM"
        avg_str = f"{rep_counter.average_rep_duration:.1f}s" if rep_counter.average_rep_duration > 0 else "--"
        stats_text = f"Cadencia: {cadence_str} | Tempo Med: {avg_str}"
        cv2.putText(
            frame,
            stats_text,
            (ex_x1 + 15, ex_y1 + 90),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.38,
            (200, 200, 200),
            1,
            cv2.LINE_AA,
        )

        # Barra de progresso da repetição atual
        bar_x = ex_x1 + 15
        bar_y = ex_y1 + 105
        bar_w = ex_panel_w - 30
        bar_h = 14
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_w, bar_y + bar_h), (50, 50, 50), -1)
        fill_w = int(bar_w * rep_counter.progress_pct)
        # Cor dinâmica: verde quando atinge o pico
        bar_color = (0, 255, 0) if rep_counter.progress_pct >= 0.95 else (0, 200, 255)
        if fill_w > 0:
            cv2.rectangle(frame, (bar_x, bar_y), (bar_x + fill_w, bar_y + bar_h), bar_color, -1)
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_w, bar_y + bar_h), (180, 180, 180), 1)

        # Mensagem de feedback dinâmico
        fb_msg = rep_counter.feedback_message
        if len(fb_msg) > 38:
            fb_msg = fb_msg[:35] + "..."
        cv2.putText(
            frame,
            fb_msg,
            (ex_x1 + 15, ex_y1 + 140),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.38,
            (255, 255, 255),
            1,
            cv2.LINE_AA,
        )

    # 4. Barra de rodapé com atalhos de controle
    trail_str = "ON" if trail_enabled else "OFF"
    mode_name = rep_counter.config.display_name if rep_counter else "Livre"
    footer_text = f"[Q] Finalizar | [R] Resetar | [M] Modo: {mode_name} | [T] Trilha: {trail_str}"
    cv2.rectangle(frame, (0, h - 30), (w, h), (15, 15, 15), -1)
    cv2.putText(
        frame,
        footer_text,
        (15, h - 10),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.42,
        (220, 220, 220),
        1,
        cv2.LINE_AA,
    )

    return frame


def generate_rom_report_graph(
    tracker: AngleTracker,
    output_image_path: str = "relatorio_angulos.png",
    show_plot: bool = True,
    rep_counter: Optional[ExerciseRepCounter] = None,
) -> str:
    """
    Gera um painel com múltiplos gráficos detalhando o comportamento angular e, caso
    haja repetições registradas, inclui gráficos de cadência e duração de repetições.
    """
    has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    if not has_display:
        matplotlib.use("Agg")

    has_reps = rep_counter is not None and len(rep_counter.reps_history) > 0

    # Ajusta tamanho e layout dependendo se há dados de repetições
    if has_reps:
        fig = plt.figure(figsize=(16, 13), dpi=120)
        gs = fig.add_gridspec(3, 2, width_ratios=[1.3, 1.0], height_ratios=[1.0, 1.0, 0.85], hspace=0.38, wspace=0.25)
        ax_reps = fig.add_subplot(gs[2, :])
    else:
        fig = plt.figure(figsize=(15, 10), dpi=120)
        gs = fig.add_gridspec(2, 2, width_ratios=[1.3, 1.0], hspace=0.35, wspace=0.25)
        ax_reps = None

    fig.patch.set_facecolor("#f8f9fa")

    ax_upper = fig.add_subplot(gs[0, 0])
    ax_lower = fig.add_subplot(gs[1, 0])
    ax_rom = fig.add_subplot(gs[0:2, 1])

    # 1. Membros Superiores (Cotovelos e Ombros)
    upper_joints = [
        ("cotovelo_esq", "Cotovelo Esquerdo", "#1f77b4", "-"),
        ("cotovelo_dir", "Cotovelo Direito", "#aec7e8", "--"),
        ("ombro_esq", "Ombro Esquerdo", "#ff7f0e", "-"),
        ("ombro_dir", "Ombro Direito", "#ffbb78", "--"),
    ]

    has_upper_data = False
    for key, label, color, style in upper_joints:
        record = tracker.joint_records.get(key)
        if record and len(record.angles) > 0:
            ax_upper.plot(
                record.timestamps,
                record.angles,
                label=f"{label} (Mín: {record.min_angle:.0f}°, Máx: {record.max_angle:.0f}°)",
                color=color,
                linestyle=style,
                linewidth=1.8,
            )
            has_upper_data = True

    ax_upper.set_title("Evolução Angular - Membros Superiores", fontsize=11, fontweight="bold", pad=8)
    ax_upper.set_xlabel("Tempo decorrido (segundos)", fontsize=9.5)
    ax_upper.set_ylabel("Ângulo (graus)", fontsize=9.5)
    ax_upper.set_ylim(0, 190)
    ax_upper.grid(True, linestyle="--", alpha=0.6)
    if has_upper_data:
        ax_upper.legend(loc="upper right", fontsize=8, framealpha=0.9)
    else:
        ax_upper.text(0.5, 0.5, "Sem dados suficientes para membros superiores", ha="center", va="center", transform=ax_upper.transAxes)

    # 2. Membros Inferiores (Joelhos e Quadris)
    lower_joints = [
        ("joelho_esq", "Joelho Esquerdo", "#2ca02c", "-"),
        ("joelho_dir", "Joelho Direito", "#98df8a", "--"),
        ("quadril_esq", "Quadril Esquerdo", "#d62728", "-"),
        ("quadril_dir", "Quadril Direito", "#ff9896", "--"),
    ]

    has_lower_data = False
    for key, label, color, style in lower_joints:
        record = tracker.joint_records.get(key)
        if record and len(record.angles) > 0:
            ax_lower.plot(
                record.timestamps,
                record.angles,
                label=f"{label} (Mín: {record.min_angle:.0f}°, Máx: {record.max_angle:.0f}°)",
                color=color,
                linestyle=style,
                linewidth=1.8,
            )
            has_lower_data = True

    ax_lower.set_title("Evolução Angular - Membros Inferiores", fontsize=11, fontweight="bold", pad=8)
    ax_lower.set_xlabel("Tempo decorrido (segundos)", fontsize=9.5)
    ax_lower.set_ylabel("Ângulo (graus)", fontsize=9.5)
    ax_lower.set_ylim(0, 190)
    ax_lower.grid(True, linestyle="--", alpha=0.6)
    if has_lower_data:
        ax_lower.legend(loc="upper right", fontsize=8, framealpha=0.9)
    else:
        ax_lower.text(0.5, 0.5, "Sem dados suficientes para membros inferiores", ha="center", va="center", transform=ax_lower.transAxes)

    # 3. Gráfico de Amplitude de Movimento (Mínimo x Máximo por Articulação)
    labels = []
    min_values = []
    max_values = []
    rom_values = []

    ordered_keys = [
        ("cotovelo_esq", "Cotovelo E."),
        ("cotovelo_dir", "Cotovelo D."),
        ("ombro_esq", "Ombro E."),
        ("ombro_dir", "Ombro D."),
        ("quadril_esq", "Quadril E."),
        ("quadril_dir", "Quadril D."),
        ("joelho_esq", "Joelho E."),
        ("joelho_dir", "Joelho D."),
    ]

    for key, short_label in ordered_keys:
        record = tracker.joint_records.get(key)
        if record and record.min_angle is not None and record.max_angle is not None:
            labels.append(short_label)
            min_values.append(record.min_angle)
            max_values.append(record.max_angle)
            rom_values.append(record.rom if record.rom is not None else 0.0)

    if labels:
        y_positions = np.arange(len(labels))
        height = 0.35

        ax_rom.barh(y_positions - height / 2, min_values, height, label="Ângulo Mínimo", color="#4e79a7", alpha=0.85)
        ax_rom.barh(y_positions + height / 2, max_values, height, label="Ângulo Máximo", color="#e15759", alpha=0.85)

        for idx, (y, r_min, r_max, rom) in enumerate(zip(y_positions, min_values, max_values, rom_values)):
            ax_rom.text(r_min + 3, y - height / 2, f"{r_min:.0f}°", va="center", fontsize=8, fontweight="bold", color="#1f2d3d")
            ax_rom.text(r_max + 3, y + height / 2, f"{r_max:.0f}°", va="center", fontsize=8, fontweight="bold", color="#1f2d3d")
            ax_rom.text(192, y, f"ROM: {rom:.0f}°", va="center", ha="right", fontsize=9, fontweight="bold", color="#2e7d32", bbox=dict(boxstyle="round,pad=0.2", facecolor="#e8f5e9", edgecolor="#a5d6a7", alpha=0.8))

        ax_rom.set_yticks(y_positions)
        ax_rom.set_yticklabels(labels, fontsize=10)
        ax_rom.invert_yaxis()
        ax_rom.set_xlim(0, 205)
        ax_rom.set_xlabel("Ângulo em Graus (°)", fontsize=9.5)
        ax_rom.set_title("Amplitude de Movimento Alcançada (ROM)", fontsize=11, fontweight="bold", pad=8)
        ax_rom.grid(True, axis="x", linestyle="--", alpha=0.6)
        if has_reps:
            ax_rom.legend(loc="lower right", fontsize=9, framealpha=0.9)
        else:
            ax_rom.legend(loc="upper center", bbox_to_anchor=(0.5, -0.09), ncol=2, fontsize=9.5, frameon=True)
    else:
        ax_rom.text(0.5, 0.5, "Nenhum movimento registrado", ha="center", va="center", transform=ax_rom.transAxes)

    # 4. Gráfico Adicional de Repetições e Cadência (Inspirado no chin_ups do vision-demos)
    if has_reps and ax_reps is not None and rep_counter is not None:
        reps = rep_counter.reps_history
        rep_nums = [r.rep_number for r in reps]
        concentric_times = [r.concentric_duration for r in reps]
        eccentric_times = [r.eccentric_duration for r in reps]

        x_indices = np.arange(len(rep_nums))
        w_bar = 0.4

        b1 = ax_reps.bar(x_indices - w_bar / 2, concentric_times, w_bar, label="Fase Concêntrica (Subida/Puxada)", color="#2b5c8f", alpha=0.9)
        b2 = ax_reps.bar(x_indices + w_bar / 2, eccentric_times, w_bar, label="Fase Excêntrica (Descida/Retorno)", color="#e67e22", alpha=0.9)

        # Anotações de tempo sobre as barras
        for i, (c_t, e_t) in enumerate(zip(concentric_times, eccentric_times)):
            ax_reps.text(i - w_bar / 2, c_t + 0.05, f"{c_t:.1f}s", ha="center", va="bottom", fontsize=8, fontweight="bold")
            ax_reps.text(i + w_bar / 2, e_t + 0.05, f"{e_t:.1f}s", ha="center", va="bottom", fontsize=8, fontweight="bold")

        ax_reps.set_xticks(x_indices)
        ax_reps.set_xticklabels([f"Rep {n}" for n in rep_nums], fontsize=9)
        ax_reps.set_ylabel("Duração (segundos)", fontsize=9.5)
        ax_reps.set_title(
            f"Análise Biomecânica de Repetições - {rep_counter.config.display_name} (Total: {len(reps)} reps | Cadência: {rep_counter.cadence_rpm:.1f} RPM)",
            fontsize=11,
            fontweight="bold",
            pad=8,
        )
        ax_reps.grid(True, axis="y", linestyle="--", alpha=0.6)
        ax_reps.legend(loc="upper right", fontsize=9)

    plt.suptitle(
        "Relatório Biomecânico de Articulações e Repetições",
        fontsize=15,
        fontweight="bold",
        y=0.98 if not has_reps else 0.99,
    )

    abs_output_path = os.path.abspath(output_image_path)
    plt.savefig(abs_output_path, bbox_inches="tight")

    if show_plot and has_display:
        try:
            plt.show()
        except Exception:
            pass

    plt.close(fig)
    return abs_output_path
