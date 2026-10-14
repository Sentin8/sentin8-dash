// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Dash RLS Guard — enforces Row-Level Security on every route.
//
// Per design/sentin8-dash-technical-design.md §7:
//   1. Organization membership gate — user must be a member of {orgId}
//      (org-scoped routes only)
//   2. Environment RBAC gate — user must have a role/group in {envId}
//      (env-scoped routes; env_id is globally unique, org_id is resolved
//      server-side — see architecture-principles.md §4.3d)
//   3. Feature enablement gate — feature must be enabled for the env
//   4. Backend RLS passthrough — envId attached to proxy headers
//   5. No client-side data filtering — server returns only authorized rows
//
// For env-scoped routes, only envId is required — orgId is not needed
// because env_id is globally unique and the backend resolves org_id
// from env_id via sentin8_sys_environments.
import 'package:flutter/material.dart';
import 'theme.dart';
import 'auth_provider.dart';

/// Result of an RLS check.
enum RlsResult { allowed, notMember, envNotFound, notAuthenticated, featureDisabled }

/// Verifies RLS for a given org/env scope before rendering a page.
///
/// [orgId] — the organization from the URL (org-scoped routes only).
/// [envId] — the environment from the URL (env-scoped routes).
/// For env-scoped routes, orgId may be empty — it is resolved server-side.
/// [feature] — optional feature area name for feature-enablement gate.
class RlsGuard extends StatefulWidget {
  final String orgId;
  final String envId;
  final String? feature;
  final Widget child;

  const RlsGuard({
    super.key,
    this.orgId = '',
    required this.envId,
    this.feature,
    required this.child,
  });

  @override
  State<RlsGuard> createState() => _RlsGuardState();
}

