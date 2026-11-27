/// Biblioteca de avaliação de mobilidade por visão computacional.
///
/// Uso básico:
/// ```dart
/// await MovimentoMobilidade.inicializar();
/// final resultado = await MovimentoMobilidade.iniciarAvaliacao(context);
/// final ombroDir = resultado?.movement('abducao_ombro')?.averages['ombro_dir'];
/// ```
library movimento_mobilidade;

import 'dart:io' show Platform;

import 'package:camera_android/camera_android.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';

import 'src/flow.dart';
import 'src/models/assessment_models.dart';
import 'src/models/perfil_avaliado.dart';
import 'src/models/protocol_models.dart';
import 'src/services/assessment_csv.dart';
import 'src/services/assessment_history_store.dart';
import 'src/services/pose_camera_session.dart';
import 'src/services/volunteer_code.dart';
import 'src/theme/app_theme.dart';
import 'src/views/camera_screen.dart';
import 'src/views/how_it_works_screen.dart';
import 'src/views/result_screen.dart';

export 'src/models/assessment_models.dart'
    show
        AssessmentRecord,
        MovementResult,
        RepMeasurement,
        MovementSpec,
        CaptureView,
        kProtocolMovements,
        jointLabel,
        stdDev;
export 'src/models/mobility_score.dart';
export 'src/models/perfil_avaliado.dart' show PerfilAvaliado;
export 'src/models/protocol_models.dart'
    show
        ProtocolSessionResult,
        PostureEvaluationResult,
        MobilityDeficitItem,
        AngleTargetRange;
export 'src/models/reference_norms.dart' show Sexo, ShoulderNorm, shoulderNorm;
export 'src/services/volunteer_code.dart' show VolunteerCode;
export 'src/views/camera_screen.dart' show CameraScreen;
export 'src/views/report_screen.dart' show ReportScreen;

/// Ponto de entrada da biblioteca.
class MovimentoMobilidade {
  MovimentoMobilidade._();

  /// Deve ser chamado uma vez, antes de [iniciarAvaliacao] (ex.: no `main`,
  /// depois de `WidgetsFlutterBinding.ensureInitialized()`).
  static Future<void> inicializar() async {
    if (Platform.isAndroid) {
      // Força a implementação estável Camera2 (camera_android).
      CameraPlatform.instance = AndroidCamera();
    }
    // Pré-aquece descoberta de câmeras e modelo nativo sem bloquear a abertura do app.
    PoseCameraSession.prewarm();
  }

  /// Abre o fluxo completo: "Como funciona?", Passo 1/2, Passo 2/2 e, se
  /// [mostrarResultado], a tela de resultado.
  ///
  /// Retorna a avaliação concluída, ou `null` se o usuário saiu antes de terminar.
  /// A avaliação também é salva no histórico local ([historico]).
  ///
  /// [voluntario] é o código anônimo (V01, V02...) usado no histórico e no CSV.
  /// Qualquer outro texto, como um nome, lança [ArgumentError].
  static Future<AssessmentRecord?> iniciarAvaliacao(
    BuildContext context, {
    String voluntario = 'V00',
    bool mostrarResultado = true,
    PerfilAvaliado? perfil,
  }) async {
    if (!VolunteerCode.isValid(voluntario)) {
      // Não repete o valor recebido: ele pode ser um nome.
      throw ArgumentError('voluntario deve ser um código como V01.');
    }
    final fluxo = AvaliacaoFluxo(
        voluntario: VolunteerCode.normalize(voluntario),
        mostrarResultado: mostrarResultado,
        perfil: perfil);
    await Navigator.of(context).push<void>(
        flowRoute((_) => HowItWorksScreen(fluxo: fluxo)));
    return fluxo.resultado;
  }

  /// Abre o protocolo de posturas e, ao fechar, devolve os valores da última
  /// sessão finalizada, ou `null` se nenhuma postura foi avaliada. Não grava no
  /// histórico.
  static Future<ProtocolSessionResult?> iniciarCameraProtocolo(
    BuildContext context, {
    PerfilAvaliado? perfil,
  }) async {
    ProtocolSessionResult? result;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Theme(
          data: AppTheme.light,
          child: CameraScreen(
            perfil: perfil,
            onSessionFinished: (value) => result = value,
          ),
        ),
      ),
    );
    return result;
  }

  /// Tela de resultado de uma avaliação já existente (somente leitura).
  static Widget telaResultado(AssessmentRecord avaliacao,
          {PerfilAvaliado? perfil}) =>
      Theme(
        data: AppTheme.light,
        child: ResultScreen(record: avaliacao, perfil: perfil),
      );

  /// Avaliações salvas neste aparelho, da mais recente para a mais antiga.
  static Future<List<AssessmentRecord>> historico() =>
      AssessmentHistoryStore().loadAll();

  /// CSV de uma avaliação (uma linha por repetição/articulação, mais a média).
  static String exportarCsv(AssessmentRecord avaliacao) =>
      AssessmentCsv.build(avaliacao);
}
