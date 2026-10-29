// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Bootstrap page - resolves user memberships and redirects.
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../theme.dart';
import '../auth_provider.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});
  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  String? _error;
  late String _initialPath;
  // Settle-window retry (master backlog 28.21): a 403 here usually means the
  // caller's identity was cached pre-grant while org/env provisioning is
  // still completing asynchronously (§3.1d-1). Auto-retry with short backoff
  // instead of stranding on a permanent error.
  int _attempt = 0;
  static const _maxAttempts = 5;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    // Capture the initial URL hash so we can preserve deep links.
    // If the user navigated directly to e.g. #/org/{orgId}/.../auth/users,
    // we should redirect there after auth init, not to /organizations.
    final hash = web.window.location.hash;
    _initialPath = hash.isNotEmpty ? hash.substring(1) : '/';
    if (_initialPath == '/' || _initialPath == '/bootstrap' || _initialPath.isEmpty) {
      _initialPath = ''; // scout: no deep link
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = AuthProvider.instance;
    // Initialize - fetches the BFF session (cookie sent automatically).
    await auth.init();
    if (!mounted) return;
    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/sign-in');
      });
      return;
    }
    try {
      final res = await auth.services!.sys.get('/v1/bootstrap');
      final memberships = res['memberships'] as List<dynamic>? ?? [];
      if (!mounted) return;
      // Navigate directly - addPostFrameCallback is unreliable in Flutter web.
      // If there's a deep link (initial URL was not / or /bootstrap), preserve it.
      if (_initialPath.isNotEmpty) {
        Navigator.pushReplacementNamed(context, _initialPath);
      } else if (memberships.isEmpty) {
        Navigator.pushReplacementNamed(context, '/org/create');
      } else if (memberships.length == 1) {
        final orgId = (memberships[0] as Map<String, dynamic>)['org_id'] as String? ??
          (memberships[0] as Map<String, dynamic>)['org_id'] as String;
        Navigator.pushReplacementNamed(context, '/home?org=$orgId');
      } else {
        Navigator.pushReplacementNamed(context, '/org');
      }
    } catch (e) {
      if (!mounted) return;
      // If the memberships bootstrap call returned 401, the
      // session token is stale (e.g. the auth server was
      // restarted with a new key).  Clear the local auth state
      // and bounce back to the sign-in page so the user can
      // re-authenticate and get a fresh token.
      final msg = e.toString();
      final isUnauth = msg.contains('401') || msg.contains('Unauthorized')
          || msg.contains('not found in JWKS')
          || msg.toLowerCase().contains('token verification failed');
      if (isUnauth) {
        // signOut is fire-and-forget (void async).  It clears
        // the BFF session cookie so the next /v1/bootstrap
        // call will hit the sign-in flow cleanly.
        AuthProvider.instance.signOut();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/sign-in');
        return;
      }
      // Settle-window retry: 403/404 during provisioning resolves within a
      // few seconds once the identity invalidation lands (§3.1d-1).
      final isSettleWindow =
          msg.contains('403') || msg.contains('404') || msg.contains('forbidden by policy');
      if (isSettleWindow && _attempt < _maxAttempts) {
        _attempt += 1;
        _retrying = true;
        setState(() => _error = null);
        await Future<void>.delayed(Duration(seconds: _attempt.clamp(1, 4)));
        if (!mounted) return;
        _retrying = false;
        return _bootstrap();
      }
      setState(() => _error = 'Failed to load memberships: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                const Icon(Icons.error_outline, color: Sentin8Colors.errorCrimson, size: 48),
                const SizedBox(height: Sentin8Spacing.md),
                Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)),
                const SizedBox(height: Sentin8Spacing.lg),
                FilledButton.icon(
                  onPressed: () {
                    _attempt = 0;
                    _retrying = false;
                    setState(() => _error = null);
                    _bootstrap();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ] else ...[
                const CircularProgressIndicator(color: Sentin8Colors.royalGold),
                const SizedBox(height: Sentin8Spacing.md),
                Text('Loading dashboard…', style: Sentin8Text.bodySecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}