// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 API service layer — HTTP clients for all Sentin8 backend services.
// Dash calls services directly (not through Sys) per the design doc §4.4.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'observability.dart';

/// Helper: build a `web.Headers` from a Dart `Map<String, String>`.
web.Headers _buildHeaders(Map<String, String> headers) {
  final h = web.Headers();
  headers.forEach((key, value) {
    // Skip headers with empty values.
    if (value.isEmpty) return;
    h.set(key, value);
  });
  return h;
}

/// Base API client with auth token and correlation ID propagation.
/// When proxyPrefix is set, the client routes through BFF:
///   {baseUrl}{proxyPrefix}/{service}{path}
/// The BFF session cookie is sent automatically by the browser.
///
/// [targetOrgId] and [targetEnvId] are sent as X-BFF-Target-Org-Id and
/// X-BFF-Target-Env-Id headers. These are BFF-internal input parameters
/// (never forwarded upstream) that tell BFF which org/env to exchange the
/// sys-realm token for via RFC 8693 token-exchange, so RLS filters correctly.
///
/// Every request also carries an `x-sentin8-correlation-id` header so the
/// downstream Rust services can correlate the request to the originating
/// Flutter action.
class ApiClient {
  final String baseUrl;
  final String? authToken;
  final String? csrfToken;
  final String? proxyPrefix;
  final String? serviceName;
  final String? targetOrgId;
  final String? targetEnvId;

