import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _themeStorageKey = 'gpxr.themeMode.v1';

/// Global theme controller. Listened to by [GpxrApp] (via the
/// [AppTheme.themeMode] notifier) to flip the [MaterialApp] between
/// light and dark schemes, and read by every static [AppTheme] color
/// getter so direct callers (we have ~170 of them across the widget
/// tree) automatically pick up the new palette on the next rebuild
/// MaterialApp triggers when the mode changes.
class AppTheme {
  // ── Brand colors (shared across both modes) ────────────────────────
  static const _primaryColor = Color(0xFF6366F1);
  static const _trackColorAlt = Color(0xFF8B5CF6);

  // ── Light palette ──────────────────────────────────────────────────
  static const _lightSurface = Color(0xFFFAFAFB);
  static const _lightCard = Colors.white;
  static const _lightBorder = Color(0xFFE5E7EB);
  static const _lightTextPrimary = Color(0xFF111827);
  static const _lightTextSecondary = Color(0xFF6B7280);

  // ── Dark palette (slate ramp) ──────────────────────────────────────
  // Slightly off-black backgrounds so the chart's primary-color curve
  // and the strava-red track polyline still pop without harsh contrast.
  static const _darkSurface = Color(0xFF0F172A); // slate-900 — scaffold
  static const _darkCard = Color(0xFF1E293B); // slate-800 — sidebar / dialogs
  static const _darkBorder = Color(0xFF334155); // slate-700
  static const _darkTextPrimary = Color(0xFFF1F5F9); // slate-100
  static const _darkTextSecondary = Color(0xFF94A3B8); // slate-400

  /// Drives the whole UI's brightness. The MaterialApp rebuild that
  /// fires when this changes only updates widgets that depend on
  /// [Theme.of] — our ~170 callers of the static color getters below
  /// don't, and their parents are often `const` so Flutter's element
  /// diff skips them. Widgets subscribe via [subscribe] to be marked
  /// dirty on toggle without losing state.
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Call once at the top of any `build` that reads the static color
  /// getters. Registers the calling element as a dependent of the
  /// [AppThemeScope] above it, so a [toggleMode] flips that element
  /// dirty and re-runs its build with the new palette. Cheap — just
  /// `context.dependOnInheritedWidgetOfExactType` under the hood.
  static void subscribe(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
  }

  static bool get _isDark => themeMode.value == ThemeMode.dark;

  /// Reads the persisted preference from localStorage and applies it.
  /// Call once from [main] before [runApp].
  static void init() {
    final v = web.window.localStorage.getItem(_themeStorageKey);
    if (v == ThemeMode.light.name) {
      themeMode.value = ThemeMode.light;
    } else if (v == ThemeMode.dark.name) {
      themeMode.value = ThemeMode.dark;
    }
  }

  /// Flips between light and dark and persists the choice. Wired to
  /// the toolbar's brightness toggle.
  static void toggleMode() {
    themeMode.value = _isDark ? ThemeMode.light : ThemeMode.dark;
    web.window.localStorage
        .setItem(_themeStorageKey, themeMode.value.name);
  }

  // Brand colors are mode-independent — the indigo/violet pair reads
  // well on both backgrounds and changing them would mean reshooting
  // the OG card and favicons.
  static Color get primaryColor => _primaryColor;
  static Color get trackColor => _primaryColor;
  static Color get trackColorAlt => _trackColorAlt;

  // Mode-aware getters used directly by ~170 widget call sites.
  static Color get surfaceColor =>
      _isDark ? _darkSurface : _lightSurface;
  static Color get cardColor => _isDark ? _darkCard : _lightCard;
  static Color get borderColor =>
      _isDark ? _darkBorder : _lightBorder;
  static Color get textPrimary =>
      _isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary =>
      _isDark ? _darkTextSecondary : _lightTextSecondary;

  static ThemeData lightTheme() => _buildTheme(Brightness.light);
  static ThemeData darkTheme() => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? _darkSurface : _lightSurface;
    final card = isDark ? _darkCard : _lightCard;
    final border = isDark ? _darkBorder : _lightBorder;
    final textPrimary = isDark ? _darkTextPrimary : _lightTextPrimary;
    final textSecondary = isDark ? _darkTextSecondary : _lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        brightness: brightness,
        surface: surface,
      ),
      scaffoldBackgroundColor: surface,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        labelMedium: TextStyle(
          color: textSecondary,
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
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: _primaryColor.withValues(alpha: 0.1),
        labelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? _darkBorder : textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// Marks the calling element as a dependent of the theme mode. Wraps
/// [AppTheme.themeMode] so that any descendant calling
/// [AppTheme.subscribe] is rebuilt when the mode flips — even if its
/// parent widget is `const` (which would otherwise short-circuit the
/// element diff and keep stale colors visible after a toggle).
class AppThemeScope extends InheritedNotifier<ValueNotifier<ThemeMode>> {
  AppThemeScope({super.key, required super.child})
      : super(notifier: AppTheme.themeMode);
}
