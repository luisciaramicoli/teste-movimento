#!/usr/bin/env python3
"""
main.py
Aplicação principal para identificação de articulações do corpo,
cálculo de ângulos em tempo real, contador de repetições, trilhas de movimento (Comet Trail)
e geração de gráficos de amplitude e cadência ao final.
"""

import argparse
import sys
import time
import cv2

from pose_detector import PoseDetector, JOINT_DEFINITIONS
from tracker import AngleTracker
from rep_counter import ExerciseRepCounter, EXERCISE_PRESETS
from motion_trail import MotionTrail
from visualizer import draw_hud, generate_rom_report_graph


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Identificação de Articulações, Análise de Amplitude (ROM) e Repetições com Gráficos"
    )
    parser.add_argument(
        "--camera",
        type=int,
        default=0,
        help="Índice da webcam a ser utilizada (padrão: 0)",
    )
    parser.add_argument(
        "--video",
        type=str,
        default=None,
        help="Caminho para arquivo de vídeo gravado (caso não queira usar webcam)",
    )
    parser.add_argument(
        "--exercise",
        type=str,
        choices=list(EXERCISE_PRESETS.keys()),
        default="free",
        help="Modo de exercício: free (livre), squat (agachamento), curl (rosca bíceps), chin_up (barra fixa)",
    )
    parser.add_argument(
        "--no-trail",
        action="store_true",
        help="Desativar trilha de movimento visual (Comet Trail)",
    )
    parser.add_argument(
        "--output-graph",
        type=str,
        default="relatorio_angulos.png",
        help="Caminho do arquivo de imagem para o gráfico final (padrão: relatorio_angulos.png)",
    )
    parser.add_argument(
        "--export-csv",
        type=str,
        default=None,
        help="Caminho opcional para exportar os dados em formato CSV",
    )
    parser.add_argument(
        "--confidence",
        type=float,
        default=0.5,
        help="Confiança mínima para detecção das articulações (0.0 a 1.0, padrão: 0.5)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Executar sem abrir janela do OpenCV (útil para testes automatizados)",
    )
    return parser.parse_args()


def print_summary_table(tracker: AngleTracker, rep_counter: ExerciseRepCounter):
    """
    Imprime no terminal uma tabela organizada com o resumo estatístico e repetições.
    """
    print("\n" + "=" * 65)
    print("      RESUMO ESTATÍSTICO DE AMPLITUDE DE MOVIMENTO (ROM)")
    print("=" * 65)
    print(
        f"{'Articulação':<22} | {'Mínimo':>8} | {'Máximo':>8} | {'ROM (Δ)':>8} | {'Média':>8}"
    )
    print("-" * 65)

    summaries = tracker.get_all_summaries()
    for key, data in summaries.items():
        if data["min"] is not None:
            min_str = f"{data['min']:.1f}°"
            max_str = f"{data['max']:.1f}°"
            rom_str = f"{data['rom']:.1f}°"
            avg_str = f"{data['avg']:.1f}°"
            print(
                f"{data['label']:<22} | {min_str:>8} | {max_str:>8} | {rom_str:>8} | {avg_str:>8}"
            )
        else:
            print(f"{data['label']:<22} | {'--':>8} | {'--':>8} | {'--':>8} | {'--':>8}")

    print("=" * 65)

    # Resumo de repetições se o modo não for livre e houver histórico
    if rep_counter.config.name != "free" or len(rep_counter.reps_history) > 0:
        print("\n" + "=" * 65)
        print(f"      RESUMO DE EXERCÍCIO: {rep_counter.config.display_name.upper()}")
        print("=" * 65)
        print(f" Total de Repetições: {rep_counter.rep_count}")
        if rep_counter.reps_history:
            print(f" Cadência Recente: {rep_counter.cadence_rpm:.1f} RPM")
            print(f" Tempo Médio por Rep: {rep_counter.average_rep_duration:.2f}s")
            print("-" * 65)
            print(f"{'Rep':<5} | {'Concêntrico':>12} | {'Excêntrico':>12} | {'Total':>8} | {'Válida?':>8}")
            print("-" * 65)
            for r in rep_counter.reps_history:
                val_str = "Sim ✅" if r.is_valid else "Não ⚠️"
                print(f"{r.rep_number:<5} | {r.concentric_duration:>11.2f}s | {r.eccentric_duration:>11.2f}s | {r.total_duration:>7.2f}s | {val_str:>8}")
        print("=" * 65 + "\n")


