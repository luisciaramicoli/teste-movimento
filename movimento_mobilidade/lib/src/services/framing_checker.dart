import 'dart:math';
import 'dart:ui' show Size;

import '../models/assessment_models.dart';
import '../models/joint_angle.dart';

enum FramingIssue {
  noPerson,
  bodyCutOff,
  tooFar,
  tooClose,
  offCenter,
  wrongOrientation,
}

class FramingStatus {
  final bool isInside;
  final FramingIssue? issue;
  final String message;
  final double bodyHeightRatio;
  final double horizontalOffset;

  const FramingStatus({
    required this.isInside,
    required this.issue,
    required this.message,
    this.bodyHeightRatio = 0,
    this.horizontalOffset = 0,
  });
}

/// Decide se o usuário está dentro do enquadramento exigido para a captura.
///
/// Critérios: corpo inteiro detectado (cabeça até os pés), dentro das bordas,
/// distância adequada, centralizado e na orientação correta (frontal/perfil).
class FramingChecker {
  /// Fração da altura da tela ocupada pelo corpo (nariz até o tornozelo).
  /// A razão é calculada sobre a altura estimada do corpo inteiro: a distância
  /// nariz→tornozelo cobre só ~88% da estatura (faltam topo da cabeça e planta
  /// do pé), então é corrigida antes de comparar.
  static const double bodyHeightCorrection = 0.88;
  static const double minBodyRatio = 0.42;
  static const double maxBodyRatio = 0.92;
  static const double maxHorizontalOffset = 0.20;
  static const double edgeMargin = 0.02;
  static const double frontalMaxYaw = 38.0;
  static const double profileMinYaw = 48.0;
  static const double minConfidence = 0.25;

  /// Folga extra (histerese) aplicada quando o usuário já estava enquadrado,
  /// para o aviso não reaparecer por oscilações de poucos pixels.
  static const double hysteresis = 0.06;

  static const List<String> _required = [
    'NOSE',
    'LEFT_SHOULDER',
    'RIGHT_SHOULDER',
    'LEFT_HIP',
    'RIGHT_HIP',
    'LEFT_KNEE',
    'RIGHT_KNEE',
    'LEFT_ANKLE',
    'RIGHT_ANKLE',
  ];

  static FramingStatus evaluate(
    ExtractedPoseData? pose,
    Size screen,
    CaptureView view, {
    bool wasInside = false,
  }) {
    final slack = wasInside ? hysteresis : 0.0;
    if (pose == null || pose.landmarks.isEmpty) {
      return const FramingStatus(
        isInside: false,
        issue: FramingIssue.noPerson,
        message: 'Apareça na câmera.',
      );
    }
    final lm = pose.landmarks;

    // Em perfil, o lado oposto à câmera fica ocluído: exige-se apenas o lado visível.
    final bool profile = view != CaptureView.frontal;
    final String side = view == CaptureView.profileRight ? 'RIGHT' : 'LEFT';
    final required = profile
        ? ['NOSE', '${side}_SHOULDER', '${side}_HIP', '${side}_KNEE', '${side}_ANKLE']
        : _required;

    // Em perfil, o lado voltado para a câmera precisa ser o do exercício.
    final shown = pose.visibleSide;
    if (profile && shown != null && shown != side) {
      String nome(String x) => x == 'LEFT' ? 'esquerdo' : 'direito';
      return FramingStatus(
        isInside: false,
        issue: FramingIssue.wrongOrientation,
        message: 'Mostre o lado ${nome(side)}.',
      );
    }

    final missing = required.where((k) {
      final p = lm[k];
      return p == null || p.confidence < minConfidence;
    }).toList();
    if (missing.isNotEmpty) {
      return const FramingStatus(
        isInside: false,
        issue: FramingIssue.bodyCutOff,
        message: 'Mostre o corpo inteiro.',
      );
    }

    final pts = [for (final k in required) lm[k]!];
    final minY = pts.map((p) => p.y).reduce(min);
    final maxY = pts.map((p) => p.y).reduce(max);
    final minX = pts.map((p) => p.x).reduce(min);
    final maxX = pts.map((p) => p.x).reduce(max);

    final mx = screen.width * (edgeMargin - slack / 2);
    final my = screen.height * (edgeMargin - slack / 2);
    if (minY < my || maxY > screen.height - my || minX < mx || maxX > screen.width - mx) {
      return const FramingStatus(
        isInside: false,
        issue: FramingIssue.bodyCutOff,
        message: 'Corpo fora da imagem.',
      );
    }

    final ratio = (maxY - minY) / bodyHeightCorrection / screen.height;
    final centerX = (minX + maxX) / 2 / screen.width;
    final offset = centerX - 0.5;

    if (ratio < minBodyRatio - slack) {
      return FramingStatus(
        isInside: false,
        issue: FramingIssue.tooFar,
        message: 'Aproxime-se.',
        bodyHeightRatio: ratio,
        horizontalOffset: offset,
      );
    }
    if (ratio > maxBodyRatio + slack) {
      return FramingStatus(
        isInside: false,
        issue: FramingIssue.tooClose,
        message: 'Afaste-se.',
        bodyHeightRatio: ratio,
        horizontalOffset: offset,
      );
    }
    if (offset.abs() > maxHorizontalOffset + slack) {
      return FramingStatus(
        isInside: false,
        issue: FramingIssue.offCenter,
        // A direção é a da pessoa: sem espelhamento, os lados se invertem.
        message: (offset < 0) == pose.mirrored
            ? 'Vá para a direita.'
            : 'Vá para a esquerda.',
        bodyHeightRatio: ratio,
        horizontalOffset: offset,
      );
    }

    final yaw = pose.bodyOrientationAngle;
    if (!profile && yaw > frontalMaxYaw + slack * 100) {
      return FramingStatus(
        isInside: false,
        issue: FramingIssue.wrongOrientation,
        message: 'Fique de frente.',
        bodyHeightRatio: ratio,
        horizontalOffset: offset,
      );
    }
    if (profile && yaw < profileMinYaw - slack * 100) {
      return FramingStatus(
        isInside: false,
        issue: FramingIssue.wrongOrientation,
        message:
            'Mostre o lado ${view == CaptureView.profileLeft ? 'esquerdo' : 'direito'}.',
        bodyHeightRatio: ratio,
        horizontalOffset: offset,
      );
    }

    return FramingStatus(
      isInside: true,
      issue: null,
      message: 'Enquadramento correto.',
      bodyHeightRatio: ratio,
      horizontalOffset: offset,
    );
  }
}
