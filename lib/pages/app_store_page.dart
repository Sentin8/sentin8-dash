// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// App Store page - browse and install App store listings.
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../theme.dart';
import '../auth_provider.dart';
import '../services.dart';
import '../test_bridge.dart';
import '../widgets/scope_selector.dart';
import '../widgets/role_selector.dart';
import 'nav_shell.dart';

class AppStorePage extends StatefulWidget {
  final String orgId;
  final String envId;
  const AppStorePage({super.key, required this.orgId, required this.envId});
  @override
  State<AppStorePage> createState() => _AppStorePageState();
}

class _AppStorePageState extends State<AppStorePage> {
  List<dynamic>? _listings;
  List<dynamic>? _instances;
  String? _error;

  // Create listing form state
  bool _showCreateForm = false;
  final _appNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _backendUrlCtrl = TextEditingController();
  // OAuth scopes + security roles for the create-listing form. The
  // [ScopeSelector] and [RoleSelector] widgets own their internal
  // state but report changes back via onChanged, which we capture
  // here for the eventual POST.
  List<String> _selectedScopes = [];
  List<RoleDraft> _selectedRoles = [];
  String? _selectedDefaultSignup;
  String? _createMessage;
  // Visibility selection for the Publish New App form.
  // 'public' (default), 'org', or 'env'.
  String _visibility = 'public';
  String _orgName = '';
  String _envName = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadNames();
    // Register test bridge handler so e2e tests can create listings
    // by calling window.sentin8TestCreateListing(appName, appSlug, description).
    // This triggers the same _createListing() method as clicking the
    // "Create & Publish" button - not a direct API call.
    setCreateListingHandler(
        (appName, appSlug, description, backendUrl,
            [scopes, roles, defaultSignupRole]) {
      _appNameCtrl.text = appName;
      // Slug is auto-generated from the app name - ignore the passed slug.
      _descriptionCtrl.text = description;
      _backendUrlCtrl.text = backendUrl;
      // scopes are optional - e2e tests can pass them via the 5th
      // arg as a comma- or space-separated list. The shared
      // [ScopeSelector] widget takes a `List<String>`, so we parse
      // the text the same way the legacy TextField used to.
      if (scopes != null && scopes.isNotEmpty) {
        _selectedScopes = scopes
            .split(RegExp(r'[\s,]+'))
            .where((s) => s.isNotEmpty)
            .toList();
      }
      // roles are optional - e2e tests pass newline-separated role
      // defs via the 6th arg. Each non-blank, non-`#` line is
      // `name:scope1,scope2`. The `default_signup_role` is passed
      // via the 7th arg (a single name). We parse into the
      // structured shape the [RoleSelector] consumes.
      if (roles != null && roles.isNotEmpty) {
        final drafts = <RoleDraft>[];
        for (final raw in roles.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final sep = line.indexOf(':');
          if (sep <= 0) continue;
          var name = line.substring(0, sep).trim();
          if (name.isEmpty) continue;
          final scopesRaw = line.substring(sep + 1);
          final scopeList = scopesRaw
              .split(RegExp(r'[\s,]+'))
              .where((s) => s.isNotEmpty)
              .toList();
          if (name.endsWith('*')) {
            name = name.substring(0, name.length - 1);
          }
          drafts.add(RoleDraft(
            name: name,
            scopes: scopeList,
          ));
        }
        _selectedRoles = drafts;
        _selectedDefaultSignup = (defaultSignupRole != null &&
                defaultSignupRole.isNotEmpty)
            ? defaultSignupRole
            : null;
      }
      _createListing();
    });
  }

  /// Fetch org/env display names from Sys so the visibility dropdown
  /// can show readable labels (e.g. "env: Production" instead of a UUID).
  Future<void> _loadNames() async {
    final auth = AuthProvider.instance;
    if (widget.orgId.isEmpty) return;
    try {
      final orgRes = await auth.services!.sys.get('/v1/org/${widget.orgId}');
      if (mounted) setState(() => _orgName = orgRes['display_name'] as String? ?? widget.orgId);
    } catch (_) {
      if (mounted) setState(() => _orgName = widget.orgId);
    }
    if (widget.envId.isEmpty) return;
    try {
      final envRes = await auth.services!.sys.get('/v1/env/${widget.envId}');
      if (mounted) setState(() => _envName = envRes['display_name'] as String? ?? widget.envId);
    } catch (_) {
      if (mounted) setState(() => _envName = widget.envId);
    }
  }

  @override
  void dispose() {
    setCreateListingHandler(null);
    _appNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _backendUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = AuthProvider.instance.services!;
    try {
      // Use scoped services so BFF exchanges the sys-realm token for an
      // env-scoped token (RFC 8693). The server then filters listings by
      // visibility using the sentin8or's real org/env (from the exchanged
      // token), not the System Org carried by the sys-realm token.
      final app = widget.orgId.isNotEmpty && widget.envId.isNotEmpty
          ? services.scoped(targetEnvId: widget.envId).app
          : services.app;
      final res = await app.get('/v1/app/store/listings');
      if (mounted) setState(() => _listings = res['data'] as List<dynamic>? ?? []);
      // Also load installed instances for this env (if env-scoped).
      if (widget.envId.isNotEmpty) {
        try {
          final instRes = await app.get('/v1/app/admin/instances?envId=${widget.envId}');
          if (mounted) setState(() => _instances = instRes['instances'] as List<dynamic>? ?? []);
        } catch (_) {
          // Admin endpoint may not be accessible for all users.
          if (mounted) setState(() => _instances = []);
        }
      } else {
        if (mounted) setState(() => _instances = []);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Async fetcher passed to the [ScopeSelector] / [RoleSelector]
  /// widgets so they can populate their autocomplete suggestions from
  /// sys's `GET /v1/scopes/catalog` endpoint. Falls back to an
  /// empty list if the catalog endpoint is unreachable.
  Future<List<String>> _fetchScopeCatalog() async {
    final services = AuthProvider.instance.services;
    if (services == null) return const [];
    try {
      return await services.fetchScopeCatalog();
    } catch (_) {
      return const [];
    }
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

  /// Check if a listing is already installed in this env.
  bool _isInstalled(String? listingId) {
    if (listingId == null || _instances == null) return false;
    for (final inst in _instances!) {
      final m = inst as Map<String, dynamic>;
      if (m['listing_id'] == listingId) return true;
    }
    return false;
  }

  /// Get the instance for a listing, or null if not installed.
  Map<String, dynamic>? _getInstance(String? listingId) {
    if (listingId == null || _instances == null) return null;
    for (final inst in _instances!) {
      final m = inst as Map<String, dynamic>;
      if (m['listing_id'] == listingId) return m;
    }
    return null;
  }

  /// Launch the app in a new browser tab using its hostname.
  void _launchApp(String hostname) {
    final url = 'https://$hostname';
    web.window.open(url, '_blank');
  }

  /// Show a dialog with the installation details for an app.
  Future<void> _showInstanceDetails(String listingId) async {
    final inst = _getInstance(listingId);
    if (inst == null) return;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sentin8Colors.carbonBlack,
        title: Text('Instance Details - ${inst['app_name'] ?? inst['app_slug'] ?? 'App'}', style: Sentin8Text.h3),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Instance ID', value: inst['id'] as String? ?? ''),
              _DetailRow(label: 'App Slug', value: inst['app_slug'] as String? ?? ''),
              _DetailRow(label: 'Instance Name', value: inst['instance_name'] as String? ?? ' - '),
              _DetailRow(label: 'Instance Description', value: inst['instance_description'] as String? ?? ' - '),
              _DetailRow(label: 'Hostname', value: inst['hostname'] as String? ?? ''),
              _DetailRow(label: 'Status', value: inst['status'] as String? ?? ''),
              _DetailRow(label: 'OAuth Client ID', value: inst['oauth_client_id'] as String? ?? ' - '),
              _DetailRow(label: 'Listing ID', value: inst['listing_id'] as String? ?? ' - '),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Delete a listing (archive). Only allowed if the app has no
  /// instances installed.
  Future<void> _deleteListing(String listingId, String appName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sentin8Colors.carbonBlack,
        title: Text('Delete "$appName"?', style: const TextStyle(color: Sentin8Colors.errorCrimson)),
        content: Text(
          'This will permanently archive the listing. This action cannot be undone.',
          style: TextStyle(color: Sentin8Colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Sentin8Colors.errorCrimson),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _scopedApp().delete('/v1/app/store/listings/$listingId');
      if (mounted) {
        setState(() => _createMessage = 'Listing deleted');
      }
      _load();
    } catch (e) {
      if (mounted) setState(() => _createMessage = 'Delete error: $e');
    }
  }

  /// Install an app: show a dialog asking for the custom subdomain
  /// (defaulted to the listing's app_slug), optional instance name
  /// and description, then POST to App /v1/app/setup which creates
  /// an instance and registers a DCR OAuth client with the org/env
  /// Auth.
  Future<void> _install(String listingId, String appSlug) async {
    final installOpts = await _showInstallDialog(appSlug);
    if (installOpts == null) return; // User cancelled

    try {
      // Use scoped services so BFF exchanges the sys-realm token for an
      // env-scoped token. Without this, the sys token's organizationId
      // (System Org) doesn't match the request body's organizationId,
      // causing 403 "organizationId does not match token".
      final app = AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .app;
      await app.post('/v1/app/setup', body: {
        'listing_id': listingId,
        'custom_domain': installOpts.customDomain,
        if (installOpts.instanceName.isNotEmpty) 'instance_name': installOpts.instanceName,
        if (installOpts.instanceDescription.isNotEmpty) 'instance_description': installOpts.instanceDescription,
        'auth_mode': installOpts.authMode,
        if (installOpts.authMode == 'staff' && installOpts.staffAuthDomain != null && installOpts.staffAuthDomain!.isNotEmpty)
          'staff_auth_domain': installOpts.staffAuthDomain,
      });
      if (mounted) {
        setState(() => _createMessage = 'Installed successfully');
      }
      _load(); // Reload to show Uninstall button
    } catch (e) {
      if (mounted) setState(() => _createMessage = 'Install error: $e');
    }
  }

  /// Show a dialog asking the member for the custom subdomain
  /// (defaulted to [appSlug]) and optional instance name + description.
  /// Returns null if cancelled, otherwise an [_InstallOptions] object.
  Future<_InstallOptions?> _showInstallDialog(String appSlug) async {
    // The subdomain is required and defaults to the app slug - the
    // user can keep it (e.g. `ebank`) or type a different prefix (e.g. `www`).
    // The full hostname is built from {subdomain}.{envSlug}.{orgDomain}
    // (e.g. www.prod.ibank.local), env-scoped like the default app hostname.
    final domainCtrl = TextEditingController(text: appSlug);
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    // Load the org's domain and the env's slug to show the fixed
    // .{envSlug}.{orgDomain} suffix. Uses the same sys GETs the page
    // already calls in _loadNames(), so the field names match everywhere.
    String orgDomain = '';
    String envSlug = '';
    try {
      final orgRes = await AuthProvider.instance.services!.sys.get('/v1/org/${widget.orgId}');
      final raw = orgRes['custom_domain'] as String? ?? '';
      orgDomain = raw.replaceAll('https://', '').replaceAll('http://', '');
    } catch (_) {}
    try {
      final envRes = await AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .sys.get('/v1/env/${widget.envId}');
      envSlug = envRes['slug'] as String? ?? '';
    } catch (_) {}
    String authMode = 'customer';
    // Story 12.4.13 - staff auth domain default value (shown when authMode=staff).
    // Pre-fill the default staff Auth domain: auth.ops.{orgDomain}
    final staffAuthDomainDefault = orgDomain.isNotEmpty
        ? 'auth.ops.$orgDomain'
        : '';
    final staffAuthDomainCtrl = TextEditingController();
    final result = await showDialog<_InstallOptions>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: Sentin8Colors.carbonBlack,
        title: Text('Install App', style: Sentin8Text.h3),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a subdomain for this app instance. The app slug is used as the default - change it if you want a custom prefix.',
                style: Sentin8Text.bodySecondary,
              ),
              const SizedBox(height: Sentin8Spacing.md),
              TextField(
                controller: domainCtrl,
                decoration: InputDecoration(
                  labelText: 'Subdomain',
                  helperText: 'DNS-label: lowercase letters, digits, dot, underscore, hyphen.',
                  border: const OutlineInputBorder(),
                  suffixText: (envSlug.isNotEmpty && orgDomain.isNotEmpty)
                      ? '.$envSlug.$orgDomain'
                      : (orgDomain.isNotEmpty ? '.$orgDomain' : null),
                  suffixStyle: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: Sentin8Spacing.md),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Instance Name (optional)',
                  hintText: 'e.g. My iBank',
                  helperText: 'Displayed as the app name to users',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Sentin8Spacing.md),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Instance Description (optional)',
                  hintText: 'A short description shown to users',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Sentin8Spacing.md),
              // Story 12.4.8 - auth mode selector.
              Text('Auth Mode', style: Sentin8Text.bodySecondary),
              const SizedBox(height: Sentin8Spacing.sm),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'customer',
                    label: Text('Customer'),
                    icon: Icon(Icons.person),
                  ),
                  ButtonSegment(
                    value: 'staff',
                    label: Text('Staff'),
                    icon: Icon(Icons.badge),
                  ),
                ],
                selected: {authMode},
                onSelectionChanged: (Set<String> v) {
                  setDialogState(() => authMode = v.first);
                },
              ),
              const SizedBox(height: Sentin8Spacing.sm),
              Text(
                authMode == 'staff'
                    ? 'Staff mode: sign-up hidden, SSO only, org-scoped Auth.'
                    : 'Customer mode: public sign-up, env-scoped Auth.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              // Story 12.4.13 - Staff Auth Domain field (only when authMode=staff).
              if (authMode == 'staff') ...[
                const SizedBox(height: Sentin8Spacing.md),
                // Use a fresh controller with the default text so the DOM
                // input is seeded correctly on first build (Flutter CanvasKit
                // doesn't sync programmatic controller.text changes to the
                // DOM input element after creation).
                TextField(
                  controller: TextEditingController(text: staffAuthDomainDefault),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Staff Auth Domain',
                    hintText: 'auth.ops.{org_domain}',
                    helperText: 'The Auth domain for staff OIDC sign-in. Defaults to the org-level Auth.',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) => staffAuthDomainCtrl.text = val,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // Validate: subdomain is required and must be a non-empty
              // DNS label. We trim and reject empty/whitespace-only
              // values - Flutter TextField doesn't enforce this for us
              // when there's a default value (the user could clear it).
              final subdomain = domainCtrl.text.trim();
              if (subdomain.isEmpty) {
                // Show an inline error rather than silently installing
                // with an empty custom_domain. The dialog stays open
                // so the user can correct the field.
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Subdomain is required')),
                );
                return;
              }
              Navigator.pop(
                ctx,
                _InstallOptions(
                  customDomain: subdomain,
                  instanceName: nameCtrl.text.trim(),
                  instanceDescription: descCtrl.text.trim(),
                  authMode: authMode,
                  staffAuthDomain: authMode == 'staff'
                      ? (staffAuthDomainCtrl.text.trim().isNotEmpty
                          ? staffAuthDomainCtrl.text.trim()
                          : staffAuthDomainDefault)
                      : null,
                ),
              );
            },
            child: Text('Install'),
          ),
        ],
      ),
      ),
    );
    domainCtrl.dispose();
    nameCtrl.dispose();
    descCtrl.dispose();
    staffAuthDomainCtrl.dispose();
    return result;
  }

  /// Uninstall an app: DELETE the instance which also revokes the
  /// DCR OAuth client via BFF /dcr/delete.
  Future<void> _uninstall(String listingId) async {
    // Find the instance ID for this listing.
    String? instanceId;
    if (_instances != null) {
      for (final inst in _instances!) {
        final m = inst as Map<String, dynamic>;
        if (m['listing_id'] == listingId) {
          instanceId = m['id'] as String?;
          break;
        }
      }
    }
    if (instanceId == null) return;
    try {
      final app = AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .app;
      await app.delete('/v1/app/admin/instances/$instanceId');
      if (mounted) {
        setState(() => _createMessage = 'Uninstalled');
      }
      _load(); // Reload to show Install button
    } catch (e) {
      if (mounted) setState(() => _createMessage = 'Uninstall error: $e');
    }
  }

  /// Returns the App client backed by the sentin8or's env-exchanged access
  /// token. BFF exchanges the sys-realm session token for an env-scoped
  /// token (RFC 8693) via the X-BFF-Target-Org-Id / X-BFF-Target-Env-Id
  /// headers, so the App server resolves the caller's real org/env from
  /// the token claims (used for visibility scoping). Falls back to the
  /// sys-realm client when no org/env is selected.
  ApiClient _scopedApp() {
    final services = AuthProvider.instance.services!;
    if (widget.envId.isNotEmpty) {
      return services.scoped(targetEnvId: widget.envId).app;
    }
    return services.app;
  }

  /// Open the App Settings dialog so the listing creator can edit the
  /// listing's details and visibility.
  Future<void> _showSettingsDialog(Map<String, dynamic> listing) async {
    final listingId = listing['id'] as String?;
    if (listingId == null) return;
    final nameCtrl = TextEditingController(text: listing['app_name'] as String? ?? '');
    final descCtrl = TextEditingController(text: listing['description'] as String? ?? '');
    final backendCtrl = TextEditingController(text: listing['backend_url'] as String? ?? '');
    String visibility = listing['visibility'] as String? ?? 'public';
    String status = listing['status'] as String? ?? 'draft';
    // Pre-fill scopes from oauth_defaults.scopes.
    final oauth = listing['oauth_defaults'];
    final scopesList = <String>[];
    if (oauth is Map<String, dynamic>) {
      final arr = oauth['scopes'];
      if (arr is List) {
        scopesList.addAll(arr.whereType<String>());
      }
    }
    // Pre-fill roles from the listing.
    final existingRoles = <RoleDraft>[];
    final rolesRaw = listing['roles'];
    if (rolesRaw is List) {
      for (final g in rolesRaw) {
        if (g is Map<String, dynamic>) {
          existingRoles.add(RoleDraft(
            name: g['name'] as String? ?? '',
            description: g['description'] as String?,
            scopes: ((g['scopes'] as List?) ?? const [])
                .whereType<String>()
                .toList(),
            includes: ((g['includes'] as List?) ?? const [])
                .whereType<String>()
                .toList(),
          ));
        }
      }
    }
    final existingDefaultSignup = listing['default_signup_role'] as String?;
    // Latest values from the nested widgets - captured on Save.
    List<String> selectedScopes = List<String>.from(scopesList);
    List<RoleDraft> selectedRoles = List<RoleDraft>.from(existingRoles);
    String? selectedDefaultSignup = existingDefaultSignup;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: Sentin8Colors.carbonBlack,
          title: Text('App Settings - ${listing['app_name'] ?? 'App'}', style: Sentin8Text.h3),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'App Name', border: OutlineInputBorder())),
                  const SizedBox(height: Sentin8Spacing.md),
                  TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
                  const SizedBox(height: Sentin8Spacing.md),
                  TextField(controller: backendCtrl, decoration: const InputDecoration(labelText: 'Backend URL', hintText: 'http://localhost:3200', border: OutlineInputBorder())),
                  const SizedBox(height: Sentin8Spacing.md),
                  // OAuth scopes - autocomplete + chip UI.
                  ScopeSelector(
                    initialScopes: scopesList,
                    fetchSuggestions: _fetchScopeCatalog,
                    label: 'OAuth Scopes',
                    helperText: 'Granted to every install of this app. Pick from the list or type a new one.',
                    hintText: 'vertical:resource:action, vertical:resource:action, ...',
                    onChanged: (v) => selectedScopes = v,
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  // App-declared security roles + their scopes.
                  // Note: in app-store listings each role is a row
                  // with name + scopes. "Includes" are NOT exposed
                  // here - app listings don't compose auth roles
                  // (those are platform-managed).  The user can
                  // still leave both scopes and roles empty and
                  // just rely on the listing's OAuth scopes.
                  RoleSelector(
                    initialRoles: existingRoles,
                    defaultSignupName: existingDefaultSignup,
                    fetchScopeSuggestions: _fetchScopeCatalog,
                    label: 'Security Roles',
                    helperText: 'Each role grants its scopes to its members. Append * to a name to make it the default signup role.',
                    onChanged: (roles, defaultSignup) {
                      selectedRoles = roles;
                      selectedDefaultSignup = defaultSignup;
                    },
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  Text('Visibility', style: Sentin8Text.label),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: visibility,
                    items: [
                      DropdownMenuItem(value: 'env', child: Text('env: ${_envName.isNotEmpty ? _envName : 'this environment'}')),
                      DropdownMenuItem(value: 'org', child: Text('org: all environments under ${_orgName.isNotEmpty ? _orgName : 'this organization'}')),
                      const DropdownMenuItem(value: 'public', child: Text('public: all orgs and envs')),
                    ],
                    onChanged: (v) { if (v != null) setSt(() => visibility = v); },
                  ),
                  const SizedBox(height: Sentin8Spacing.sm),
                  Text('Status', style: Sentin8Text.label),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'published', child: Text('published')),
                      DropdownMenuItem(value: 'draft', child: Text('draft')),
                      DropdownMenuItem(value: 'disabled', child: Text('disabled')),
                    ],
                    onChanged: (v) { if (v != null) setSt(() => status = v); },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
    backendCtrl.dispose();
    if (saved != true) return;
    // Build the wire-format roles list - drop any rows that don't
    // have a name set (the user clicked away without finishing).
    final rolesPayload = <Map<String, dynamic>>[];
    for (final g in selectedRoles) {
      final name = g.name.trim();
      if (name.isEmpty) continue;
      rolesPayload.add({
        'name': name,
        if (g.description != null && g.description!.isNotEmpty)
          'description': g.description,
        'scopes': g.scopes,
        if (g.includes.isNotEmpty) 'includes': g.includes,
      });
    }
    try {
      await _scopedApp().put('/v1/app/store/listings/$listingId', body: {
        'app_name': nameCtrl.text,
        'description': descCtrl.text,
        'visibility': visibility,
        'status': status,
        if (backendCtrl.text.isNotEmpty) 'backend_url': backendCtrl.text,
        if (selectedScopes.isNotEmpty) 'oauth_defaults': {'scopes': selectedScopes},
        'roles': rolesPayload,
        if (selectedDefaultSignup != null && selectedDefaultSignup!.isNotEmpty)
          'default_signup_role': selectedDefaultSignup,
      });
      if (mounted) setState(() => _createMessage = 'Settings saved');
      _load();
    } catch (e) {
      if (mounted) setState(() => _createMessage = 'Save error: $e');
    }
  }

  /// Parse the multi-line roles text field into the structured payload
  /// the App server expects.  Each non-blank, non-`#`-prefixed line is
  Future<void> _createListing() async {
    try {
      // Auto-generate slug from app name.
      final appSlug = _nameToSlug(_appNameCtrl.text);
      // POST creates the listing in 'draft' status. The response
      // includes the listing ID which we use to publish it.
      // The new [ScopeSelector] / [RoleSelector] widgets manage
      // their own state and report changes via onChanged; we read
      // the latest values from the state fields we captured.
      final rolesPayload = <Map<String, dynamic>>[];
      for (final g in _selectedRoles) {
        if (g.name.trim().isEmpty) continue;
        rolesPayload.add({
          'name': g.name,
          if (g.description != null && g.description!.isNotEmpty)
            'description': g.description,
          'scopes': g.scopes,
          if (g.includes.isNotEmpty) 'includes': g.includes,
        });
      }
      final res = await _scopedApp().post('/v1/app/store/listings', body: {
        'app_name': _appNameCtrl.text,
        'app_slug': appSlug,
        'description': _descriptionCtrl.text,
        'backend_url': _backendUrlCtrl.text,
        if (_selectedScopes.isNotEmpty)
          'oauth_defaults': {'scopes': _selectedScopes},
        'visibility': _visibility,
        if (rolesPayload.isNotEmpty) 'roles': rolesPayload,
        if (_selectedDefaultSignup != null)
          'default_signup_role': _selectedDefaultSignup,
      });
      if (mounted) {
        setState(() {
          _createMessage = 'Listing created. Now publishing...';
        });
      }
      // Publish the listing using the ID from the POST response.
      final listingId = res['id'] as String?;
      if (listingId != null && listingId.isNotEmpty) {
        await _scopedApp().put('/v1/app/store/listings/$listingId', body: {'status': 'published'});
        // Store the listing ID for e2e test bridge retrieval.
        setLastListingId(listingId);
      }
      if (mounted) {
        setState(() {
          _createMessage = 'Published!';
          _showCreateForm = false;
          _appNameCtrl.clear();
          _descriptionCtrl.clear();
          _backendUrlCtrl.clear();
          _selectedScopes = [];
          _selectedRoles = [];
          _selectedDefaultSignup = null;
        });
        _load();
      }
    } catch (e) {
      if (mounted) setState(() => _createMessage = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: 'App Store',
      child: Padding(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('App Store', style: Sentin8Text.h1),
                FilledButton.icon(
                  onPressed: () => setState(() => _showCreateForm = !_showCreateForm),
                  icon: const Icon(Icons.add),
                  label: Text('Publish New App'),
                ),
              ],
            ),
            const SizedBox(height: Sentin8Spacing.md),
            if (_createMessage != null) ...[
              Text(_createMessage!, style: const TextStyle(color: Sentin8Colors.royalGold)),
              const SizedBox(height: Sentin8Spacing.sm),
            ],
            if (_showCreateForm) ...[
              GlassPanel(
                padding: const EdgeInsets.all(Sentin8Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Publish New App', style: Sentin8Text.h3),
                    const SizedBox(height: Sentin8Spacing.md),
                    TextField(controller: _appNameCtrl, decoration: const InputDecoration(labelText: 'App Name')),
                    const SizedBox(height: Sentin8Spacing.sm),
                    TextField(controller: _descriptionCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
                    const SizedBox(height: Sentin8Spacing.sm),
                    TextField(controller: _backendUrlCtrl, decoration: const InputDecoration(labelText: 'Backend URL', hintText: 'http://localhost:3200')),
                    const SizedBox(height: Sentin8Spacing.sm),
                    // OAuth scopes - autocomplete + chip UI. The new
                    // selector replaces the old comma-separated
                    // textbox. OIDC scopes (openid, profile, email)
                    // are still added automatically by the server.
                    ScopeSelector(
                      initialScopes: _selectedScopes,
                      fetchSuggestions: _fetchScopeCatalog,
                      label: 'OAuth Scopes',
                      helperText: 'Pick from the suggestions or type a new one. OIDC scopes (openid, profile, email) are added automatically.',
                      hintText: 'vertical:resource:action, vertical:resource:action, ...',
                      onChanged: (v) => setState(() => _selectedScopes = v),
                    ),
                    const SizedBox(height: Sentin8Spacing.md),
                    // Security roles - each row is one role with its
                    // own name + scopes. Append * to a name to mark
                    // the default signup role. "Includes" are not
                    // exposed for app listings (auth roles are
                    // platform-managed and listed via the auth
                    // roles page).
                    RoleSelector(
                      initialRoles: _selectedRoles,
                      defaultSignupName: _selectedDefaultSignup,
                      fetchScopeSuggestions: _fetchScopeCatalog,
                      label: 'Security Roles',
                      helperText: 'One role per row. Append * to a name to make it the default signup role.',
                      onChanged: (roles, defaultSignup) {
                        setState(() {
                          _selectedRoles = roles;
                          _selectedDefaultSignup = defaultSignup;
                        });
                      },
                    ),
                    const SizedBox(height: Sentin8Spacing.sm),
                    // Visibility selector - controls which orgs/envs can see
                    // this listing in their App Store.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DropdownButton<String>(
                        value: _visibility,
                        items: [
                          DropdownMenuItem(
                            value: 'env',
                            child: Text('env: ${_envName.isNotEmpty ? _envName : widget.envId.isEmpty ? "this environment" : widget.envId}'),
                          ),
                          DropdownMenuItem(
                            value: 'org',
                            child: Text('org: all environments under ${_orgName.isNotEmpty ? _orgName : widget.orgId.isEmpty ? "this organization" : widget.orgId}'),
                          ),
                          const DropdownMenuItem(
                            value: 'public',
                            child: Text('public: all orgs and envs'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _visibility = v);
                        },
                        hint: Text('Visibility'),
                      ),
                    ),
                    const SizedBox(height: Sentin8Spacing.md),
                    FilledButton(
                      onPressed: _createListing,
                      child: Text('Create & Publish'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Sentin8Spacing.xl),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson))
            else if (_listings == null)
              const CircularProgressIndicator(color: Sentin8Colors.royalGold)
            else if (_listings!.isEmpty)
              GlassPanel(child: Center(child: Text('No apps available yet.', style: Sentin8Text.bodySecondary)))
            else
              SizedBox(
                height: 600,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, childAspectRatio: 0.8, crossAxisSpacing: Sentin8Spacing.md, mainAxisSpacing: Sentin8Spacing.md),
                  itemCount: _listings!.length,
                  itemBuilder: (context, i) {
                    final listing = _listings![i] as Map<String, dynamic>;
                    final listingId = listing['id'] as String?;
                    final installed = _isInstalled(listingId);
                    final inst = _getInstance(listingId);
                    final visibility = listing['visibility'] as String? ?? 'public';
                    // Only the app creator sees the listing ID and Delete button.
                    final currentUserId = AuthProvider.instance.state.userId ?? '';
                    final createdBy = listing['created_by'] as String? ?? '';
                    final isCreator = createdBy.isNotEmpty && createdBy == currentUserId;
                    return GlassPanel(
                      padding: const EdgeInsets.all(Sentin8Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.apps, color: Sentin8Colors.royalGold, size: 40),
                          const SizedBox(height: Sentin8Spacing.sm),
                          Text(listing['app_name'] as String? ?? 'Unknown', style: Sentin8Text.h3),
                          const SizedBox(height: Sentin8Spacing.xs),
                          // Visibility badge - shows the listing's scope.
                          _VisibilityBadge(visibility: visibility),
                          const SizedBox(height: Sentin8Spacing.xs),
                          Text(listing['description'] as String? ?? '', style: Sentin8Text.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
                          // Show listing ID only for the app creator.
                          if (isCreator && listingId != null) ...[
                            const SizedBox(height: Sentin8Spacing.xs),
                            Text('ID: $listingId', style: const TextStyle(fontSize: 10, color: Sentin8Colors.textMuted), overflow: TextOverflow.ellipsis),
                          ],
                          const Spacer(),
                          // Action icon buttons based on installation state.
                          // For installers (someone other than the creator),
                          // the only public action is Launch (if installed).
                          // For the registerer (creator), extra actions are
                          // available: Install, Uninstall, Delete, Details.
                          if (installed) ...[
                            // Installed: Launch (installer-friendly) + Details
                            // + Uninstall (registerer / anyone with delete rights).
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (inst?['hostname'] != null && inst!['hostname'].isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.open_in_new),
                                    color: Sentin8Colors.royalGold,
                                    tooltip: 'Launch',
                                    onPressed: () => _launchApp(inst['hostname'] as String),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  color: Sentin8Colors.royalGold,
                                  tooltip: 'Details',
                                  onPressed: () => _showInstanceDetails(listingId!),
                                ),
                                if (isCreator)
                                  IconButton(
                                    icon: const Icon(Icons.settings),
                                    color: Sentin8Colors.royalGold,
                                    tooltip: 'App Settings',
                                    onPressed: () => _showSettingsDialog(listing),
                                  ),
                                if (isCreator)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Sentin8Colors.errorCrimson,
                                    tooltip: 'Uninstall',
                                    onPressed: () => _uninstall(listing['id']),
                                  ),
                              ],
                            ),
                          ] else ...[
                            // Not installed: Install + Details (creator only)
                            // + Delete (creator only, no instances).
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.download),
                                  color: Sentin8Colors.royalGold,
                                  tooltip: 'Install',
                                  onPressed: () => _install(
                                    listing['id'] as String,
                                    (listing['app_slug'] as String?) ?? '',
                                  ),
                                ),
                                if (isCreator && listingId != null) ...[
                                  IconButton(
                                    icon: const Icon(Icons.info_outline),
                                    color: Sentin8Colors.royalGold,
                                    tooltip: 'Details',
                                    onPressed: () => _showInstanceDetails(listingId),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.settings),
                                    color: Sentin8Colors.royalGold,
                                    tooltip: 'App Settings',
                                    onPressed: () => _showSettingsDialog(listing),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever),
                                    color: Sentin8Colors.errorCrimson,
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteListing(listingId, listing['app_name'] as String? ?? 'App'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
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

/// Detail row for the instance details dialog.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sentin8Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: Sentin8Text.label),
          ),
          Expanded(child: SelectableText(value, style: Sentin8Text.body)),
        ],
      ),
    );
  }
}

/// Options collected from the install dialog.
class _InstallOptions {
  final String customDomain;
  final String instanceName;
  final String instanceDescription;
  final String authMode; // 'customer' or 'staff'
  final String? staffAuthDomain; // Story 12.4.13  -  only when authMode=staff
  const _InstallOptions({
    required this.customDomain,
    required this.instanceName,
    required this.instanceDescription,
    this.authMode = 'customer',
    this.staffAuthDomain,
  });
}

/// A small badge showing a listing's visibility scope.
class _VisibilityBadge extends StatelessWidget {
  final String visibility;
  const _VisibilityBadge({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (visibility) {
      'public' => ('public', Sentin8Colors.royalGold),
      'org' => ('org', Sentin8Colors.softGold),
      _ => ('env', Sentin8Colors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
