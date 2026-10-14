// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth provider — manages BFF session state for Dash.
//
// Dash uses the standard BFF (Backend for Frontend) OAuth flow:
//   1. User clicks "Sign in" → Dash redirects to BFF GET /auth/login
//   2. BFF generates PKCE server-side, stores in Redis, redirects to Auth
//   3. User authenticates at Auth
//   4. Auth redirects to BFF GET /auth/callback?code=...&state=...
//   5. BFF exchanges the code via back-channel, stores tokens encrypted,
//      sets __Host-bff-session HttpOnly cookie, redirects to Dash homepage
//   6. Dash calls GET /auth/session (with credentials) to fetch user metadata
//
// The authorization code NEVER reaches the frontend. PKCE verifier is
// generated and stored server-side. Access/refresh tokens are held by BFF.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'observability.dart';
import 'services.dart';

/// AuthProvider manages the current BFF session state.
class AuthProvider extends ChangeNotifier {
  /// Singleton instance — shared across the app so all pages use the
  /// same initialized provider with its services and session state.
  static final AuthProvider instance = AuthProvider._();

  AuthProvider._();

  AuthState _state = AuthState.unauthenticated;
  Sentin8Services? _services;
  // _sentin8Domain (for the orgDomain/envDomain UI helpers) and _bffBaseUrl
  // are both derived from the hostname dash is served from (see
  // _currentHost / _inferSentin8Domain / _inferBffBaseUrl). dash constructs
  // exactly ONE external URL — `bff.{current host}` — and routes every
  // other service (auth sign-up/sign-out, …) THROUGH BFF, so there are no
  // hardcoded `sentin8.local` / `bff.dash.ops.sys` / `auth.*` literals.
  String _sentin8Domain = _inferSentin8Domain();
  String _bffBaseUrl = _inferBffBaseUrl();
  String? _csrfToken;
  int _featureVersion = 0;
  Completer<void>? _initCompleter;

  AuthState get state => _state;
  bool get isAuthenticated => _state.isAuthenticated;
  String? get token => _state.token; // BFF session token (opaque, no JWT)
  Sentin8Services? get services => _services;
  String? get csrfToken => _csrfToken;
  String get bffBaseUrl => _bffBaseUrl;
  int get featureVersion => _featureVersion;
  /// The Sentin8 root domain (e.g. "sentin8.local") inferred from the current
  /// window hostname. Used by pages that need to construct org/env domains.
  String get sentin8Domain => _sentin8Domain;

  /// Compute the org's root domain from its slug and optional custom domain.
  /// - If `customDomain` is set, use it as-is.
  /// - Otherwise, return `{slug}.{sentin8Domain}` (e.g. `ibank.sentin8.local`).
  String orgDomain({required String slug, String? customDomain}) {
    if (customDomain != null && customDomain.isNotEmpty) return customDomain;
    return '$slug.$_sentin8Domain';
  }

  /// Compute an environment's root domain from the org's domain and the
  /// env's slug.
  /// - Custom org domain (no `.o.`): `{envSlug}.{orgDomain}`.
  /// - Default org domain (contains `.o.`): `{envSlug}.e.{orgDomain}`.
  String envDomain({required String orgDomain, required String envSlug}) {
    final isCustom = !orgDomain.contains('.o.');
    return isCustom ? '$envSlug.$orgDomain' : '$envSlug.e.$orgDomain';
  }

  /// The hostname dash is currently served from (e.g.
  /// `sentin8-dash.ops.sys.sentin8.local`, `dash.ops.ibank.sentin8.local`). All
  /// scope-dependent URLs are derived from this so one build runs on
  /// platform / org / env dash instances. Empty outside a browser (unit
  /// tests) — inject via `init(sentin8Domain: ...)` then.
  static String _currentHost() {
    try {
      return web.window.location.hostname;
    } catch (_) {
      return '';
    }
  }

  /// Sentin8 root domain derived from the current hostname
  /// (`sentin8-dash.ops.sys.sentin8.local` → `sentin8.local`). Empty if unknown.
  static String _inferSentin8Domain() {
    final host = _currentHost();
    if (host.isEmpty) return '';
    final parts = host.split('.');
    return parts.length >= 2 ? parts.sublist(parts.length - 2).join('.') : host;
  }