class _RlsGuardState extends State<RlsGuard> {
  RlsResult? _result;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(RlsGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.envId != widget.envId ||
        oldWidget.orgId != widget.orgId ||
        oldWidget.feature != widget.feature) {
      _result = null;
      _detail = null;
      _check();
    }
  }

  Future<void> _check() async {
    final auth = AuthProvider.instance;

    // Wait for auth initialization to complete before checking.
    // Without this, the RlsGuard may see isAuthenticated=false because
    // auth.init() (called from main.dart initState) hasn't finished yet.
    await auth.ready;

    // Gate 0: Authentication
    if (!auth.isAuthenticated) {
      if (mounted) setState(() => _result = RlsResult.notAuthenticated);
      return;
    }

    final scopes = auth.state.scopes;
    // Platform admin is permission-based: the scout scope is
    // `sentin8:sys:admin` (architecture-principles §6.0b uniform naming).
    // (`sentin8:app:admin` kept as an alias for app-store admins.)
    final isPlatformAdmin = scopes
        .any((s) => s == 'sentin8:sys:admin' || s == 'sentin8:app:admin');

    // Gate 1: Organization membership (org-scoped routes only).
    // For env-scoped routes (envId is set), org_id is resolved server-side
    // from env_id — no client-side org membership check needed.
    if (widget.envId.isEmpty && widget.orgId.isNotEmpty) {
      if (!isPlatformAdmin) {
        // Verify the user is a member of this org via Sys.
        //
        // Settle-window retry (design §7.1-1): immediately after org creation
        // the services may still hold the caller's cached pre-grant identity —
        // the bootstrap probe answers 403 (or 200 with memberships not yet
        // containing the new org) until the `sentin8:sys:identity:updated`
        // invalidation event propagates (policy design §3.1d-1; observed up to
        // ~6s). Retry every non-member outcome with 1s/2s/4s/8s backoff before
        // declaring notMember; the backend RLS remains the final authority.
        Map<String, dynamic>? lastBootstrap;
        for (var attempt = 0; attempt < 5; attempt++) {
          if (attempt > 0) {
            // 1s / 2s / 4s backoff — bounded above the invalidation window.
            await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
          }
          if (!mounted) return;
          try {
            final res = await auth.services!.sys.get('/v1/bootstrap');
            lastBootstrap = res;
            final memberships = res['memberships'] as List<dynamic>? ?? [];
            final isMember = memberships.any((m) {
              final orgId = (m as Map<String, dynamic>)['org_id'] as String?;
              return orgId == widget.orgId;
            });
            if (isMember) break;
            // 200 with memberships that do not (yet) include this org —
            // likely a stale cached identity. Keep retrying.
          } catch (_) {
            // Bootstrap failed (e.g. 403 — the services still hold the
            // caller's cached pre-grant identity, policy design §3.1d-1).
            //
            // The session orgId is a sign-in-time snapshot and is STALE right
            // after org creation (the user's session org does not yet list
            // the new org), so it must never produce an instant notMember
            // denial while settle-window retries remain. Keep retrying; if
            // bootstrap never succeeds, allow but log — the backend RLS
            // enforces the final decision.
          }
        }
        if (lastBootstrap != null) {
          final memberships =
              lastBootstrap['memberships'] as List<dynamic>? ?? [];
          final isMember = memberships.any((m) {
            final orgId = (m as Map<String, dynamic>)['org_id'] as String?;
            return orgId == widget.orgId;
          });
          if (!isMember && mounted) {
            // The settled identity really lacks this org membership. Block
            // (the panel offers a manual Retry that re-runs the check).
            setState(() {
              _result = RlsResult.notMember;
              _detail = 'You are not a member of organization ${widget.orgId}.';
            });
            return;
          }
        }
        // lastBootstrap == null: bootstrap failed on every attempt with no
        // session-org mismatch — allow but log; backend RLS enforces.
      }
    }

    // Gate 2: Environment RBAC + feature enablement (env-scoped routes only).
    // env_id is globally unique — the backend resolves org_id from env_id
    // and validates RBAC. We fetch the env to check feature enablement.
    if (widget.envId.isNotEmpty) {
      Map<String, dynamic>? envRes;
      String? gate2Error;
      // Retry up to 3 times — the first request after page load can fail
      // transiently (BFF token refresh, network race, etc).
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          envRes = await auth.services!.sys.get(
            '/v1/env/${widget.envId}',
          );
          break;
        } catch (e) {
          gate2Error = '$e';
          // Brief back-off before retry.
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
      if (envRes == null) {
        // All retries failed — only treat as envNotFound if the error
        // is a 404. Other errors (502, network, etc) are transient and
        // should not permanently block the page.
        final is404 = gate2Error != null && gate2Error.contains('404');
        if (mounted) {
          setState(() {
            _result = is404 ? RlsResult.envNotFound : RlsResult.allowed;
            _detail = is404
                ? 'Environment ${widget.envId} not found.'
                : null;
          });
        }
        // If non-404, allow through — backend RLS will enforce the final decision.
        return;
      }
      try {
        final res = envRes;

        // Gate 3: Feature enablement check.
        if (widget.feature != null) {
          final features = res['features'] as Map<String, dynamic>? ?? {};
          // Features default to enabled when not explicitly set in the response.
          // The Sys server returns all features (merged with defaults), but
          // if a feature key is missing, default to true rather than false.
          final enabled = features[widget.feature] as bool? ?? true;
          if (!enabled) {
            if (mounted) {
              setState(() {
                _result = RlsResult.featureDisabled;
                _detail = 'Feature "${widget.feature}" is not enabled for this environment.';
              });
            }
            return;
          }
        }
      } catch (e) {
        // Unexpected error parsing the env response — allow through.
        // The backend RLS will enforce the final decision.
      }
    }

    if (mounted) setState(() => _result = RlsResult.allowed);
  }

  @override
  Widget build(BuildContext context) {
    switch (_result) {
      case null:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: Sentin8Colors.royalGold)),
        );
      case RlsResult.allowed:
        return widget.child;
      case RlsResult.notAuthenticated:
        return _Forbidden(
          title: 'Authentication Required',
          message: 'You must be signed in to access this page.',
        );
      case RlsResult.notMember:
        return _Forbidden(
          title: 'Access Denied — Organization Membership',
          message: _detail ?? 'You are not a member of this organization.',
          onRetry: _check,
        );
      case RlsResult.envNotFound:
        return _Forbidden(
          title: 'Access Denied — Environment Not Found',
          message: _detail ?? 'This environment does not exist or you do not have access to it.',
        );
      case RlsResult.featureDisabled:
        return _Forbidden(
          title: 'Feature Not Enabled',
          message: _detail ?? 'This feature is not enabled for the current environment.',
        );
    }
  }
}

class _Forbidden extends StatelessWidget {
  final String title;
  final String message;
  final Future<void> Function()? onRetry;
  const _Forbidden({required this.title, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(Sentin8Spacing.xl),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 48, color: Sentin8Colors.errorCrimson),
                const SizedBox(height: Sentin8Spacing.lg),
                Text(title, style: Sentin8Text.h2),
                const SizedBox(height: Sentin8Spacing.sm),
                Text(message, style: Sentin8Text.bodySecondary, textAlign: TextAlign.center),
                const SizedBox(height: Sentin8Spacing.lg),
                if (onRetry != null) ...[
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: Sentin8Spacing.sm),
                ],
                FilledButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/org'),
                  child: Text('Back to Organizations'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}