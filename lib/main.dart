// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Dash — Operator Dashboard (Flutter Web)
// Dash is the primary web application for Sentin8 operators and organization staff.
//
// The dash owns only the shell routes (signin, bootstrap, org/env management).
// All service admin pages are served via RFW (Remote Flutter Widgets).
// See sentin8-architecture-principles.md §4.15.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'theme.dart';
import 'auth_provider.dart';
import 'observability.dart';
import 'rls_guard.dart';
import 'test_bridge.dart';
import 'pages/pages.dart';
import 'pages/nav_shell.dart';
import 'rfw/rfw_page.dart';

void main() {
  // Enable semantics so that Playwright/e2e tests can interact with
  // form fields via ARIA labels. Flutter CanvasKit renders to a canvas
  // by default; with semantics enabled, it creates real DOM elements
  // (flt-semantics containers with aria-label) that test automation
  // can find and fill.
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  // Register the test bridge for e2e automation (sentin8TestCreateListing,
  // sentin8TestSignOut).
  registerTestBridge();
  // Wire the sentin8TestSignOut bridge so e2e tests can sign out via
  // the same code path as clicking the user menu → "Sign Out" item.
  setSignOutBridgeHandler(() {
    AuthProvider.instance.signOut();
  });
  DashLogger.info('dash app starting',
      metadata: {'correlation_id': sessionCorrelationId});
  runApp(const DashApp());
}

class DashApp extends StatefulWidget {
  const DashApp({super.key});
  @override
  State<DashApp> createState() => _DashAppState();
}

class _DashAppState extends State<DashApp> {
  final AuthProvider _auth = AuthProvider.instance;

