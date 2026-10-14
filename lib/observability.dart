// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Dash observability — structured logging, metrics, traces, alerts.
//
// All logs carry correlation IDs for traceability across the Flutter → BFF →
// Rust service boundary. Correlation IDs are generated on the Flutter side and
// sent as `x-sentin8-correlation-id` on every BFF request. BFF and the
// downstream Rust services pick this up via `sentin8-middleware::correlation_id`
// and stamp it onto every log line, giving true end-to-end traceability.
//
// Metrics cover the operator dashboard's primary journeys:
//   - Sign-in success rate
//   - Org/env creation funnel
//   - BFF / proxied service latency
//   - API error rates by service
//
// Alerts cover:
//   - Auth failure spikes
//   - BFF unreachable
//   - Cross-tenant denial anomalies
//
// Stories: 4.1.1-4.1.5 (operator dashboard observability)

import 'dart:math';

/// Session-scoped correlation ID. Generated once per app session and
/// stamped on every outgoing request as `x-sentin8-correlation-id`. The Rust
/// `sentin8-middleware::correlation_id` middleware reads this header and
/// echoes it on every log line in the request's downstream path.
///
/// To track a sub-flow within a session (e.g. "create org" → "create env"),
/// callers can pass an explicit [correlationId] to API helpers — the default
/// behaviour reuses the session-level ID.
String _sessionCorrelationId = _newCorrelationId();

/// Returns the current session-level correlation ID.
String get sessionCorrelationId => _sessionCorrelationId;

/// Generate a fresh correlation ID. Format: `dsh-{epoch_ms}-{rand}`.
String generateCorrelationId() => _newCorrelationId();

String _newCorrelationId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rng = Random();
  // Use nextDouble + multiply instead of nextInt(1 << 32) because the
  // latter gets miscompiled by dart2js (1 << 32 wraps to 1 in JS).
  // 53-bit mantissa of double gives us plenty of entropy for an ID.
  final tail = (rng.nextDouble() * 0xFFFFFFFF).toInt().toRadixString(36);
  return 'dsh-$now-$tail';
}

/// Reset the session correlation ID. Useful when the user signs in/out
/// so the new session's logs don't share an ID with the previous one.
void resetSessionCorrelationId() {
  _sessionCorrelationId = _newCorrelationId();
}

/// Structured log entry with correlation ID.
class LogEntry {
  final String level; // INFO, WARN, ERROR
  final String message;
  final String correlationId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final String? service; // e.g. "dash", "bff", "sys"

  const LogEntry({
    required this.level,
    required this.message,
    required this.correlationId,
    required this.timestamp,
    this.metadata,
    this.service,
  });

  Map<String, dynamic> toJson() => {
        'level': level,
        'message': message,
        'correlation_id': correlationId,
        'timestamp': timestamp.toIso8601String(),
        'service': service ?? 'dash',
        if (metadata != null) 'metadata': metadata,
      };
}

/// In-memory structured logger. Lines are also forwarded to the BFF
/// via a `x-dash-log` header on the next outgoing request (best-effort
/// side-channel) so the Rust side can record them in the same log stream
/// as server-side events. For now we primarily use `dart:developer log`
/// (visible in browser DevTools) and `print` as a fallback.
class DashLogger {
  static final List<LogEntry> _entries = [];
  static const int _maxEntries = 1000;
  static final _pendingBatch = <LogEntry>[];

  static void info(String message,
      {String? correlationId, Map<String, dynamic>? metadata, String? service}) {
    _log('INFO', message, correlationId, metadata, service);
  }

  static void warn(String message,
      {String? correlationId,
      Map<String, dynamic>? metadata,
      String? service,
      Object? error,
      StackTrace? stackTrace}) {
    final meta = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    _log('WARN', message, correlationId, meta.isEmpty ? null : meta, service);
  }

  static void error(String message,
      {String? correlationId,
      Map<String, dynamic>? metadata,
      String? service,
      Object? error,
      StackTrace? stackTrace}) {
    final meta = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    _log('ERROR', message, correlationId, meta.isEmpty ? null : meta, service);
  }

