import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Identidade visual "Composição corporal": fundo branco,
/// header preto, botões pílula pretos, cards brancos arredondados e
/// destaques em vermelho/verde.
class AppColors {
  static const Color background = Color(0xFFFFFFFF);
  static const Color header = Color(0xFF0B0B0B);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF4F4F4);
  static const Color border = Color(0xFFE6DADA);
  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF6E6666);
  static const Color accent = Color(0xFF0B0B0B);
  static const Color highlight = Color(0xFFE86969);
  static const Color ok = Color(0xFF8BD44F);
  static const Color warn = Color(0xFFE0A030);
  static const Color error = Color(0xFFE86969);

  /// Texto e fundo (42% de opacidade) das etiquetas de alerta, como o "Ruim".
  static const Color alertText = Color(0xFF913939);
  static const Color alertBg = Color(0x6BE86969);
}

/// Cores do painel sobre a câmera (tela de captura permanece escura).
class CameraColors {
  static const Color panel = Color(0xE6171D24);
  static const Color border = Color(0xFF2B343E);
  static const Color textSecondary = Color(0xFF9AA5B1);
}

/// Scaffold padrão da identidade visual (fundo branco liso).
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  const AppScaffold({super.key, this.appBar, required this.body});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: appBar, body: body);
}

class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      outline: AppColors.border,
    );
    const radius = BorderRadius.all(Radius.circular(16));
    const pill = StadiumBorder();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: NoSplash.splashFactory,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.header,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 72,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        // Cabeçalho "Mobilidade" do Figma: 20 px, peso 400, espaçamento -0.8.
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.8,
          color: Color(0xEEEEEEEE),
        ),
      ),
      cardTheme: const CardTheme(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFBDB5B5),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: pill,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.accent, width: 1.2),
          shape: pill,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }

  /// Tema escuro, usado somente sobre a imagem da câmera.
  static ThemeData get camera => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          surface: Color(0xFF171D24),
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: Colors.black,
        splashFactory: NoSplash.splashFactory,
      );
}

class AppText {
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: AppColors.textSecondary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.4,
    color: AppColors.textPrimary,
  );
  static const TextStyle muted = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: AppColors.textSecondary,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const TextStyle value = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
