#!/usr/bin/env python3
"""
main.py
Aplicação principal para identificação de articulações do corpo,
cálculo de ângulos em tempo real e geração de gráficos de amplitude ao final.
"""

import argparse
import sys
import time
import cv2

from pose_detector import PoseDetector, JOINT_DEFINITIONS
from tracker import AngleTracker
from visualizer import draw_hud, generate_rom_report_graph


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Identificação de Articulações e Análise de Amplitude Angular (ROM) com Gráficos"
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


def print_summary_table(tracker: AngleTracker):
    """
    Imprime no terminal uma tabela organizada com o resumo estatístico.
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

    print("=" * 65 + "\n")


def main():
    args = parse_arguments()

    # 1. Inicializar detector e rastreador
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

    # 2. Configurar fonte de vídeo (Webcam ou Arquivo de Vídeo)
    source = args.video if args.video else args.camera
    print(f"Abrindo fonte de vídeo: {source} ...")
    cap = cv2.VideoCapture(source)

    if not cap.isOpened():
        print(f"\n[ERRO] Não foi possível abrir a fonte de vídeo: {source}")
        if not args.video:
            print("Dica: Se você não tiver uma webcam conectada, pode testar com um vídeo: python3 main.py --video arquivo.mp4")
        sys.exit(1)

    print("\nIniciando monitoramento.")
    print(" - Pressione [Q] ou [ESC] na janela de vídeo para finalizar e gerar o relatório gráfico.")
    print(" - Pressione [R] para reiniciar os recordes de amplitude mínima/máxima.\n")

    start_time = time.time()
    frame_count = 0
    fps = 0.0
    last_fps_time = start_time

    window_name = "Rastreamento de Articulações - MediaPipe Pose"

    try:
        while cap.isOpened():
            success, frame = cap.read()
            if not success:
                # Fim do vídeo gravado ou falha de captura
                if args.video:
                    print("Fim do vídeo gravado alcançado.")
                break

            current_time = time.time()
            elapsed_total = current_time - start_time
            frame_count += 1

            # Cálculo de FPS a cada 10 frames
            if frame_count % 10 == 0:
                fps = 10.0 / (current_time - last_fps_time)
                last_fps_time = current_time

            # Detecção da pose
            results = detector.find_pose(frame)

            # Desenha as conexões corporais nativas do MediaPipe se houver
            if not args.headless:
                detector.draw_landmarks_on_image(frame, results)

            # Extração de pontos e cálculo de ângulos
            landmarks = detector.extract_landmarks(results, frame.shape)
            angles_data = detector.calculate_all_joint_angles(landmarks)

            # Atualização dos recordes no rastreador
            tracker.update(angles_data, elapsed_total)

            # Renderização de HUD e anotações visuais
            if not args.headless:
                frame_with_hud = draw_hud(frame, angles_data, tracker, fps)
                cv2.imshow(window_name, frame_with_hud)

                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), ord("Q"), 27):  # 'q', 'Q' ou ESC
                    print("\nEncerrando captura solicitado pelo usuário...")
                    break
                elif key in (ord("r"), ord("R")):
                    tracker.reset_all()
                    print("[INFO] Recordes de amplitude reiniciados.")

    except KeyboardInterrupt:
        print("\nInterrupção por teclado (Ctrl+C) detectada. Finalizando...")

    finally:
        cap.release()
        if not args.headless:
            cv2.destroyAllWindows()

    # 3. Exibir resumo e gerar gráficos
    print_summary_table(tracker)

    # Exportar CSV caso solicitado
    if args.export_csv:
        try:
            tracker.export_to_csv(args.export_csv)
            print(f"[OK] Dados temporais exportados para: {args.export_csv}")
        except Exception as e:
            print(f"[AVISO] Não foi possível exportar CSV: {e}")

    # Gerar e salvar gráfico de relatório final
    print("Gerando painel gráfico de relatório...")
    try:
        saved_path = generate_rom_report_graph(
            tracker,
            output_image_path=args.output_graph,
            show_plot=not args.headless,
        )
        print(f"[SUCESSO] Gráfico de ângulos e amplitudes salvo em:\n  -> {saved_path}")
    except Exception as e:
        print(f"[ERRO] Falha ao gerar relatório gráfico: {e}")


if __name__ == "__main__":
    main()
