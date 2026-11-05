import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  static ThemeData get enterpriseDark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.spaceBlue,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentCyan,
        secondary: AppColors.accentBlue,
        surface: AppColors.surfaceNavy,
        error: AppColors.dangerRose,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white),
        displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
        bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.white),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white38),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceNavy,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.glassWhite),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.glassWhite,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}
