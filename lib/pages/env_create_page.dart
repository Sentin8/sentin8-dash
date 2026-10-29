// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Environment creation - `/org/{orgId}/env/create` (Story 13.1.11).

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

class EnvCreatePage extends StatelessWidget {
  final String orgId;
  final Future<void> Function({required String name, required String type})? onSubmit;

  const EnvCreatePage({super.key, required this.orgId, this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final name = TextEditingController();
    String type = 'sandbox';
    return StatefulBuilder(
      builder: (context, setState) => Scaffold(
        backgroundColor: Sentin8DesignTokens.obsidianBlack,
        appBar: AppBar(
          backgroundColor: Sentin8DesignTokens.carbonBlack,
          title: Text('Create environment', style: Sentin8Typography.h2),
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
                  Text('New environment in $orgId', style: Sentin8Typography.h1),
                  const SizedBox(height: Sentin8DesignTokens.space4),
                  Sentin8Input(label: 'Environment name', controller: name),
                  const SizedBox(height: Sentin8DesignTokens.space3),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'sandbox', child: Text('Sandbox')),
                      DropdownMenuItem(value: 'production', child: Text('Production')),
                    ],
                    onChanged: (v) => setState(() => type = v ?? 'sandbox'),
                  ),
                  const SizedBox(height: Sentin8DesignTokens.space4),
                  Sentin8PrimaryButton(
                    label: 'Create environment',
                    icon: Icons.add,
                    onPressed: () => onSubmit?.call(name: name.text, type: type),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}