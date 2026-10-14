// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sign-out page — clears session and redirects to sign-in.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';

class SignOutPage extends StatefulWidget {
  const SignOutPage({super.key});
  @override
  State<SignOutPage> createState() => _SignOutPageState();
}

class _SignOutPageState extends State<SignOutPage> {
  @override
  void initState() {
    super.initState();
    AuthProvider.instance.signOut();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamedAndRemoveUntil(context, '/sign-in', (_) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Sentin8Colors.royalGold)),
    );
  }
}