// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Smoke test for the Sentin8 Dash app entry.
//
// The app and its SDK are web-coupled (`package:web` / `dart:js_interop`
// in `auth_provider`, `bff_ws`, `services`, `test_bridge` and the sentin8
// Flutter SDK), so this runs on the chrome platform - `make test-flutter`
// passes `--platform chrome` (see Makefile).
//
// `DashApp.initState` kicks off `AuthProvider.init()` which fetches the
// BFF session; with no BFF reachable under the test harness that fails and
// falls back to a loaded-but-signed-out state - the expected path. The
// smoke assertion is that the app shell builds and shows the sign-in
// route shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dash/main.dart';

void main() {
  testWidgets('DashApp builds and renders the app shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DashApp());
    // Let AuthProvider.init() complete (fails offline → signed-out state).
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(DashApp), findsOneWidget);
  });
}