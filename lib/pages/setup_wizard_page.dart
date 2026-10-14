// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Setup wizard page — install an App listing into an environment.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class SetupWizardPage extends StatefulWidget {
  final String orgId;
  final String envId;
  const SetupWizardPage({super.key, required this.orgId, required this.envId});
  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String _orgDomain = '';

  @override
  void initState() {
    super.initState();
    _loadOrgDomain();
  }

  Future<void> _loadOrgDomain() async {
    try {
      final res = await AuthProvider.instance.services!.sys.get('/v1/org/${widget.orgId}');
      final raw = res['custom_domain'] as String? ?? '';
      if (mounted) setState(() => _orgDomain = raw.replaceAll('https://', '').replaceAll('http://', ''));
    } catch (_) {}
  }

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Use scoped services so BFF exchanges the sys-realm token for an
      // env-scoped token (X-BFF-Target-Org-Id / X-BFF-Target-Env-Id
      // headers). Without this, the sys token's organizationId (System
      // Org) doesn't match the request body's organizationId.
      final app = AuthProvider.instance.services!
          .scoped(targetEnvId: widget.envId)
          .app;
      final res = await app.post('/v1/app/setup', body: {
        'org_id': widget.orgId,
        'env_id': widget.envId,
        'listing_id': Uri.parse(ModalRoute.of(context)?.settings.name ?? '').queryParameters['listing_id'] ?? '',
        'oauth_client': {
          'client_id': _clientIdCtrl.text,
          'client_secret': _clientSecretCtrl.text,
          'redirect_uris': [],
          'grant_types': ['authorization_code', 'refresh_token'],
          'response_types': ['code'],
          'token_endpoint_auth_method': 'client_secret_post',
          'scopes': ['openid', 'profile', 'email'],
        },
        'custom_domain': _domainCtrl.text.isNotEmpty ? _domainCtrl.text : null,
      });
      if (mounted) {
        final instanceId = res['id'] as String? ?? res['app_instance_id'] as String? ?? '';
        Navigator.pushReplacementNamed(context, '/app/instances/$instanceId?env=${widget.envId}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: widget.envId,
      title: 'Setup Wizard',
      child: Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(40),
          margin: const EdgeInsets.all(Sentin8Spacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Setup Wizard', style: Sentin8Text.h1),
                const SizedBox(height: Sentin8Spacing.sm),
                Text('Paste your OAuth client credentials to install the app.', style: Sentin8Text.bodySecondary),
                const SizedBox(height: Sentin8Spacing.xl),
                TextField(controller: _clientIdCtrl, decoration: const InputDecoration(labelText: 'Client ID')),
                const SizedBox(height: Sentin8Spacing.md),
                TextField(controller: _clientSecretCtrl, decoration: const InputDecoration(labelText: 'Client Secret'), obscureText: true),
                const SizedBox(height: Sentin8Spacing.md),
                TextField(
                  controller: _domainCtrl,
                  decoration: InputDecoration(
                    labelText: 'Subdomain (optional)',
                    hintText: 'www',
                    suffixText: _orgDomain.isNotEmpty ? '.$_orgDomain' : null,
                    suffixStyle: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: Sentin8Spacing.lg),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)),
                  const SizedBox(height: Sentin8Spacing.md),
                ],
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Install'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}