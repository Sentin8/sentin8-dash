// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Organization settings - `/org/{orgId}/settings` (Story 13.1.9).

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

class OrgSettingsPage extends StatelessWidget {
  final String orgId;
  final String? name;
  final String? slug;
  final String? brandingRef;
  final VoidCallback? onSave;

  const OrgSettingsPage({
    super.key,
    required this.orgId,
    this.name,
    this.slug,
    this.brandingRef,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final nameCtl = TextEditingController(text: name ?? '');
    final slugCtl = TextEditingController(text: slug ?? '');
    return Scaffold(
      backgroundColor: Sentin8DesignTokens.obsidianBlack,
      appBar: AppBar(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        title: Text('Organization settings', style: Sentin8Typography.h2),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassPanel(
            padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('General', style: Sentin8Typography.h1),
                const SizedBox(height: Sentin8DesignTokens.space4),
                Sentin8Input(label: 'Organization name', controller: nameCtl),
                const SizedBox(height: Sentin8DesignTokens.space3),
                Sentin8Input(label: 'Slug', controller: slugCtl),
                const SizedBox(height: Sentin8DesignTokens.space3),
                Sentin8Input(label: 'Branding ref', hint: brandingRef ?? ''),
                const SizedBox(height: Sentin8DesignTokens.space4),
                Sentin8PrimaryButton(label: 'Save changes', icon: Icons.save_outlined, onPressed: onSave),
              ],
            ),
          ),
        ),
      ),
    );
  }
}