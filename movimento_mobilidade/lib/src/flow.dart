import 'package:flutter/material.dart';

import 'models/assessment_models.dart';
import 'models/perfil_avaliado.dart';
import 'theme/app_theme.dart';

/// Nome comum de todas as rotas do fluxo; permite sair de todas de uma vez.
const String kFlowRoute = 'movimento_mobilidade/fluxo';

/// Nome do pacote, necessário para carregar os assets da biblioteca.
const String kPackage = 'movimento_mobilidade';

/// Estado compartilhado entre as telas de uma avaliação em andamento.
class AvaliacaoFluxo {
  /// Identificação do voluntário gravada no histórico e no CSV.
  final String voluntario;

  /// Se a tela de resultado deve ser exibida ao fim da avaliação.
  final bool mostrarResultado;

  /// Dados do avaliado exibidos no cabeçalho da tela de resultado.
  final PerfilAvaliado? perfil;

  /// Resultado da última avaliação concluída neste fluxo.
  AssessmentRecord? resultado;

  AvaliacaoFluxo(
      {required this.voluntario, this.mostrarResultado = true, this.perfil});
}

/// Rota do fluxo, já com o tema visual da biblioteca (independente do app host).
Route<T> flowRoute<T>(WidgetBuilder builder) => MaterialPageRoute<T>(
      settings: const RouteSettings(name: kFlowRoute),
      builder: (context) => Theme(data: AppTheme.light, child: builder(context)),
    );

/// Fecha todas as telas do fluxo e volta para quem o iniciou.
void exitFlow(BuildContext context) => Navigator.of(context)
    .popUntil((route) => route.settings.name != kFlowRoute);