  /// BFF base URL for the current dash instance. Apps (dash included)
  /// talk ONLY to BFF — `bff.{current host}` — and route every other
  /// service (auth sign-up/sign-out, …) THROUGH BFF. So this is the
  /// single external URL dash constructs; no hostname parsing or hardcoded
  /// auth/platform hosts anywhere.
  static String _inferBffBaseUrl() {
    final host = _currentHost();
    return host.isEmpty ? '' : 'https://bff.$host';
  }

  /// Increment the feature version counter and notify listeners.
  /// Called after env feature toggles are saved so the nav shell
  /// reloads its feature-gated items immediately.
  void notifyFeatureChange() {
    _featureVersion++;
    notifyListeners();
  }

  /// Returns a Future that completes when the first init() call finishes.
  /// Widgets like RlsGuard can await this to avoid checking isAuthenticated
  /// before the BFF session has been fetched.
  Future<void> get ready => _initCompleter?.future ?? Future.value();

  /// Refresh the BFF session token then re-initialize.
  ///
  /// After creating a new org/env, the user is added to new roles
  /// (org-admin, env-admin) with new scopes. The BFF session token
  /// still has the OLD scopes from sign-in time. This method calls
  /// `POST /auth/refresh` to get a new token with the updated scopes,
  /// then re-initializes to pick up the new session metadata
  /// (org_id, env_id, scopes, target headers).
  ///
  /// Called by the create org/env pages after successful creation.
  Future<void> refreshAndInit() async {
    _bffBaseUrl = _inferBffBaseUrl();
    try {
      await web.window.fetch(
        '$_bffBaseUrl/auth/refresh'.toJS,
        web.RequestInit(method: 'POST', credentials: 'include'),
      ).toDart;
    } catch (_) {
      // Best-effort — if refresh fails, init() will use the old session.
    }
    await init();
  }

  /// Initialize from the BFF session cookie.
  Future<void> init({String? sentin8Domain}) async {
    if (sentin8Domain != null && sentin8Domain.isNotEmpty) {
      _sentin8Domain = sentin8Domain;
    } else {
      // (Re)derive from the live hostname in case the browser navigated to
      // a different dash instance since construction.
      _sentin8Domain = _inferSentin8Domain();
    }
    _bffBaseUrl = _inferBffBaseUrl();
    if (_initCompleter == null) {
      _initCompleter = Completer<void>();
    }
    final completer = _initCompleter!;

    // Check BFF session metadata — the session cookie is HttpOnly so we can't
    // read it directly; instead we call GET /auth/session.
    await _fetchSession();
    notifyListeners();
    if (!completer.isCompleted) completer.complete();
  }

