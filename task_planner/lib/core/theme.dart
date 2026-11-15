import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Single source of truth for the app's look: color scheme, typography,
/// and component themes. Screens must not hard-code colors or shapes;
/// read them from [Theme.of].
///
/// Colors are semantic light/dark pairs derived from the Dribbble reference.
/// All HEX values are visual estimates and must be pixel-sampled from the
/// reference images before final sign-off.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final Color surface = surfaceColor(brightness);
  final Color onSurface = onSurfaceColor(brightness);
  final Color surfaceVariant = surfaceVariantColor(brightness);
  final Color onSurfaceVariant = onSurfaceVariantColor(brightness);
  final Color outline = outlineColor(brightness);
  final Color error = errorColor(brightness);
  final Color success = successColor(brightness);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: isDark ? accentDark : accentLight,
    onPrimary: isDark ? surfaceDark : surfaceLight,
    secondary: surfaceVariant,
    onSecondary: onSurface,
    tertiary: isDark ? priorityHighDark : priorityHighLight,
    onTertiary: isDark ? surfaceDark : surfaceLight,
    error: error,
    onError: isDark ? surfaceDark : surfaceLight,
    surface: surface,
    onSurface: onSurface,
    background: isDark ? bgDark : bgLight,
    onBackground: onSurface,
    surfaceContainerLow: surface,
    surfaceContainerHighest: surfaceVariant,
    // Container colors for material widgets (FAB, filled buttons, error chips).
    // These are required because ColorScheme() does not auto-generate them
    // like ColorScheme.fromSeed() does.
    primaryContainer: isDark
        ? const Color(0xFFA3E635)
        : const Color(0xFFA3E635),
    onPrimaryContainer: const Color(0xFF0F172A),
    errorContainer: isDark ? const Color(0xFFFECACA) : const Color(0xFFFEE2E2),
    onErrorContainer: isDark
        ? const Color(0xFF7F1D1D)
        : const Color(0xFF991B1B),
    outlineVariant: outline,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: titleLarge.copyWith(color: scheme.onSurface),
    ),
    // Primary containers: cards, sheets. Softest radius, subtle border.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    // Secondary surfaces: chips, filters, small badges. Tightest radius.
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusChip)),
      side: BorderSide.none,
    ),
    // Tertiary surfaces: inputs, buttons. Moderate radius.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Size.fromHeight would give an infinite minimum width, which
        // crashes layout inside Rows / intrinsic measurement (it broke the
        // members list). Height stays 48; width stays intrinsic.
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusInput)),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: BorderSide(color: error, width: 1.2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusChip)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusChip)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}
