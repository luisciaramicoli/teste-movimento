import os
os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib_cache")

import unittest
import numpy as np

from pose_detector import PoseDetector, calculate_angle, JOINT_DEFINITIONS, LANDMARKS
from tracker import AngleTracker
from rep_counter import ExerciseRepCounter
from motion_trail import MotionTrail
from protocol_evaluator import ProtocolEvaluator
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

    def test_heel_and_foot_landmarks_registered(self):
        self.assertIn("LEFT_HEEL", LANDMARKS)
        self.assertIn("RIGHT_HEEL", LANDMARKS)
        self.assertIn("LEFT_FOOT_INDEX", LANDMARKS)
        self.assertIn("RIGHT_FOOT_INDEX", LANDMARKS)
        self.assertIn("tornozelo_esq", JOINT_DEFINITIONS)
        self.assertIn("tornozelo_dir", JOINT_DEFINITIONS)

    def test_tracker_statistics_and_rom(self):
        tracker = AngleTracker()

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
        tracker = AngleTracker({k: v[3] for k, v in JOINT_DEFINITIONS.items()})

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
                "tornozelo_esq": {"angle": float(115 + 20 * np.sin(ts * 1.2)), "valid": True},
                "tornozelo_dir": {"angle": float(115 + 20 * np.cos(ts * 1.2)), "valid": True},
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

    def test_protocol_evaluator_positioning_and_calf_posture(self):
        protocol = ProtocolEvaluator(enabled=True)
        frame_shape = (800, 400, 3)

        good_landmarks = {
            "NOSE": {"pixel": (200, 180), "normalized": (0.5, 0.22), "z": 0.0, "valid": True},
            "LEFT_SHOULDER": {"pixel": (165, 250), "normalized": (0.41, 0.31), "z": 0.0, "valid": True},
            "RIGHT_SHOULDER": {"pixel": (235, 250), "normalized": (0.59, 0.31), "z": 0.0, "valid": True},
            "LEFT_ELBOW": {"pixel": (150, 340), "normalized": (0.37, 0.42), "z": 0.0, "valid": True},
            "RIGHT_ELBOW": {"pixel": (250, 340), "normalized": (0.62, 0.42), "z": 0.0, "valid": True},
            "LEFT_WRIST": {"pixel": (145, 420), "normalized": (0.36, 0.52), "z": 0.0, "valid": True},
            "RIGHT_WRIST": {"pixel": (255, 420), "normalized": (0.63, 0.52), "z": 0.0, "valid": True},
            "LEFT_HIP": {"pixel": (175, 430), "normalized": (0.43, 0.53), "z": 0.0, "valid": True},
            "RIGHT_HIP": {"pixel": (225, 430), "normalized": (0.56, 0.53), "z": 0.0, "valid": True},
            "LEFT_KNEE": {"pixel": (175, 550), "normalized": (0.43, 0.68), "z": 0.0, "valid": True},
            "RIGHT_KNEE": {"pixel": (225, 550), "normalized": (0.56, 0.68), "z": 0.0, "valid": True},
            "LEFT_ANKLE": {"pixel": (175, 660), "normalized": (0.43, 0.82), "z": 0.0, "valid": True},
            "RIGHT_ANKLE": {"pixel": (225, 660), "normalized": (0.56, 0.82), "z": 0.0, "valid": True},
            "LEFT_HEEL": {"pixel": (178, 680), "normalized": (0.44, 0.85), "z": 0.0, "valid": True},
            "RIGHT_HEEL": {"pixel": (222, 680), "normalized": (0.55, 0.85), "z": 0.0, "valid": True},
            "LEFT_FOOT_INDEX": {"pixel": (165, 685), "normalized": (0.41, 0.86), "z": 0.0, "valid": True},
            "RIGHT_FOOT_INDEX": {"pixel": (235, 685), "normalized": (0.59, 0.86), "z": 0.0, "valid": True},
        }
        calf_orient = {
            "calf_elevation_left_pct": 10.0,
            "calf_elevation_right_pct": 10.0,
            "max_calf_elevation_pct": 10.0,
            "body_orientation_angle": 12.0,
            "body_orientation_label": "Frontal",
        }

        protocol.update(good_landmarks, {}, calf_orient, frame_shape, 0.0)
        self.assertTrue(protocol.positioning_result.is_all_good)
        protocol.update(good_landmarks, {}, calf_orient, frame_shape, 2.2)
        self.assertEqual(protocol.stage, "posture_replication")

        # Testa Postura 3: Elevação de Panturrilha
        protocol.current_posture_idx = 2
        calf_angles = {
            "tornozelo_esq": {"angle": 135.0, "valid": True},
            "tornozelo_dir": {"angle": 134.0, "valid": True},
            "joelho_esq": {"angle": 172.0, "valid": True},
            "joelho_dir": {"angle": 171.0, "valid": True},
        }
        calf_orient_high = {
            "calf_elevation_left_pct": 65.0,
            "calf_elevation_right_pct": 62.0,
            "max_calf_elevation_pct": 65.0,
            "body_orientation_angle": 35.0,
            "body_orientation_label": "Diagonal",
        }
        protocol.update(good_landmarks, calf_angles, calf_orient_high, frame_shape, 3.0)
        self.assertGreaterEqual(protocol.posture_accuracy_pct, 90.0)
        protocol.update(good_landmarks, calf_angles, calf_orient_high, frame_shape, 5.7)
        self.assertEqual(len(protocol.completed_postures), 1)
        self.assertEqual(protocol.completed_postures[0]["id"], "elevacao_panturrilha")

    def test_rep_counter_squat_and_calf_raise(self):
        counter = ExerciseRepCounter(exercise_name="squat")
        self.assertEqual(counter.rep_count, 0)

        counter.update({"joelho_esq": {"angle": 165.0, "valid": True}}, timestamp=0.0)
        counter.update({"joelho_esq": {"angle": 130.0, "valid": True}}, timestamp=0.5)
        counter.update({"joelho_esq": {"angle": 88.0, "valid": True}}, timestamp=1.0)
        counter.update({"joelho_esq": {"angle": 125.0, "valid": True}}, timestamp=1.5)
        rep = counter.update({"joelho_esq": {"angle": 162.0, "valid": True}}, timestamp=2.0)

        self.assertIsNotNone(rep)
        self.assertEqual(counter.rep_count, 1)

        # Testa contador de elevação de panturrilha (calf_raise)
        calf_counter = ExerciseRepCounter(exercise_name="calf_raise")
        calf_counter.update({"tornozelo_esq": {"angle": 100.0, "valid": True}}, timestamp=0.0)
        calf_counter.update({"tornozelo_esq": {"angle": 118.0, "valid": True}}, timestamp=0.5)
        calf_counter.update({"tornozelo_esq": {"angle": 138.0, "valid": True}}, timestamp=1.0)
        calf_counter.update({"tornozelo_esq": {"angle": 115.0, "valid": True}}, timestamp=1.5)
        calf_rep = calf_counter.update({"tornozelo_esq": {"angle": 102.0, "valid": True}}, timestamp=2.0)
        self.assertIsNotNone(calf_rep)
        self.assertEqual(calf_counter.rep_count, 1)

    def test_motion_trail(self):
        trail = MotionTrail(max_length=5, enabled=True)
        for i in range(10):
            mock_landmarks = {
                "LEFT_WRIST": {"pixel": (100 + i * 5, 200 + i * 2), "valid": True}
            }
            trail.update(mock_landmarks)

        self.assertEqual(len(trail.trails["LEFT_WRIST"]), 5)

        mock_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        drawn = trail.draw(mock_frame)
        self.assertEqual(drawn.shape, (480, 640, 3))

        trail.toggle()
        self.assertFalse(trail.enabled)
        self.assertEqual(len(trail.trails["LEFT_WRIST"]), 0)


if __name__ == "__main__":
    unittest.main()
