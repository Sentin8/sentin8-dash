// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Create environment page - form for creating a new environment.
// The env subdomain (slug) is auto-generated from the environment name
// (e.g. "Production" → "prod"). The full env domain is shown as a
// fixed, read-only suffix in the subdomain field, derived from the org's
// domain. The user can override the subdomain if they want a different
// hostname (e.g. `eu-prod` instead of `prod`).
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import '../widgets/clickable_subdomain_field.dart';
import 'nav_shell.dart';

class CreateEnvironmentPage extends StatefulWidget {
  final String orgId;
  const CreateEnvironmentPage({super.key, required this.orgId});
  @override
  State<CreateEnvironmentPage> createState() => _CreateEnvironmentPageState();
}

class _CreateEnvironmentPageState extends State<CreateEnvironmentPage> {
  final _nameCtrl = TextEditingController();
  final _subdomainCtrl = TextEditingController();
  // Owns the click-to-edit field state. `defaultValue` is the
  // auto-derived slug from the env name; the widget re-reads it on
  // every build so the read-only display stays in sync.
  late final SubdomainFieldController _subdomainField;
  bool _loading = false;
  bool _subdomainManuallyEdited = false;
  String? _error;
  String _orgDomain = '';
  String _orgSlug = '';

  @override
  void initState() {
    super.initState();
    _subdomainField = SubdomainFieldController(
      controller: _subdomainCtrl,
      defaultValue: '',
    );
    // Rebuild when the shared field's controller notifies so the
    // read-only display reflects resets triggered from inside the
    // widget (e.g. the "set to default" icon button).
    _subdomainField.addListener(_onSubdomainFieldChanged);
    _loadOrgDomain();
    // Pre-fill the subdomain with the default slug derived from the
    // name (handled in _onNameChanged). The full env domain is shown
    // as a fixed suffix so the user always sees the host they'll get.
  }

  void _onSubdomainFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _subdomainField.removeListener(_onSubdomainFieldChanged);
    _subdomainField.dispose();
    super.dispose();
  }

  Future<void> _loadOrgDomain() async {
    try {
      final auth = AuthProvider.instance;
      await auth.ready;
      final res = await auth.services!.sys.get('/v1/org/${widget.orgId}');
      if (!mounted) return;
      final orgSlug = res['slug'] as String? ?? '';
      final customDomain = res['custom_domain'] as String?;
      final orgDomain = AuthProvider.instance.orgDomain(
        slug: orgSlug,
        customDomain: customDomain,
      );
      setState(() {
        _orgSlug = orgSlug;
        _orgDomain = orgDomain;
      });
    } catch (_) {}
  }

  /// Converts a display name to a URL-safe slug.
  String _nameToSlug(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'[\s_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .replaceAll(RegExp(r'-{2,}'), '-');
  }

  void _onNameChanged(String value) {
    if (!_subdomainManuallyEdited) {
      final slug = _nameToSlug(value);
      _subdomainCtrl.text = slug;
      _subdomainCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: slug.length),
      );
      // Keep the shared widget's `defaultValue` in sync so the
      // read-only display shows the up-to-date full env domain.
      _subdomainField.defaultValue = slug;
      // Trigger a rebuild so the env domain suffix updates to match the
      // new subdomain.
      setState(() {});
    }
  }

  void _onSubdomainChanged(String value) {
    // Once the user edits the subdomain, stop auto-syncing it from the name.
    _subdomainManuallyEdited = value.isNotEmpty;
    setState(() {});
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Environment name is required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // Use the subdomain override if provided, otherwise auto-generate from name.
      final slug = _subdomainCtrl.text.trim().isNotEmpty
          ? _nameToSlug(_subdomainCtrl.text.trim())
          : _nameToSlug(name);
      final res = await AuthProvider.instance.services!.sys.post(
        '/v1/e',
        body: {'slug': slug, 'display_name': name, 'org_id': widget.orgId},
      );
      if (mounted) {
        final envId = res['id'] as String;
        // Refresh the BFF session token (picks up new env-admin scopes)
        // then re-initialize the AuthProvider so the Sentin8Services
        // client picks up the updated session metadata (target org/env).
        // Without this, subsequent API calls use stale scopes → 403 errors.
        await AuthProvider.instance.refreshAndInit();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/home?env=$envId', (_) => false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The full env domain - used in the read-only display so the user
  /// sees the entire hostname they'll get.
  ///   custom org domain (no `.o.`): `{subdomain}.{orgDomain}`
  ///   default org domain:           `{subdomain}.e.{orgDomain}`
  /// When the env name is empty, the slug is unknown - return the
  /// fixed suffix (e.g. `.ibank.local`) instead of using a placeholder
  /// like `prod`, so we don't show a misleading hostname.
  String get _fullEnvDomain {
    if (_orgDomain.isEmpty) return '';
    final slug = _subdomainCtrl.text.trim();
    if (slug.isEmpty) {
      // No name yet - just show the org-derived suffix.
      return _envDomainSuffix;
    }
    return AuthProvider.instance.envDomain(orgDomain: _orgDomain, envSlug: slug);
  }

  /// The fixed (non-editable) part of the env domain - the env domain
  /// with the editable subdomain prefix stripped off. e.g. for
  /// "staging.ibank.local" with slug "staging", returns ".ibank.local".
  /// Starts with a leading `.` so it can be used directly as a
  /// TextField suffix that sits flush with the editable prefix.
  String get _envDomainSuffix {
    if (_orgDomain.isEmpty) return '';
    final slug = _subdomainCtrl.text.trim().isNotEmpty
        ? _subdomainCtrl.text.trim()
        : 'prod';
    final fullDomain =
        AuthProvider.instance.envDomain(orgDomain: _orgDomain, envSlug: slug);
    if (fullDomain.toLowerCase().startsWith('${slug.toLowerCase()}.')) {
      return fullDomain.substring(slug.length);
    }
    return '.$fullDomain';
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: '',
      title: 'Create Environment',
      child: Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(40),
          margin: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create Environment', style: Sentin8Text.h1),
                const SizedBox(height: Sentin8Spacing.xl),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Environment Name'),
                  onChanged: _onNameChanged,
                ),
                const SizedBox(height: Sentin8Spacing.md),
                // ── Subdomain (click-to-edit) ────────────────────────
                Text('Subdomain', style: Sentin8Text.label),
                const SizedBox(height: Sentin8Spacing.sm),
                ClickableSubdomainField(
                  state: _subdomainField,
                  // Show the full env domain so the user sees the
                  // entire hostname they'll get. The slug is already
                  // embedded in it - no need to repeat it.
                  value: _fullEnvDomain,
                  // Suffix is the env domain MINUS the slug the user
                  // is editing. The slug is editable; the rest of the
                  // hostname (org-derived) is fixed.
                  suffix: _envDomainSuffix,
                  hintText: 'prod',
                  resetTooltip: 'Revert to auto-derived subdomain',
                  onChanged: _onSubdomainChanged,
                ),
                const SizedBox(height: Sentin8Spacing.xs),
                Text(
                  'Pre-filled from the environment name. Click the value to override.',
                  style: Sentin8Text.caption,
                ),
                const SizedBox(height: Sentin8Spacing.md),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)),
                  const SizedBox(height: Sentin8Spacing.md),
                ],
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Create'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}