def main():
    args = parse_arguments()

    # 1. Inicializar detector, rastreador, contador e efeito de cometa
    print("Inicializando MediaPipe Pose Detector...")
    try:
        detector = PoseDetector(
            min_detection_confidence=args.confidence,
            min_tracking_confidence=args.confidence,
        )
    except Exception as e:
        print(f"\n[ERRO] Falha ao inicializar MediaPipe: {e}")
        print("Certifique-se de que as dependências estão instaladas: pip install -r requirements.txt")
        sys.exit(1)

    tracker = AngleTracker(
        joint_labels={k: v[3] for k, v in JOINT_DEFINITIONS.items()}
    )
    rep_counter = ExerciseRepCounter(exercise_name=args.exercise)
    motion_trail = MotionTrail(enabled=not args.no_trail)

    # 2. Configurar fonte de vídeo (Webcam ou Arquivo de Vídeo)
    source = args.video if args.video else args.camera
    print(f"Abrindo fonte de vídeo: {source} ...")
    cap = cv2.VideoCapture(source)

    if not cap.isOpened():
        print(f"\n[ERRO] Não foi possível abrir a fonte de vídeo: {source}")
        if not args.video:
            print("Dica: Se você não tiver uma webcam conectada, pode testar com um vídeo: python3 main.py --video arquivo.mp4")
        sys.exit(1)

    modes_list = list(EXERCISE_PRESETS.keys())
    current_mode_idx = modes_list.index(args.exercise) if args.exercise in modes_list else 0

    print("\nIniciando monitoramento.")
    print(" - [Q] ou [ESC]: finalizar sessão e gerar o relatório gráfico.")
    print(" - [R]: reiniciar recordes e contador de repetições.")
    print(" - [M]: alternar modo de exercício (Livre, Agachamento, Rosca, Barra).")
    print(" - [T]: ligar/desligar trilha visual ('Comet Trail').\n")

    start_time = time.time()
    frame_count = 0
    fps = 0.0
    last_fps_time = start_time

    window_name = "Rastreamento de Articulações - MediaPipe Pose"

    try:
        while cap.isOpened():
            success, frame = cap.read()
            if not success:
                if args.video:
                    print("Fim do vídeo gravado alcançado.")
                break

            current_time = time.time()
            elapsed_total = current_time - start_time
            frame_count += 1

            if frame_count % 10 == 0:
                fps = 10.0 / (current_time - last_fps_time)
                last_fps_time = current_time

            # Detecção de pose
            results = detector.find_pose(frame)

            # Desenho das conexões ósseas do MediaPipe
            if not args.headless:
                detector.draw_landmarks_on_image(frame, results)

            # Extração de coordenadas e cálculo angular
            landmarks = detector.extract_landmarks(results, frame.shape)
            angles_data = detector.calculate_all_joint_angles(landmarks)

            # Atualização do rastreador de amplitude
            tracker.update(angles_data, elapsed_total)

            # Atualização do contador de repetições
            completed_rep = rep_counter.update(angles_data, elapsed_total)
            if completed_rep:
                print(f"[REP {completed_rep.rep_number}] Feita em {completed_rep.total_duration:.2f}s | ROM: {completed_rep.rom}° | {completed_rep.feedback}")

            # Atualização e renderização da trilha de cometa
            motion_trail.update(landmarks)

            if not args.headless:
                frame = motion_trail.draw(frame)
                frame_with_hud = draw_hud(
                    frame,
                    angles_data,
                    tracker,
                    fps,
                    rep_counter=rep_counter,
                    trail_enabled=motion_trail.enabled,
                )
                cv2.imshow(window_name, frame_with_hud)

                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), ord("Q"), 27):  # 'q', 'Q' ou ESC
                    print("\nEncerrando captura solicitado pelo usuário...")
                    break
                elif key in (ord("r"), ord("R")):
                    tracker.reset_all()
                    rep_counter.reset()
                    motion_trail.clear()
                    print("[INFO] Recordes e repetições reiniciados.")
                elif key in (ord("m"), ord("M")):
                    current_mode_idx = (current_mode_idx + 1) % len(modes_list)
                    new_mode = modes_list[current_mode_idx]
                    rep_counter.set_exercise(new_mode)
                    print(f"[MODO] Alterado para: {rep_counter.config.display_name}")
                elif key in (ord("t"), ord("T")):
                    is_on = motion_trail.toggle()
                    print(f"[TRILHA] Comet Trail {'ativada' if is_on else 'desativada'}.")

    except KeyboardInterrupt:
        print("\nInterrupção por teclado (Ctrl+C) detectada. Finalizando...")

    finally:
        cap.release()
        if not args.headless:
            cv2.destroyAllWindows()

    # 3. Exibir tabelas de resumo no terminal
    print_summary_table(tracker, rep_counter)

    # Exportar CSV caso solicitado
    if args.export_csv:
        try:
            tracker.export_to_csv(args.export_csv)
            print(f"[OK] Dados temporais exportados para: {args.export_csv}")
        except Exception as e:
            print(f"[AVISO] Não foi possível exportar CSV: {e}")

    # Gerar e salvar gráfico de relatório final (com subgráfico de repetições se houver)
    print("Gerando painel gráfico de relatório...")
    try:
        saved_path = generate_rom_report_graph(
            tracker,
            output_image_path=args.output_graph,
            show_plot=not args.headless,
            rep_counter=rep_counter,
        )
        print(f"[SUCESSO] Gráfico de ângulos e amplitudes salvo em:\n  -> {saved_path}")
    except Exception as e:
        print(f"[ERRO] Falha ao gerar relatório gráfico: {e}")


if __name__ == "__main__":
    main()
