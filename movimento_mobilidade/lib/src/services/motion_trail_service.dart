import 'dart:collection';
import 'package:flutter/material.dart';
import '../models/joint_angle.dart';

class MotionTrailService {
  final int maxLength;
  bool enabled;

  final Map<String, Queue<Point2D>> trails = {};

  final Map<String, Color> jointColors = {
    'LEFT_WRIST': const Color(0xFFFFD700),  // Dourado
    'RIGHT_WRIST': const Color(0xFF00E5FF), // Ciano
    'LEFT_KNEE': const Color(0xFF00E676),   // Verde neon
    'RIGHT_KNEE': const Color(0xFFFF9100),  // Laranja
    'LEFT_ANKLE': const Color(0xFFFF4081),  // Rosa
    'RIGHT_ANKLE': const Color(0xFF7C4DFF), // Roxo
  };

  MotionTrailService({this.maxLength = 18, this.enabled = true});

  bool toggle() {
    enabled = !enabled;
    if (!enabled) {
      clear();
    }
    return enabled;
  }

  void clear() {
    for (final q in trails.values) {
      q.clear();
    }
  }

  void update(Map<String, Point2D?> currentPoints) {
    if (!enabled) return;

    for (final key in jointColors.keys) {
      if (!trails.containsKey(key)) {
        trails[key] = Queue<Point2D>();
      }

      final pt = currentPoints[key];
      if (pt != null) {
        trails[key]!.addLast(pt);
        if (trails[key]!.length > maxLength) {
          trails[key]!.removeFirst();
        }
      } else {
        if (trails[key]!.isNotEmpty) {
          trails[key]!.removeFirst();
        }
      }
    }
  }
}

