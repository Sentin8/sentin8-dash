// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Health page - readiness dashboard for all services.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class HealthPage extends StatefulWidget {
  final String orgId;
  final String envId;
  const HealthPage({super.key, required this.orgId, required this.envId});
  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  final Map<String, dynamic> _health = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = AuthProvider.instance;
    final services = ['auth', 'sys', 'db', 'storage', 'bus', 'app'];
    for (final svc in services) {
      try {
        final res = await auth.services!.sys.get('/v1/readiness');
        if (mounted) setState(() => _health[svc] = res);
        return;
      } catch (_) {}
      try {
        final client = auth.services;
        late final Future<Map<String, dynamic>> future;
        switch (svc) {
          case 'auth': future = client!.auth.get('/v1/health'); break;
          case 'sys': future = client!.sys.get('/v1/health'); break;
          case 'db': future = client!.db.get('/v1/health'); break;
          case 'storage': future = client!.storage.get('/v1/health'); break;
          case 'bus': future = client!.bus.get('/v1/health'); break;
          case 'app': future = client!.app.get('/v1/health'); break;
          default: continue;
        }
        final res = await future;
        if (mounted) setState(() => _health[svc] = res);
      } catch (e) {
        if (mounted) setState(() => _health[svc] = {'status': 'error', 'error': '$e'});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: 'Health',
      child: Padding(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service Health', style: Sentin8Text.h1),
            const SizedBox(height: Sentin8Spacing.xl),
            Wrap(
              spacing: Sentin8Spacing.md,
              runSpacing: Sentin8Spacing.md,
              children: ['auth', 'sys', 'db', 'storage', 'bus', 'app'].map((svc) {
                final h = _health[svc] as Map<String, dynamic>?;
                final status = h?['status'] as String? ?? 'checking';
                return GlassPanel(
                  padding: const EdgeInsets.all(Sentin8Spacing.lg),
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_icon(svc), color: Sentin8Colors.royalGold, size: 20),
                            const SizedBox(width: Sentin8Spacing.sm),
                            Text(svc, style: Sentin8Text.body),
                          ],
                        ),
                        const SizedBox(height: Sentin8Spacing.sm),
                        StatusBadge(
                          label: status,
                          type: status == 'ok' ? StatusType.active : status == 'degraded' ? StatusType.warning : StatusType.error,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(String svc) => switch (svc) {
    'auth' => Icons.security,
    'sys' => Icons.settings,
    'db' => Icons.storage,
    'storage' => Icons.cloud,
    'bus' => Icons.stream,
    'app' => Icons.apps,
    _ => Icons.circle,
  };
}