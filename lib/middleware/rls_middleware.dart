// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// RLS enforcement middleware (Story 13.1.16).
//
// Verifies org membership and env ownership on every org/env-scoped route.
// Returns a [RedirectDetails] describing what to do if access is denied.

import 'package:flutter/widgets.dart';

/// The result of an RLS guard check.
class RlsCheckResult {
  /// True when the user is a member of [orgId] (org-scoped) or has a
  /// role/group in [envId] (env-scoped). env_id is globally unique  - 
  /// org_id is resolved server-side from env_id.
  final bool allowed;
  /// Optional redirect location when [allowed] is false.
  final String? redirectTo;
  /// Optional human-readable reason.
  final String? reason;

  const RlsCheckResult({required this.allowed, this.redirectTo, this.reason});
}

/// Resolves whether the current user may access the given scope.
typedef RlsResolver = RlsCheckResult Function({
  required String orgId,
  String? envId,
});

/// Default resolver: allows access when an [orgId] or [envId] is present.
/// For env-scoped routes, only envId is needed (org_id resolved server-side).
RlsCheckResult defaultRlsResolver({required String orgId, String? envId}) {
  if (envId != null && envId.isNotEmpty) {
    return const RlsCheckResult(allowed: true);
  }
  if (orgId.isEmpty) {
    return const RlsCheckResult(allowed: false, redirectTo: '/', reason: 'Missing orgId or envId');
  }
  return const RlsCheckResult(allowed: true);
}

/// Wraps a page-building function so it only runs when the RLS check passes.
///
/// Usage:
/// ```dart
/// rlsGuard(
///   context,
///   orgId: orgId,
///   envId: envId,
///   resolver: myResolver,
///   builder: () => const EnvHomePage(...),
///   denied: (reason) => const AccessDeniedPage(),
/// );
/// ```
Widget rlsGuard({
  required BuildContext context,
  required String orgId,
  String? envId,
  RlsResolver resolver = defaultRlsResolver,
  required Widget Function() builder,
  Widget Function(String? reason)? denied,
}) {
  final result = resolver(orgId: orgId, envId: envId);
  if (!result.allowed) {
    return denied?.call(result.reason) ??
        const Center(child: Text('Access denied'));
  }
  return builder();
}

/// A route middleware that can be plugged into the router to short-circuit
/// scoped routes before they render.
class RlsMiddleware {
  final RlsResolver resolver;

  RlsMiddleware({this.resolver = defaultRlsResolver});

  /// Returns null to continue, or a redirect path to short-circuit.
  String? guard({required String orgId, String? envId}) {
    final result = resolver(orgId: orgId, envId: envId);
    if (result.allowed) return null;
    return result.redirectTo ?? '/';
  }
}