// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Instance detail page - admin view of an App instance.
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class InstanceDetailPage extends StatefulWidget {
  final String orgId;
  final String envId;
  final String instanceId;
  const InstanceDetailPage({super.key, required this.orgId, required this.envId, required this.instanceId});
  @override
  State<InstanceDetailPage> createState() => _InstanceDetailPageState();
}

class _InstanceDetailPageState extends State<InstanceDetailPage> {
  Map<String, dynamic>? _instance;
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
          .app.get('/v1/app/admin/instances/${widget.instanceId}');
      if (mounted) setState(() => _instance = res);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: 'Instance Detail',
      child: Padding(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instance Detail', style: Sentin8Text.h1),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson))
            else if (_instance == null)
              const CircularProgressIndicator(color: Sentin8Colors.royalGold)
            else
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(label: 'Instance ID', value: widget.instanceId),
                    _DetailRow(label: 'Status', value: _instance!['status'] as String? ?? 'unknown'),
                    _DetailRow(label: 'Custom Domain', value: _instance!['custom_domain'] as String? ?? ' - '),
                    _DetailRow(label: 'Listing ID', value: _instance!['listing_id'] as String? ?? ' - '),
                    const SizedBox(height: Sentin8Spacing.lg),
                    FilledButton.icon(
                      onPressed: () {
                        final customDomain = _instance!['custom_domain'] as String?;
                        if (customDomain != null && customDomain.isNotEmpty) {
                          web.window.location.href = customDomain;
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text('Open App'),
                    ),
                    const SizedBox(height: Sentin8Spacing.md),
                    OutlinedButton.icon(
                      onPressed: () => _confirmUninstall(context),
                      icon: const Icon(Icons.delete_outline, color: Sentin8Colors.errorCrimson),
                      label: Text('Uninstall', style: TextStyle(color: Sentin8Colors.errorCrimson)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Sentin8Colors.errorCrimson)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmUninstall(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sentin8Colors.carbonBlack,
        title: Text('Uninstall App?', style: TextStyle(color: Sentin8Colors.errorCrimson)),
        content: Text(
          'This will revoke the OAuth client and remove the app instance. This action cannot be undone.',
          style: TextStyle(color: Sentin8Colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _uninstall();
            },
            style: FilledButton.styleFrom(backgroundColor: Sentin8Colors.errorCrimson),
            child: Text('Uninstall'),
          ),
        ],
      ),
    );
  }

  Future<void> _uninstall() async {
    try {
      await AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .app.delete('/v1/app/admin/instances/${widget.instanceId}');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/app/instances?env=${widget.envId}', (_) => false);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Uninstall failed: $e');
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Sentin8Spacing.sm),
    child: Row(
      children: [
        SizedBox(width: 160, child: Text(label, style: Sentin8Text.label)),
        Expanded(child: Text(value, style: Sentin8Text.body)),
      ],
    ),
  );
}