// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Branding pages — hierarchical branding management.
// Routes: /org/{orgId}/branding                     → org branding
//         /org/{orgId}/env/{envId}/branding            → env branding
//         /org/{orgId}/auth/branding                → org Auth (Staff) branding
//         /org/{orgId}/env/{envId}/auth/branding      → env Auth (Customers) branding
//
// Branding is hierarchical: the most specific scope wins for each field.
// Fields that are null/empty at a level fall through to the next level up.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

/// Org-level branding page — branding for the entire organization.
class OrgBrandingPage extends StatelessWidget {
  final String orgId;
  const OrgBrandingPage({super.key, required this.orgId});

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: orgId,
      envId: '',
      title: 'Branding',
      child: _BrandingForm(orgId: orgId, envId: '', scope: 'org'),
    );
  }
}

/// Env-level branding page — branding for a specific environment.
/// Extends org branding; env fields override org fields when set.
class BrandingPage extends StatelessWidget {
  final String orgId;
  final String envId;
  const BrandingPage({super.key, required this.orgId, required this.envId});

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: orgId,
      envId: envId,
      title: 'Branding',
      child: _BrandingForm(orgId: orgId, envId: envId, scope: 'env'),
    );
  }
}

/// Branding form widget — loads, edits, and saves branding for a given
/// org/env/scope. Shows a "Preview (Merged)" section that displays the
/// effective branding after merging all levels.
class _BrandingForm extends StatefulWidget {
  final String orgId;
  final String envId;
  final String scope;
  const _BrandingForm({required this.orgId, required this.envId, required this.scope});

  @override
  State<_BrandingForm> createState() => _BrandingFormState();
}

class _BrandingFormState extends State<_BrandingForm> {
  final _logoUrlCtrl = TextEditingController();
  final _logoIconUrlCtrl = TextEditingController();
  final _primaryColorCtrl = TextEditingController();
  final _accentColorCtrl = TextEditingController();
  final _fontFamilyCtrl = TextEditingController();
  final _customCssCtrl = TextEditingController();
  String _themeMode = ''; // 'light', 'dark', or '' (default)
  Map<String, dynamic>? _merged;
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _apiPath {
    if (widget.scope == 'org') {
      return '/v1/org/${widget.orgId}/branding';
    } else {
      return '/v1/env/${widget.envId}/branding';
    }
  }

  String get _mergedPath {
    return '/v1/env/${widget.envId}/branding/merged';
  }

