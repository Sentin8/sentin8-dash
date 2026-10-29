// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// LeftRail - Dash left navigation rail (Story 13.1.3).
//
// Contains the Sentin8 logo, feature-area navigation, user menu, and the
// organization/environment selector. Rendered as the start drawer of the
// main Scaffold in the authenticated shell.

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// A single navigation destination in the left rail.
class NavEntry {
  final String label;
  final IconData icon;
  final String route;

  const NavEntry({required this.label, required this.icon, required this.route});
}

/// The left rail navigation widget.
class LeftRail extends StatelessWidget {
  final String currentRoute;
  final ValueChanged<String> onNavigate;
  final List<NavEntry> entries;
  final String? orgLabel;
  final String? envLabel;
  final VoidCallback? onPickOrg;
  final VoidCallback? onPickEnv;
  final String? userLabel;
  final VoidCallback? onSignOut;

  const LeftRail({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
    this.entries = const [
      NavEntry(label: 'Overview', icon: Icons.dashboard_outlined, route: '/'),
      NavEntry(label: 'Ledger', icon: Icons.account_balance_outlined, route: '/ledger'),
      NavEntry(label: 'Payments', icon: Icons.send_outlined, route: '/payments'),
      NavEntry(label: 'FDX', icon: Icons.handshake_outlined, route: '/fdx'),
      NavEntry(label: 'App Store', icon: Icons.apps_outlined, route: '/app'),
      NavEntry(label: 'Audit', icon: Icons.history, route: '/audit'),
      NavEntry(label: 'Settings', icon: Icons.settings_outlined, route: '/settings'),
    ],
    this.orgLabel,
    this.envLabel,
    this.onPickOrg,
    this.onPickEnv,
    this.userLabel,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Sentin8DesignTokens.carbonBlack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sentin8DesignTokens.space4,
              vertical: Sentin8DesignTokens.space4,
            ),
            child: Row(
              children: [
                const Icon(Sentin8Icons.logo, color: Sentin8DesignTokens.royalGold),
                const SizedBox(width: Sentin8DesignTokens.space2),
                Text('Sentin8', style: Sentin8Typography.h1),
              ],
            ),
          ),
          const Divider(height: 1, color: Sentin8DesignTokens.glassBorder),
          // Org/env selector
          _scopeTile(orgLabel ?? 'Select organization', onPickOrg, Icons.business_outlined),
          _scopeTile(envLabel ?? 'Select environment', onPickEnv, Icons.layers_outlined),
          const Divider(height: 1, color: Sentin8DesignTokens.glassBorder),
          // Feature nav
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: Sentin8DesignTokens.space2),
              children: entries.map((e) => _navTile(e)).toList(),
            ),
          ),
          const Divider(height: 1, color: Sentin8DesignTokens.glassBorder),
          // User menu
          ListTile(
            leading: CircleAvatar(child: Text(_initials(userLabel ?? 'Guest'))),
            title: Text(userLabel ?? 'Guest', style: Sentin8Typography.body, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.logout, color: Sentin8DesignTokens.textSecondary),
              onPressed: onSignOut,
              tooltip: 'Sign out',
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeTile(String label, VoidCallback? onTap, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Sentin8DesignTokens.softGold, size: 18),
      title: Text(label, style: Sentin8Typography.body, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: Sentin8DesignTokens.textMuted, size: 16),
      onTap: onTap,
    );
  }

  Widget _navTile(NavEntry e) {
    final selected = currentRoute == e.route || currentRoute.startsWith('${e.route}/');
    return ListTile(
      leading: Icon(e.icon, color: selected ? Sentin8DesignTokens.royalGold : Sentin8DesignTokens.textSecondary),
      title: Text(
        e.label,
        style: selected
            ? Sentin8Typography.body.copyWith(color: Sentin8DesignTokens.royalGold)
            : Sentin8Typography.body,
      ),
      selected: selected,
      onTap: () => onNavigate(e.route),
    );
  }

  String _initials(String label) {
    if (label.isEmpty) return '?';
    final parts = label.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return label[0].toUpperCase();
  }
}

/// Small helper exposing a logo glyph from the icon font fallback.
class Sentin8Icons {
  static const IconData logo = Icons.diamond_outlined;
}