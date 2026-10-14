// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Auth callback page — legacy fallback.
// In the standard BFF flow, BFF handles /auth/callback entirely server-side
// and redirects to the homepage. This page exists only as a fallback if the
// user lands on the frontend /#/auth/callback route directly — it refreshes
// the session from the BFF cookie and redirects to the dashboard.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';

class AuthCallbackPage extends StatefulWidget {
  final String code;
  const AuthCallbackPage({super.key, required this.code});
  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final auth = AuthProvider.instance;
    await auth.init();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
        context, auth.isAuthenticated ? '/bootstrap' : '/sign-in', (_) => false);
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
              CircularProgressIndicator(color: Sentin8Colors.royalGold),
              SizedBox(height: Sentin8Spacing.md),
              Text('Completing sign-in…', style: Sentin8Text.bodySecondary),
            ],
          ),
        ),
      ),
    );
  }
}