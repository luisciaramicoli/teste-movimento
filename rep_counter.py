"""
rep_counter.py
Módulo responsável pela contagem inteligente de repetições e análise de cadência
utilizando máquina de estados com histerese, inspirado no demo chin_ups do vision-demos.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple


class RepState(Enum):
    IDLE = "Aguardando"
    START_POSITION = "Posição Inicial"
    IN_PROGRESS = "Em Movimento"
    PEAK = "Pico Atingido"
    RETURNING = "Retornando"


@dataclass
class RepInfo:
    rep_number: int
    start_time: float
    peak_time: float
    end_time: float
    concentric_duration: float
    eccentric_duration: float
    total_duration: float
    min_angle: float
    max_angle: float
    rom: float
    is_valid: bool
    feedback: str


class ExerciseConfig:
    def __init__(
        self,
        name: str,
        display_name: str,
        target_joints: List[str],
        start_threshold: float,
        peak_threshold: float,
        invert: bool = True,  # True se o pico for um ângulo MENOR (ex: agachamento/flexão)
        instruction_start: str = "Assuma a posição inicial",
        instruction_down: str = "Flexione / Desça",
        instruction_up: str = "Estenda / Suba",
    ):
        self.name = name
        self.display_name = display_name
        self.target_joints = target_joints
        self.start_threshold = start_threshold
        self.peak_threshold = peak_threshold
        self.invert = invert
        self.instruction_start = instruction_start
        self.instruction_down = instruction_down
        self.instruction_up = instruction_up


EXERCISE_PRESETS: Dict[str, ExerciseConfig] = {
    "free": ExerciseConfig(
        name="free",
        display_name="Modo Livre (ROM Geral)",
        target_joints=[],
        start_threshold=0.0,
        peak_threshold=0.0,
        instruction_start="Movimente-se livremente para medir amplitudes",
    ),
    "squat": ExerciseConfig(
        name="squat",
        display_name="Agachamento (Squat)",
        target_joints=["joelho_esq", "joelho_dir"],
        start_threshold=155.0,  # Em pé (pernas estendidas)
        peak_threshold=95.0,    # Agachado (joelho a ~90°)
        invert=True,
        instruction_start="Fique em pé para iniciar",
        instruction_down="Agache até os joelhos ficarem a 90°",
        instruction_up="Suba de volta estendendo as pernas",
    ),
    "curl": ExerciseConfig(
        name="curl",
        display_name="Rosca Bíceps (Arm Curl)",
        target_joints=["cotovelo_esq", "cotovelo_dir"],
        start_threshold=145.0,  # Braço estendido
        peak_threshold=55.0,    # Braço flexionado no topo
        invert=True,
        instruction_start="Estenda os braços para iniciar",
        instruction_down="Flexione os cotovelos subindo o peso",
        instruction_up="Desça controladamente até estender",
    ),
    "chin_up": ExerciseConfig(
        name="chin_up",
        display_name="Barra / Puxada (Chin-up)",
        target_joints=["cotovelo_esq", "cotovelo_dir", "ombro_esq", "ombro_dir"],
        start_threshold=150.0,  # Suspenso na barra
        peak_threshold=60.0,    # Queixo passando a barra
        invert=True,
        instruction_start="Posicione-se suspenso na barra",
        instruction_down="Puxe o corpo até o queixo passar da barra",
        instruction_up="Desça de forma controlada",
    ),
    "calf_raise": ExerciseConfig(
        name="calf_raise",
        display_name="Elevação de Panturrilha (Calf Raise)",
        target_joints=["tornozelo_esq", "tornozelo_dir"],
        start_threshold=105.0,  # Calcanhar no chão
        peak_threshold=132.0,   # Na ponta dos pés (plantiflexão)
        invert=False,           # Pico é um ângulo MAIOR
        instruction_start="Apoie os calcanhares no solo para iniciar",
        instruction_down="Suba na ponta dos pés contraindo a panturrilha",
        instruction_up="Desça os calcanhares controladamente",
    ),
}


class ExerciseRepCounter:
    """
    Máquina de estados por histerese para detecção e temporização de repetições.
    """

    def __init__(self, exercise_name: str = "squat"):
        self.config = EXERCISE_PRESETS.get(exercise_name, EXERCISE_PRESETS["squat"])
        self.state = RepState.IDLE
        self.rep_count = 0
        self.reps_history: List[RepInfo] = []

        # Variáveis de rastreamento do ciclo atual
        self._rep_start_time: Optional[float] = None
        self._rep_peak_time: Optional[float] = None
        self._current_rep_angles: List[float] = []
        self._last_angle: Optional[float] = None
        self._reached_peak_target: bool = False

        # Feedback em tempo real
        self.feedback_message: str = self.config.instruction_start
        self.progress_pct: float = 0.0

    def set_exercise(self, exercise_name: str):
        if exercise_name in EXERCISE_PRESETS:
            self.config = EXERCISE_PRESETS[exercise_name]
            self.reset()

    def reset(self):
        self.state = RepState.IDLE
        self.rep_count = 0
        self.reps_history.clear()
        self._rep_start_time = None
        self._rep_peak_time = None
        self._current_rep_angles.clear()
        self._reached_peak_target = False
        self.feedback_message = self.config.instruction_start
        self.progress_pct = 0.0

    def _extract_primary_angle(self, angles_data: Dict[str, Dict]) -> Optional[float]:
        """
        Extrai a média dos ângulos válidos para os membros alvo do exercício.
        """
        if not self.config.target_joints:
            return None

        valid_angles = []
        for joint in self.config.target_joints:
            data = angles_data.get(joint)
            if data and data.get("valid") and data.get("angle") is not None:
                valid_angles.append(data["angle"])

        if valid_angles:
            return float(sum(valid_angles) / len(valid_angles))
        return None

    def update(self, angles_data: Dict[str, Dict], timestamp: float) -> Optional[RepInfo]:
        """
        Processa o frame atual e atualiza a máquina de estados.
        Retorna RepInfo caso uma repetição tenha acabado de ser completada.
        """
        if self.config.name == "free":
            self.progress_pct = 0.0
            self.feedback_message = "Medição livre de amplitude"
            return None

        angle = self._extract_primary_angle(angles_data)
        if angle is None:
            return None

        self._last_angle = angle
        completed_rep: Optional[RepInfo] = None

        # Cálculo da porcentagem de progresso da repetição [0.0 a 1.0]
        start_th = self.config.start_threshold
        peak_th = self.config.peak_threshold

        if self.config.invert:
            # ex: start=160, peak=90. Ângulos decrescem conforme progride
            total_span = max(1.0, start_th - peak_th)
            prog = (start_th - angle) / total_span
        else:
            total_span = max(1.0, peak_th - start_th)
            prog = (angle - start_th) / total_span

        self.progress_pct = max(0.0, min(1.0, float(prog)))

        # Lógica da Máquina de Estados por Histerese
        if self.state == RepState.IDLE or self.state == RepState.START_POSITION:
            is_at_start = (angle >= start_th - 5.0) if self.config.invert else (angle <= start_th + 5.0)
            if is_at_start:
                self.state = RepState.START_POSITION
                self.feedback_message = "Pronto! Comece o movimento."
            else:
                # Se começou a mover saindo da posição inicial
                if self.progress_pct > 0.20:
                    self.state = RepState.IN_PROGRESS
                    self._rep_start_time = timestamp
                    self._current_rep_angles = [angle]
                    self._reached_peak_target = False
                    self.feedback_message = self.config.instruction_down

        elif self.state == RepState.IN_PROGRESS:
            self._current_rep_angles.append(angle)

            # Verifica se atingiu o limiar de pico
            reached_peak = (angle <= peak_th) if self.config.invert else (angle >= peak_th)
            if reached_peak:
                self.state = RepState.PEAK
                self._rep_peak_time = timestamp
                self._reached_peak_target = True
                self.feedback_message = "Pico atingido! Boa amplitude! ✅"
            else:
                if self.progress_pct > 0.70:
                    self.feedback_message = "Quase lá, complete a amplitude!"
                else:
                    self.feedback_message = self.config.instruction_down

        elif self.state == RepState.PEAK:
            self._current_rep_angles.append(angle)
            # Usuário começa a retornar
            started_returning = (angle > peak_th + 8.0) if self.config.invert else (angle < peak_th - 8.0)
            if started_returning:
                self.state = RepState.RETURNING
                self.feedback_message = self.config.instruction_up

        elif self.state == RepState.RETURNING:
            self._current_rep_angles.append(angle)

            # Chegou de volta à posição inicial (repetição completa!)
            returned_to_start = (angle >= start_th - 8.0) if self.config.invert else (angle <= start_th + 8.0)
            if returned_to_start:
                end_time = timestamp
                start_time = self._rep_start_time if self._rep_start_time is not None else end_time - 1.0
                peak_time = self._rep_peak_time if self._rep_peak_time is not None else (start_time + end_time) / 2.0

                concentric = max(0.1, peak_time - start_time)
                eccentric = max(0.1, end_time - peak_time)
                total_dur = concentric + eccentric

                min_a = min(self._current_rep_angles) if self._current_rep_angles else angle
                max_a = max(self._current_rep_angles) if self._current_rep_angles else angle
                rom = round(max_a - min_a, 1)

                is_valid = self._reached_peak_target

                # Avaliação de qualidade / feedback
                if not is_valid:
                    fb = "Amplitude incompleta! Desça mais na próxima."
                elif total_dur < 1.0:
                    fb = "Repetição muito rápida! Controle a descida."
                else:
                    fb = "Excelente repetição! Ritmo perfeito. 🔥"

                self.rep_count += 1
                completed_rep = RepInfo(
                    rep_number=self.rep_count,
                    start_time=round(start_time, 2),
                    peak_time=round(peak_time, 2),
                    end_time=round(end_time, 2),
                    concentric_duration=round(concentric, 2),
                    eccentric_duration=round(eccentric, 2),
                    total_duration=round(total_dur, 2),
                    min_angle=round(min_a, 1),
                    max_angle=round(max_a, 1),
                    rom=rom,
                    is_valid=is_valid,
                    feedback=fb,
                )

                self.reps_history.append(completed_rep)
                self.feedback_message = f"Rep {self.rep_count} feita! ({total_dur:.1f}s) - {fb}"

                # Reinicia ciclo
                self.state = RepState.START_POSITION
                self._rep_start_time = None
                self._rep_peak_time = None
                self._current_rep_angles.clear()
                self._reached_peak_target = False

        return completed_rep

    @property
    def cadence_rpm(self) -> float:
        """
        Calcula a cadência recente em repetições por minuto (RPM).
        """
        if len(self.reps_history) < 2:
            return 0.0
        # Considera as últimas repetições (até 5)
        recent = self.reps_history[-5:]
        total_time = recent[-1].end_time - recent[0].start_time
        if total_time <= 0.5:
            return 0.0
        return round((len(recent) / total_time) * 60.0, 1)

    @property
    def average_rep_duration(self) -> float:
        if not self.reps_history:
            return 0.0
        return round(sum(r.total_duration for r in self.reps_history) / len(self.reps_history), 2)