  static void _log(String level, String message, String? correlationId,
      Map<String, dynamic>? metadata, String? service) {
    final entry = LogEntry(
      level: level,
      message: message,
      correlationId: correlationId ?? _sessionCorrelationId,
      timestamp: DateTime.now(),
      metadata: metadata,
      service: service,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    _pendingBatch.add(entry);
    if (_pendingBatch.length > 50) _pendingBatch.removeAt(0);

    // Print to browser console (DevTools) with correlation_id so e2e tests
    // and operators can see what's happening from the frontend.
    // ignore: avoid_print
    print('[${entry.level}] ${entry.timestamp.toIso8601String()} '
        '[${entry.correlationId}] ${entry.service} '
        '$message'
        '${entry.metadata == null ? '' : ' ${entry.metadata}'}');
  }

  /// Drain the recent log entries for side-channel upload. Returns and
  /// clears the pending batch.
  static List<LogEntry> drainPending() => List.of(_pendingBatch)..clear();

  static List<LogEntry> get entries => List.unmodifiable(_entries);
}

/// Metrics counters for Dash. Tracks operator-journey conversion rates
/// and BFF latency so the team can monitor dashboard health from the
/// browser console and from server-side correlates.
class DashMetrics {
  // Sign-in / sign-out
  int _signInAttempts = 0;
  int _signInSuccesses = 0;
  int _signOutAttempts = 0;

  // Org/env creation funnel
  int _orgCreateAttempts = 0;
  int _orgCreateSuccesses = 0;
  int _envCreateAttempts = 0;
  int _envCreateSuccesses = 0;

  // Membership management
  int _memberInviteAttempts = 0;
  int _memberInviteSuccesses = 0;

  // API health
  int _apiErrors = 0;
  final Map<String, int> _errorsByService = {};

  // Latency tracking
  final Map<String, List<int>> _apiLatencies = {};

  void recordSignInAttempt() => _signInAttempts++;
  void recordSignInSuccess() => _signInSuccesses++;
  void recordSignOutAttempt() => _signOutAttempts++;

  void recordOrgCreateAttempt() => _orgCreateAttempts++;
  void recordOrgCreateSuccess() => _orgCreateSuccesses++;
  void recordEnvCreateAttempt() => _envCreateAttempts++;
  void recordEnvCreateSuccess() => _envCreateSuccesses++;

  void recordMemberInviteAttempt() => _memberInviteAttempts++;
  void recordMemberInviteSuccess() => _memberInviteSuccesses++;

  void recordApiError(String service) {
    _apiErrors++;
    _errorsByService[service] = (_errorsByService[service] ?? 0) + 1;
  }

  void recordApiLatency(String service, int milliseconds) {
    _apiLatencies.putIfAbsent(service, () => []).add(milliseconds);
    if (_apiLatencies[service]!.length > 100) {
      _apiLatencies[service]!.removeAt(0);
    }
  }

  double get signInSuccessRate =>
      _signInAttempts > 0 ? _signInSuccesses / _signInAttempts : 0;
  double get orgCreateConversionRate =>
      _orgCreateAttempts > 0 ? _orgCreateSuccesses / _orgCreateAttempts : 0;
  double get envCreateConversionRate =>
      _envCreateAttempts > 0 ? _envCreateSuccesses / _envCreateAttempts : 0;
  int get apiErrorCount => _apiErrors;

  Map<String, double> get averageLatencies {
    final result = <String, double>{};
    _apiLatencies.forEach((service, latencies) {
      if (latencies.isNotEmpty) {
        result[service] =
            latencies.reduce((a, b) => a + b) / latencies.length;
      }
    });
    return result;
  }

  Map<String, dynamic> toJson() => {
        'signInSuccessRate': signInSuccessRate,
        'signInAttempts': _signInAttempts,
        'signInSuccesses': _signInSuccesses,
        'orgCreateConversionRate': orgCreateConversionRate,
        'envCreateConversionRate': envCreateConversionRate,
        'apiErrorCount': _apiErrors,
        'errorsByService': Map.of(_errorsByService),
        'averageLatencies': averageLatencies,
      };
}

/// Alert configuration for Dash. Tracks recent failures in a sliding
/// window and emits warnings via [DashLogger] when thresholds are crossed.
class DashAlerts {
  static const int authFailureThreshold = 5;
  static const int apiErrorThreshold = 10;
  static const Duration window = Duration(minutes: 5);

  final List<DateTime> _authFailures = [];
  final List<DateTime> _apiErrors = [];

  void recordAuthFailure() {
    _authFailures.add(DateTime.now());
    _prune(_authFailures);
    if (_authFailures.length >= authFailureThreshold) {
      DashLogger.warn(
        'Auth failure spike detected: ${_authFailures.length} failures in $window',
      );
    }
  }

  void recordApiError(String service) {
    _apiErrors.add(DateTime.now());
    _prune(_apiErrors);
    if (_apiErrors.length >= apiErrorThreshold) {
      DashLogger.warn(
        'BFF/API error spike: ${_apiErrors.length} errors in $window (latest service=$service)',
      );
    }
  }

  void _prune(List<DateTime> events) {
    final cutoff = DateTime.now().subtract(window);
    events.removeWhere((e) => e.isBefore(cutoff));
  }
}

/// Global alert tracker instance. Page-level widgets add to this via
/// `DashAlerts.instance.recordApiError(...)` etc.
final dashAlerts = DashAlerts();
