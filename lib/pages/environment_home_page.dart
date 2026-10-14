// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Environment home page — the main dashboard with left rail navigation.
//
// Shows dynamic service cards discovered at runtime from the module registry
// (sentin8_vertical_services.admin_ui, populated by `sentin8-cli vertical enroll`).
// The dash has zero compile-time knowledge of which services exist.

import 'package:flutter/material.dart';

import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';
import 'package:sentin8/sentin8.dart' hide Sentin8Colors, Sentin8Text, Sentin8Spacing, Sentin8ColorsDark, GlassPanel;
import '../widgets/icon_lookup.dart';

class EnvironmentHomePage extends StatefulWidget {
  final String orgId;
  final String envId;
  const EnvironmentHomePage(
      {super.key, required this.orgId, required this.envId});
  @override
  State<EnvironmentHomePage> createState() => _EnvironmentHomePageState();
}

class _EnvironmentHomePageState extends State<EnvironmentHomePage> {
  Map<String, dynamic>? _env;
  Map<String, dynamic>? _org;
  String _orgDomain = '';
  String? _error;
  List<VerticalService> _services = [];
  bool _servicesLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final auth = AuthProvider.instance;
      await auth.ready;
      final sys = auth.services!.sys;
      // Fetch env, org, and module services in parallel.
      final envRes =
          await sys.get('/v1/env/${widget.envId}');
      // Resolve org_id from env response when orgId is empty (env_id is globally unique).
      final resolvedOrgId = widget.orgId.isNotEmpty ? widget.orgId : (envRes['org_id'] as String? ?? '');
      final orgRes = resolvedOrgId.isNotEmpty ? await sys.get('/v1/org/$resolvedOrgId') : <String, dynamic>{};

      // Fetch module services via the Sys API client (routes through BFF proxy).
      List<VerticalService> services = [];
      try {
        final modulesRes = await sys.get(
            '/v1/verticals/services?env_id=${widget.envId}');
        if (modulesRes is List) {
          services = VerticalService.fromJsonList(modulesRes);
        } else if (modulesRes['data'] is List) {
          services = VerticalService.fromJsonList(modulesRes['data']);
        }
      } catch (_) {}

      if (!mounted) return;
      final orgSlug = orgRes['slug'] as String? ?? '';
      final customDomain = orgRes['custom_domain'] as String?;
      final orgRoot = auth.orgDomain(slug: orgSlug, customDomain: customDomain);
      final envSlug = envRes['slug'] as String? ?? '';
      final envDomain = envSlug.isEmpty
          ? ''
          : auth.envDomain(orgDomain: orgRoot, envSlug: envSlug);
      setState(() {
        _env = envRes;
        _org = orgRes;
        _orgDomain = envDomain;
        _services = services;
        _servicesLoaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final envName = _env?['display_name'] as String? ?? 'Environment';
    final orgName = _org?['display_name'] as String? ?? '';
    final envStatus = _env?['status'] as String? ?? 'active';
    final title = orgName.isNotEmpty ? '$orgName:$envName' : envName;

    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: title,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(_error!,
                  style: const TextStyle(color: Sentin8Colors.errorCrimson))
            else if (_env == null)
              const Center(
                  child:
                      CircularProgressIndicator(color: Sentin8Colors.royalGold))
            else ...[
              // Header row: env name + status badge
              Row(
                children: [
                  Text(title, style: Sentin8Text.h1),
                  const SizedBox(width: Sentin8Spacing.md),
                  StatusBadge(
                    label: envStatus.toUpperCase(),
                    type: envStatus == 'active'
                        ? StatusType.active
                        : StatusType.warning,
                  ),
                ],
              ),
              const SizedBox(height: Sentin8Spacing.lg),

              // Env domain
              SelectableText(
                _orgDomain,
                style: const TextStyle(
                  color: Sentin8Colors.royalGold,
                  fontSize: 16,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: Sentin8Spacing.xl),

              // Services grid (dynamic from module registry)
              Text('Services', style: Sentin8Text.h2),
              const SizedBox(height: Sentin8Spacing.md),
              if (!_servicesLoaded)
                const Center(
                    child: CircularProgressIndicator(
                        color: Sentin8Colors.royalGold))
              else if (_services.isEmpty)
                Text('No services registered.',
                    style: Sentin8Text.bodySecondary)
              else
                _ServiceGrid(
                  orgId: widget.orgId,
                  envId: widget.envId,
                  services: _services,
                  iconForName: iconForName,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grid of service cards built from the module registry.
class _ServiceGrid extends StatelessWidget {
  final String orgId;
  final String envId;
  final List<VerticalService> services;
  final IconData Function(String?) iconForName;
  const _ServiceGrid({
    required this.orgId,
    required this.envId,
    required this.services,
    required this.iconForName,
  });

  @override
  Widget build(BuildContext context) {
    final base = '?env=$envId';
    final enabled = services.where((s) => s.enabled).toList();
    final disabled = services.where((s) => !s.enabled).toList();

    return Wrap(
      spacing: Sentin8Spacing.md,
      runSpacing: Sentin8Spacing.md,
      children: [
        ...enabled.map((s) => _ServiceCard(
              service: s,
              route:
                  '/${s.service}/${s.pages.isNotEmpty ? s.pages.first.route : 'overview'}$base',
              iconForName: iconForName,
            )),
        if (disabled.isNotEmpty) ...[
          const SizedBox(width: double.maxFinite),
          Text('Disabled',
              style: TextStyle(color: Sentin8Colors.textMuted, fontSize: 13)),
          ...disabled.map((s) => _ServiceCard(
                service: s,
                route:
                    '/${s.service}/${s.pages.isNotEmpty ? s.pages.first.route : 'overview'}$base',
                iconForName: iconForName,
                disabled: true,
              )),
        ],
      ],
    );
  }
}

/// A single service card with icon, name, page count, and tap action.
class _ServiceCard extends StatelessWidget {
  final VerticalService service;
  final String route;
  final IconData Function(String?) iconForName;
  final bool disabled;
  const _ServiceCard({
    required this.service,
    required this.route,
    required this.iconForName,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : () => Navigator.pushNamed(context, route),
      child: GlassPanel(
        padding: const EdgeInsets.all(Sentin8Spacing.lg),
        child: SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x26C6A667),
                      borderRadius: BorderRadius.circular(Sentin8Radii.medium),
                    ),
                    child: Icon(iconForName(service.icon),
                        size: 20, color: Sentin8Colors.royalGold),
                  ),
                  const SizedBox(width: Sentin8Spacing.md),
                  Expanded(
                    child: Text(
                      () {
                        // Identity prefix before the vertical separator
                        // (colon identity with legacy hyphen fallback).
                        final prefix = service.service.split(':').first.split('-').first;
                        return prefix.isEmpty || prefix == service.service
                            ? service.label
                            : '${prefix[0].toUpperCase()}${prefix.substring(1)}:${service.label}';
                      }(),
                      style: Sentin8Text.h3,
                    ),
                  ),
                  if (disabled)
                    const Icon(Icons.lock_outline,
                        size: 14, color: Sentin8Colors.textMuted)
                  else
                    const Icon(Icons.chevron_right,
                        size: 18, color: Sentin8Colors.textMuted),
                ],
              ),
              const SizedBox(height: Sentin8Spacing.sm),
              Text(
                '${service.pages.length} admin pages',
                style: Sentin8Text.bodySecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
