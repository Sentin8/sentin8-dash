// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Create organization page — form for creating a new Sentin8 organization.
// The slug is auto-generated from the organization name and the user can
// edit it inline. The org domain is pre-filled with the platform default
// (`{slug}.{sentin8_domain}`) and the user can override it. TLS uses
// the org domain to derive every service subdomain (auth, dash, ledger, …).
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import '../widgets/clickable_subdomain_field.dart';
import 'nav_shell.dart';

class CreateOrganizationPage extends StatefulWidget {
  const CreateOrganizationPage({super.key});
  @override
  State<CreateOrganizationPage> createState() => _CreateOrganizationPageState();
}

class _CreateOrganizationPageState extends State<CreateOrganizationPage> {
  final _slugCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  // The "auto-derived" / platform default org domain. The shared
  // click-to-edit widget reads this so the read-only display always
  // shows the up-to-date default, and the "set to default" icon
  // restores it.
  late final SubdomainFieldController _domainField;
  bool _loading = false;
  bool _slugManuallyEdited = false;
  bool _domainManuallyEdited = false;
  bool _slugChecking = false;
  bool _slugAvailable = false;
  String? _error;
  Timer? _slugCheckTimer;

  @override
  void initState() {
    super.initState();
    // Pre-fill the domain with the platform default so the user always
    // sees a sensible value. As the slug changes, the domain is updated
    // unless the user has manually edited it.
    _domainField = SubdomainFieldController(
      controller: _domainCtrl,
      defaultValue: _defaultDomain(),
    );
    // Rebuild when the shared field's controller notifies so the
    // read-only display reflects resets triggered from inside the
    // widget (e.g. the "set to default" icon button).
    _domainField.addListener(_onDomainFieldChanged);
    _domainCtrl.text = _defaultDomain();
  }

  void _onDomainFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _slugCheckTimer?.cancel();
    _domainField.removeListener(_onDomainFieldChanged);
    _domainField.dispose();
    super.dispose();
  }

  /// The default org domain is computed as `{slug}.{sentin8Domain}`.
  /// The user can override it with a `custom_domain` (e.g. `ibank.local`).
  String _defaultDomain() {
    final slug = _slugCtrl.text.trim();
    if (slug.isEmpty) return '';
    return AuthProvider.instance.orgDomain(slug: slug);
  }

  /// Converts a display name to a URL-safe slug.
  /// e.g. "Acme Bank!" → "acme-bank"
  String _nameToSlug(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '') // remove non-alphanumeric
        .replaceAll(RegExp(r'[\s_-]+'), '-')      // collapse separators to -
        .replaceAll(RegExp(r'^-+|-+$'), '')       // trim leading/trailing -
        .replaceAll(RegExp(r'-{2,}'), '-');       // collapse multiple -
  }

  /// The user can also reset to the default without first entering edit
  /// mode. Refresh the controller so the read-only box updates.
  void _resetDomainToDefault() {
    final def = _defaultDomain();
    setState(() {
      _domainManuallyEdited = false;
      _domainField.defaultValue = def;
      _domainField.controller.text = def;
    });
  }

  /// Sync the domain to the slug (only when not manually edited). Also
  /// updates the shared widget's `defaultValue` so its read-only display
  /// stays in sync.
  void _syncDomainToSlug() {
    if (_domainManuallyEdited) return;
    final def = _defaultDomain();
    _domainField.defaultValue = def;
    _domainCtrl.text = def;
    setState(() {});
  }

  void _onNameChanged(String value) {
    if (!_slugManuallyEdited) {
      final slug = _nameToSlug(value);
      _slugCtrl.text = slug;
      _slugCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: slug.length),
      );
      // Trigger a rebuild so the hintText / domain display update.
      setState(() {});
      _syncDomainToSlug();
      _checkSlugAvailability(slug);
    }
  }

  void _onSlugChanged(String value) {
    _slugManuallyEdited = value.isNotEmpty;
    setState(() {});
    _syncDomainToSlug();
    _checkSlugAvailability(value);
  }

  void _onDomainChanged(String value) {
    // Once the user edits the domain, stop auto-syncing it from the slug.
    _domainManuallyEdited = value.isNotEmpty;
    setState(() {});
  }

  /// Debounced slug availability check — calls Sys to see if the slug
  /// is already taken by an existing organization.
  void _checkSlugAvailability(String slug) {
    _slugCheckTimer?.cancel();
    if (slug.isEmpty) {
      setState(() { _slugChecking = false; _slugAvailable = false; });
      return;
    }
    setState(() { _slugChecking = true; });
    _slugCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final auth = AuthProvider.instance;
        // Check if slug is available via Sys
        final res = await auth.services!.sys.get('/v1/slug-available/$slug');
        if (!mounted) return;
        setState(() {
          _slugChecking = false;
          _slugAvailable = res['available'] as bool? ?? false;
        });
      } catch (e) {
        // If the endpoint doesn't exist or errors, assume available
        if (!mounted) return;
        setState(() { _slugChecking = false; _slugAvailable = true; });
      }
    });
  }

  Future<void> _submit() async {
    final slug = _slugCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (slug.isEmpty || name.isEmpty) {
      setState(() => _error = 'Organization name is required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final auth = AuthProvider.instance;
      // Always send a domain — fall back to the platform default
      // (`{slug}.{sentin8_domain}`) if the user cleared the field.
      final customDomain = _domainCtrl.text.trim().isNotEmpty
          ? _domainCtrl.text.trim()
          : AuthProvider.instance.orgDomain(slug: slug);
      final res = await auth.services!.sys.post('/v1/o', body: {
        'slug': slug,
        'display_name': name,
        'custom_domain': customDomain,
      });
      if (mounted) {
        final orgId = res['id'] as String;
        // Refresh the BFF session token (picks up new org-admin scopes)
        // then re-initialize the AuthProvider so the Sentin8Services
        // client picks up the updated session metadata (target org/env).
        // Without this, subsequent API calls use stale scopes → 403 errors.
        await AuthProvider.instance.refreshAndInit();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/home?org=$orgId', (_) => false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canSubmit =>
      !_loading &&
      _nameCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // The org domain has no fixed suffix — it's a single label the
    // user can fully override. Pass `null` suffix so the edit field
    // shows the textbox alone (no `{orgDomain}` to the right).
    return DashShell(
      orgId: '',
      envId: '',
      title: 'Create Organization',
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
                Text('Create Organization', style: Sentin8Text.h1),
                const SizedBox(height: Sentin8Spacing.xl),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Organization Name'),
                  onChanged: _onNameChanged,
                ),
                const SizedBox(height: Sentin8Spacing.lg),
                // ── Org Domain (click-to-edit) ──────────────────────
                Text('Org Domain', style: Sentin8Text.label),
                const SizedBox(height: Sentin8Spacing.sm),
                ClickableSubdomainField(
                  state: _domainField,
                  value: _domainCtrl.text.isEmpty
                      ? _defaultDomain()
                      : _domainCtrl.text,
                  suffix: null,
                  hintText: 'e.g. ibank.local',
                  resetTooltip: 'Restore platform default',
                  onChanged: (v) {
                    _domainManuallyEdited = v.isNotEmpty;
                    setState(() {});
                  },
                ),
                const SizedBox(height: Sentin8Spacing.xs),
                Text(
                  'Pre-filled with the platform default. Click the value to override.',
                  style: Sentin8Text.caption,
                ),
                const SizedBox(height: Sentin8Spacing.lg),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)),
                  const SizedBox(height: Sentin8Spacing.md),
                ],
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Create'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}