  /// Fetch session metadata from BFF (the cookie is sent automatically).
  Future<void> _fetchSession() async {
    try {
      // Use the browser's fetch API with credentials: 'include' so the
      // HttpOnly __Host-bff-session cookie is sent to the BFF domain.
      // The Dart `http` package uses a separate cookie jar that the browser
      // doesn't share with, so the cookie set by BFF wouldn't be sent.
      final sw = Stopwatch()..start();
      final response = await web.window.fetch(
        '$_bffBaseUrl/auth/session'.toJS,
        web.RequestInit(
          method: 'GET',
          credentials: 'include',
          headers: web.Headers()
            ..set('x-sentin8-correlation-id', sessionCorrelationId),
        ),
      ).toDart;
      sw.stop();
      DashMetrics().recordApiLatency('bff', sw.elapsedMilliseconds);
      if (response.status != 200) {
        _state = AuthState.unauthenticated;
        DashLogger.info(
          'bff /auth/session → ${response.status} (${sw.elapsedMilliseconds}ms)',
          metadata: {'service': 'bff', 'status': response.status},
        );
        return;
      }
      final raw = (await response.text().toDart).toDart;
      final res = jsonDecode(raw) as Map<String, dynamic>;
      final user = res['user'] as Map<String, dynamic>?;
      if (user != null) {
        final scopeList = (res['scopes'] as List<dynamic>?)
                ?.map((s) => s as String)
                .toList() ??
            <String>[];
        _state = AuthState(
          isAuthenticated: true,
          token: 'bff-session', // Opaque marker — real token is in HttpOnly cookie
          userId: user['id'] as String?,
          organizationId: user['org_id'] as String? ??
              res['org_id'] as String?,
          environmentId: user['env_id'] as String? ??
              res['env_id'] as String?,
          realm: user['subject_type'] as String?,
          scopes: scopeList,
        );
        _csrfToken = res['csrf_token'] as String?;
        _services = Sentin8Services(
          baseUrlFor: (service) => _bffBaseUrl,
          authToken: null, // BFF uses cookie, not Bearer token
          csrfToken: _csrfToken,
          proxyPrefix: '/proxy',
          // Set target org/env from the session so that ALL requests include
          // X-BFF-Target-Org-Id / X-BFF-Target-Env-Id headers. This ensures
          // the CORS preflight (cached by the browser) always allows these
          // headers, so scoped() calls don't have them stripped.
          targetOrgId: _state.organizationId,
          targetEnvId: _state.environmentId,
        );
        DashMetrics().recordSignInSuccess();
        DashLogger.info(
          'session restored',
          metadata: {
            'user_id': _state.userId,
            'realm': _state.realm,
            'org_id': _state.organizationId,
            'env_id': _state.environmentId,
            'scopes': scopeList.length,
          },
        );
      }
    } catch (e, st) {
      DashLogger.warn('session fetch failed: $e', error: e, stackTrace: st);
      // No active session — user is unauthenticated
      _state = AuthState.unauthenticated;
    }
  }

  /// Redirect to BFF to initiate the OAuth flow.
  /// BFF generates PKCE server-side, stores it in Redis, and redirects
  /// to Auth /oauth/authorize. The authorization code never reaches
  /// the frontend — Auth redirects back to BFF /auth/callback.
  void signInWithAuth() {
    DashMetrics().recordSignInAttempt();
    DashLogger.info('sign-in initiated via BFF OAuth redirect');
    // Rotate correlation ID for the new session so the new auth flow's
    // downstream logs don't share an ID with the previous session.
    resetSessionCorrelationId();
    web.window.location.href = '$_bffBaseUrl/auth/login';
  }

  /// Redirect to Auth sign-up page directly (not through BFF OAuth flow).
  /// After sign-up, the user can sign in via the BFF OAuth flow.
  void signUpWithAuth() {
    DashLogger.info('sign-up initiated via BFF (Auth hosted sign-up)');
    resetSessionCorrelationId();
    // Route through BFF — it redirects to the Auth hosted sign-up page
    // with the OAuth params for this scope. dash never calls Auth directly.
    web.window.location.href = '$_bffBaseUrl/auth/sign-up';
  }

  /// Sign out — call BFF sign-out (server-side token revocation) and
  /// Auth sign-out (clears __session cookie), then redirect to sign-in.
  void signOut() async {
    DashMetrics().recordSignOutAttempt();
    // 1. Call BFF sign-out to revoke the BFF session and clear
    //    the __Host-bff-session cookie.
    try {
      final sw = Stopwatch()..start();
      await web.window.fetch(
        '$_bffBaseUrl/auth/sign-out'.toJS,
        web.RequestInit(
          method: 'POST',
          credentials: 'include',
          headers: web.Headers()
            ..set('x-sentin8-correlation-id', sessionCorrelationId),
          body: '{}'.toJS,
        ),
      ).toDart;
      sw.stop();
      DashMetrics().recordApiLatency('bff', sw.elapsedMilliseconds);
      DashLogger.info('bff sign-out complete (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      DashLogger.warn('bff sign-out failed: $e');
    }

    // Clear local state and redirect to sign-in.
    _state = AuthState.unauthenticated;
    _services = null;
    _csrfToken = null;
    notifyListeners();
    DashLogger.info('local session cleared, redirecting to sign-in');
    // Rotate correlation ID so the new anonymous session has a fresh ID.
    resetSessionCorrelationId();
    // Return to the sign-in page of the SAME dash instance the user is on
    // (platform / org / env scoped) — never assume a fixed platform host.
    web.window.location.href = '${web.window.location.origin}/#/sign-in';
  }
}
