// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Design System — Theme tokens for Dash.
// Implements the design system defined in design/sentin8-design-system.md.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sentin8 color palette.
class Sentin8Colors {
  // Primary palette
  static const obsidianBlack = Color(0xFF0A0A0A);
  static const carbonBlack = Color(0xFF111111);
  static const matteGraphite = Color(0xFF1C1C1C);
  static const royalGold = Color(0xFFD4AF37);
  static const softGold = Color(0xFFE6C878);

  // Semantic
  static const successGold = Color(0xFFC6A667);
  static const warningAmber = Color(0xFFFFB84D);
  static const errorCrimson = Color(0xFFD64545);
  static const infoSoftGold = Color(0xFFE8D9A8);

  // Text
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFFA0A0A0);
  static const textMuted = Color(0xFF6E6E6E);

  // Surfaces
  static const glassFill = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const neonGoldGlow = Color(0x66D4AF37); // rgba(212,175,55,0.40)
  static const neonCrimsonGlow = Color(0x66D64545);

  // Row hover
  static const rowHover = Color(0x0AFFFFFF); // rgba(255,255,255,0.04)
  static const rowSelected = Color(0x14D4AF37); // rgba(212,175,55,0.08)
}

/// Sentin8 typography scale.
class Sentin8Text {
  /// Page titles — uses the same font as the Sentin8 logo (Rock Salt).
  static TextStyle get h1 => GoogleFonts.quicksand(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: Sentin8Colors.textPrimary,
        height: 1.2,
      );
  static TextStyle get h2 => GoogleFonts.quicksand(fontSize: 24, fontWeight: FontWeight.w600, color: Sentin8Colors.textPrimary, height: 1.3);
  static TextStyle get h3 => GoogleFonts.quicksand(fontSize: 20, fontWeight: FontWeight.w500, color: Sentin8Colors.textPrimary, height: 1.4);
  static TextStyle get body => GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.w400, color: Sentin8Colors.textPrimary, height: 1.5);
  static TextStyle get bodySecondary => GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.w400, color: Sentin8Colors.textSecondary, height: 1.5);
  static TextStyle get caption => GoogleFonts.quicksand(fontSize: 12, fontWeight: FontWeight.w400, color: Sentin8Colors.textMuted, height: 1.4);
  static TextStyle get label => GoogleFonts.quicksand(fontSize: 12, fontWeight: FontWeight.w500, color: Sentin8Colors.textSecondary, height: 1.2);
  static const mono = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Sentin8Colors.textPrimary, fontFamily: 'monospace', height: 1.4);
}

/// Sentin8 spacing (4px grid).
class Sentin8Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

/// Sentin8 border radii.
class Sentin8Radii {
  static const small = 4.0;
  static const medium = 8.0;
  static const large = 12.0;
  static const xl = 16.0;
}

/// Sentin8 shadow elevations.
class Sentin8Shadows {
  static const level1 = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const level2 = [
    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const level3 = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const level4 = [
    BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const level5 = [
    BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 12)),
  ];
}

/// Builds the Sentin8 dark theme for MaterialApp.
ThemeData sentin8Theme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Sentin8Colors.royalGold,
      brightness: Brightness.dark,
    ).copyWith(
      surface: Sentin8Colors.obsidianBlack,
      primary: Sentin8Colors.royalGold,
      onPrimary: Sentin8Colors.obsidianBlack,
      secondary: Sentin8Colors.softGold,
      error: Sentin8Colors.errorCrimson,
    ),
    scaffoldBackgroundColor: Sentin8Colors.obsidianBlack,
    cardColor: Sentin8Colors.carbonBlack,
    dividerColor: Sentin8Colors.glassBorder,
    textTheme: TextTheme(
      displayLarge: Sentin8Text.h1,
      displayMedium: Sentin8Text.h2,
      titleLarge: Sentin8Text.h3,
      bodyLarge: Sentin8Text.body,
      bodyMedium: Sentin8Text.bodySecondary,
      labelLarge: Sentin8Text.label,
      labelSmall: Sentin8Text.caption,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Sentin8Colors.matteGraphite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.royalGold, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.errorCrimson),
      ),
      labelStyle: const TextStyle(color: Sentin8Colors.textMuted),
      hintStyle: const TextStyle(color: Sentin8Colors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Sentin8Colors.royalGold,
        foregroundColor: Sentin8Colors.obsidianBlack,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Sentin8Colors.royalGold,
        foregroundColor: Sentin8Colors.obsidianBlack,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Sentin8Colors.royalGold,
        side: const BorderSide(color: Sentin8Colors.royalGold),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Sentin8Colors.textSecondary),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(Sentin8Colors.carbonBlack),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Sentin8Colors.rowSelected;
        if (states.contains(WidgetState.hovered)) return Sentin8Colors.rowHover;
        return Colors.transparent;
      }),
      headingTextStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Sentin8Colors.textSecondary),
      dataTextStyle: const TextStyle(fontSize: 14, color: Sentin8Colors.textPrimary),
      horizontalMargin: Sentin8Spacing.md,
      columnSpacing: Sentin8Spacing.lg,
      dividerThickness: 0.5,
    ),
    cardTheme: CardThemeData(
      color: Sentin8Colors.carbonBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.large),
        side: const BorderSide(color: Sentin8Colors.glassBorder),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Sentin8Colors.carbonBlack,
      contentTextStyle: const TextStyle(color: Sentin8Colors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
    ),
  );
}

/// A glass panel container — the primary surface element.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  const GlassPanel({super.key, required this.child, this.padding, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(Sentin8Spacing.lg),
      decoration: BoxDecoration(
        color: Sentin8Colors.carbonBlack,
        borderRadius: BorderRadius.circular(Sentin8Radii.large),
        border: Border.all(color: Sentin8Colors.glassBorder),
        boxShadow: Sentin8Shadows.level2,
      ),
      child: child,
    );
  }
}

/// Status badge widget.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType type;

  const StatusBadge({super.key, required this.label, required this.type});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Sentin8Radii.small),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  (Color, Color) _colors(StatusType t) => switch (t) {
    StatusType.active   => (const Color(0x26C6A667), Sentin8Colors.successGold),
    StatusType.warning   => (const Color(0x26FFB84D), Sentin8Colors.warningAmber),
    StatusType.error     => (const Color(0x26D64545), Sentin8Colors.errorCrimson),
    StatusType.info      => (const Color(0x26E8D9A8), Sentin8Colors.infoSoftGold),
    StatusType.role      => (const Color(0x26D4AF37), Sentin8Colors.softGold),
  };
}

enum StatusType { active, warning, error, info, role }