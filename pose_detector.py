"""
pose_detector.py
Módulo responsável pela detecção de articulações do corpo humano utilizando MediaPipe Pose
(compatível com MediaPipe Tasks API moderna e MediaPipe Solutions clássico), cálculo angular
de 10 articulações (incluindo Tornozelo/Panturrilha com Calcanhar e Ponta do Pé) e métricas de
elevação da panturrilha e orientação corporal 3D/2D.
"""

from typing import Dict, List, Optional, Tuple
import math
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


# Índices padrão de marcos anatômicos do MediaPipe Pose (33 pontos BlazePose)
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
    "LEFT_HEEL": 29,
    "RIGHT_HEEL": 30,
    "LEFT_FOOT_INDEX": 31,
    "RIGHT_FOOT_INDEX": 32,
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
    "tornozelo_esq": ("LEFT_KNEE", "LEFT_HEEL", "LEFT_FOOT_INDEX", "Tornozelo / Panturrilha Esq."),
    "tornozelo_dir": ("RIGHT_KNEE", "RIGHT_HEEL", "RIGHT_FOOT_INDEX", "Tornozelo / Panturrilha Dir."),
}

MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"


class PoseDetector:
    """
    Detector de pose baseado no MediaPipe Pose (33 pontos).
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

            if not os.path.exists(model_path):
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
        self, results, frame_shape: Tuple[int, int, int], min_visibility: float = 0.45
    ) -> Dict[str, Dict]:
        """
        Extrai as coordenadas em pixels, coordenada Z e a visibilidade de cada marco anatômico relevante.
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
                # Tolerância ligeiramente menor para calcanhar e ponta do pé
                threshold = min_visibility * 0.8 if ("HEEL" in name or "FOOT" in name) else min_visibility
                is_valid = (vis is None) or (vis >= threshold)

                px_x = int(lm.x * w)
                px_y = int(lm.y * h)
                z_val = float(getattr(lm, "z", 0.0))

                landmarks_dict[name] = {
                    "pixel": (px_x, px_y),
                    "normalized": (lm.x, lm.y),
                    "z": z_val,
                    "visibility": vis,
                    "valid": is_valid,
                }

        return landmarks_dict

    def calculate_all_joint_angles(
        self, landmarks_dict: Dict[str, Dict]
    ) -> Dict[str, Dict]:
        """
        Calcula os ângulos de todas as 10 articulações definidas se os três pontos forem válidos.
        """
        angles_result = {}

        for joint_key, (pt_a_name, pt_b_name, pt_c_name, label) in JOINT_DEFINITIONS.items():
            actual_b_name = pt_b_name
            # Fallback para ANKLE caso HEEL não esteja válido no frame
            if joint_key == "tornozelo_esq" and (
                "LEFT_HEEL" not in landmarks_dict or not landmarks_dict["LEFT_HEEL"].get("valid")
            ):
                actual_b_name = "LEFT_ANKLE"
            elif joint_key == "tornozelo_dir" and (
                "RIGHT_HEEL" not in landmarks_dict or not landmarks_dict["RIGHT_HEEL"].get("valid")
            ):
                actual_b_name = "RIGHT_ANKLE"

            if (
                pt_a_name in landmarks_dict
                and actual_b_name in landmarks_dict
                and pt_c_name in landmarks_dict
            ):
                lm_a = landmarks_dict[pt_a_name]
                lm_b = landmarks_dict[actual_b_name]
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

            angles_result[joint_key] = {
                "angle": None,
                "vertex_px": None,
                "label": label,
                "valid": False,
            }

        return angles_result

    def calculate_calf_and_orientation_metrics(
        self, landmarks_dict: Dict[str, Dict], angles_result: Dict[str, Dict]
    ) -> Dict[str, object]:
        """
        Calcula a porcentagem de elevação da panturrilha (subida do calcanhar em relação à ponta do pé)
        e estima o ângulo de orientação corporal 3D/2D (Frontal, Diagonal, Perfil).
        """
        def _side_calf_pct(knee_k: str, ankle_k: str, heel_k: str, foot_k: str, angle_k: str) -> float:
            v_score = 0.0
            a_score = 0.0
            if (
                knee_k in landmarks_dict and landmarks_dict[knee_k].get("valid")
                and ankle_k in landmarks_dict and landmarks_dict[ankle_k].get("valid")
                and heel_k in landmarks_dict and landmarks_dict[heel_k].get("valid")
                and foot_k in landmarks_dict and landmarks_dict[foot_k].get("valid")
            ):
                kx, ky = landmarks_dict[knee_k]["pixel"]
                ax, ay = landmarks_dict[ankle_k]["pixel"]
                hx, hy = landmarks_dict[heel_k]["pixel"]
                fx, fy = landmarks_dict[foot_k]["pixel"]
                tibia_len = max(25.0, math.hypot(kx - ax, ky - ay))
                heel_lift_px = float(fy - hy)
                v_score = max(0.0, min(1.0, heel_lift_px / (tibia_len * 0.18))) * 100.0

            ang_data = angles_result.get(angle_k)
            if ang_data and ang_data.get("valid") and ang_data.get("angle") is not None:
                a_score = max(0.0, min(1.0, (ang_data["angle"] - 105.0) / 40.0)) * 100.0

            return round(max(v_score, v_score * 0.6 + a_score * 0.4), 1)

        calf_left = _side_calf_pct("LEFT_KNEE", "LEFT_ANKLE", "LEFT_HEEL", "LEFT_FOOT_INDEX", "tornozelo_esq")
        calf_right = _side_calf_pct("RIGHT_KNEE", "RIGHT_ANKLE", "RIGHT_HEEL", "RIGHT_FOOT_INDEX", "tornozelo_dir")

        # Orientação corporal
        yaw_deg = 0.0
        yaw_label = "Frontal"
        if (
            "LEFT_SHOULDER" in landmarks_dict and landmarks_dict["LEFT_SHOULDER"].get("valid")
            and "RIGHT_SHOULDER" in landmarks_dict and landmarks_dict["RIGHT_SHOULDER"].get("valid")
            and "LEFT_HIP" in landmarks_dict and landmarks_dict["LEFT_HIP"].get("valid")
            and "RIGHT_HIP" in landmarks_dict and landmarks_dict["RIGHT_HIP"].get("valid")
        ):
            ls = landmarks_dict["LEFT_SHOULDER"]
            rs = landmarks_dict["RIGHT_SHOULDER"]
            lh = landmarks_dict["LEFT_HIP"]
            rh = landmarks_dict["RIGHT_HIP"]

            shoulder_w = abs(ls["pixel"][0] - rs["pixel"][0])
            mid_sy = (ls["pixel"][1] + rs["pixel"][1]) / 2.0
            mid_hy = (lh["pixel"][1] + rh["pixel"][1]) / 2.0
            torso_h = max(20.0, abs(mid_hy - mid_sy))

            ratio = max(0.0, min(1.0, shoulder_w / (torso_h * 0.72)))
            angle_2d = math.degrees(math.acos(ratio))
            dz = abs(ls.get("z", 0.0) - rs.get("z", 0.0))
            angle_3d = math.degrees(math.atan2(dz, max(0.05, abs(ls["normalized"][0] - rs["normalized"][0]))))
            yaw_deg = round(max(0.0, min(90.0, angle_2d * 0.7 + angle_3d * 0.3)), 1)

            if yaw_deg < 25.0:
                yaw_label = "Frontal"
            elif yaw_deg < 60.0:
                yaw_label = "Diagonal"
            else:
                yaw_label = "Perfil"

        return {
            "calf_elevation_left_pct": calf_left,
            "calf_elevation_right_pct": calf_right,
            "max_calf_elevation_pct": max(calf_left, calf_right),
            "body_orientation_angle": yaw_deg,
            "body_orientation_label": yaw_label,
        }
