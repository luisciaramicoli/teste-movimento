import 'package:flutter/material.dart';

/// Identidade visual clínica: superfícies planas, uma única cor de destaque,
/// sem sombras, brilhos, gradientes ou animações decorativas.
class AppColors {
  static const Color background = Color(0xFF0F1419);
  static const Color surface = Color(0xFF171D24);
  static const Color surfaceAlt = Color(0xFF1E252D);
  static const Color border = Color(0xFF2B343E);
  static const Color textPrimary = Color(0xFFE8ECF0);
  static const Color textSecondary = Color(0xFF9AA5B1);
  static const Color accent = Color(0xFF4F9FD6);
  static const Color ok = Color(0xFF4CAF86);
  static const Color warn = Color(0xFFD9A441);
  static const Color error = Color(0xFFD9645A);
}

class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF06121C),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      outline: AppColors.border,
    );
    const radius = BorderRadius.all(Radius.circular(6));
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: NoSplash.splashFactory,
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF06121C),
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.border),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
}

class AppText {
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
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
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const TextStyle value = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
