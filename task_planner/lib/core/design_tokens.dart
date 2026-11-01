/// Centralized design tokens for the Task Planner visual identity.
///
/// All color values below are visual estimates derived from the Dribbble
/// reference screenshots. They must be pixel-sampled from the reference
/// images before final sign-off.
///
/// Tokens are defined per brightness so the same component code renders
/// correctly in both dark and light modes. `ThemeData` and `ColorScheme`
/// remain the single source of truth for component theming; this file only
/// supplies the semantic values.

import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Colors (semantic, per brightness)
/// ---------------------------------------------------------------------------

/// Background color for scaffolds and page chrome.
const Color bgDark = Color(0xFF0F172A);
const Color bgLight = Color(0xFFF8FAFC);

/// Card and primary container surfaces.
const Color surfaceDark = Color(0xFF1E293B);
const Color surfaceLight = Color(0xFFFFFFFF);

/// Subtle containers, inputs, and secondary surfaces.
const Color surfaceVariantDark = Color(0xFF334155);
const Color surfaceVariantLight = Color(0xFFF1F5F9);

/// Primary text on dark / light surfaces.
const Color onSurfaceDark = Color(0xFFFFFFFF);
const Color onSurfaceLight = Color(0xFF0F172A);

/// Secondary text, metadata, captions.
const Color onSurfaceVariantDark = Color(0xFFCBD5E1);
const Color onSurfaceVariantLight = Color(0xFF64748B);

/// Dividers and borders.
const Color outlineDark = Color(0xFF334155);
const Color outlineLight = Color(0xFFCBD5E1);

/// Priority colors (data model: low / medium / high).
const Color priorityHighDark = Color(0xFFBEF264);
const Color priorityHighLight = Color(0xFFBEF264);
const Color priorityMediumDark = Color(0xFF22D3EE);
const Color priorityMediumLight = Color(0xFF22D3EE);
const Color priorityLowDark = Color(0xFFC4B5FD);
const Color priorityLowLight = Color(0xFFC4B5FD);

/// Accent color for active states, FAB, today pill.
const Color accentDark = Color(0xFFA3E635);
const Color accentLight = Color(0xFFA3E635);

/// Semantic error and success.
const Color errorDark = Color(0xFFF87171);
const Color errorLight = Color(0xFFEF4444);
const Color successDark = Color(0xFF34D399);
const Color successLight = Color(0xFF10B981);

/// ---------------------------------------------------------------------------
/// Accessibility contrast notes (to be verified against sampled colors)
/// ---------------------------------------------------------------------------
///
/// - priorityHigh / priorityMedium / priorityLow on `surfaceDark`:
///   text drawn on these cards must be dark (near-black) to meet WCAG AA
///   contrast; do not use white text on these light priority cards.
/// - accent on `surfaceDark` / `surfaceLight`: verify contrast for white
///   text on the accent fill.
/// - error / success on `surfaceDark` / `surfaceLight`: verify contrast.

/// Returns the semantic color for [brightness] when a light/dark pair exists.
Color surfaceColor(Brightness brightness) =>
    brightness == Brightness.dark ? surfaceDark : surfaceLight;

Color surfaceVariantColor(Brightness brightness) =>
    brightness == Brightness.dark ? surfaceVariantDark : surfaceVariantLight;

Color onSurfaceColor(Brightness brightness) =>
    brightness == Brightness.dark ? onSurfaceDark : onSurfaceLight;

Color onSurfaceVariantColor(Brightness brightness) =>
    brightness == Brightness.dark ? onSurfaceVariantDark : onSurfaceVariantLight;

Color outlineColor(Brightness brightness) =>
    brightness == Brightness.dark ? outlineDark : outlineLight;

Color errorColor(Brightness brightness) =>
    brightness == Brightness.dark ? errorDark : errorLight;

Color successColor(Brightness brightness) =>
    brightness == Brightness.dark ? successDark : successLight;

Color priorityHighColor(Brightness brightness) =>
    brightness == Brightness.dark ? priorityHighDark : priorityHighLight;

Color priorityMediumColor(Brightness brightness) =>
    brightness == Brightness.dark ? priorityMediumDark : priorityMediumLight;

Color priorityLowColor(Brightness brightness) =>
    brightness == Brightness.dark ? priorityLowDark : priorityLowLight;

/// ---------------------------------------------------------------------------
/// Typography scale
/// ---------------------------------------------------------------------------

/// Hero headline ("Every Day Your Task Plan").
const TextStyle displayLarge = TextStyle(
  fontSize: 32,
  fontWeight: FontWeight.bold,
);

/// Section headers and app bar titles.
const TextStyle titleLarge = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// Card titles.
const TextStyle bodyLarge = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w500,
);

/// Subtitles, metadata.
const TextStyle bodyMedium = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.normal,
);

/// Captions ("10 task"), percentages.
const TextStyle bodySmall = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.normal,
);

/// Chip text, time labels.
const TextStyle labelLarge = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w500,
);

/// ---------------------------------------------------------------------------
/// Spacing scale (8px grid)
/// ---------------------------------------------------------------------------

const double spaceXs = 4;
const double spaceS = 8;
const double spaceM = 12;
const double spaceL = 16;
const double spaceXL = 20;
const double spaceXXL = 24;

/// ---------------------------------------------------------------------------
/// Corner radius scale
/// ---------------------------------------------------------------------------

const double radiusCard = 16; // cards, sheets
const double radiusChip = 8; // chips, filters, badges
const double radiusInput = 12; // inputs, buttons
const double radiusAvatar = 20; // circular avatars (overflow)
