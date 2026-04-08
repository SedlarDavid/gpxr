import 'package:flutter/material.dart';

class AppTheme {
  static const _primaryColor = Color(0xFF6366F1);
  static const _surfaceColor = Color(0xFFFAFAFB);
  static const _cardColor = Colors.white;
  static const _borderColor = Color(0xFFE5E7EB);
  static const _textPrimary = Color(0xFF111827);
  static const _textSecondary = Color(0xFF6B7280);
  static const _trackColor = Color(0xFF6366F1);
  static const _trackColorAlt = Color(0xFF8B5CF6);

  static Color get primaryColor => _primaryColor;
  static Color get surfaceColor => _surfaceColor;
  static Color get cardColor => _cardColor;
  static Color get borderColor => _borderColor;
  static Color get textPrimary => _textPrimary;
  static Color get textSecondary => _textSecondary;
  static Color get trackColor => _trackColor;
  static Color get trackColorAlt => _trackColorAlt;

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        brightness: Brightness.light,
        surface: _surfaceColor,
      ),
      scaffoldBackgroundColor: _surfaceColor,
      cardTheme: CardThemeData(
        color: _cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _borderColor, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        bodyMedium: TextStyle(color: _textPrimary),
        bodySmall: TextStyle(color: _textSecondary),
        labelMedium: TextStyle(
          color: _textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _textPrimary,
          side: const BorderSide(color: _borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _textSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      dividerTheme: const DividerThemeData(
        color: _borderColor,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceColor,
        selectedColor: _primaryColor.withValues(alpha: 0.1),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        side: const BorderSide(color: _borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
