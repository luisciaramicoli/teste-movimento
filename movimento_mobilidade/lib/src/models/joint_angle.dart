import 'dart:math';

class Point2D {
  final double x;
  final double y;
  final double z;
  final double confidence;

  const Point2D(
    this.x,
    this.y, {
    this.z = 0.0,
    this.confidence = 1.0,
  });

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

  /// Menor confiança entre os pontos usados no cálculo; null se não informada.
  final double? confidence;

  const JointAngleData({
    required this.key,
    required this.label,
    this.angle,
    this.vertex,
    this.isValid = false,
    this.confidence,
  });
}

class ExtractedPoseData {
  final Map<String, JointAngleData> angles;
  final Map<String, Point2D> landmarks;

  /// Elevação estimada do calcanhar / panturrilha (0% = pé plano, 100% = plantiflexão máxima)
  final double calfElevationLeftPct;
  final double calfElevationRightPct;

  /// Ângulo estimado de rotação do corpo em relação à câmera (0° = Frontal, 90° = Perfil/Sagital)
  final double bodyOrientationAngle;
  final String bodyOrientationLabel;

  /// Em perfil: lado do corpo realmente voltado para a câmera ('LEFT'/'RIGHT'),
  /// deduzido da direção do corpo. Null quando não aplicável ou indeterminado.
  final String? visibleSide;

  const ExtractedPoseData({
    required this.angles,
    required this.landmarks,
    this.calfElevationLeftPct = 0.0,
    this.calfElevationRightPct = 0.0,
    this.bodyOrientationAngle = 0.0,
    this.bodyOrientationLabel = 'Frontal',
    this.visibleSide,
  });

  double get maxCalfElevationPct => max(calfElevationLeftPct, calfElevationRightPct);
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
  double maxCalfElevationLeftPct = 0.0;
  double maxCalfElevationRightPct = 0.0;

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
      'tornozelo_esq': 'Tornozelo / Panturrilha Esq.',
      'tornozelo_dir': 'Tornozelo / Panturrilha Dir.',
    };

    defaultJoints.forEach((key, label) {
      records[key] = JointRecord(key: key, label: label);
    });
  }

  void update(
    Map<String, JointAngleData> anglesData,
    double timestamp, {
    double calfLeftPct = 0.0,
    double calfRightPct = 0.0,
  }) {
    anglesData.forEach((key, data) {
      if (data.isValid && data.angle != null) {
        if (!records.containsKey(key)) {
          records[key] = JointRecord(key: key, label: data.label);
        }
        records[key]!.update(data.angle!, timestamp);
      }
    });

    if (calfLeftPct > maxCalfElevationLeftPct) {
      maxCalfElevationLeftPct = calfLeftPct;
    }
    if (calfRightPct > maxCalfElevationRightPct) {
      maxCalfElevationRightPct = calfRightPct;
    }
  }

  void resetAll() {
    for (final r in records.values) {
      r.reset();
    }
    maxCalfElevationLeftPct = 0.0;
    maxCalfElevationRightPct = 0.0;
  }
}
