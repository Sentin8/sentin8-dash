// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Environment settings and branding pages.
// Routes: /org/{orgId}/env/{envId}/settings
//         /org/{orgId}/env/{envId}/branding
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'package:sentin8/sentin8.dart' hide Sentin8Colors, Sentin8Text, Sentin8Spacing, Sentin8ColorsDark, GlassPanel;
import '../widgets/icon_lookup.dart';
import 'nav_shell.dart';

class EnvironmentSettingsPage extends StatelessWidget {
  final String orgId;
  final String envId;
  const EnvironmentSettingsPage(
      {super.key, required this.orgId, required this.envId});

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: orgId,
      envId: envId,
      title: 'Environment Settings',
      child: _SettingsContent(orgId: orgId, envId: envId),
    );
  }
}

class _SettingsContent extends StatefulWidget {
  final String orgId;
  final String envId;
  const _SettingsContent({required this.orgId, required this.envId});

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  Map<String, dynamic>? _env;
  String _orgName = '';
  Map<String, bool> _featureChanges = {};
  List<VerticalService> _verticalServices = [];
  String? _message;

  /// Sentin8 core platform services are always-on and not listed in the
  /// env settings service toggle section. Only vertical services
  /// (bank8-*, hotel8-*, etc.) are shown as toggleable cards.
  static const _corePlatformServices = {
    'auth', 'app', 'bus', 'cron', 'db', 'flow', 'func', 'post', 'stat',
    'storage', 'acme', 'sys',
  };

  bool _isCorePlatformService(String service) =>
      _corePlatformServices.contains(service);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Wait for auth.init() so auth.services is populated before we
      // dereference it (prevents "Null check operator used on a null
      // value" on hard reloads that land on this page before the
      // BFF session metadata is fetched).
      await AuthProvider.instance.ready;
      final services = AuthProvider.instance.services;
      if (services == null) {
        if (mounted) {
          setState(() => _message = 'Error: auth services not initialized');
        }
        return;
      }
      final res =
          await services.sys.get('/v1/env/${widget.envId}');
      // Resolve org_id from env response for display purposes.
      final resolvedOrgId = widget.orgId.isNotEmpty ? widget.orgId : (res['org_id'] as String? ?? '');
      if (resolvedOrgId.isNotEmpty) {
        try {
          final orgRes = await services.sys.get('/v1/org/$resolvedOrgId');
          _orgName = orgRes['display_name'] as String? ?? '';
        } catch (_) {}
      }
      if (!mounted) return;

      // Fetch registered module services from the registry.
      try {
        final modulesRes = await services.sys.get(
            '/v1/verticals/services?env_id=${widget.envId}');
        if (modulesRes is List) {
          _verticalServices = VerticalService.fromJsonList(modulesRes);
        } else if (modulesRes['data'] is List) {
          _verticalServices = VerticalService.fromJsonList(modulesRes['data']);
        }
      } catch (_) {}

