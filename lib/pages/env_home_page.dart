// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Environment home — `?env={envId}`.
// env_id is globally unique — org_id is resolved server-side.
//
// Shows dynamic service cards discovered at runtime from the module registry
// (sentin8_vertical_services.admin_ui, populated by `sentin8-cli vertical enroll`).
// The dash has zero compile-time knowledge of which services exist.

import 'package:flutter/material.dart';

import '../theme/design_system.dart';
import '../auth_provider.dart';
import 'package:sentin8/sentin8.dart' hide Sentin8Colors, Sentin8Text, Sentin8Spacing, Sentin8ColorsDark, GlassPanel;
import '../widgets/icon_lookup.dart';

class EnvHomePage extends StatefulWidget {
  final String orgId;
  final String envId;

  const EnvHomePage({super.key, required this.orgId, required this.envId});

  @override
  State<EnvHomePage> createState() => _EnvHomePageState();
}

class _EnvHomePageState extends State<EnvHomePage> {
  List<VerticalService> _services = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final auth = AuthProvider.instance;
      await auth.ready;
      final sys = auth.services!.sys;
      final modulesRes = await sys.get(
          '/v1/verticals/services?env_id=${widget.envId}');
      if (modulesRes is List) {
        _services = VerticalService.fromJsonList(modulesRes);
      } else if (modulesRes['data'] is List) {
        _services = VerticalService.fromJsonList(modulesRes['data']);
      }
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sentin8DesignTokens.obsidianBlack,
      appBar: AppBar(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        title:
            Text('Environment · ${widget.envId}', style: Sentin8Typography.h2),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load services', style: Sentin8Typography.h2),
            const SizedBox(height: 8),
            Text(_error!, style: Sentin8Typography.caption),
            const SizedBox(height: 16),
            Sentin8OutlineButton(
              label: 'Retry',
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadServices();
              },
            ),
          ],
        ),
      );
    }

    final enabledServices = _services.where((s) => s.enabled).toList();
    final disabledServices = _services.where((s) => !s.enabled).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
            child: Text('Services', style: Sentin8Typography.h2),
          ),
          if (enabledServices.isEmpty && disabledServices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
              child: Text('No services registered.',
                  style: Sentin8Typography.caption),
            ),
          if (enabledServices.isNotEmpty)
            GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children:
                  enabledServices.map((s) => _serviceCard(context, s)).toList(),
            ),
          if (disabledServices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sentin8DesignTokens.space6),
              child:
                  Text('Disabled Services', style: Sentin8Typography.caption),
            ),
            GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: disabledServices
                  .map((s) => _serviceCard(context, s))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _serviceCard(BuildContext context, VerticalService s) {
    final firstPage = s.pages.isNotEmpty ? s.pages.first.route : 'overview';
    final route = '/${s.service}/$firstPage?env=${widget.envId}';

    return GlassPanel(
      padding: const EdgeInsets.all(Sentin8DesignTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconForName(s.icon), color: Sentin8DesignTokens.softGold),
              const SizedBox(width: Sentin8DesignTokens.space2),
              Expanded(
                  child: Text(
                    () {
                      // Identity prefix before the vertical separator
                      // (`bank8:ledger` → `Bank8:Ledger`). Colon identity
                      // (architecture-principles.md §6.0) with legacy
                      // hyphen fallback.
                      final prefix = s.service.split(':').first.split('-').first;
                      return prefix.isEmpty || prefix == s.service
                          ? s.label
                          : '${prefix[0].toUpperCase()}${prefix.substring(1)}:${s.label}';
                    }(),
                    style: Sentin8Typography.h2,
                    overflow: TextOverflow.ellipsis)),
              Sentin8Badge(
                label: s.enabled ? 'On' : 'Off',
                tone: s.enabled
                    ? Sentin8BadgeTone.success
                    : Sentin8BadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: Sentin8DesignTokens.space2),
          Text('${s.pages.length} pages',
              style: Sentin8Typography.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const Spacer(),
          Sentin8OutlineButton(
            label: 'Open',
            onPressed:
                s.enabled ? () => Navigator.of(context).pushNamed(route) : null,
          ),
        ],
      ),
    );
  }
}
