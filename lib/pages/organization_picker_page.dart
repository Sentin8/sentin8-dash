// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Organization picker page — lists organizations the user belongs to.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import '../bff_ws.dart';
import 'nav_shell.dart';
import '../config.dart';

class OrganizationPickerPage extends StatefulWidget {
  const OrganizationPickerPage({super.key});
  @override
  State<OrganizationPickerPage> createState() => _OrganizationPickerPageState();
}

class _OrganizationPickerPageState extends State<OrganizationPickerPage> {
  List<dynamic> _orgs = [];
  bool _loading = true;
  String? _error;
  BffWebSocket? _ws;

  @override
  void initState() {
    super.initState();
    _loadOrgs();
    _connectWS();
  }

  @override
  void dispose() {
    _ws?.disconnect();
    super.dispose();
  }

  Future<void> _loadOrgs() async {
    try {
      final auth = AuthProvider.instance;
      await auth.ready;
      final res = await auth.services!.sys.get('/v1/o');
      final orgs = res['data'] as List<dynamic>? ??
          res['organizations'] as List<dynamic>? ??
          [];
      if (mounted) {
        setState(() { _orgs = orgs; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _connectWS() {
    final bffUrl = AuthProvider.instance.bffBaseUrl;
    if (bffUrl.isEmpty) return;
    _ws = BffWebSocket(bffBaseUrl: bffUrl);
    _ws!.onOrgCreated = (_) => _loadOrgs();
    _ws!.onOrgUpdated = (_) => _loadOrgs();
    _ws!.connect(['sentin8:sys.org.created', 'sentin8:sys.org.updated']);
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: '',
      envId: '',
      title: 'Organizations',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: Sentin8Colors.royalGold))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)))
              : _buildOrgs(),
    );
  }

  Widget _buildOrgs() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Your Organizations', style: Sentin8Text.h1),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/org/create'),
                  icon: const Icon(Icons.add),
                  label: Text('Create Organization'),
                ),
              ],
            ),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_orgs.isEmpty)
              GlassPanel(child: Center(child: Text('No organizations yet. Create one to get started.', style: Sentin8Text.bodySecondary)))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _orgs.length,
                itemBuilder: (context, i) {
                  final org = _orgs[i] as Map<String, dynamic>;
                  final slug = org['slug'] as String? ?? '';
                  final customDomain = org['custom_domain'] as String?;
                  final domain = AuthProvider.instance.orgDomain(
                    slug: slug,
                    customDomain: customDomain,
                  );
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.business, color: Sentin8Colors.royalGold),
                      title: Text(org['display_name'] as String? ?? 'Unknown', style: Sentin8Text.body),
                      subtitle: Text(domain, style: Sentin8Text.caption),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Organization settings',
                            icon: const Icon(Icons.settings_outlined, color: Sentin8Colors.royalGold),
                            onPressed: () => Navigator.pushNamed(context, '/settings?org=${org['id']}'),
                          ),
                          const StatusBadge(label: 'Active', type: StatusType.active),
                        ],
                      ),
                      onTap: () => Navigator.pushNamed(context, '/home?org=${org['id']}'),
                    ),
                  );
                },
              ),
            const SizedBox(height: Sentin8Spacing.xl),
          ],
        ),
      ),
    );
  }
}