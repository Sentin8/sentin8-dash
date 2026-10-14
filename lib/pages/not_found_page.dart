// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Not found page — 404 fallback.
import 'package:flutter/material.dart';
import '../theme.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Sentin8Colors.warningAmber),
              const SizedBox(height: Sentin8Spacing.lg),
              Text('Page Not Found', style: Sentin8Text.h1),
              const SizedBox(height: Sentin8Spacing.sm),
              Text('The page you are looking for does not exist.', style: Sentin8Text.bodySecondary),
              const SizedBox(height: Sentin8Spacing.xl),
              FilledButton(onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false), child: Text('Go Home')),
            ],
          ),
        ),
      ),
    );
  }
}