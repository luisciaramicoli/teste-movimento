"""
tracker.py
Módulo responsável por registrar o histórico de ângulos articulares ao longo do tempo,
computar estatísticas de Amplitude de Movimento (ROM - Range of Motion: mín, máx, média)
e exportar os dados para análise posterior.
"""

import csv
from typing import Dict, List, Optional
import numpy as np


class JointRecord:
    """
    Mantém o histórico e estatísticas de uma articulação específica.
    """

    def __init__(self, key: str, label: str):
        self.key = key
        self.label = label
        self.current_angle: Optional[float] = None
        self.min_angle: Optional[float] = None
        self.max_angle: Optional[float] = None
        self.timestamps: List[float] = []
        self.angles: List[float] = []

    def update(self, angle: float, timestamp: float):
        """
        Registra um novo valor de ângulo para a articulação.
        """
        self.current_angle = angle
        self.timestamps.append(timestamp)
        self.angles.append(angle)

        if self.min_angle is None or angle < self.min_angle:
            self.min_angle = angle

        if self.max_angle is None or angle > self.max_angle:
            self.max_angle = angle

    def reset(self):
        """
        Reinicia as métricas acumuladas.
        """
        self.current_angle = None
        self.min_angle = None
        self.max_angle = None
        self.timestamps.clear()
        self.angles.clear()

    @property
    def rom(self) -> Optional[float]:
        """
        Range of Motion (Amplitude de movimento atingida = máx - mín).
        """
        if self.min_angle is not None and self.max_angle is not None:
            return round(self.max_angle - self.min_angle, 1)
        return None

    @property
    def average_angle(self) -> Optional[float]:
        """
        Média de todos os ângulos registrados.
        """
        if self.angles:
            return round(float(np.mean(self.angles)), 1)
        return None

    def get_summary(self) -> Dict:
        return {
            "key": self.key,
            "label": self.label,
            "current": self.current_angle,
            "min": self.min_angle,
            "max": self.max_angle,
            "rom": self.rom,
            "avg": self.average_angle,
            "count": len(self.angles),
        }


class AngleTracker:
    """
    Controlador central de rastreamento para todas as articulações corporais monitoradas.
    """

    def __init__(self, joint_labels: Optional[Dict[str, str]] = None):
        self.joint_records: Dict[str, JointRecord] = {}

        if joint_labels:
            for key, label in joint_labels.items():
                self.joint_records[key] = JointRecord(key, label)

    def register_joint(self, key: str, label: str):
        if key not in self.joint_records:
            self.joint_records[key] = JointRecord(key, label)

    def update(self, angles_data: Dict[str, Dict], timestamp: float):
        """
        Atualiza os registros com os ângulos calculados no frame atual.

        Args:
            angles_data: Dicionário retornado por PoseDetector.calculate_all_joint_angles()
            timestamp: Momento em segundos decorridos desde o início
        """
        for key, data in angles_data.items():
            if key not in self.joint_records:
                self.joint_records[key] = JointRecord(key, data.get("label", key))

            if data.get("valid") and data.get("angle") is not None:
                self.joint_records[key].update(data["angle"], timestamp)

    def reset_all(self):
        """
        Zera todos os recordes de amplitude e séries temporais.
        """
        for record in self.joint_records.values():
            record.reset()

    def get_all_summaries(self) -> Dict[str, Dict]:
        """
        Retorna o resumo estatístico de todas as articulações.
        """
        return {key: record.get_summary() for key, record in self.joint_records.items()}

    def export_to_csv(self, file_path: str):
        """
        Exporta a série temporal de todos os ângulos para um arquivo CSV.
        """
        # Coleta união ordenada de todos os timestamps
        all_timestamps = sorted(
            list(
                set(
                    ts
                    for record in self.joint_records.values()
                    for ts in record.timestamps
                )
            )
        )

        fieldnames = ["timestamp_sec"] + list(self.joint_records.keys())

        # Mapeamento rápido de timestamp para valor de cada articulação
        data_by_ts: Dict[float, Dict[str, Optional[float]]] = {
            ts: {} for ts in all_timestamps
        }
        for key, record in self.joint_records.items():
            for ts, angle in zip(record.timestamps, record.angles):
                data_by_ts[ts][key] = angle

        with open(file_path, mode="w", newline="", encoding="utf-8") as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
            writer.writeheader()
            for ts in all_timestamps:
                row = {"timestamp_sec": round(ts, 3)}
                for key in self.joint_records.keys():
                    row[key] = data_by_ts[ts].get(key, "")
                writer.writerow(row)

