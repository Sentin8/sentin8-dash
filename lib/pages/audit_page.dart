// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Audit page - filterable audit event timeline.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class AuditPage extends StatefulWidget {
  final String orgId;
  final String envId;
  const AuditPage({super.key, required this.orgId, required this.envId});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  List<dynamic>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final auth = AuthProvider.instance;
      // Try Sys audit first, then Auth audit
      try {
        final res = await auth.services!.sys.get('/v1/audit');
        if (mounted) setState(() => _events = res['events'] as List<dynamic>? ?? []);
        return;
      } catch (_) {}
      final res = await auth.services!.auth.get('/v1/admin/audit');
      if (mounted) setState(() => _events = res['events'] as List<dynamic>? ?? []);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: 'Audit',
      child: Padding(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audit Events', style: Sentin8Text.h1),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson))
            else if (_events == null)
              const CircularProgressIndicator(color: Sentin8Colors.royalGold)
            else if (_events!.isEmpty)
              GlassPanel(child: Center(child: Text('No audit events.', style: Sentin8Text.bodySecondary)))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _events!.length,
                  itemBuilder: (context, i) {
                    final e = _events![i] as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.history, color: Sentin8Colors.royalGold),
                        title: Text(e['action'] as String? ?? 'unknown'),
                        subtitle: Text(e['timestamp'] as String? ?? ''),
                        trailing: Text(e['actor_user_id'] as String? ?? '', style: Sentin8Text.caption),
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