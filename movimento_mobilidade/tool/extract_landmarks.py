"""Extrai os 33 pontos de cada quadro de um vídeo com o MediaPipe Pose Landmarker.

Usa o mesmo modelo e os mesmos limites do plugin Android, com a imagem reduzida à
metade. A saída alimenta tool/replay_video_test.dart.

Uso: python extract_landmarks.py VIDEO SAIDA.json [--mirrored]
"""
import argparse
import json
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision

MODEL = Path(__file__).resolve().parent.parent / "android/src/main/assets/pose_landmarker_lite.task"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video")
    parser.add_argument("output")
    parser.add_argument("--mirrored", action="store_true",
                        help="o vídeo está espelhado (câmera frontal): desfaz antes de analisar")
    args = parser.parse_args()

    options = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    capture = cv2.VideoCapture(args.video)
    if not capture.isOpened():
        raise SystemExit(f"Não foi possível abrir {args.video}")

    frames, size, last_ms = [], None, -1
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            ms = max(int(capture.get(cv2.CAP_PROP_POS_MSEC)), last_ms + 1)
            last_ms = ms
            if args.mirrored:
                frame = cv2.flip(frame, 1)
            size = (frame.shape[1], frame.shape[0])
            small = cv2.cvtColor(frame[::2, ::2], cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=small.copy())
            result = landmarker.detect_for_video(image, ms)
            points = []
            if result.pose_landmarks:
                for p in result.pose_landmarks[0]:
                    points += [p.x, p.y, p.z, p.visibility]
            frames.append({"t": ms / 1000, "p": points})

    Path(args.output).write_text(json.dumps(
        {"width": size[0], "height": size[1], "frames": frames}))
    found = sum(1 for f in frames if f["p"])
    print(f"{len(frames)} quadros, {found} com pessoa, {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
