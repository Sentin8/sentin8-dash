// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Dash GoRouter configuration (Story 13.1.51+).
//
// The dash owns only the shell routes (signin, bootstrap, org/env management).
// All service admin pages are served via RFW (Remote Flutter Widgets) through
// the catch-all route `/env/:envId/:service/:page` (env-scoped) or
// `/org/:orgId/:service/:page` (org-scoped).
// See sentin8-architecture-principles.md §4.15.

import 'package:go_router/go_router.dart';

import 'middleware/rls_middleware.dart';
import 'rfw/rfw_page.dart' as rfw_page;
import 'services.dart';
import 'pages/sign_in_page.dart' as sign_in;
import 'pages/bootstrap_page.dart' as bootstrap;
import 'pages/org_create_page.dart';
import 'pages/org_home_page.dart';
import 'pages/org_settings_page.dart';
import 'pages/members_page.dart';
import 'pages/env_create_page.dart';
import 'pages/env_home_page.dart';
import 'pages/env_settings_page.dart';
import 'pages/env_branding_page.dart';
import 'pages/nav_shell.dart';

/// Dash router wrapper around [GoRouter].
class DashRouter {
  DashRouter({RlsMiddleware? rls, this.services, this.baseUrlFor})
      : _rls = rls ?? RlsMiddleware();

  final RlsMiddleware _rls;
  final Sentin8Services? services;
  final String? Function(String)? baseUrlFor;

  late final GoRouter config = GoRouter(
    initialLocation: '/signin',
    routes: _routes,
    redirect: (context, state) {
      final matched = state.matchedLocation.isEmpty
          ? state.uri.toString()
          : state.matchedLocation;
      // RLS guard: env-scoped routes start with /env/{envId},
      // org-scoped routes start with /org/{orgId}.
      final envMatch = RegExp(r'^/env/([^/]+)(/.*)?$').firstMatch(matched);
      if (envMatch != null) {
        final envId = envMatch.group(1)!;
        final redirect = _rls.guard(orgId: '', envId: envId);
        if (redirect != null) return redirect;
      }
      final orgMatch = RegExp(r'^/org/([^/]+)(/.*)?$').firstMatch(matched);
      if (orgMatch != null) {
        final orgId = orgMatch.group(1)!;
        final redirect = _rls.guard(orgId: orgId);
        if (redirect != null) return redirect;
      }
      return null;
    },
  );

  List<RouteBase> get _routes => [
        GoRoute(
          path: '/signin',
          builder: (context, state) => const sign_in.SignInPage(),
        ),
        GoRoute(
          path: '/bootstrap',
          builder: (context, state) => const bootstrap.BootstrapPage(),
        ),
        GoRoute(
          path: '/org/create',
          builder: (context, state) => const OrgCreatePage(),
        ),
        GoRoute(
          path: '/org/:orgId',
          builder: (context, state) =>
              OrgHomePage(orgId: state.pathParameters['orgId']!),
        ),
        GoRoute(
          path: '/org/:orgId/settings',
          builder: (context, state) =>
              OrgSettingsPage(orgId: state.pathParameters['orgId']!),
        ),
        GoRoute(
          path: '/org/:orgId/members',
          builder: (context, state) =>
              MembersPage(orgId: state.pathParameters['orgId']!),
        ),
        GoRoute(
          path: '/org/:orgId/env/create',
          builder: (context, state) =>
              EnvCreatePage(orgId: state.pathParameters['orgId']!),
        ),
        GoRoute(
          path: '/env/:envId',
          builder: (context, state) => EnvHomePage(
            orgId: '',
            envId: state.pathParameters['envId']!,
          ),
        ),
        GoRoute(
          path: '/env/:envId/settings',
          builder: (context, state) => EnvironmentSettingsPage(
            orgId: '',
            envId: state.pathParameters['envId']!,
          ),
        ),
        GoRoute(
          path: '/env/:envId/branding',
          builder: (context, state) => EnvBrandingPage(
            orgId: '',
            envId: state.pathParameters['envId']!,
          ),
        ),
        // ── RFW catch-all routes (dynamic, discovered at runtime) ──────────
        // All service admin pages are served as Remote Flutter Widgets.
        // The dash has ZERO compile-time knowledge of which services exist.
        // Service/page parameters are resolved from the admin_ui registry
        // in sentin8_vertical_services (populated by sentin8-cli vertical enroll).

        // Platform-scoped services (e.g. /log, /post) — sys realm.
        GoRoute(
          path: '/:service/:page',
          builder: (context, state) {
            final service = state.pathParameters['service']!;
            final page = state.pathParameters['page']!;
            return DashShell(
              orgId: '00000000-0000-0000-0000-000000000001',
              envId: '00000000-0000-0000-0000-000000000002',
              title: service,
              platformScoped: true,
              child: rfw_page.RfwPage(
                orgId: '00000000-0000-0000-0000-000000000001',
                envId: '00000000-0000-0000-0000-000000000002',
                service: service,
                page: page,
                services: services,
                baseUrlFor: baseUrlFor,
              ),
            );
          },
        ),
        // Env-scoped services (e.g. /env/{envId}/auth, .../db).
        GoRoute(
          path: '/env/:envId/:service/:page',
          builder: (context, state) {
            final envId = state.pathParameters['envId']!;
            final service = state.pathParameters['service']!;
            final page = state.pathParameters['page']!;
            return DashShell(
              orgId: '',
              envId: envId,
              title: service,
              child: rfw_page.RfwPage(
                orgId: '',
                envId: envId,
                service: service,
                page: page,
                services: services,
                baseUrlFor: baseUrlFor,
              ),
            );
          },
        ),
      ];
}
