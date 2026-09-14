"""
motion_trail.py
Módulo para renderização de trilhas de movimento ("Comet Trail"), inspirado no demo running
do vision-demos. Desenha um rastro translúcido das articulações em movimento (fade out).
"""

from collections import deque
from typing import Dict, List, Optional, Tuple
import cv2
import numpy as np


class MotionTrail:
    """
    Mantém o histórico de coordenadas das articulações e renderiza
    efeito de cometa (trilha suave com desvanecimento translúcido).
    """

    def __init__(self, max_length: int = 24, enabled: bool = True):
        self.max_length = max_length
        self.enabled = enabled
        # Dicionário de deques para cada ponto rastreado: nome -> deque[(x, y)]
        self.trails: Dict[str, deque] = {}

        # Cores padrão para articulações principais (BGR)
        self.colors = {
            "LEFT_WRIST": (0, 255, 255),    # Amarelo/Ciano
            "RIGHT_WRIST": (255, 190, 0),   # Azul claro
            "LEFT_KNEE": (0, 230, 115),     # Verde neon
            "RIGHT_KNEE": (20, 240, 255),   # Amarelo elétrico
            "LEFT_ANKLE": (255, 105, 180),  # Rosa
            "RIGHT_ANKLE": (180, 105, 255), # Roxo/Lilás
        }

    def toggle(self) -> bool:
        self.enabled = not self.enabled
        if not self.enabled:
            self.clear()
        return self.enabled

    def clear(self):
        for d in self.trails.values():
            d.clear()

    def update(self, landmarks_dict: Dict[str, Dict]):
        """
        Atualiza as posições dos marcos com as coordenadas atuais.
        """
        if not self.enabled:
            return

        for name in self.colors.keys():
            if name not in self.trails:
                self.trails[name] = deque(maxlen=self.max_length)

            if name in landmarks_dict and landmarks_dict[name]["valid"]:
                px = landmarks_dict[name]["pixel"]
                self.trails[name].append(px)
            else:
                # Se não visível no frame atual, mantém o rastro encolhendo gradualmente
                if self.trails[name]:
                    self.trails[name].popleft()

    def draw(self, frame: np.ndarray) -> np.ndarray:
        """
        Desenha as trilhas sobre o frame com fade-out gradual e espessura dinâmica.
        """
        if not self.enabled:
            return frame

        overlay = frame.copy()
        has_elements = False

        for name, points in self.trails.items():
            n = len(points)
            if n < 2:
                continue

            has_elements = True
            base_color = self.colors.get(name, (0, 255, 255))

            for i in range(1, n):
                pt1 = points[i - 1]
                pt2 = points[i]

                # Fator de interpolação: 0 no início do rastro, 1 no ponto mais recente
                alpha_factor = i / float(n)

                # Espessura dinâmica decrescente para a cauda
                thickness = max(1, int(4 * alpha_factor))

                # Variação sutil de cor / brilho ao longo do rastro
                color = (
                    int(base_color[0] * alpha_factor),
                    int(base_color[1] * alpha_factor),
                    int(base_color[2] * alpha_factor),
                )

                cv2.line(overlay, pt1, pt2, color, thickness, cv2.LINE_AA)
                # Ponto brilhante no vértice da articulação
                if i == n - 1:
                    cv2.circle(overlay, pt2, 4, base_color, -1, cv2.LINE_AA)

        if has_elements:
            # Mistura suave do overlay com o frame original
            cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)

        return frame
