import 'dart:math';

class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  double distanceTo(Point2D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return sqrt(dx * dx + dy * dy);
  }
}

/// Calcula o ângulo em graus no vértice b formado pelos pontos a, b e c.
/// Retorna valor entre 0 e 180 graus.
double calculateAngle(Point2D a, Point2D b, Point2D c) {
  final double radians =
      atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);
  double angle = (radians * 180.0 / pi).abs();

  if (angle > 180.0) {
    angle = 360.0 - angle;
  }

  return double.parse(angle.toStringAsFixed(1));
}

class JointAngleData {
  final String key;
  final String label;
  final double? angle;
  final Point2D? vertex;
  final bool isValid;

  const JointAngleData({
    required this.key,
    required this.label,
    this.angle,
    this.vertex,
    this.isValid = false,
  });
}

class JointRecord {
  final String key;
  final String label;
  double? currentAngle;
  double? minAngle;
  double? maxAngle;
  final List<double> timestamps = [];
  final List<double> angles = [];

  JointRecord({required this.key, required this.label});

  void update(double angle, double timestamp) {
    currentAngle = angle;
    timestamps.add(timestamp);
    angles.add(angle);

    if (minAngle == null || angle < minAngle!) {
      minAngle = angle;
    }
    if (maxAngle == null || angle > maxAngle!) {
      maxAngle = angle;
    }
  }

  void reset() {
    currentAngle = null;
    minAngle = null;
    maxAngle = null;
    timestamps.clear();
    angles.clear();
  }

  double? get rom {
    if (minAngle != null && maxAngle != null) {
      return double.parse((maxAngle! - minAngle!).toStringAsFixed(1));
    }
    return null;
  }

  double? get averageAngle {
    if (angles.isEmpty) return null;
    final sum = angles.reduce((a, b) => a + b);
    return double.parse((sum / angles.length).toStringAsFixed(1));
  }
}

class JointAngleTracker {
  final Map<String, JointRecord> records = {};

  JointAngleTracker() {
    _registerDefaultJoints();
  }

  void _registerDefaultJoints() {
    final defaultJoints = {
      'cotovelo_esq': 'Cotovelo Esquerdo',
      'cotovelo_dir': 'Cotovelo Direito',
      'ombro_esq': 'Ombro Esquerdo',
      'ombro_dir': 'Ombro Direito',
      'quadril_esq': 'Quadril Esquerdo',
      'quadril_dir': 'Quadril Direito',
      'joelho_esq': 'Joelho Esquerdo',
      'joelho_dir': 'Joelho Direito',
    };

    defaultJoints.forEach((key, label) {
      records[key] = JointRecord(key: key, label: label);
    });
  }

  void update(Map<String, JointAngleData> anglesData, double timestamp) {
    anglesData.forEach((key, data) {
      if (data.isValid && data.angle != null) {
        if (!records.containsKey(key)) {
          records[key] = JointRecord(key: key, label: data.label);
        }
        records[key]!.update(data.angle!, timestamp);
      }
    });
  }

  void resetAll() {
    for (final r in records.values) {
      r.reset();
    }
  }
}

