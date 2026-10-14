// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Member management — `/org/{orgId}/members` (Story 13.1.10).

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

class MembersPage extends StatelessWidget {
  final String orgId;
  final List<Map<String, dynamic>> members;
  final VoidCallback? onInvite;

  const MembersPage({
    super.key,
    required this.orgId,
    this.members = const [],
    this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sentin8DesignTokens.obsidianBlack,
      appBar: AppBar(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        title: Text('Members · $orgId', style: Sentin8Typography.h2),
        actions: [
          Sentin8PrimaryButton(label: 'Invite member', icon: Icons.person_add_outlined, onPressed: onInvite),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
        child: members.isEmpty
            ? Center(
                child: GlassPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.group_outlined, size: 48, color: Sentin8DesignTokens.softGold),
                      const SizedBox(height: Sentin8DesignTokens.space3),
                      Text('No members yet', style: Sentin8Typography.h2),
                    ],
                  ),
                ),
              )
            : Sentin8Table(
                columns: const ['Member', 'Email', 'Role', 'Status'],
                rows: members.map((m) => [
                      Text((m['name'] as String?) ?? '', style: Sentin8Typography.body),
                      Text((m['email'] as String?) ?? '', style: Sentin8Typography.body),
                      Text((m['role'] as String?) ?? '', style: Sentin8Typography.body),
                      Sentin8Badge(label: (m['status'] as String?) ?? 'active'),
                    ]).toList(),
              ),
      ),
    );
  }
}