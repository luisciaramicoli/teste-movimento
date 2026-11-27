import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Identidade visual principal da biblioteca (fluxo guiado).
class AppColors {
  AppColors._();

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

  /// Texto e fundo (42% de opacidade) das etiquetas de alerta.
  static const Color alertText = Color(0xFF913939);
  static const Color alertBg = Color(0x6BE86969);
}

/// Tokens de cores e raios da tela de resultado (layout Figma 393 px).
class ResultColors {
  ResultColors._();

  static const Color card = Color(0xFFF3F3F3);
  static const Color cardBorder = Color(0xFFB9B9B9);
  static const Color track = Color(0xFFE6E6E6);
  static const Color red = Color(0xFFE86969);
  static const Color green = Color(0xFF8BD44F);
  static const Color amber = Color(0xFFF2B84B);
  static const Color text = Color(0xFF212121);
  static const Color badgeBg = Color(0xFFB0CDD9);
  static const Color badgeScore = Color(0xFF137C9D);
  static const double radius = 18;
}

/// Paleta escura usada na câmera de protocolo e no relatório biométrico.
class ProtocolColors {
  ProtocolColors._();

  static const Color background = Color(0xFF0D0E14);
  static const Color surface = Color(0xFF161922);
  static const Color cardDark = Color(0xFF1E1E1E);
  static const Color cardBorder = Color(0xFF282E3D);
  static const Color brandRed = Color(0xFFE51937);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color green = Color(0xFF00E676);
  static const Color yellow = Color(0xFFFFEA00);
  static const Color gold = Color(0xFFFFD700);
  static const Color amber = Color(0xFFFFAB00);
  static const Color orange = Color(0xFFFF9100);
  static const Color pink = Color(0xFFFF4081);
  static const Color red = Color(0xFFFF5252);
  static const Color mutedText = Color(0xFFA0A8B8);
}

class AppTheme {
  AppTheme._();

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

  /// Tema escuro usado sobre a imagem da câmera.
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
