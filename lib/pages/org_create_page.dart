// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Organization creation flow — `/org/create` (Story 13.1.7).

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

class OrgCreatePage extends StatelessWidget {
  final Future<void> Function({required String name, required String slug})? onSubmit;

  const OrgCreatePage({super.key, this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final name = TextEditingController();
    final slug = TextEditingController();
    return Scaffold(
      backgroundColor: Sentin8DesignTokens.obsidianBlack,
      appBar: AppBar(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        title: Text('Create organization', style: Sentin8Typography.h2),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: GlassPanel(
            padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New organization', style: Sentin8Typography.h1),
                const SizedBox(height: Sentin8DesignTokens.space4),
                Sentin8Input(label: 'Organization name', controller: name),
                const SizedBox(height: Sentin8DesignTokens.space3),
                Sentin8Input(label: 'Slug', controller: slug, hint: 'lowercase, no spaces'),
                const SizedBox(height: Sentin8DesignTokens.space4),
                Sentin8PrimaryButton(
                  label: 'Create organization',
                  icon: Icons.add,
                  onPressed: () => onSubmit?.call(name: name.text, slug: slug.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}