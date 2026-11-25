"""
protocol_evaluator.py
Módulo responsável pelo Protocolo de Posicionamento de Câmera (distância, centralização,
angulação/orientação 3D e visibilidade completa incluindo calcanhares) e pela avaliação
de Posturas de Exemplo para replicação em tempo real.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
import math


@dataclass
class AngleTarget:
    joint_key: str
    label: str
    target_angle: float
    tolerance: float = 18.0

    def is_within_range(self, angle: float) -> bool:
        return (self.target_angle - self.tolerance) <= angle <= (self.target_angle + self.tolerance)

    def score_for_angle(self, angle: float) -> float:
        diff = abs(angle - self.target_angle)
        if diff <= self.tolerance:
            return 1.0
        excess = diff - self.tolerance
        return max(0.0, min(1.0, 1.0 - (excess / 45.0)))


@dataclass
class ProtocolPostureModel:
    id: str
    title: str
    badge: str
    instruction: str
    recommended_view: str
    target_angles: Dict[str, AngleTarget]
    guide_landmarks_norm: Dict[str, Tuple[float, float]]
    min_calf_elevation_pct: Optional[float] = None
    hold_duration_sec: float = 2.5


@dataclass
class PositioningCheckResult:
    is_distance_good: bool
    distance_status: str
    distance_message: str
    body_height_ratio: float
    is_centered: bool
    horizontal_offset: float
    horizontal_message: str
    is_angle_good: bool
    trunk_tilt_deg: float
    body_orientation_angle: float
    body_orientation_label: str
    angle_message: str
    are_all_points_visible: bool
    missing_parts: List[str]
    visibility_message: str
    hold_progress: float = 0.0

    @property
    def is_all_good(self) -> bool:
        return (
            self.is_distance_good
            and self.is_centered
            and self.is_angle_good
            and self.are_all_points_visible
        )

    @property
    def primary_guidance(self) -> str:
        if not self.are_all_points_visible:
            return self.visibility_message
        if not self.is_distance_good:
            return self.distance_message
        if not self.is_centered:
            return self.horizontal_message
        if not self.is_angle_good:
            return self.angle_message
        return "Posicao perfeita! Mantenha-se parado para iniciar..."


DEFAULT_PROTOCOL_POSTURES: List[ProtocolPostureModel] = [
    ProtocolPostureModel(
        id="ortostatica",
        title="1. Posicao Neutra (Ortostatica)",
        badge="MODELO TESTE 1/5",
        instruction="Fique em pe, corpo ereto, bracos relaxados e calcanhares apoiados no chao.",
        recommended_view="Frontal (0-30°)",
        target_angles={
            "ombro_esq": AngleTarget("ombro_esq", "Ombro E.", 20.0, 18.0),
            "ombro_dir": AngleTarget("ombro_dir", "Ombro D.", 20.0, 18.0),
            "cotovelo_esq": AngleTarget("cotovelo_esq", "Cotovelo E.", 168.0, 20.0),
            "cotovelo_dir": AngleTarget("cotovelo_dir", "Cotovelo D.", 168.0, 20.0),
            "quadril_esq": AngleTarget("quadril_esq", "Quadril E.", 172.0, 15.0),
            "quadril_dir": AngleTarget("quadril_dir", "Quadril D.", 172.0, 15.0),
            "joelho_esq": AngleTarget("joelho_esq", "Joelho E.", 174.0, 14.0),
            "joelho_dir": AngleTarget("joelho_dir", "Joelho D.", 174.0, 14.0),
        },
        guide_landmarks_norm={
            "NOSE": (0.50, 0.14),
            "LEFT_SHOULDER": (0.39, 0.25),
            "RIGHT_SHOULDER": (0.61, 0.25),
            "LEFT_ELBOW": (0.36, 0.39),
            "RIGHT_ELBOW": (0.64, 0.39),
            "LEFT_WRIST": (0.35, 0.52),
            "RIGHT_WRIST": (0.65, 0.52),
            "LEFT_HIP": (0.43, 0.52),
            "RIGHT_HIP": (0.57, 0.52),
            "LEFT_KNEE": (0.43, 0.71),
            "RIGHT_KNEE": (0.57, 0.71),
            "LEFT_ANKLE": (0.43, 0.88),
            "RIGHT_ANKLE": (0.57, 0.88),
            "LEFT_HEEL": (0.44, 0.91),
            "RIGHT_HEEL": (0.56, 0.91),
            "LEFT_FOOT_INDEX": (0.40, 0.92),
            "RIGHT_FOOT_INDEX": (0.60, 0.92),
        },
    ),
    ProtocolPostureModel(
        id="bracos_t",
        title="2. Abducao de Ombros (Bracos em T)",
        badge="MODELO TESTE 2/5",
        instruction="Abra os dois bracos lateralmente na altura dos ombros (90°) com cotovelos estendidos.",
        recommended_view="Frontal (0-30°)",
        target_angles={
            "ombro_esq": AngleTarget("ombro_esq", "Ombro E.", 90.0, 18.0),
            "ombro_dir": AngleTarget("ombro_dir", "Ombro D.", 90.0, 18.0),
            "cotovelo_esq": AngleTarget("cotovelo_esq", "Cotovelo E.", 170.0, 18.0),
            "cotovelo_dir": AngleTarget("cotovelo_dir", "Cotovelo D.", 170.0, 18.0),
            "joelho_esq": AngleTarget("joelho_esq", "Joelho E.", 172.0, 15.0),
            "joelho_dir": AngleTarget("joelho_dir", "Joelho D.", 172.0, 15.0),
        },
        guide_landmarks_norm={
            "NOSE": (0.50, 0.14),
            "LEFT_SHOULDER": (0.39, 0.25),
            "RIGHT_SHOULDER": (0.61, 0.25),
            "LEFT_ELBOW": (0.24, 0.25),
            "RIGHT_ELBOW": (0.76, 0.25),
            "LEFT_WRIST": (0.10, 0.25),
            "RIGHT_WRIST": (0.90, 0.25),
            "LEFT_HIP": (0.43, 0.52),
            "RIGHT_HIP": (0.57, 0.52),
            "LEFT_KNEE": (0.43, 0.71),
            "RIGHT_KNEE": (0.57, 0.71),
            "LEFT_ANKLE": (0.43, 0.88),
            "RIGHT_ANKLE": (0.57, 0.88),
            "LEFT_HEEL": (0.44, 0.91),
            "RIGHT_HEEL": (0.56, 0.91),
            "LEFT_FOOT_INDEX": (0.40, 0.92),
            "RIGHT_FOOT_INDEX": (0.60, 0.92),
        },
    ),
    ProtocolPostureModel(
        id="elevacao_panturrilha",
        title="3. Elevacao de Panturrilha (Ponta dos Pes)",
        badge="MODELO TESTE 3/5",
        instruction="Suba na ponta dos pes elevando os calcanhares ao maximo! Mantenha joelhos estendidos.",
        recommended_view="Diagonal ou Perfil (25-85°)",
        min_calf_elevation_pct=22.0,
        target_angles={
            "tornozelo_esq": AngleTarget("tornozelo_esq", "Tornozelo E.", 132.0, 24.0),
            "tornozelo_dir": AngleTarget("tornozelo_dir", "Tornozelo D.", 132.0, 24.0),
            "joelho_esq": AngleTarget("joelho_esq", "Joelho E.", 170.0, 16.0),
            "joelho_dir": AngleTarget("joelho_dir", "Joelho D.", 170.0, 16.0),
        },
        guide_landmarks_norm={
            "NOSE": (0.50, 0.11),
            "LEFT_SHOULDER": (0.41, 0.22),
            "RIGHT_SHOULDER": (0.59, 0.22),
            "LEFT_ELBOW": (0.34, 0.34),
            "RIGHT_ELBOW": (0.66, 0.34),
            "LEFT_WRIST": (0.41, 0.44),
            "RIGHT_WRIST": (0.59, 0.44),
            "LEFT_HIP": (0.44, 0.49),
            "RIGHT_HIP": (0.56, 0.49),
            "LEFT_KNEE": (0.44, 0.68),
            "RIGHT_KNEE": (0.56, 0.68),
            "LEFT_ANKLE": (0.44, 0.84),
            "RIGHT_ANKLE": (0.56, 0.84),
            "LEFT_HEEL": (0.46, 0.86),
            "RIGHT_HEEL": (0.58, 0.86),
            "LEFT_FOOT_INDEX": (0.40, 0.92),
            "RIGHT_FOOT_INDEX": (0.52, 0.92),
        },
    ),
    ProtocolPostureModel(
        id="agachamento_iso",
        title="4. Agachamento Isometrico (90-110°)",
        badge="MODELO TESTE 4/5",
        instruction="Flexione joelhos e quadril (~105°), mantendo calcanhares no chao e bracos a frente.",
        recommended_view="Diagonal ou Frontal",
        target_angles={
            "joelho_esq": AngleTarget("joelho_esq", "Joelho E.", 105.0, 20.0),
            "joelho_dir": AngleTarget("joelho_dir", "Joelho D.", 105.0, 20.0),
            "quadril_esq": AngleTarget("quadril_esq", "Quadril E.", 105.0, 22.0),
            "quadril_dir": AngleTarget("quadril_dir", "Quadril D.", 105.0, 22.0),
            "ombro_esq": AngleTarget("ombro_esq", "Ombro E.", 85.0, 25.0),
            "ombro_dir": AngleTarget("ombro_dir", "Ombro D.", 85.0, 25.0),
        },
        guide_landmarks_norm={
            "NOSE": (0.50, 0.24),
            "LEFT_SHOULDER": (0.40, 0.35),
            "RIGHT_SHOULDER": (0.60, 0.35),
            "LEFT_ELBOW": (0.32, 0.38),
            "RIGHT_ELBOW": (0.68, 0.38),
            "LEFT_WRIST": (0.26, 0.36),
            "RIGHT_WRIST": (0.74, 0.36),
            "LEFT_HIP": (0.43, 0.60),
            "RIGHT_HIP": (0.57, 0.60),
            "LEFT_KNEE": (0.37, 0.74),
            "RIGHT_KNEE": (0.63, 0.74),
            "LEFT_ANKLE": (0.43, 0.89),
            "RIGHT_ANKLE": (0.57, 0.89),
            "LEFT_HEEL": (0.45, 0.91),
            "RIGHT_HEEL": (0.55, 0.91),
            "LEFT_FOOT_INDEX": (0.39, 0.92),
            "RIGHT_FOOT_INDEX": (0.61, 0.92),
        },
    ),
    ProtocolPostureModel(
        id="duplo_biceps",
        title="5. Bracos em W (90° / 90°)",
        badge="MODELO TESTE 5/5",
        instruction="Eleve os ombros a 90° e flexione os cotovelos a 90° apontando as maos para cima.",
        recommended_view="Frontal (0-30°)",
        target_angles={
            "ombro_esq": AngleTarget("ombro_esq", "Ombro E.", 90.0, 18.0),
            "ombro_dir": AngleTarget("ombro_dir", "Ombro D.", 90.0, 18.0),
            "cotovelo_esq": AngleTarget("cotovelo_esq", "Cotovelo E.", 90.0, 18.0),
            "cotovelo_dir": AngleTarget("cotovelo_dir", "Cotovelo D.", 90.0, 18.0),
            "joelho_esq": AngleTarget("joelho_esq", "Joelho E.", 172.0, 15.0),
            "joelho_dir": AngleTarget("joelho_dir", "Joelho D.", 172.0, 15.0),
        },
        guide_landmarks_norm={
            "NOSE": (0.50, 0.14),
            "LEFT_SHOULDER": (0.39, 0.25),
            "RIGHT_SHOULDER": (0.61, 0.25),
            "LEFT_ELBOW": (0.24, 0.25),
            "RIGHT_ELBOW": (0.76, 0.25),
            "LEFT_WRIST": (0.24, 0.13),
            "RIGHT_WRIST": (0.76, 0.13),
            "LEFT_HIP": (0.43, 0.52),
            "RIGHT_HIP": (0.57, 0.52),
            "LEFT_KNEE": (0.43, 0.71),
            "RIGHT_KNEE": (0.57, 0.71),
            "LEFT_ANKLE": (0.43, 0.88),
            "RIGHT_ANKLE": (0.57, 0.88),
            "LEFT_HEEL": (0.44, 0.91),
            "RIGHT_HEEL": (0.56, 0.91),
            "LEFT_FOOT_INDEX": (0.40, 0.92),
            "RIGHT_FOOT_INDEX": (0.60, 0.92),
        },
    ),
]


class ProtocolEvaluator:
    """
    Gerencia o protocolo guiado em etapas no módulo Python:
    - Etapa 'positioning': verifica distância, centralização, angulação e visibilidade dos calcanhares
    - Etapa 'posture_replication': guia o usuário pelas 5 posturas de exemplo com silhueta-guia
    - Etapa 'completed' / 'free': concluído ou modo livre
    """

    def __init__(self, enabled: bool = True):
        self.postures = DEFAULT_PROTOCOL_POSTURES
        self.stage = "positioning" if enabled else "free"
        self.current_posture_idx = 0
        self.positioning_result: Optional[PositioningCheckResult] = None
        self.posture_accuracy_pct: float = 0.0
        self.posture_hold_progress: float = 0.0
        self.joint_feedbacks: Dict[str, Dict] = {}
        self.completed_postures: List[Dict] = []

        self._pos_good_start: Optional[float] = None
        self._posture_hold_start: Optional[float] = None
        self.positioning_hold_sec = 2.0

    @property
    def current_posture(self) -> ProtocolPostureModel:
        idx = max(0, min(self.current_posture_idx, len(self.postures) - 1))
        return self.postures[idx]

    def reset(self):
        self.stage = "positioning"
        self.current_posture_idx = 0
        self.posture_accuracy_pct = 0.0
        self.posture_hold_progress = 0.0
        self.joint_feedbacks.clear()
        self.completed_postures.clear()
        self._pos_good_start = None
        self._posture_hold_start = None

    def toggle_protocol_mode(self) -> str:
        if self.stage == "free":
            self.stage = "positioning"
            self._pos_good_start = None
        else:
            self.stage = "free"
        return self.stage

    def next_posture(self):
        self._posture_hold_start = None
        self.posture_hold_progress = 0.0
        if self.stage == "positioning":
            self.stage = "posture_replication"
            return
        if self.current_posture_idx < len(self.postures) - 1:
            self.current_posture_idx += 1
            self.stage = "posture_replication"
        else:
            self.stage = "completed"

    def evaluate_positioning(
        self,
        landmarks_dict: Dict[str, Dict],
        frame_shape: Tuple[int, int, int],
        calf_and_orient: Dict[str, object],
        timestamp: float,
    ) -> PositioningCheckResult:
        h, w, _ = frame_shape
        valid_lms = {k: v for k, v in landmarks_dict.items() if v.get("valid")}

        has_head_torso = all(
            k in valid_lms for k in ("NOSE", "LEFT_SHOULDER", "RIGHT_SHOULDER", "LEFT_HIP", "RIGHT_HIP")
        )
        has_arms = all(
            k in valid_lms for k in ("LEFT_ELBOW", "RIGHT_ELBOW", "LEFT_WRIST", "RIGHT_WRIST")
        )
        has_legs = all(
            k in valid_lms for k in ("LEFT_KNEE", "RIGHT_KNEE", "LEFT_ANKLE", "RIGHT_ANKLE")
        )
        has_heels = (
            ("LEFT_HEEL" in valid_lms or "LEFT_FOOT_INDEX" in valid_lms)
            and ("RIGHT_HEEL" in valid_lms or "RIGHT_FOOT_INDEX" in valid_lms)
        )

        missing = []
        if not has_head_torso:
            missing.append("Cabeca/Tronco")
        if not has_arms:
            missing.append("Bracos")
        if not has_legs:
            missing.append("Joelhos/Tornozelos")
        if not has_heels:
            missing.append("Calcanhares/Pes")

        are_all_visible = len(missing) == 0
        vis_msg = (
            "Corpo inteiro e calcanhares visiveis [OK]"
            if are_all_visible
            else f"Enquadre na camera: {', '.join(missing)}"
        )

        if not valid_lms:
            return PositioningCheckResult(
                is_distance_good=False,
                distance_status="no_person",
                distance_message="Posicione-se em frente a camera",
                body_height_ratio=0.0,
                is_centered=False,
                horizontal_offset=0.0,
                horizontal_message="Centralize-se no quadro",
                is_angle_good=False,
                trunk_tilt_deg=0.0,
                body_orientation_angle=0.0,
                body_orientation_label="--",
                angle_message="Aguardando deteccao",
                are_all_points_visible=False,
                missing_parts=missing,
                visibility_message=vis_msg,
            )

        ys = [v["pixel"][1] for v in valid_lms.values()]
        min_y = float(min(ys))
        max_y = float(max(ys))

        if "NOSE" in valid_lms and "LEFT_SHOULDER" in valid_lms and "RIGHT_SHOULDER" in valid_lms:
            ny = valid_lms["NOSE"]["pixel"][1]
            msy = (valid_lms["LEFT_SHOULDER"]["pixel"][1] + valid_lms["RIGHT_SHOULDER"]["pixel"][1]) / 2.0
            head_top = ny - (msy - ny) * 0.65
            min_y = min(min_y, head_top)

        body_ratio = max(0.0, min(1.0, (max_y - min_y) / max(1.0, float(h))))
        clipped_top = min_y < h * 0.03
        clipped_bottom = max_y > h * 0.95

        if not has_legs or not has_heels or clipped_top or clipped_bottom or body_ratio > 0.89:
            is_dist_good = False
            dist_status = "too_close"
            dist_msg = "Muito perto! Afaste-se para mostrar dos pes a cabeca"
        elif body_ratio < 0.44:
            is_dist_good = False
            dist_status = "too_far"
            dist_msg = "Muito longe! Aproxime-se um pouco da camera"
        else:
            is_dist_good = True
            dist_status = "optimal"
            dist_msg = f"Distancia ideal ({int(body_ratio * 100)}% do quadro) [OK]"

        # Centralização
        if has_head_torso:
            mid_x = (
                valid_lms["LEFT_SHOULDER"]["pixel"][0]
                + valid_lms["RIGHT_SHOULDER"]["pixel"][0]
                + valid_lms["LEFT_HIP"]["pixel"][0]
                + valid_lms["RIGHT_HIP"]["pixel"][0]
            ) / 4.0
            cx_norm = mid_x / max(1.0, float(w))
        else:
            xs = [v["pixel"][0] for v in valid_lms.values()]
            cx_norm = (sum(xs) / len(xs)) / max(1.0, float(w))

        horiz_offset = cx_norm - 0.5
        is_centered = abs(horiz_offset) <= 0.18
        if horiz_offset < -0.18:
            horiz_msg = "Mova-se um pouco para a DIREITA ->"
        elif horiz_offset > 0.18:
            horiz_msg = "<- Mova-se um pouco para a ESQUERDA"
        else:
            horiz_msg = "Centralizado no quadro [OK]"

        # Inclinação vertical do tronco
        trunk_tilt = 0.0
        if has_head_torso:
            msx = (valid_lms["LEFT_SHOULDER"]["pixel"][0] + valid_lms["RIGHT_SHOULDER"]["pixel"][0]) / 2.0
            msy = (valid_lms["LEFT_SHOULDER"]["pixel"][1] + valid_lms["RIGHT_SHOULDER"]["pixel"][1]) / 2.0
            mhx = (valid_lms["LEFT_HIP"]["pixel"][0] + valid_lms["RIGHT_HIP"]["pixel"][0]) / 2.0
            mhy = (valid_lms["LEFT_HIP"]["pixel"][1] + valid_lms["RIGHT_HIP"]["pixel"][1]) / 2.0
            trunk_tilt = math.degrees(math.atan2(abs(msx - mhx), max(1.0, abs(mhy - msy))))

        orient_angle = float(calf_and_orient.get("body_orientation_angle", 0.0))
        orient_label = str(calf_and_orient.get("body_orientation_label", "Frontal"))
        is_angle_good = trunk_tilt <= 16.0
        angle_msg = (
            f"Angulacao OK: {orient_label} ({int(orient_angle)}°) [OK]"
            if is_angle_good
            else f"Alinhe a coluna verticalmente (inclinacao: {int(trunk_tilt)}°)"
        )

        res = PositioningCheckResult(
            is_distance_good=is_dist_good,
            distance_status=dist_status,
            distance_message=dist_msg,
            body_height_ratio=round(body_ratio, 2),
            is_centered=is_centered,
            horizontal_offset=round(horiz_offset, 2),
            horizontal_message=horiz_msg,
            is_angle_good=is_angle_good,
            trunk_tilt_deg=round(trunk_tilt, 1),
            body_orientation_angle=orient_angle,
            body_orientation_label=orient_label,
            angle_message=angle_msg,
            are_all_points_visible=are_all_visible,
            missing_parts=missing,
            visibility_message=vis_msg,
        )

        if self.stage == "positioning":
            if res.is_all_good:
                if self._pos_good_start is None:
                    self._pos_good_start = timestamp
                held = timestamp - self._pos_good_start
                res.hold_progress = max(0.0, min(1.0, held / self.positioning_hold_sec))
                if res.hold_progress >= 1.0:
                    self.stage = "posture_replication"
                    self._pos_good_start = None
            else:
                self._pos_good_start = None

        self.positioning_result = res
        return res

    def update(
        self,
        landmarks_dict: Dict[str, Dict],
        angles_data: Dict[str, Dict],
        calf_and_orient: Dict[str, object],
        frame_shape: Tuple[int, int, int],
        timestamp: float,
    ):
        self.evaluate_positioning(landmarks_dict, frame_shape, calf_and_orient, timestamp)

        if self.stage == "posture_replication":
            posture = self.current_posture
            total_score = 0.0
            count = 0
            feedbacks = {}

            for j_key, target in posture.target_angles.items():
                count += 1
                j_info = angles_data.get(j_key, {})
                ang = j_info.get("angle") if j_info.get("valid") else None
                if ang is None:
                    feedbacks[j_key] = {
                        "label": target.label,
                        "current": None,
                        "target": target.target_angle,
                        "matched": False,
                    }
                else:
                    matched = target.is_within_range(ang)
                    total_score += target.score_for_angle(ang)
                    feedbacks[j_key] = {
                        "label": target.label,
                        "current": ang,
                        "target": target.target_angle,
                        "matched": matched,
                    }

            if posture.min_calf_elevation_pct is not None:
                count += 1
                max_calf = float(calf_and_orient.get("max_calf_elevation_pct", 0.0))
                total_score += max(0.0, min(1.0, max_calf / posture.min_calf_elevation_pct))

            self.joint_feedbacks = feedbacks
            self.posture_accuracy_pct = round((total_score / max(1, count)) * 100.0, 1)

            if self.posture_accuracy_pct >= 75.0:
                if self._posture_hold_start is None:
                    self._posture_hold_start = timestamp
                held = timestamp - self._posture_hold_start
                self.posture_hold_progress = max(0.0, min(1.0, held / posture.hold_duration_sec))
                if self.posture_hold_progress >= 1.0:
                    self.completed_postures.append(
                        {
                            "id": posture.id,
                            "title": posture.title,
                            "accuracy": self.posture_accuracy_pct,
                            "calf_pct": calf_and_orient.get("max_calf_elevation_pct", 0.0),
                        }
                    )
                    self.next_posture()
            else:
                self._posture_hold_start = None
                self.posture_hold_progress = 0.0