  @override
  void initState() {
    super.initState();
    _auth.init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sentin8 Dashboard',
      theme: sentin8Theme(),
      debugShowCheckedModeBanner: false,
      onGenerateRoute: _generateRoute,
    );
  }

  /// Wraps a page widget in an RlsGuard for org-scoped shell routes.
  /// org-scoped routes have envId='' — the guard checks org membership only.
  Widget _guardOrg(String orgId, Widget child) =>
      RlsGuard(envId: '', orgId: orgId, child: child);

  /// Wraps a page widget in an RlsGuard for env-scoped routes.
  /// env_id is globally unique — org_id is NOT required (resolved server-side).
  Widget _guardEnv(String envId, {String? feature, required Widget child}) =>
      RlsGuard(envId: envId, feature: feature, child: child);

  /// Platform org/env IDs for sys-realm (platform-scoped) services.
  static const _platformOrgId = '00000000-0000-0000-0000-000000000001';
  static const _platformEnvId = '00000000-0000-0000-0000-000000000002';

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    // Parse the hash route. Flutter web gives us the path after '#'.
    // Normalize: strip leading '#', parse path + query params.
    var name = settings.name ?? '/';
    if (name.startsWith('#')) name = name.substring(1);
    final uri = Uri.parse(name);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final query = uri.queryParameters;

    // Debug: log the route
    DashLogger.info('route: name=$name segments=$segments query=$query');
    // Expose the app's actual navigation state to e2e automation — the
    // browser URL can lag the Navigator on programmatic pushes.
    setLastRouteBridge(name);

    // --- Shell routes (dash-owned pages) ---
    // Flat route names with optional ?org= and ?env= query params.
    // Scope is determined by which query params are present.

    if (segments.isEmpty) return _page(const BootstrapPage(), settings);
    if (listEquals(segments, ['sign-in'])) return _page(const SignInPage(), settings);
    if (listEquals(segments, ['sign-out'])) return _page(const SignOutPage(), settings);
    if (listEquals(segments, ['bootstrap'])) return _page(const BootstrapPage(), settings);
    if (listEquals(segments, ['org'])) return _page(const OrganizationPickerPage(), settings);
    if (listEquals(segments, ['org', 'create'])) return _page(const CreateOrganizationPage(), settings);
    if (listEquals(segments, ['auth', 'callback'])) {
      return _page(AuthCallbackPage(code: query['code'] ?? ''), settings);
    }

    // Shell routes with ?org= (org-scoped) or ?env= (env-scoped).
    // env_id is globally unique — org_id is NOT required in the URL for
    // env-scoped routes. The backend resolves org_id from env_id via
    // sentin8_sys_environments (see architecture-principles.md §3.1, §4.3e).
    final orgId = query['org'] ?? '';
    final envId = query['env'] ?? '';

    if (listEquals(segments, ['home']) && orgId.isNotEmpty && envId.isEmpty) {
      return _page(_guardOrg(orgId, OrganizationHomePage(orgId: orgId)), settings);
    }
    if (listEquals(segments, ['home']) && envId.isNotEmpty) {
      return _page(_guardEnv(envId, child: EnvironmentHomePage(orgId: orgId, envId: envId)), settings);
    }
    if (listEquals(segments, ['settings']) && orgId.isNotEmpty && envId.isEmpty) {
      return _page(_guardOrg(orgId, OrganizationSettingsPage(orgId: orgId)), settings);
    }
    if (listEquals(segments, ['settings']) && envId.isNotEmpty) {
      return _page(_guardEnv(envId, child: EnvironmentSettingsPage(orgId: orgId, envId: envId)), settings);
    }
    if (listEquals(segments, ['sentin8ors']) && orgId.isNotEmpty) {
      return _page(_guardOrg(orgId, Sentin8orsPage(orgId: orgId)), settings);
    }
    if (listEquals(segments, ['branding']) && orgId.isNotEmpty && envId.isEmpty) {
      return _page(_guardOrg(orgId, OrgBrandingPage(orgId: orgId)), settings);
    }
    if (listEquals(segments, ['branding']) && envId.isNotEmpty) {
      return _page(_guardEnv(envId, child: BrandingPage(orgId: orgId, envId: envId)), settings);
    }
    if (listEquals(segments, ['audit']) && envId.isNotEmpty) {
      return _page(_guardEnv(envId, child: AuditPage(orgId: orgId, envId: envId)), settings);
    }
    if (listEquals(segments, ['env', 'create']) && orgId.isNotEmpty) {
      return _page(_guardOrg(orgId, CreateEnvironmentPage(orgId: orgId)), settings);
    }

    // --- RFW catch-all (service admin pages) ---
    // Every RFW route is: /{service}/{**page}?env={envId}
    // The dash has ZERO compile-time knowledge of which services exist.
    // The scope (platform/env) is determined by query params:
    //   no org/env  → platform-scoped
    //   env only    → env-scoped (org_id resolved server-side from env_id)
    // Extra props (listing_id, instance_id) are passed as query params too:
    //   /app/install?env={envId}&listing_id={listingId}
    //   /app/uninstall?env={envId}&instance_id={instanceId}
    if (segments.isNotEmpty) {
      final service = segments[0];
      // Default to "overview" when no page is specified (e.g. #/auth → #/auth/overview).
      final page = segments.sublist(1).join('/').isEmpty
          ? 'overview'
          : segments.sublist(1).join('/');

      // Build extraProps from query params (listing_id, instance_id, type, etc.)
      Map<String, dynamic>? extraProps;
      for (final key in ['listing_id', 'instance_id', 'app_id', 'app_instance_id', 'type']) {
        if (query[key] != null && query[key]!.isNotEmpty) {
          extraProps ??= {};
          extraProps[key] = query[key];
        }
      }

      // Determine scope from query params:
      //   no org/env  → platform-scoped
      //   env only    → env-scoped (org_id not in URL — resolved server-side)
      if (orgId.isEmpty && envId.isEmpty) {
        // Platform-scoped
        return _page(
            DashShell(
              orgId: _platformOrgId,
              envId: _platformEnvId,
              title: service,
              platformScoped: true,
              child: RfwPage(
                key: ValueKey('$service/$page/${extraProps?['type'] ?? ''}'),
                orgId: _platformOrgId,
                envId: _platformEnvId,
                service: service,
                page: page,
                services: null,
                baseUrlFor: null,
                extraProps: extraProps,
              ),
            ),
            settings);
      } else {
        // Env-scoped (env_id only — org_id resolved server-side from env_id)
        return _page(
            _guardEnv(
              envId,
              child: DashShell(
                orgId: '',
                envId: envId,
                title: service,
                child: RfwPage(
                  orgId: '',
                  envId: envId,
                  service: service,
                  page: page,
                  services: null,
                  baseUrlFor: null,
                  extraProps: extraProps,
                ),
              ),
            ),
            settings);
      }
    }

    // Fallback
    return _page(const NotFoundPage(), settings);
  }

  MaterialPageRoute _page(Widget page, RouteSettings settings) =>
      MaterialPageRoute(builder: (_) => page, settings: settings);
}
