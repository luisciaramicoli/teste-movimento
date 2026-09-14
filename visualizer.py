"""
visualizer.py
Módulo responsável pela renderização visual em tempo real sobre os frames de vídeo (HUD/OpenCV)
e pela geração e salvamento do relatório gráfico final com Matplotlib.
"""

from typing import Dict, Optional, Tuple
import os
os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib_cache")

import cv2
import numpy as np
import matplotlib
import matplotlib.pyplot as plt

from tracker import AngleTracker


def draw_hud(
    frame: np.ndarray,
    angles_data: Dict[str, Dict],
    tracker: AngleTracker,
    fps: float = 0.0,
) -> np.ndarray:
    """
    Desenha os ângulos sobre as articulações no corpo e exibe um painel lateral (HUD)
    com os ângulos atuais, amplitudes mínimas e máximas alcançadas.
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
            text = f"{int(round(angle))} deg"
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

    # 2. Painel lateral semi-transparente (HUD) no canto superior esquerdo
    panel_w = 340
    panel_h = 300
    cv2.rectangle(overlay, (10, 10), (10 + panel_w, 10 + panel_h), (25, 25, 25), -1)
    alpha = 0.65
    cv2.addWeighted(overlay, alpha, frame, 1 - alpha, 0, frame)

    # Borda do painel
    cv2.rectangle(frame, (10, 10), (10 + panel_w, 10 + panel_h), (80, 80, 80), 1)

    # Título do painel e FPS
    cv2.putText(
        frame,
        "MONITORAMENTO ANGULAR",
        (20, 35),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
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

    # Cabeçalho da tabela
    cv2.putText(
        frame,
        "Articulacao          Atual   Min   Max   ROM",
        (20, 60),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.40,
        (200, 200, 200),
        1,
        cv2.LINE_AA,
    )
    cv2.line(frame, (20, 68), (10 + panel_w - 10, 68), (100, 100, 100), 1)

    # Linhas de articulações no painel
    row_y = 88
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
        curr = f"{int(round(summary['current']))}o" if summary.get("current") is not None else "--"
        min_v = f"{int(round(summary['min']))}o" if summary.get("min") is not None else "--"
        max_v = f"{int(round(summary['max']))}o" if summary.get("max") is not None else "--"
        rom_v = f"{int(round(summary['rom']))}o" if summary.get("rom") is not None else "--"

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

    # 3. Barra de rodapé com atalhos
    footer_text = "Pressione [Q] para finalizar e ver graficos | [R] resetar recordes"
    cv2.rectangle(frame, (0, h - 30), (w, h), (15, 15, 15), -1)
    cv2.putText(
        frame,
        footer_text,
        (15, h - 10),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (220, 220, 220),
        1,
        cv2.LINE_AA,
    )

    return frame


def generate_rom_report_graph(
    tracker: AngleTracker,
    output_image_path: str = "relatorio_angulos.png",
    show_plot: bool = True,
) -> str:
    """
    Gera um painel com múltiplos gráficos detalhando o comportamento angular de cada articulação:
    1. Gráfico temporal superior: Evolução dos ângulos de membros superiores (Cotovelos e Ombros).
    2. Gráfico temporal inferior: Evolução dos ângulos de membros inferiores (Joelhos e Quadris).
    3. Gráfico de barras: Amplitude de Movimento Alcançada (Mínimo vs Máximo com destaque para o ROM).

    Args:
        tracker: Instância de AngleTracker com os dados registrados
        output_image_path: Caminho onde a imagem do relatório será salva
        show_plot: Se True, tenta exibir a janela interativa com plt.show()

    Returns:
        Caminho absoluto do arquivo salvo
    """
    # Detecta se há display disponível
    has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    if not has_display:
        matplotlib.use("Agg")

    fig = plt.figure(figsize=(15, 10), dpi=120)
    fig.patch.set_facecolor("#f8f9fa")

    # Layout de 3 subplots: 2 na esquerda (séries temporais) e 1 na direita (barras de amplitude)
    gs = fig.add_gridspec(2, 2, width_ratios=[1.3, 1.0], hspace=0.35, wspace=0.25)

    ax_upper = fig.add_subplot(gs[0, 0])
    ax_lower = fig.add_subplot(gs[1, 0])
    ax_rom = fig.add_subplot(gs[:, 1])

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

    ax_upper.set_title("Evolução Angular - Membros Superiores", fontsize=12, fontweight="bold", pad=8)
    ax_upper.set_xlabel("Tempo decorrido (segundos)", fontsize=10)
    ax_upper.set_ylabel("Ângulo (graus)", fontsize=10)
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

    ax_lower.set_title("Evolução Angular - Membros Inferiores", fontsize=12, fontweight="bold", pad=8)
    ax_lower.set_xlabel("Tempo decorrido (segundos)", fontsize=10)
    ax_lower.set_ylabel("Ângulo (graus)", fontsize=10)
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

        # Barras de ângulo mínimo e máximo
        bars_min = ax_rom.barh(y_positions - height / 2, min_values, height, label="Ângulo Mínimo", color="#4e79a7", alpha=0.85)
        bars_max = ax_rom.barh(y_positions + height / 2, max_values, height, label="Ângulo Máximo", color="#e15759", alpha=0.85)

        # Anotações dos valores nas barras
        for idx, (y, r_min, r_max, rom) in enumerate(zip(y_positions, min_values, max_values, rom_values)):
            ax_rom.text(r_min + 3, y - height / 2, f"{r_min:.0f}°", va="center", fontsize=8, fontweight="bold", color="#1f2d3d")
            ax_rom.text(r_max + 3, y + height / 2, f"{r_max:.0f}°", va="center", fontsize=8, fontweight="bold", color="#1f2d3d")
            # Anotação da amplitude alcançada (Delta = Max - Min)
            ax_rom.text(188, y, f"ROM: {rom:.0f}°", va="center", ha="right", fontsize=9, fontweight="bold", color="#2e7d32", bbox=dict(boxstyle="round,pad=0.2", facecolor="#e8f5e9", edgecolor="#a5d6a7", alpha=0.8))

        ax_rom.set_yticks(y_positions)
        ax_rom.set_yticklabels(labels, fontsize=10)
        ax_rom.invert_yaxis()  # Primeira articulação no topo
        ax_rom.set_xlim(0, 205)
        ax_rom.set_xlabel("Ângulo em Graus (°)", fontsize=10)
        ax_rom.set_title("Amplitude de Movimento Alcançada (ROM)", fontsize=12, fontweight="bold", pad=8)
        ax_rom.grid(True, axis="x", linestyle="--", alpha=0.6)
        ax_rom.legend(loc="upper center", bbox_to_anchor=(0.5, -0.09), ncol=2, fontsize=9.5, frameon=True)
    else:
        ax_rom.text(0.5, 0.5, "Nenhum movimento registrado", ha="center", va="center", transform=ax_rom.transAxes)

    plt.suptitle(
        "Relatório de Amplitude Articular e Rastreamento Biomecânico",
        fontsize=15,
        fontweight="bold",
        y=0.98,
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
