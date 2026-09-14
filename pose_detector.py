"""
pose_detector.py
Módulo responsável pela detecção de articulações do corpo humano utilizando MediaPipe Pose
(compatível com MediaPipe Tasks API moderna e MediaPipe Solutions clássico) e cálculo angular.
"""

from typing import Dict, List, Optional, Tuple
import os
import urllib.request
import numpy as np


def calculate_angle(a: Tuple[float, float], b: Tuple[float, float], c: Tuple[float, float]) -> float:
    """
    Calcula o ângulo em graus no vértice b formado pelos pontos a, b e c.
    
    Args:
        a: Coordenadas do primeiro ponto (ex: ombro)
        b: Coordenadas do vértice / articulação (ex: cotovelo)
        c: Coordenadas do terceiro ponto (ex: punho)
        
    Returns:
        Ângulo em graus no intervalo [0.0, 180.0]
    """
    a_arr = np.array(a, dtype=np.float64)
    b_arr = np.array(b, dtype=np.float64)
    c_arr = np.array(c, dtype=np.float64)

    ba = a_arr - b_arr
    bc = c_arr - b_arr

    norm_ba = np.linalg.norm(ba)
    norm_bc = np.linalg.norm(bc)

    if norm_ba < 1e-6 or norm_bc < 1e-6:
        return 0.0

    cosine_angle = np.dot(ba, bc) / (norm_ba * norm_bc)
    cosine_angle = np.clip(cosine_angle, -1.0, 1.0)
    angle = np.degrees(np.arccos(cosine_angle))
    return round(float(angle), 1)


# Índices padrão de marcos anatômicos do MediaPipe Pose
LANDMARKS = {
    "NOSE": 0,
    "LEFT_SHOULDER": 11,
    "RIGHT_SHOULDER": 12,
    "LEFT_ELBOW": 13,
    "RIGHT_ELBOW": 14,
    "LEFT_WRIST": 15,
    "RIGHT_WRIST": 16,
    "LEFT_HIP": 23,
    "RIGHT_HIP": 24,
    "LEFT_KNEE": 25,
    "RIGHT_KNEE": 26,
    "LEFT_ANKLE": 27,
    "RIGHT_ANKLE": 28,
}

# Definição das articulações a serem monitoradas:
# Nome da articulação: (Ponto A, Vértice B, Ponto C, Rótulo em PT-BR)
JOINT_DEFINITIONS = {
    "cotovelo_esq": ("LEFT_SHOULDER", "LEFT_ELBOW", "LEFT_WRIST", "Cotovelo Esquerdo"),
    "cotovelo_dir": ("RIGHT_SHOULDER", "RIGHT_ELBOW", "RIGHT_WRIST", "Cotovelo Direito"),
    "ombro_esq": ("LEFT_HIP", "LEFT_SHOULDER", "LEFT_ELBOW", "Ombro Esquerdo"),
    "ombro_dir": ("RIGHT_HIP", "RIGHT_SHOULDER", "RIGHT_ELBOW", "Ombro Direito"),
    "quadril_esq": ("LEFT_SHOULDER", "LEFT_HIP", "LEFT_KNEE", "Quadril Esquerdo"),
    "quadril_dir": ("RIGHT_SHOULDER", "RIGHT_HIP", "RIGHT_KNEE", "Quadril Direito"),
    "joelho_esq": ("LEFT_HIP", "LEFT_KNEE", "LEFT_ANKLE", "Joelho Esquerdo"),
    "joelho_dir": ("RIGHT_HIP", "RIGHT_KNEE", "RIGHT_ANKLE", "Joelho Direito"),
}

MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"


