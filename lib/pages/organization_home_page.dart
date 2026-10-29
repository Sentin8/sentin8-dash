// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Organization home page - shows environments for an organization.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import '../bff_ws.dart';
import 'nav_shell.dart';
import '../config.dart';

class OrganizationHomePage extends StatefulWidget {
  final String orgId;
  const OrganizationHomePage({super.key, required this.orgId});
  @override
  State<OrganizationHomePage> createState() => _OrganizationHomePageState();
}

class _OrganizationHomePageState extends State<OrganizationHomePage> {
  Map<String, dynamic>? _org;
  List<dynamic>? _envs;
  String? _error;
  BffWebSocket? _ws;

  @override
  void initState() {
    super.initState();
    _load();
    _connectWS();
  }

  @override
  void dispose() {
    _ws?.disconnect();
    super.dispose();
  }

  void _connectWS() {
    final bffUrl = AuthProvider.instance.bffBaseUrl;
    if (bffUrl.isEmpty) return;
    _ws = BffWebSocket(bffBaseUrl: bffUrl);
    _ws!.onEnvCreated = (_) => _load();
    _ws!.onEnvUpdated = (_) => _load();
    _ws!.connect(['sentin8:sys.env.created', 'sentin8:sys.env.updated']);
  }

  Future<void> _load() async {
    try {
      final auth = AuthProvider.instance;
      // Wait for auth.init() to complete so auth.services is set
      // before we dereference it.
      await auth.ready;
      // Identity-cache invalidation race (policy design §3.1d-1): right
      // after org creation the services may still hold the caller's cached
      // pre-grant identity - sys answers 403 until the invalidation event
      // propagates (observed up to ~1.6s; bounded by the 30s resolver
      // TTL). Retry with a backoff budget comfortably above that window.
      Map<String, dynamic>? orgRes;
      Map<String, dynamic>? envRes;
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          orgRes = await auth.services!.sys.get('/v1/org/${widget.orgId}');
          envRes = await auth.services!.sys.get('/v1/e?org_id=${widget.orgId}');
          break;
        } catch (_) {
          if (attempt == 5) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 750));
        }
      }
      if (mounted && orgRes != null) {
        setState(() {
          _org = orgRes;
          // Sys returns a bare JSON array; the ApiClient._decode wraps it
          // in {'data': [...]}. Fall back to 'environments' in case the
          // server later wraps it explicitly.
          _envs = envRes?['data'] as List<dynamic>?
              ?? envRes?['environments'] as List<dynamic>?
              ?? [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgDisplayName = _org?['display_name'] as String? ?? 'Organization';
    if (_envs == null && _error == null) {
      return DashShell(
        orgId: widget.orgId,
        envId: '',
        title: orgDisplayName,
        child: const Center(child: CircularProgressIndicator(color: Sentin8Colors.royalGold)),
      );
    }
    if (_error != null) {
      return DashShell(
        orgId: widget.orgId,
        envId: '',
        title: orgDisplayName,
        child: Center(child: Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson))),
      );
    }
    if (_envs!.isEmpty) {
      // No environments - show create CTA
      return DashShell(
        orgId: widget.orgId,
        envId: '',
        title: orgDisplayName,
        child: Center(
          child: GlassPanel(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_circle_outline, size: 48, color: Sentin8Colors.royalGold),
                const SizedBox(height: Sentin8Spacing.lg),
                Text('No Environments', style: Sentin8Text.h2),
                const SizedBox(height: Sentin8Spacing.sm),
                Text('Create your first environment to get started.', style: Sentin8Text.bodySecondary),
                const SizedBox(height: Sentin8Spacing.xl),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/env/create?org=${widget.orgId}'),
                  icon: const Icon(Icons.add),
                  label: Text('Create Environment'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Show environment picker (no auto-redirect for single env)
    return DashShell(
      orgId: widget.orgId,
      envId: '',
      title: orgDisplayName,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(Sentin8Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_org?['display_name'] as String? ?? 'Organization', style: Sentin8Text.h1),
              const SizedBox(height: Sentin8Spacing.xl),
              Row(
                children: [
                  Text('Environments', style: Sentin8Text.h2),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/env/create?org=${widget.orgId}'),
                    icon: const Icon(Icons.add),
                    label: Text('Create Environment'),
                  ),
                ],
              ),
              const SizedBox(height: Sentin8Spacing.lg),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _envs!.length,
                itemBuilder: (context, i) {
                  final env = _envs![i] as Map<String, dynamic>;
                  // Show the env's root domain (custom or default) instead
                  // of the slug, so users see the same hostname they will
                  // use in their browser URLs.
                  final envSlug = env['slug'] as String? ?? '';
                  final orgSlug = _org?['slug'] as String? ?? '';
                  final customDomain = _org?['custom_domain'] as String?;
                  final orgRoot = AuthProvider.instance.orgDomain(
                    slug: orgSlug,
                    customDomain: customDomain,
                  );
                  final envDomain = AuthProvider.instance.envDomain(
                    orgDomain: orgRoot,
                    envSlug: envSlug,
                  );
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.layers, color: Sentin8Colors.royalGold),
                      title: Text(env['display_name'] as String? ?? 'Unknown'),
                      subtitle: Text(envDomain, style: Sentin8Text.caption),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Environment settings',
                            icon: const Icon(Icons.settings_outlined, color: Sentin8Colors.royalGold),
                            onPressed: () => Navigator.pushNamed(context, '/settings?env=${env['id']}'),
                          ),
                          const StatusBadge(label: 'Active', type: StatusType.active),
                        ],
                      ),
                      onTap: () => Navigator.pushNamed(context, '/home?env=${env['id']}'),
                    ),
                  );
                },
              ),
              const SizedBox(height: Sentin8Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}