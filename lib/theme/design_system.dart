// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Design System - colors, typography, glass panels, buttons, inputs,
// tables, badges (Story 13.1.2).
//
// Token-based design system used by Dash pages. Mirrors the tokens in
// lib/theme.dart but exposes them as higher-level building blocks (panels,
// buttons, inputs, tables, badges) for fast page scaffolding.

import 'package:flutter/material.dart';

/// Sentin8 design tokens.
class Sentin8DesignTokens {
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
  static const glassFill = Color(0x0FFFFFFF);
  static const glassBorder = Color(0x1AFFFFFF);
  static const neonGoldGlow = Color(0x66D4AF37);
  static const neonCrimsonGlow = Color(0x66D64545);

  // Radii
  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 16.0;

  // Spacing
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
}

/// Typography presets.
class Sentin8Typography {
  static const display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: Sentin8DesignTokens.textPrimary,
    letterSpacing: -0.5,
  );
  static const h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: Sentin8DesignTokens.textPrimary,
  );
  static const h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Sentin8DesignTokens.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 14,
    color: Sentin8DesignTokens.textPrimary,
  );
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Sentin8DesignTokens.textSecondary,
  );
  static const caption = TextStyle(
    fontSize: 11,
    color: Sentin8DesignTokens.textMuted,
  );
}

/// A frosted-glass panel used as the default surface for cards and shelves.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double? width;

  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(Sentin8DesignTokens.space4), this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Sentin8DesignTokens.glassFill,
        borderRadius: BorderRadius.circular(Sentin8DesignTokens.radiusLg),
        border: Border.all(color: Sentin8DesignTokens.glassBorder),
      ),
      child: child,
    );
  }
}

/// Primary gold-toned button.
class Sentin8PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const Sentin8PrimaryButton({super.key, required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Sentin8DesignTokens.royalGold,
        foregroundColor: Sentin8DesignTokens.obsidianBlack,
        padding: const EdgeInsets.symmetric(horizontal: Sentin8DesignTokens.space6, vertical: Sentin8DesignTokens.space3),
      ),
    );
  }
}

/// Secondary outline button.
class Sentin8OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const Sentin8OutlineButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Sentin8DesignTokens.softGold,
        side: const BorderSide(color: Sentin8DesignTokens.glassBorder),
        padding: const EdgeInsets.symmetric(horizontal: Sentin8DesignTokens.space6, vertical: Sentin8DesignTokens.space3),
      ),
      child: Text(label),
    );
  }
}

/// Standard text input with a glass border.
class Sentin8Input extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final bool obscure;
  final String? hint;

  const Sentin8Input({
    super.key,
    required this.label,
    this.controller,
    this.obscure = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: Sentin8Typography.label,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sentin8DesignTokens.radiusMd),
          borderSide: const BorderSide(color: Sentin8DesignTokens.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sentin8DesignTokens.radiusMd),
          borderSide: const BorderSide(color: Sentin8DesignTokens.royalGold),
        ),
      ),
    );
  }
}

/// A glass-styled data table for list views.
class Sentin8Table extends StatelessWidget {
  final List<String> columns;
  final List<List<Widget>> rows;

  const Sentin8Table({super.key, required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: DataTable(
        columns: columns
            .map((c) => DataColumn(label: Text(c, style: Sentin8Typography.label)))
            .toList(),
        rows: rows
            .map((r) => DataRow(cells: r.map((cell) => DataCell(cell)).toList()))
            .toList(),
      ),
    );
  }
}

/// A small status badge with semantic color.
class Sentin8Badge extends StatelessWidget {
  final String label;
  final Sentin8BadgeTone tone;

  const Sentin8Badge({super.key, required this.label, this.tone = Sentin8BadgeTone.neutral});

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      Sentin8BadgeTone.success => Sentin8DesignTokens.successGold,
      Sentin8BadgeTone.warning => Sentin8DesignTokens.warningAmber,
      Sentin8BadgeTone.error => Sentin8DesignTokens.errorCrimson,
      Sentin8BadgeTone.info => Sentin8DesignTokens.infoSoftGold,
      Sentin8BadgeTone.neutral => Sentin8DesignTokens.textMuted,
    };
    return Chip(
      label: Text(label, style: Sentin8Typography.caption),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}

enum Sentin8BadgeTone { success, warning, error, info, neutral }