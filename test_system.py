import os
os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib_cache")

import unittest
import numpy as np

from pose_detector import PoseDetector, calculate_angle, JOINT_DEFINITIONS
from tracker import AngleTracker
from rep_counter import ExerciseRepCounter
from motion_trail import MotionTrail
from visualizer import generate_rom_report_graph


class TestJointTracking(unittest.TestCase):

    def test_calculate_angle_right_angle(self):
        # Ângulo reto de 90 graus: A=(0, 1), B=(0, 0), C=(1, 0)
        angle = calculate_angle((0, 1), (0, 0), (1, 0))
        self.assertAlmostEqual(angle, 90.0, places=1)

    def test_calculate_angle_straight_line(self):
        # Linha reta de 180 graus: A=(-1, 0), B=(0, 0), C=(1, 0)
        angle = calculate_angle((-1, 0), (0, 0), (1, 0))
        self.assertAlmostEqual(angle, 180.0, places=1)

    def test_calculate_angle_45_degrees(self):
        # Ângulo de 45 graus: A=(1, 1), B=(0, 0), C=(1, 0)
        angle = calculate_angle((1, 1), (0, 0), (1, 0))
        self.assertAlmostEqual(angle, 45.0, places=1)

    def test_tracker_statistics_and_rom(self):
        tracker = AngleTracker()
        
        # Simula medições de cotovelo esquerdo variando de 40 a 160 graus
        angles_sequence = [160.0, 120.0, 80.0, 40.0, 90.0, 150.0]
        for i, ang in enumerate(angles_sequence):
            mock_data = {
                "cotovelo_esq": {
                    "angle": ang,
                    "vertex_px": (100, 100),
                    "label": "Cotovelo Esquerdo",
                    "valid": True,
                }
            }
            tracker.update(mock_data, timestamp=i * 0.5)

        summary = tracker.get_all_summaries()["cotovelo_esq"]
        self.assertEqual(summary["min"], 40.0)
        self.assertEqual(summary["max"], 160.0)
        self.assertEqual(summary["rom"], 120.0)
        self.assertAlmostEqual(summary["avg"], np.mean(angles_sequence), places=1)

    def test_tracker_csv_export(self):
        tracker = AngleTracker()
        mock_data = {
            "cotovelo_esq": {"angle": 90.0, "valid": True},
            "joelho_esq": {"angle": 120.0, "valid": True},
        }
        tracker.update(mock_data, timestamp=1.0)
        
        csv_path = "test_export.csv"
        try:
            tracker.export_to_csv(csv_path)
            self.assertTrue(os.path.exists(csv_path))
            with open(csv_path, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("timestamp_sec", content)
                self.assertIn("cotovelo_esq", content)
                self.assertIn("90.0", content)
        finally:
            if os.path.exists(csv_path):
                os.remove(csv_path)

    def test_graph_generation(self):
        # Simula uma sessão completa de movimento para testar a renderização do Matplotlib
        tracker = AngleTracker({k: v[3] for k, v in JOINT_DEFINITIONS.items()})

        # Gera 30 frames de dados sintéticos simulando flexão e extensão
        for t in range(30):
            ts = t * 0.1
            mock_angles = {
                "cotovelo_esq": {"angle": float(90 + 50 * np.sin(ts * 2)), "valid": True},
                "cotovelo_dir": {"angle": float(85 + 45 * np.cos(ts * 2)), "valid": True},
                "joelho_esq": {"angle": float(110 + 40 * np.sin(ts * 1.5)), "valid": True},
                "joelho_dir": {"angle": float(115 + 35 * np.cos(ts * 1.5)), "valid": True},
                "ombro_esq": {"angle": float(60 + 30 * np.sin(ts)), "valid": True},
                "ombro_dir": {"angle": float(65 + 25 * np.cos(ts)), "valid": True},
                "quadril_esq": {"angle": float(130 + 20 * np.sin(ts * 0.8)), "valid": True},
                "quadril_dir": {"angle": float(135 + 15 * np.cos(ts * 0.8)), "valid": True},
            }
            tracker.update(mock_angles, timestamp=ts)

        test_img_path = "test_relatorio.png"
        try:
            saved_path = generate_rom_report_graph(
                tracker, output_image_path=test_img_path, show_plot=False
            )
            self.assertTrue(os.path.exists(test_img_path))
            file_size = os.path.getsize(test_img_path)
            self.assertGreater(file_size, 10000, "O arquivo de imagem gerado deve ter conteúdo válido")
        finally:
            if os.path.exists(test_img_path):
                os.remove(test_img_path)

    def test_pose_detector_inference(self):
        detector = PoseDetector()
        mock_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        results = detector.find_pose(mock_frame)
        landmarks = detector.extract_landmarks(results, mock_frame.shape)
        angles = detector.calculate_all_joint_angles(landmarks)
        self.assertIsInstance(angles, dict)
        self.assertEqual(len(angles), len(JOINT_DEFINITIONS))

    def test_rep_counter_squat(self):
        counter = ExerciseRepCounter(exercise_name="squat")
        self.assertEqual(counter.rep_count, 0)

        # Simula ciclo de agachamento:
        # Posição inicial em pé (165°)
        counter.update({"joelho_esq": {"angle": 165.0, "valid": True}}, timestamp=0.0)
        # Descida até 90° (pico de agachamento)
        counter.update({"joelho_esq": {"angle": 130.0, "valid": True}}, timestamp=0.5)
        counter.update({"joelho_esq": {"angle": 88.0, "valid": True}}, timestamp=1.0)
        # Retorno subindo até a posição em pé (160°)
        counter.update({"joelho_esq": {"angle": 125.0, "valid": True}}, timestamp=1.5)
        rep = counter.update({"joelho_esq": {"angle": 162.0, "valid": True}}, timestamp=2.0)

        self.assertIsNotNone(rep)
        self.assertEqual(counter.rep_count, 1)
        self.assertTrue(rep.is_valid)
        self.assertGreater(rep.total_duration, 0.5)
        self.assertGreater(rep.rom, 60.0)

    def test_rep_counter_curl(self):
        counter = ExerciseRepCounter(exercise_name="curl")
        # Simula rosca bíceps: 150° -> 45° -> 150°
        counter.update({"cotovelo_esq": {"angle": 150.0, "valid": True}}, timestamp=0.0)
        counter.update({"cotovelo_esq": {"angle": 90.0, "valid": True}}, timestamp=0.6)
        counter.update({"cotovelo_esq": {"angle": 45.0, "valid": True}}, timestamp=1.2)
        counter.update({"cotovelo_esq": {"angle": 100.0, "valid": True}}, timestamp=1.8)
        rep = counter.update({"cotovelo_esq": {"angle": 148.0, "valid": True}}, timestamp=2.4)

        self.assertIsNotNone(rep)
        self.assertEqual(counter.rep_count, 1)
        self.assertEqual(rep.rep_number, 1)

    def test_motion_trail(self):
        trail = MotionTrail(max_length=5, enabled=True)
        # Simula movimentação do pulso esquerdo
        for i in range(10):
            mock_landmarks = {
                "LEFT_WRIST": {"pixel": (100 + i * 5, 200 + i * 2), "valid": True}
            }
            trail.update(mock_landmarks)

        # Não deve ultrapassar max_length
        self.assertEqual(len(trail.trails["LEFT_WRIST"]), 5)

        # Testa desenho sobre frame
        mock_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        drawn = trail.draw(mock_frame)
        self.assertEqual(drawn.shape, (480, 640, 3))

        # Testa toggle e clear
        trail.toggle()
        self.assertFalse(trail.enabled)
        self.assertEqual(len(trail.trails["LEFT_WRIST"]), 0)


if __name__ == "__main__":
    unittest.main()

