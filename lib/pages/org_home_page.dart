// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Organization home - `/org/{orgId}` (Story 13.1.8).
//
// Lists the environments belonging to the active organization and routes to
// environment creation or environment home.

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

class OrgHomePage extends StatelessWidget {
  final String orgId;
  final List<Map<String, dynamic>> environments;
  final VoidCallback? onCreate;

  const OrgHomePage({
    super.key,
    required this.orgId,
    this.environments = const [],
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sentin8DesignTokens.obsidianBlack,
      appBar: AppBar(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        title: Text('Organization · $orgId', style: Sentin8Typography.h2),
        actions: [
          Sentin8PrimaryButton(label: 'New environment', icon: Icons.add, onPressed: onCreate),
        ],
      ),
      body: environments.isEmpty
          ? Center(
              child: GlassPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers_outlined, size: 48, color: Sentin8DesignTokens.softGold),
                    const SizedBox(height: Sentin8DesignTokens.space3),
                    Text('No environments yet', style: Sentin8Typography.h2),
                    const SizedBox(height: Sentin8DesignTokens.space2),
                    Sentin8OutlineButton(label: 'Create environment', onPressed: onCreate),
                  ],
                ),
              ),
            )
          : GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
              childAspectRatio: 1.6,
              children: environments.map((e) => _envCard(e)).toList(),
            ),
    );
  }

  Widget _envCard(Map<String, dynamic> e) {
    return GlassPanel(
      padding: const EdgeInsets.all(Sentin8DesignTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((e['name'] as String?) ?? 'Environment', style: Sentin8Typography.h2),
          const SizedBox(height: Sentin8DesignTokens.space2),
          Text('Type: ${(e['type'] as String?) ?? 'sandbox'}', style: Sentin8Typography.caption),
          const Spacer(),
          Sentin8Badge(
            label: (e['type'] as String?) ?? 'sandbox',
            tone: (e['type'] == 'production') ? Sentin8BadgeTone.success : Sentin8BadgeTone.info,
          ),
        ],
      ),
    );
  }
}