  Future<void> _load() async {
    try {
      final sys = AuthProvider.instance.services!
          .scoped(targetOrgId: widget.envId.isEmpty ? widget.orgId : null, targetEnvId: widget.envId.isNotEmpty ? widget.envId : null)
          .sys;
      final res = await sys.get(_apiPath);
      if (mounted) {
        _logoUrlCtrl.text = res['logo_url'] as String? ?? '';
        _logoIconUrlCtrl.text = res['logo_icon_url'] as String? ?? '';
        _primaryColorCtrl.text = res['primary_color'] as String? ?? '';
        _accentColorCtrl.text = res['accent_color'] as String? ?? '';
        _fontFamilyCtrl.text = res['font_family'] as String? ?? '';
        _themeMode = res['theme_mode'] as String? ?? '';
        _customCssCtrl.text = res['custom_css'] as String? ?? '';
        setState(() => _loading = false);
      }
      // Load merged branding preview (only for env-scoped pages).
      if (widget.envId.isNotEmpty) {
        try {
          final mergedRes = await AuthProvider.instance.services!
              .scoped(targetEnvId: widget.envId)
              .sys.get(_mergedPath);
          if (mounted) setState(() => _merged = mergedRes);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await AuthProvider.instance.services!
          .scoped(targetOrgId: widget.envId.isEmpty ? widget.orgId : null, targetEnvId: widget.envId.isNotEmpty ? widget.envId : null)
          .sys.put(_apiPath, body: {
        'logo_url': _logoUrlCtrl.text,
        'logo_icon_url': _logoIconUrlCtrl.text,
        'primary_color': _primaryColorCtrl.text,
        'accent_color': _accentColorCtrl.text,
        'font_family': _fontFamilyCtrl.text,
        'theme_mode': _themeMode,
        'custom_css': _customCssCtrl.text,
      });
      if (mounted) setState(() => _message = 'Saved');
      // Reload merged preview.
      if (widget.envId.isNotEmpty) {
        try {
          final mergedRes = await AuthProvider.instance.services!
              .scoped(targetEnvId: widget.envId)
              .sys.get(_mergedPath);
          if (mounted) setState(() => _merged = mergedRes);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Error: $e');
    }
  }

  @override
  void dispose() {
    _logoUrlCtrl.dispose();
    _logoIconUrlCtrl.dispose();
    _primaryColorCtrl.dispose();
    _accentColorCtrl.dispose();
    _fontFamilyCtrl.dispose();
    _customCssCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Sentin8Colors.royalGold));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Sentin8Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Branding', style: Sentin8Text.h1),
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            'Scope: ${_scopeLabel(widget.scope)} — fields set here override the parent level.',
            style: Sentin8Text.bodySecondary,
          ),
          const SizedBox(height: Sentin8Spacing.lg),

          // Logo URL
          SizedBox(
            width: 500,
            child: TextField(
              controller: _logoUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Logo URL',
                hintText: 'https://... or /storage/...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: Sentin8Spacing.md),

          // Logo Icon URL (for favicon, small icon contexts)
          SizedBox(
            width: 500,
            child: TextField(
              controller: _logoIconUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Logo Icon URL',
                hintText: 'https://... or /storage/... (for favicon, small icons)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: Sentin8Spacing.md),

          // Theme mode (light/dark)
          Row(
            children: [
              Text('Theme Mode: ', style: Sentin8Text.label),
              const SizedBox(width: Sentin8Spacing.sm),
              ChoiceChip(
                label: Text('Default (Dark)'),
                selected: _themeMode.isEmpty,
                onSelected: (_) => setState(() => _themeMode = ''),
              ),
              const SizedBox(width: Sentin8Spacing.sm),
              ChoiceChip(
                label: Text('Light'),
                selected: _themeMode == 'light',
                onSelected: (_) => setState(() => _themeMode = 'light'),
              ),
              const SizedBox(width: Sentin8Spacing.sm),
              ChoiceChip(
                label: Text('Dark'),
                selected: _themeMode == 'dark',
                onSelected: (_) => setState(() => _themeMode = 'dark'),
              ),
            ],
          ),
          const SizedBox(height: Sentin8Spacing.md),

          // Primary color
          Row(
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _primaryColorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Primary Color',
                    hintText: '#D4AF37',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: Sentin8Spacing.sm),
              if (_primaryColorCtrl.text.isNotEmpty)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _parseColor(_primaryColorCtrl.text),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Sentin8Colors.glassBorder),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Sentin8Spacing.md),

          // Accent color
          Row(
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _accentColorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Accent Color',
                    hintText: '#E6C878',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: Sentin8Spacing.sm),
              if (_accentColorCtrl.text.isNotEmpty)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _parseColor(_accentColorCtrl.text),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Sentin8Colors.glassBorder),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Sentin8Spacing.md),

          // Font family
          SizedBox(
            width: 300,
            child: TextField(
              controller: _fontFamilyCtrl,
              decoration: const InputDecoration(
                labelText: 'Font Family',
                hintText: 'Inter, sans-serif',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: Sentin8Spacing.md),

          // Custom CSS
          SizedBox(
            width: 600,
            child: TextField(
              controller: _customCssCtrl,
              decoration: const InputDecoration(
                labelText: 'Custom CSS',
                hintText: '/* Override styles */',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
          ),
          const SizedBox(height: Sentin8Spacing.lg),

          // Save button
          FilledButton(onPressed: _save, child: Text('Save')),
          if (_message != null) ...[
            const SizedBox(height: Sentin8Spacing.sm),
            Text(_message!, style: const TextStyle(color: Sentin8Colors.successGold)),
          ],

          // Merged preview (only for env-scoped pages)
          if (_merged != null) ...[
            const SizedBox(height: Sentin8Spacing.xl),
            Text('Effective Branding (Merged)', style: Sentin8Text.h2),
            const SizedBox(height: Sentin8Spacing.sm),
            Text(
              'All levels merged: org → env. '
              'Each field uses the most specific non-empty value.',
              style: Sentin8Text.bodySecondary,
            ),
            const SizedBox(height: Sentin8Spacing.md),
            _MergedPreview(merged: _merged!),
          ],
        ],
      ),
    );
  }
}

/// Displays the merged branding values as read-only rows.
class _MergedPreview extends StatelessWidget {
  final Map<String, dynamic> merged;
  const _MergedPreview({required this.merged});

  @override
  Widget build(BuildContext context) {
    final fields = ['logoUrl', 'logoIconUrl', 'primaryColor', 'accentColor', 'fontFamily', 'themeMode', 'customCss'];
    return GlassPanel(
      padding: const EdgeInsets.all(Sentin8Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: fields.map((f) {
          final val = merged[f] as String? ?? '—';
          return Padding(
            padding: const EdgeInsets.only(bottom: Sentin8Spacing.sm),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text(f, style: Sentin8Text.label)),
                Expanded(child: SelectableText(val, style: Sentin8Text.body)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Returns a human-readable label for a branding scope.
String _scopeLabel(String scope) => switch (scope) {
      'org' => 'Organization',
      'env' => 'Environment',
      _ => scope,
    };

/// Parses a hex color string, falling back to gold if invalid.
Color _parseColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return Sentin8Colors.royalGold;
  }
}