class PoseDetector:
    """
    Detector de pose baseado no MediaPipe Pose.
    Compatível com MediaPipe Tasks API (moderno) e Solutions (legado).
    """

    def __init__(
        self,
        model_path: str = "pose_landmarker_lite.task",
        min_detection_confidence: float = 0.5,
        min_tracking_confidence: float = 0.5,
    ):
        import mediapipe as mp
        self.mp = mp
        self.use_tasks_api = False

        if hasattr(mp, "solutions") and hasattr(mp.solutions, "pose"):
            # Modo MediaPipe Solutions clássico
            self.mp_pose = mp.solutions.pose
            self.mp_drawing = mp.solutions.drawing_utils
            self.mp_drawing_styles = mp.solutions.drawing_styles
            self.pose = self.mp_pose.Pose(
                min_detection_confidence=min_detection_confidence,
                min_tracking_confidence=min_tracking_confidence,
            )
        else:
            # Modo MediaPipe Tasks API moderno
            self.use_tasks_api = True
            from mediapipe.tasks import python
            from mediapipe.tasks.python import vision

            self.vision = vision

            # Garante que o arquivo do modelo existe
            if not os.path.exists(model_path):
                # Tenta procurar no mesmo diretório do arquivo atual
                local_dir_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), model_path)
                if os.path.exists(local_dir_path):
                    model_path = local_dir_path
                else:
                    print(f"Baixando modelo MediaPipe Pose ({model_path})...")
                    try:
                        urllib.request.urlretrieve(MODEL_URL, model_path)
                        print("Download concluído com sucesso!")
                    except Exception as e:
                        raise RuntimeError(
                            f"Falha ao baixar o modelo {model_path}. Baixe manualmente de {MODEL_URL}: {e}"
                        )

            base_options = python.BaseOptions(model_asset_path=model_path)
            options = vision.PoseLandmarkerOptions(
                base_options=base_options,
                min_pose_detection_confidence=min_detection_confidence,
                min_pose_presence_confidence=min_tracking_confidence,
                min_tracking_confidence=min_tracking_confidence,
                output_segmentation_masks=False,
            )
            self.landmarker = vision.PoseLandmarker.create_from_options(options)
            self.connections = vision.PoseLandmarksConnections.POSE_LANDMARKS
            self.drawing_utils = vision.drawing_utils

    def find_pose(self, image: np.ndarray):
        """
        Processa um frame BGR e retorna o resultado bruto da inferência.
        """
        import cv2

        if self.use_tasks_api:
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            mp_image = self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=image_rgb)
            return self.landmarker.detect(mp_image)
        else:
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            image_rgb.flags.writeable = False
            results = self.pose.process(image_rgb)
            image_rgb.flags.writeable = True
            return results

    def draw_landmarks_on_image(self, frame: np.ndarray, results):
        """
        Desenha as conexões e marcos anatômicos sobre o frame.
        """
        if not results:
            return

        if self.use_tasks_api:
            if getattr(results, "pose_landmarks", None):
                for pose_lms in results.pose_landmarks:
                    self.drawing_utils.draw_landmarks(
                        frame,
                        pose_lms,
                        connections=self.connections,
                    )
        else:
            if getattr(results, "pose_landmarks", None):
                self.mp_drawing.draw_landmarks(
                    frame,
                    results.pose_landmarks,
                    self.mp_pose.POSE_CONNECTIONS,
                    landmark_drawing_spec=self.mp_drawing_styles.get_default_pose_landmarks_style(),
                )

    def extract_landmarks(
        self, results, frame_shape: Tuple[int, int, int], min_visibility: float = 0.5
    ) -> Dict[str, Dict]:
        """
        Extrai as coordenadas em pixels e a visibilidade de cada marco anatômico relevante.
        """
        landmarks_dict = {}
        h, w, _ = frame_shape

        if not results or not getattr(results, "pose_landmarks", None):
            return landmarks_dict

        if self.use_tasks_api:
            if len(results.pose_landmarks) == 0:
                return landmarks_dict
            raw_landmarks = results.pose_landmarks[0]
        else:
            raw_landmarks = results.pose_landmarks.landmark

        for name, idx in LANDMARKS.items():
            if idx < len(raw_landmarks):
                lm = raw_landmarks[idx]
                vis = getattr(lm, "visibility", None)
                if vis is None:
                    vis = getattr(lm, "presence", 1.0)
                is_valid = (vis is None) or (vis >= min_visibility)

                px_x = int(lm.x * w)
                px_y = int(lm.y * h)

                landmarks_dict[name] = {
                    "pixel": (px_x, px_y),
                    "normalized": (lm.x, lm.y),
                    "visibility": vis,
                    "valid": is_valid,
                }

        return landmarks_dict

    def calculate_all_joint_angles(
        self, landmarks_dict: Dict[str, Dict]
    ) -> Dict[str, Dict]:
        """
        Calcula os ângulos de todas as articulações definidas se os três pontos forem válidos.
        """
        angles_result = {}

        for joint_key, (pt_a_name, pt_b_name, pt_c_name, label) in JOINT_DEFINITIONS.items():
            if (
                pt_a_name in landmarks_dict
                and pt_b_name in landmarks_dict
                and pt_c_name in landmarks_dict
            ):
                lm_a = landmarks_dict[pt_a_name]
                lm_b = landmarks_dict[pt_b_name]
                lm_c = landmarks_dict[pt_c_name]

                if lm_a["valid"] and lm_b["valid"] and lm_c["valid"]:
                    angle = calculate_angle(lm_a["pixel"], lm_b["pixel"], lm_c["pixel"])
                    angles_result[joint_key] = {
                        "angle": angle,
                        "vertex_px": lm_b["pixel"],
                        "label": label,
                        "valid": True,
                    }
                    continue

            # Caso não seja visível ou válido
            angles_result[joint_key] = {
                "angle": None,
                "vertex_px": None,
                "label": label,
                "valid": False,
            }

        return angles_result

