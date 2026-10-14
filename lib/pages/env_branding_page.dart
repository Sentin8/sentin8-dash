// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Environment branding — `/org/{orgId}/env/{envId}/branding` (Story 13.1.14).
//
// Logo URL, logo icon URL, primary color, accent color, font family, theme
// mode, custom CSS. Overrides org branding per-field.

import 'package:flutter/material.dart';

import '../theme/design_system.dart';
import '../auth_provider.dart';

class EnvBrandingPage extends StatefulWidget {
  final String orgId;
  final String envId;

  const EnvBrandingPage({super.key, required this.orgId, required this.envId});

  @override
  State<EnvBrandingPage> createState() => _EnvBrandingPageState();
}

class _EnvBrandingPageState extends State<EnvBrandingPage> {
  final _logoUrlCtrl = TextEditingController();
  final _logoIconUrlCtrl = TextEditingController();
  final _primaryColorCtrl = TextEditingController();
  final _accentColorCtrl = TextEditingController();
  final _fontFamilyCtrl = TextEditingController();
  final _customCssCtrl = TextEditingController();
  String _themeMode = 'light';
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AuthProvider.instance.services!.sys
          .get('/v1/env/${widget.envId}/branding/merged');
      if (mounted) {
        _logoUrlCtrl.text = res['logo_url'] as String? ?? '';
        _logoIconUrlCtrl.text = res['logo_icon_url'] as String? ?? '';
        _primaryColorCtrl.text = res['primary_color'] as String? ?? '';
        _accentColorCtrl.text = res['accent_color'] as String? ?? '';
        _fontFamilyCtrl.text = res['font_family'] as String? ?? '';
        _customCssCtrl.text = res['custom_css'] as String? ?? '';
        _themeMode = res['theme_mode'] as String? ?? 'light';
        if (_themeMode.isEmpty) _themeMode = 'light';
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _message = 'Saving…');
    try {
      await AuthProvider.instance.services!.sys
          .put('/v1/env/${widget.envId}/branding', body: {
        'logo_url': _logoUrlCtrl.text,
        'logo_icon_url': _logoIconUrlCtrl.text,
        'primary_color': _primaryColorCtrl.text,
        'accent_color': _accentColorCtrl.text,
        'font_family': _fontFamilyCtrl.text,
        'theme_mode': _themeMode,
        'custom_css': _customCssCtrl.text,
      });
      if (mounted) setState(() => _message = 'Saved');
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
    return Scaffold(
      backgroundColor: Sentin8DesignTokens.obsidianBlack,
      appBar: AppBar(
        backgroundColor: Sentin8DesignTokens.carbonBlack,
        title: Text('Environment branding', style: Sentin8Typography.h2),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: GlassPanel(
            padding: const EdgeInsets.all(Sentin8DesignTokens.space6),
            child: _loading
                ? const CircularProgressIndicator(color: Sentin8DesignTokens.royalGold)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Branding overrides', style: Sentin8Typography.h1),
                        const SizedBox(height: Sentin8DesignTokens.space4),
                        Sentin8Input(label: 'Logo URL', controller: _logoUrlCtrl),
                        const SizedBox(height: Sentin8DesignTokens.space3),
                        Sentin8Input(label: 'Logo icon URL', controller: _logoIconUrlCtrl),
                        const SizedBox(height: Sentin8DesignTokens.space3),
                        Sentin8Input(label: 'Primary color', controller: _primaryColorCtrl),
                        const SizedBox(height: Sentin8DesignTokens.space3),
                        Sentin8Input(label: 'Accent color', controller: _accentColorCtrl),
                        const SizedBox(height: Sentin8DesignTokens.space3),
                        Sentin8Input(label: 'Font family', controller: _fontFamilyCtrl),
                        const SizedBox(height: Sentin8DesignTokens.space3),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Theme mode'),
                          value: _themeMode,
                          items: const [
                            DropdownMenuItem(value: 'light', child: Text('Light')),
                            DropdownMenuItem(value: 'dark', child: Text('Dark')),
                            DropdownMenuItem(value: 'system', child: Text('System')),
                          ],
                          onChanged: (v) => setState(() => _themeMode = v ?? 'light'),
                        ),
                        const SizedBox(height: Sentin8DesignTokens.space3),
                        Sentin8Input(label: 'Custom CSS', controller: _customCssCtrl),
                        const SizedBox(height: Sentin8DesignTokens.space4),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Sentin8DesignTokens.space3),
                            child: Text(_message!, style: Sentin8Typography.caption),
                          ),
                        Sentin8PrimaryButton(label: 'Save branding', icon: Icons.save_outlined, onPressed: _save),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}