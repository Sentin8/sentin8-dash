// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Organization settings page - profile, members, branding, custom domain.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class OrganizationSettingsPage extends StatefulWidget {
  final String orgId;
  const OrganizationSettingsPage({super.key, required this.orgId});
  @override
  State<OrganizationSettingsPage> createState() => _OrganizationSettingsPageState();
}

class _OrganizationSettingsPageState extends State<OrganizationSettingsPage> {
  Map<String, dynamic>? _org;
  final _nameCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  bool _loading = false;
  bool _domainLoading = false;
  String? _error;
  String? _domainMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Wait for auth.init() to complete so auth.services is populated
      // before we dereference it. Without this, a hard reload that
      // lands on /org/{id}/settings before the BFF session metadata
      // is fetched crashes the build with "Null check operator used
      // on a null value" on auth.services.
      final auth = AuthProvider.instance;
      await auth.ready;
      final res = await auth.services!.sys.get('/v1/org/${widget.orgId}');
      if (mounted) {
        setState(() {
          _org = res;
          _nameCtrl.text = res['display_name'] as String? ?? '';
          _domainCtrl.text = res['custom_domain'] as String? ?? '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The default org domain is computed server-side as
  /// `{slug}.{sentin8_domain}` (e.g. `ibank.local.sentin8.dev`).
  String? get _defaultDomain {
    final slug = _org?['slug'] as String?;
    if (slug == null || slug.isEmpty) return null;
    return '$slug.${AuthProvider.instance.sentin8Domain}';
  }

  Future<void> _save() async {
    final auth = AuthProvider.instance;
    await auth.ready;
    setState(() { _loading = true; _error = null; });
    try {
      await auth.services!.sys.put('/v1/org/${widget.orgId}', body: {'display_name': _nameCtrl.text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDomain() async {
    final auth = AuthProvider.instance;
    await auth.ready;
    setState(() { _domainLoading = true; _domainMessage = null; });
    try {
      await auth.services!.sys.put('/v1/org/${widget.orgId}', body: {
        'custom_domain': _domainCtrl.text.trim(),
      });
      if (mounted) setState(() => _domainMessage = 'Domain updated - subdomains re-provisioned');
    } catch (e) {
      if (mounted) setState(() => _domainMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _domainLoading = false);
    }
  }

  /// Restore the org domain to the server-computed default
  /// (`{slug}.local.sentin8.dev`) by clearing the domain field.
  Future<void> _restoreDefaultDomain() async {
    _domainCtrl.text = '';
    await _saveDomain();
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: '',
      title: 'Settings',
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(Sentin8Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organization Settings', style: Sentin8Text.h1),
              const SizedBox(height: Sentin8Spacing.xl),
              if (_error != null) Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Display Name')),
              const SizedBox(height: Sentin8Spacing.md),
              Text('Slug: ${_org?['slug'] ?? '…'}', style: Sentin8Text.caption),
              const SizedBox(height: Sentin8Spacing.lg),
              FilledButton(onPressed: _loading ? null : _save, child: Text('Save')),
              const SizedBox(height: Sentin8Spacing.xxl),
              const Divider(color: Sentin8Colors.glassBorder),
              const SizedBox(height: Sentin8Spacing.lg),
              // ── Custom Domain ──────────────────────────────────
              Text('Custom Domain', style: Sentin8Text.h2),
              const SizedBox(height: Sentin8Spacing.sm),
              Text(
                'The root domain for this organization. All service subdomains '
                '(auth, dash, ledger, etc.) derive from this domain.',
                style: Sentin8Text.caption,
              ),
              const SizedBox(height: Sentin8Spacing.md),
              TextField(
                controller: _domainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Org Domain',
                  hintText: 'e.g. ibank.local',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Sentin8Spacing.sm),
              if (_defaultDomain != null)
                Text(
                  'Default (auto-generated): ${_defaultDomain!}',
                  style: Sentin8Text.caption,
                ),
              const SizedBox(height: Sentin8Spacing.sm),
              if (_domainMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Sentin8Spacing.sm),
                  child: Text(_domainMessage!, style: Sentin8Text.caption),
                ),
              Wrap(
                spacing: Sentin8Spacing.md,
                runSpacing: Sentin8Spacing.sm,
                children: [
                  FilledButton(
                    onPressed: _domainLoading ? null : _saveDomain,
                    child: _domainLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Update Domain'),
                  ),
                  OutlinedButton(
                    onPressed: _domainLoading ? null : _restoreDefaultDomain,
                    child: Text('Restore Default'),
                  ),
                ],
              ),
              const SizedBox(height: Sentin8Spacing.xxl),
              const Divider(color: Sentin8Colors.glassBorder),
              const SizedBox(height: Sentin8Spacing.lg),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/sentin8ors?org=${widget.orgId}'),
                icon: const Icon(Icons.people),
                label: Text('Manage Sentin8ors'),
              ),
              const SizedBox(height: Sentin8Spacing.xl),
              Text('Danger Zone', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Sentin8Colors.errorCrimson)),
              const SizedBox(height: Sentin8Spacing.sm),
              OutlinedButton.icon(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_forever, color: Sentin8Colors.errorCrimson),
                label: Text('Delete Organization', style: TextStyle(color: Sentin8Colors.errorCrimson)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Sentin8Colors.errorCrimson),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sentin8Colors.carbonBlack,
        title: Text('Delete Organization?', style: TextStyle(color: Sentin8Colors.errorCrimson)),
        content: Text(
          'This will permanently delete "${_org?['display_name'] ?? 'this organization'}" and ALL its environments, '
          'memberships, features, bindings, and app instances. This action cannot be undone.',
          style: const TextStyle(color: Sentin8Colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteOrg();
            },
            style: FilledButton.styleFrom(backgroundColor: Sentin8Colors.errorCrimson),
            child: Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOrg() async {
    final auth = AuthProvider.instance;
    await auth.ready;
    setState(() { _loading = true; _error = null; });
    try {
      await auth.services!.sys.delete('/v1/org/${widget.orgId}');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/org', (_) => false);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}