      setState(() => _env = res);
    } catch (e) {
      // Show the error instead of silently swallowing it — the previous
      // `catch (_) {}` caused the settings page to render blank when the
      // env fetch failed, with no indication of what went wrong.
      if (mounted) {
        setState(() => _message = 'Error loading environment: $e');
      }
    }
  }

  Future<void> _saveSingle(String key, bool enabled,
      {Map<String, dynamic>? config}) async {
    final sys = AuthProvider.instance.services!.sys;
    try {
      await sys.put('/v1/env/${widget.envId}/services',
          body: {
            'service': key,
            'enabled': enabled,
            if (config != null) 'config': config
          });
      _featureChanges.remove(key);
      // Update the local module list so the toggle reflects the new
      // state immediately — without this, the button text stays as
      // "Enable X" even after the PUT succeeds because _verticalServices
      // is only loaded once in _load().
      if (mounted) {
        setState(() {
          for (final m in _verticalServices) {
            if (m.serviceFlag == key) {
              m.enabled = enabled;
            }
          }
        });
      }
      // Notify the AuthProvider so the sidebar (and any other listeners)
      // immediately pick up the feature change — no page reload needed.
      AuthProvider.instance.notifyFeatureChange();
    } catch (e) {
      if (mounted) setState(() => _message = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Sentin8Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _orgName.isNotEmpty
                ? '$_orgName:${_env!['display_name'] as String? ?? 'Environment'}'
                : 'Environment Settings',
            style: Sentin8Text.h1,
          ),
          const SizedBox(height: Sentin8Spacing.lg),
          if (_env != null) ...[
            _Row(label: 'Name', value: _env!['display_name'] as String? ?? ''),
            const SizedBox(height: Sentin8Spacing.lg),
            // ── Services ─────────────────────────────────────────
            // Dynamic from the module registry (sentin8_vertical_services.admin_ui).
            Text('Services', style: Sentin8Text.h2),
            const SizedBox(height: Sentin8Spacing.md),
            // Only vertical services are listed here — Sentin8 core
            // platform services (auth, app, bus, cron, db, flow, func,
            // post, stat, storage, acme) are always-on and not toggleable.
            ..._verticalServices
                .where((m) => !_isCorePlatformService(m.service))
                .map((m) {
              // Identity prefix before the vertical separator (colon
              // identity with legacy hyphen fallback).
              final modulePrefix = m.service.split(':').first.split('-').first;
              final displayLabel = modulePrefix.isEmpty || modulePrefix == m.service
                  ? m.label
                  : '${modulePrefix[0].toUpperCase()}${modulePrefix.substring(1)}:${m.label}';
              return _FeatureCard(
                name: m.serviceFlag,
                displayName: displayLabel,
                description: '${m.pages.length} admin pages — ${m.serviceFlag}',
                icon: iconForName(m.icon),
                enabled: m.enabled,
                locked: false,
                onChanged: (v) {
                  _saveSingle(m.serviceFlag, v);
                },
              );
            }),
          ],
          if (_message != null) ...[
            const SizedBox(height: Sentin8Spacing.sm),
            Text(_message!,
                style: const TextStyle(color: Sentin8Colors.successGold))
          ],
          const Spacer(),
          const Divider(color: Sentin8Colors.glassBorder),
          const SizedBox(height: Sentin8Spacing.lg),
          Text('Danger Zone',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Sentin8Colors.errorCrimson)),
          const SizedBox(height: Sentin8Spacing.sm),
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_forever,
                color: Sentin8Colors.errorCrimson),
            label: Text('Delete Environment',
                style: TextStyle(color: Sentin8Colors.errorCrimson)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Sentin8Colors.errorCrimson),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sentin8Colors.carbonBlack,
        title: Text('Delete Environment?',
            style: TextStyle(color: Sentin8Colors.errorCrimson)),
        content: Text(
          'This will permanently delete "${_env?['display_name'] ?? 'this environment'}" and ALL its '
          'features, bindings, and app instances. This action cannot be undone.',
          style: const TextStyle(color: Sentin8Colors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteEnv();
            },
            style: FilledButton.styleFrom(
                backgroundColor: Sentin8Colors.errorCrimson),
            child: Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEnv() async {
    setState(() => _message = 'Deleting…');
    try {
      await AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .sys
          .delete('/v1/env/${widget.envId}');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/org/${widget.orgId}', (_) => false);
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Error: $e');
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sentin8Spacing.sm),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: Sentin8Text.label)),
          Expanded(child: Text(value, style: Sentin8Text.body)),
        ],
      ),
    );
  }
}

/// Feature card with icon, name, description, and a toggle switch.
class _FeatureCard extends StatelessWidget {
  final String name;
  final String displayName;
  final String description;
  final IconData icon;
  final bool enabled;
  final bool locked;
  final ValueChanged<bool>? onChanged;

  /// Optional widget rendered below the card when the feature is enabled
  /// (e.g. FDX provider settings).
  final Widget? trailing;
  const _FeatureCard({
    required this.name,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.enabled,
    required this.locked,
    this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 0),
          child: GlassPanel(
            padding: const EdgeInsets.all(Sentin8Spacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: enabled
                        ? const Color(0x26C6A667)
                        : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(Sentin8Radii.medium),
                  ),
                  child: Icon(icon,
                      size: 22,
                      color: enabled
                          ? Sentin8Colors.royalGold
                          : Sentin8Colors.textMuted),
                ),
                const SizedBox(width: Sentin8Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(displayName, style: Sentin8Text.h3),
                          if (locked) ...[
                            const SizedBox(width: Sentin8Spacing.sm),
                            StatusBadge(
                                label: 'Always On', type: StatusType.info),
                          ],
                        ],
                      ),
                      const SizedBox(height: Sentin8Spacing.xs),
                      Text(description, style: Sentin8Text.bodySecondary),
                    ],
                  ),
                ),
                const SizedBox(width: Sentin8Spacing.md),
                // Use a tappable button instead of a Switch — Flutter CanvasKit
                // Switch widgets don't respond to Playwright mouse events in E2E
                // tests. The button has role="button" in semantics, which
                // clickFlutterButton can find and click.
                if (locked)
                  StatusBadge(label: 'On', type: StatusType.active)
                else
                  FilledButton.tonal(
                    onPressed: () => onChanged?.call(!enabled),
                    style: FilledButton.styleFrom(
                      backgroundColor: enabled
                          ? Sentin8Colors.royalGold
                          : const Color(0xFF2A2A2A),
                      foregroundColor: enabled
                          ? Sentin8Colors.carbonBlack
                          : Sentin8Colors.textSecondary,
                    ),
                    child: Text(enabled ? 'Enabled' : 'Enable $displayName'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sentin8Spacing.md),
        // FDX settings (version + clusters) shown below the card when enabled.
        if (trailing != null) trailing!,
      ],
    );
  }
}
