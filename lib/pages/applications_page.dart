// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Applications page — list, create, detail, archive.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class ApplicationsPage extends StatefulWidget {
  final String orgId;
  final String envId;
  const ApplicationsPage({super.key, required this.orgId, required this.envId});
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  List<dynamic>? _apps;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .sys.get(
        '/v1/env/${widget.envId}/applications',
      );
      if (mounted) setState(() => _apps = res['applications'] as List<dynamic>? ?? []);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: 'Applications',
      child: Padding(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Applications', style: Sentin8Text.h1),
                const Spacer(),
                FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: Text('Create Application')),
              ],
            ),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson))
            else if (_apps == null)
              const CircularProgressIndicator(color: Sentin8Colors.royalGold)
            else if (_apps!.isEmpty)
              GlassPanel(child: Center(child: Text('No applications yet.', style: Sentin8Text.bodySecondary)))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _apps!.length,
                  itemBuilder: (context, i) {
                    final app = _apps![i] as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.apps, color: Sentin8Colors.royalGold),
                        title: Text(app['name'] as String? ?? 'Unknown'),
                        subtitle: Text(app['slug'] as String? ?? ''),
                        trailing: StatusBadge(label: app['status'] as String? ?? 'active', type: StatusType.active),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}