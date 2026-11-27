import 'package:flutter/material.dart';

import '../flow.dart';
import '../services/assessment_history_store.dart';
import '../services/pose_camera_session.dart';
import '../theme/app_theme.dart';
import 'assessment_screen.dart';

/// Tela 1: "Como funciona?" — instruções antes de iniciar a avaliação.
class HowItWorksScreen extends StatefulWidget {
  final AvaliacaoFluxo fluxo;
  const HowItWorksScreen({super.key, required this.fluxo});

  @override
  State<HowItWorksScreen> createState() => _HowItWorksScreenState();
}

class _HowItWorksScreenState extends State<HowItWorksScreen> {
  static const TextStyle _text =
      TextStyle(fontSize: 13, height: 1.35, color: Color(0xFF1A1A1A));

  /// Largura da coluna das imagens; o centro dela alinha os pontilhados e o ícone.
  static const double _imgCol = 96;

  /// Espaço entre a coluna das imagens e os textos.
  static const double _gap = 22;

  static const Color _bg = Color(0xFFFAFAFA);

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Pré-aquece câmera e modelo nativo enquanto o usuário lê as instruções.
    PoseCameraSession.prewarm();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    final volunteer = widget.fluxo.voluntario;
    final n = await AssessmentHistoryStore().nextTestNumber(volunteer);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).push(flowRoute((_) => AssessmentScreen(
        volunteerCode: volunteer, testNumber: n, fluxo: widget.fluxo)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Mobilidade'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => exitFlow(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(19, 26, 50, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 13),
                      child: Text('Como funciona?',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 28),
                    // 1) Tripé: texto centralizado na altura da foto.
                    Row(children: [
                      SizedBox(
                        width: _imgCol,
                        child: Center(
                          child: Image.asset('assets/images/tripe.png',
                              package: kPackage, height: 158),
                        ),
                      ),
                      const SizedBox(width: _gap),
                      const Expanded(
                          child: Text(
                              'Esteja com roupas confortáveis. Posicione seu celular no tripé da academia.',
                              style: _text)),
                    ]),
                    const SizedBox(height: 26),
                    const _Dots(width: _imgCol),
                    const SizedBox(height: 10),
                    // 2) Ícone da câmera.
                    Row(children: [
                      SizedBox(
                        width: _imgCol,
                        child: Center(
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(5)),
                            child: const Icon(Icons.photo_camera_outlined,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: _gap),
                      const Expanded(
                          child: Text(
                              'Aperte iniciar. O aplicativo irá ativar a câmera do seu celular.',
                              style: _text)),
                    ]),
                    const SizedBox(height: 10),
                    const _Dots(width: _imgCol),
                    const SizedBox(height: 26),
                    // 3) Pessoa: texto alinhado ao topo da foto.
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: _imgCol,
                        height: 113,
                        // Multiplica pelo fundo da tela: o branco da foto some.
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                              _bg, BlendMode.multiply),
                          // A imagem tem duas posições; mostra só a de braços
                          // erguidos, à direita.
                          child: Image.asset('assets/images/abducao.png',
                              package: kPackage,
                              fit: BoxFit.cover,
                              alignment: const Alignment(0.73, 0)),
                        ),
                      ),
                      const SizedBox(width: _gap),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                              '1) De frente: levante os braços acima da cabeça, '
                              'esticados, movimentando apenas o ombro.\n\n'
                              '2) De perfil, com o lado direito para a câmera: '
                              'agache o máximo que conseguir, tentando não tirar '
                              'o calcanhar do chão.\n\n'
                              'São 3 repetições de cada. Se sentir dor, pare o '
                              'movimento.',
                              style: _text),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: SizedBox(
                width: 184,
                height: 41,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(184, 41)),
                  onPressed: _busy ? null : _start,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Iniciar',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Três pontinhos cinza entre os passos, centralizados na coluna das imagens.
class _Dots extends StatelessWidget {
  final double width;
  const _Dots({required this.width});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 3,
              height: 3,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.55),
                  shape: BoxShape.circle),
            ),
        ]),
      );
}
