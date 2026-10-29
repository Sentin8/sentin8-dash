// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sign-in page - redirects to Auth hosted UI.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(40),
          margin: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.account_balance, color: Sentin8Colors.royalGold, size: 48),
                const SizedBox(height: Sentin8Spacing.lg),
                Text('Sentin8 Dashboard', style: Sentin8Text.h1, textAlign: TextAlign.center),
                const SizedBox(height: Sentin8Spacing.sm),
                Text('Sign in to manage your Sentin8 tenants', style: Sentin8Text.bodySecondary, textAlign: TextAlign.center),
                const SizedBox(height: Sentin8Spacing.xl),
                FilledButton.icon(
                  onPressed: () => AuthProvider.instance.signInWithAuth(),
                  icon: const Icon(Icons.login),
                  label: Text('Sign in with Auth'),
                ),
                const SizedBox(height: Sentin8Spacing.md),
                OutlinedButton.icon(
                  onPressed: () {
                    // Redirect to Auth sign-up page
                    AuthProvider.instance.signUpWithAuth();
                  },
                  icon: const Icon(Icons.person_add),
                  label: Text('Sign up'),
                ),
                const SizedBox(height: Sentin8Spacing.md),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/org'),
                  child: Text('Browse as guest'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}