  ApiClient({
    required this.baseUrl,
    this.authToken,
    this.csrfToken,
    this.proxyPrefix,
    this.serviceName,
    this.targetOrgId,
    this.targetEnvId,
  });

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-sentin8-correlation-id':
            sessionCorrelationId, // SDK8 §3.9 observability
        if (authToken != null) 'authorization': 'Bearer $authToken',
        if (csrfToken != null) 'X-BFF-CSRF': csrfToken!,
        // For env-scoped requests (targetEnvId set), only send target_env_id —
        // org_id is resolved server-side from env_id. For org-scoped requests
        // (targetOrgId set, no targetEnvId), send target_org_id.
        if (targetEnvId != null && targetEnvId!.isNotEmpty)
          'X-BFF-Target-Env-Id': targetEnvId!
        else if (targetOrgId != null && targetOrgId!.isNotEmpty)
          'X-BFF-Target-Org-Id': targetOrgId!,
      };

  String _buildUrl(String path) {
    // Append target params as query params. This avoids CORS preflight
    // issues with custom headers (X-BFF-Target-* is stripped by the
    // browser when credentials: include is used and the CORS preflight
    // doesn't explicitly allow the header).
    //
    // For env-scoped requests (targetEnvId set), only target_env_id is
    // sent — org_id is resolved server-side from env_id via
    // sentin8_sys_environments (env_id is globally unique).
    // For org-scoped requests (targetOrgId set, no targetEnvId),
    // target_org_id is sent.
    final base = proxyPrefix != null && serviceName != null
        ? '$baseUrl$proxyPrefix/$serviceName$path'
        : '$baseUrl$path';
    if (targetEnvId != null && targetEnvId!.isNotEmpty) {
      final sep = base.contains('?') ? '&' : '?';
      return '$base${sep}target_env_id=$targetEnvId';
    }
    if (targetOrgId != null && targetOrgId!.isNotEmpty) {
      final sep = base.contains('?') ? '&' : '?';
      return '$base${sep}target_org_id=$targetOrgId';
    }
    return base;
  }

  /// Record a request's latency and outcome. Centralised so all four
  /// HTTP verb methods below can share the same observability behaviour.
  void _record(String method, String path, int status, int millis) {
    final svc = serviceName ?? 'unknown';
    DashMetrics().recordApiLatency(svc, millis);
    DashLogger.info(
      'HTTP $method $path → $status (${millis}ms)',
      metadata: {'service': svc, 'method': method, 'status': status, 'latency_ms': millis},
    );
  }

  void _recordError(String method, String path, int status, int millis, String reason) {
    final svc = serviceName ?? 'unknown';
    DashMetrics().recordApiError(svc);
    dashAlerts.recordApiError(svc);
    DashLogger.warn(
      'HTTP $method $path → $status ($reason) (${millis}ms)',
      metadata: {'service': svc, 'method': method, 'status': status, 'latency_ms': millis, 'reason': reason},
    );
  }

  Future<Map<String, dynamic>> get(String path) async {
    final sw = Stopwatch()..start();
    final response = await web.window.fetch(
      _buildUrl(path).toJS,
      web.RequestInit(
        method: 'GET',
        credentials: 'include',
        headers: _buildHeaders(_headers),
      ),
    ).toDart;
    sw.stop();
    final status = response.status;
    if (status >= 400) {
      _recordError('GET', path, status, sw.elapsedMilliseconds, 'error_status');
    } else {
      _record('GET', path, status, sw.elapsedMilliseconds);
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    final sw = Stopwatch()..start();
    final response = await web.window.fetch(
      _buildUrl(path).toJS,
      web.RequestInit(
        method: 'POST',
        credentials: 'include',
        headers: _buildHeaders(_headers),
        body: body != null ? jsonEncode(body).toJS : null,
      ),
    ).toDart;
    sw.stop();
    final status = response.status;
    if (status >= 400) {
      _recordError('POST', path, status, sw.elapsedMilliseconds, 'error_status');
    } else {
      _record('POST', path, status, sw.elapsedMilliseconds);
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) async {
    final sw = Stopwatch()..start();
    final response = await web.window.fetch(
      _buildUrl(path).toJS,
      web.RequestInit(
        method: 'PUT',
        credentials: 'include',
        headers: _buildHeaders(_headers),
        body: body != null ? jsonEncode(body).toJS : null,
      ),
    ).toDart;
    sw.stop();
    final status = response.status;
    if (status >= 400) {
      _recordError('PUT', path, status, sw.elapsedMilliseconds, 'error_status');
    } else {
      _record('PUT', path, status, sw.elapsedMilliseconds);
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final sw = Stopwatch()..start();
    final response = await web.window.fetch(
      _buildUrl(path).toJS,
      web.RequestInit(
        method: 'DELETE',
        credentials: 'include',
        headers: _buildHeaders(_headers),
      ),
    ).toDart;
    sw.stop();
    final status = response.status;
    if (status >= 400) {
      _recordError('DELETE', path, status, sw.elapsedMilliseconds, 'error_status');
    } else {
      _record('DELETE', path, status, sw.elapsedMilliseconds);
    }
    return _decode(response);
  }

  /// Fetches raw binary data (e.g. WASM bytes) from the given path.
  /// Returns the raw byte array without JSON decoding.
  Future<Uint8List> getRaw(String path) async {
    final sw = Stopwatch()..start();
    final response = await web.window.fetch(
      _buildUrl(path).toJS,
      web.RequestInit(
        method: 'GET',
        credentials: 'include',
        headers: _buildHeaders(_headers),
      ),
    ).toDart;
    sw.stop();
    if (response.status >= 400) {
      _recordError('GET-RAW', path, response.status, sw.elapsedMilliseconds, 'error_status');
      throw ApiException(response.status, 'Download failed', {});
    }
    _record('GET-RAW', path, response.status, sw.elapsedMilliseconds);
    final jsArrayBuffer = await response.arrayBuffer().toDart;
    return jsArrayBuffer.toDart.asUint8List();
  }

  Future<Map<String, dynamic>> _decode(web.Response response) async {
    final jsRaw = await response.text().toDart;
    final raw = jsRaw.toDart;
    if (raw.isEmpty) {
      if (response.status >= 400) {
        throw ApiException(response.status, 'Request failed', {});
      }
      return <String, dynamic>{};
    }

    // For error responses, the body may be plain text (e.g. "db error: ...")
    // rather than JSON. Try to parse it as JSON, but fall back to using the
    // raw text as the error message so callers see a useful error instead of
    // a FormatException.
    if (response.status >= 400) {
      Map<String, dynamic> body = <String, dynamic>{};
      String message = 'Request failed';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
          message = body['message'] as String? ?? message;
        } else {
          // JSON but not a map — use the raw text as the message.
          message = raw;
        }
      } on FormatException {
        // Not JSON — treat the raw text as the error message.
        message = raw;
      }
      throw ApiException(response.status, message, body);
    }

    final decoded = jsonDecode(raw);
    // Some API endpoints return a JSON array (e.g. GET /v1/app/store/listings
    // returns Vec<StoreListingResponse>). Wrap arrays in a Map so the caller
    // can access them via res['data'] or res['listings'].
    return decoded is List
        ? <String, dynamic>{'data': decoded}
        : decoded as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic> body;
  ApiException(this.statusCode, this.message, this.body);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Centralized Sentin8 service clients.
/// When proxyPrefix is set, all service calls route through BFF:
///   {baseUrl}/proxy/{service}{path}
/// The BFF session cookie is sent automatically by the browser, and
/// BFF attaches the real access token to the upstream request.
///
/// [targetOrgId] is sent as X-BFF-Target-Org-Id header for **org-scoped**
/// requests only (no env). [targetEnvId] is sent as X-BFF-Target-Env-Id
/// header for **env-scoped** requests. When both are present, only
/// target_env_id is sent — the BFF and backend resolve org_id from env_id
/// via sentin8_sys_environments (env_id is globally unique).
/// These are BFF-internal input parameters (never forwarded upstream) that
/// tell BFF which org/env to exchange the sys-realm token for via RFC 8693
/// token-exchange, so RLS filters correctly.
class Sentin8Services {
  final ApiClient auth;
  final ApiClient sys;
  final ApiClient db;
  final ApiClient storage;
  final ApiClient app;
  final ApiClient bus;
  final ApiClient stat;
  final ApiClient func;
  final ApiClient cron;
  final ApiClient flow;
  final ApiClient log;

  Sentin8Services({
    required String Function(String service) baseUrlFor,
    String? authToken,
    String? csrfToken,
    String? proxyPrefix,
    String? targetOrgId,
    String? targetEnvId,
  })  : auth = ApiClient(baseUrl: baseUrlFor('auth'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'auth', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        sys = ApiClient(baseUrl: baseUrlFor('sys'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'sys', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        db = ApiClient(baseUrl: baseUrlFor('db'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'db', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        storage = ApiClient(baseUrl: baseUrlFor('storage'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'storage', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        app = ApiClient(baseUrl: baseUrlFor('app'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'app', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        bus = ApiClient(baseUrl: baseUrlFor('bus'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'bus', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        stat = ApiClient(baseUrl: baseUrlFor('stat'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'stat', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        func = ApiClient(baseUrl: baseUrlFor('func'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'func', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        cron = ApiClient(baseUrl: baseUrlFor('cron'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'cron', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        flow = ApiClient(baseUrl: baseUrlFor('flow'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'flow', targetOrgId: targetOrgId, targetEnvId: targetEnvId),
        log = ApiClient(baseUrl: baseUrlFor('log'), authToken: authToken, csrfToken: csrfToken, proxyPrefix: proxyPrefix, serviceName: 'log', targetOrgId: targetOrgId, targetEnvId: targetEnvId);

  /// Default base URL resolver using the SENTIN8_DOMAIN pattern.
  static String defaultBaseUrl(String service, String domain) =>
      'https://$service.$domain';

  /// Creates a copy of this Sentin8Services with the given target org/env IDs.
  /// For env-scoped requests, pass only [targetEnvId] — the BFF resolves
  /// org_id from env_id via sentin8_sys_environments (env_id is globally
  /// unique). For org-scoped requests, pass only [targetOrgId].
  /// When the BFF proxy sees the target header on a sys-realm request,
  /// it exchanges the sys token for an org/env-scoped token (RFC 8693) so
  /// RLS filters correctly. Without this, sys operators see ALL data.
  Sentin8Services scoped({String? targetOrgId, String? targetEnvId}) {
    return Sentin8Services(
      baseUrlFor: (service) => auth.baseUrl,
      authToken: auth.authToken,
      csrfToken: auth.csrfToken,
      proxyPrefix: auth.proxyPrefix,
      targetOrgId: targetOrgId ?? auth.targetOrgId,
      targetEnvId: targetEnvId ?? auth.targetEnvId,
    );
  }

  /// Fetches the platform-wide OAuth scope catalog from sys
  /// (`GET /v1/scopes/catalog`).  Used by the [ScopeSelector] widget
  /// to populate its autocomplete suggestions without duplicating
  /// the list on the client side.  The endpoint is public (no
  /// auth required) and returns the same list for every caller.
  Future<List<String>> fetchScopeCatalog() async {
    final res = await sys.get('/v1/scopes/catalog');
    final scopes = (res['scopes'] as List?) ?? const [];
    return scopes.cast<String>();
  }
}

/// Auth session state.
class AuthState {
  final bool isAuthenticated;
  final String? token;
  final String? userId;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? realm;
  final String? organizationId;
  final String? environmentId;
  final List<String> scopes;

  const AuthState({
    this.isAuthenticated = false,
    this.token,
    this.userId,
    this.email,
    this.firstName,
    this.lastName,
    this.realm,
    this.organizationId,
    this.environmentId,
    this.scopes = const [],
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? token,
    String? userId,
    String? email,
    String? firstName,
    String? lastName,
    String? realm,
    String? organizationId,
    String? environmentId,
    List<String>? scopes,
  }) => AuthState(
    isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    token: token ?? this.token,
    userId: userId ?? this.userId,
    email: email ?? this.email,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    realm: realm ?? this.realm,
    organizationId: organizationId ?? this.organizationId,
    environmentId: environmentId ?? this.environmentId,
    scopes: scopes ?? this.scopes,
  );

  static const unauthenticated = AuthState();
}