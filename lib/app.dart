// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Dash app shell - `DashApp` widget (Story 13.1.1, second half).
//
// Wraps the router with providers and the Sentin8 theme. Apps that already have
// a `main.dart` with `DashApp` defined can keep using it; this file exposes
// the same widget for direct import.

import 'package:flutter/material.dart';

import 'theme/design_system.dart';
import 'router.dart';

class DashApp extends StatelessWidget {
  final DashRouter? router;

  const DashApp({super.key, this.router});

  @override
  Widget build(BuildContext context) {
    final r = router ?? DashRouter();
    return MaterialApp.router(
      title: 'Sentin8 Dashboard',
      theme: _sentin8Theme(),
      debugShowCheckedModeBanner: false,
      routerConfig: r.config,
    );
  }

  ThemeData _sentin8Theme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Sentin8DesignTokens.obsidianBlack,
      colorScheme: const ColorScheme.dark(
        primary: Sentin8DesignTokens.royalGold,
        onPrimary: Sentin8DesignTokens.obsidianBlack,
        secondary: Sentin8DesignTokens.softGold,
        surface: Sentin8DesignTokens.carbonBlack,
        error: Sentin8DesignTokens.errorCrimson,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        foregroundColor: Sentin8DesignTokens.textPrimary,
      ),
      textTheme: const TextTheme(
        displayLarge: Sentin8Typography.display,
        headlineMedium: Sentin8Typography.h1,
        headlineSmall: Sentin8Typography.h2,
        bodyMedium: Sentin8Typography.body,
        labelSmall: Sentin8Typography.label,
      ),
    );
  }
}