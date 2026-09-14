import 'dart:math';
import '../models/joint_angle.dart';
import '../models/exercise_preset.dart';

enum RepState {
  idle,
  startPosition,
  inProgress,
  peak,
  returning,
}

class RepCounterService {
  ExerciseConfig config;
  RepState state = RepState.idle;
  int repCount = 0;
  final List<RepInfo> repsHistory = [];

  double? _repStartTime;
  double? _repPeakTime;
  final List<double> _currentRepAngles = [];
  bool _reachedPeakTarget = false;

  String feedbackMessage = '';
  double progressPct = 0.0;

  RepCounterService({String initialExercise = 'squat'})
      : config = exercisePresets[initialExercise] ?? exercisePresets['squat']! {
    feedbackMessage = config.instructionStart;
  }

  void setExercise(String exerciseName) {
    if (exercisePresets.containsKey(exerciseName)) {
      config = exercisePresets[exerciseName]!;
      reset();
    }
  }

  void reset() {
    state = RepState.idle;
    repCount = 0;
    repsHistory.clear();
    _repStartTime = null;
    _repPeakTime = null;
    _currentRepAngles.clear();
    _reachedPeakTarget = false;
    feedbackMessage = config.instructionStart;
    progressPct = 0.0;
  }

  double? _extractPrimaryAngle(Map<String, JointAngleData> anglesData) {
    if (config.targetJoints.isEmpty) return null;

    final validAngles = <double>[];
    for (final joint in config.targetJoints) {
      final data = anglesData[joint];
      if (data != null && data.isValid && data.angle != null) {
        validAngles.add(data.angle!);
      }
    }

    if (validAngles.isNotEmpty) {
      return validAngles.reduce((a, b) => a + b) / validAngles.length;
    }
    return null;
  }

  RepInfo? update(Map<String, JointAngleData> anglesData, double timestamp) {
    if (config.name == 'free') {
      progressPct = 0.0;
      feedbackMessage = 'Medição livre de amplitude';
      return null;
    }

    final angle = _extractPrimaryAngle(anglesData);
    if (angle == null) return null;

    RepInfo? completedRep;

    final startTh = config.startThreshold;
    final peakTh = config.peakThreshold;

    // Cálculo da porcentagem de progresso [0.0 a 1.0]
    double prog;
    if (config.invert) {
      final totalSpan = max(1.0, startTh - peakTh);
      prog = (startTh - angle) / totalSpan;
    } else {
      final totalSpan = max(1.0, peakTh - startTh);
      prog = (angle - startTh) / totalSpan;
    }
    progressPct = prog.clamp(0.0, 1.0);

    // Máquina de estados por Histerese
    if (state == RepState.idle || state == RepState.startPosition) {
      final isAtStart = config.invert
          ? (angle >= startTh - 5.0)
          : (angle <= startTh + 5.0);

      if (isAtStart) {
        state = RepState.startPosition;
        feedbackMessage = 'Pronto! Comece o movimento.';
      } else {
        if (progressPct > 0.20) {
          state = RepState.inProgress;
          _repStartTime = timestamp;
          _currentRepAngles.clear();
          _currentRepAngles.add(angle);
          _reachedPeakTarget = false;
          feedbackMessage = config.instructionDown;
        }
      }
    } else if (state == RepState.inProgress) {
      _currentRepAngles.add(angle);

      final reachedPeak =
          config.invert ? (angle <= peakTh) : (angle >= peakTh);

      if (reachedPeak) {
        state = RepState.peak;
        _repPeakTime = timestamp;
        _reachedPeakTarget = true;
        feedbackMessage = 'Pico atingido! Boa amplitude! ✅';
      } else {
        if (progressPct > 0.70) {
          feedbackMessage = 'Quase lá, complete a amplitude!';
        } else {
          feedbackMessage = config.instructionDown;
        }
      }
    } else if (state == RepState.peak) {
      _currentRepAngles.add(angle);

      final startedReturning = config.invert
          ? (angle > peakTh + 8.0)
          : (angle < peakTh - 8.0);

      if (startedReturning) {
        state = RepState.returning;
        feedbackMessage = config.instructionUp;
      }
    } else if (state == RepState.returning) {
      _currentRepAngles.add(angle);

      final returnedToStart = config.invert
          ? (angle >= startTh - 8.0)
          : (angle <= startTh + 8.0);

      if (returnedToStart) {
        final endTime = timestamp;
        final startTime = _repStartTime ?? (endTime - 1.0);
        final peakTime = _repPeakTime ?? ((startTime + endTime) / 2.0);

        final concentric = max(0.1, peakTime - startTime);
        final eccentric = max(0.1, endTime - peakTime);
        final totalDur = concentric + eccentric;

        final minA = _currentRepAngles.isNotEmpty
            ? _currentRepAngles.reduce(min)
            : angle;
        final maxA = _currentRepAngles.isNotEmpty
            ? _currentRepAngles.reduce(max)
            : angle;
        final rom = double.parse((maxA - minA).toStringAsFixed(1));

        final isValid = _reachedPeakTarget;
        String fb;
        if (!isValid) {
          fb = 'Amplitude incompleta! Desça mais.';
        } else if (totalDur < 1.0) {
          fb = 'Muito rápido! Controle a descida.';
        } else {
          fb = 'Excelente repetição! Ritmo perfeito. 🔥';
        }

        repCount++;
        completedRep = RepInfo(
          repNumber: repCount,
          startTime: double.parse(startTime.toStringAsFixed(2)),
          peakTime: double.parse(peakTime.toStringAsFixed(2)),
          endTime: double.parse(endTime.toStringAsFixed(2)),
          concentricDuration: double.parse(concentric.toStringAsFixed(2)),
          eccentricDuration: double.parse(eccentric.toStringAsFixed(2)),
          totalDuration: double.parse(totalDur.toStringAsFixed(2)),
          minAngle: double.parse(minA.toStringAsFixed(1)),
          maxAngle: double.parse(maxA.toStringAsFixed(1)),
          rom: rom,
          isValid: isValid,
          feedback: fb,
        );

        repsHistory.add(completedRep);
        feedbackMessage = 'Rep $repCount feita! (${totalDur.toStringAsFixed(1)}s)';

        // Reinicia ciclo
        state = RepState.startPosition;
        _repStartTime = null;
        _repPeakTime = null;
        _currentRepAngles.clear();
        _reachedPeakTarget = false;
      }
    }

    return completedRep;
  }

  double get cadenceRpm {
    if (repsHistory.length < 2) return 0.0;
    final recent = repsHistory.sublist(max(0, repsHistory.length - 5));
    final totalTime = recent.last.endTime - recent.first.startTime;
    if (totalTime <= 0.5) return 0.0;
    final rpm = (recent.length / totalTime) * 60.0;
    return double.parse(rpm.toStringAsFixed(1));
  }

  double get averageRepDuration {
    if (repsHistory.isEmpty) return 0.0;
    final sum = repsHistory.fold<double>(0.0, (acc, r) => acc + r.totalDuration);
    return double.parse((sum / repsHistory.length).toStringAsFixed(2));
  }
}
