// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Reusable service traffic metrics table widget.
//
// Displays per-service traffic metrics in a DataTable with SLO status indicators.
// Fetches initial data via HTTP from Stat `/v1/data/traffic`, then subscribes
// to `stat.traffic.snapshot` via BFF WS for live updates (pub/sub, no polling).

import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../auth_provider.dart';
import '../../bff_ws.dart';

/// SLO thresholds for status coloring.
const _kErrorRateWarn = 1.0; // % — yellow band
const _kErrorRateCritical = 5.0; // % — red
const _kP95WarnMs = 500; // ms — yellow band
const _kP95CriticalMs = 2000; // ms — red

/// A self-contained metrics table that:
/// 1. Fetches initial data via HTTP from Stat `/v1/data/traffic`
/// 2. Subscribes to `stat.traffic.snapshot` via BFF WS for live updates
/// 3. Parses the `tls.traffic.{from}→{to}.*` metric names into rows
/// 4. Displays a DataTable with status icon, service pair, requests, errors, latency
class MetricsTable extends StatefulWidget {
  final String orgId;
  final String envId;
  final String title;

  const MetricsTable({
    super.key,
    required this.orgId,
    required this.envId,
    this.title = 'Service Traffic',
  });

  @override
  State<MetricsTable> createState() => _MetricsTableState();
}

class _MetricsTableState extends State<MetricsTable> {
  List<Map<String, dynamic>> _metrics = [];
  bool _loading = true;
  String? _error;
  BffWebSocket? _ws;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _connectWS();
  }

  @override
  void dispose() {
    _ws?.disconnect();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final services = AuthProvider.instance.services;
      if (services == null) {
        if (mounted) setState(() { _loading = false; _error = 'Not authenticated'; });
        return;
      }
      final scoped = services.scoped(targetEnvId: widget.envId);
      final result = await scoped.stat.get('/v1/data/traffic');
      final List<dynamic> rawRows = result['data'] as List? ?? <dynamic>[];
      if (mounted) {
        setState(() {
          _metrics = rawRows.map((r) {
            return <String, dynamic>{
              'from': r['from'] ?? 'unknown',
              'to': r['to'] ?? 'unknown',
              'count': (r['count'] ?? 0).toDouble(),
              'latency_ms': (r['latency_ms'] ?? 0).toDouble(),
              'errors': (r['errors'] ?? 0).toDouble(),
            };
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _connectWS() {
    final bffUrl = AuthProvider.instance.bffBaseUrl;
    if (bffUrl.isEmpty) return;
    _ws = BffWebSocket(bffBaseUrl: bffUrl);
    _ws!.onTrafficSnapshot = (msg) {
      if (!mounted) return;
      final snapOrgId = msg['org_id'] as String? ?? '';
      final snapEnvId = msg['env_id'] as String? ?? '';
      if (snapOrgId != widget.orgId || snapEnvId != widget.envId) return;
      final metricsMap = msg['metrics'] as Map<String, dynamic>? ?? {};
      final rows = _parseTrafficMetrics(metricsMap);
      if (mounted) {
        setState(() {
          _metrics = rows;
          _loading = false;
        });
      }
    };
    _ws!.connect(['sentin8:stat.traffic.snapshot']);
  }

  /// Parse the flat metrics map into per-(from→to) row objects.
  /// Each metric name is `tls.traffic.{from}→{to}.{suffix}`.
  List<Map<String, dynamic>> _parseTrafficMetrics(Map<String, dynamic> metrics) {
    // Group by (from, to) pair.
    final pairs = <String, Map<String, dynamic>>{};
    metrics.forEach((name, value) {
      final rest = name.startsWith('tls.traffic.') ? name.substring('tls.traffic.'.length) : null;
      if (rest == null) return;
      final dotPos = rest.lastIndexOf('.');
        if (dotPos < 0) return;
        final pairStr = rest.substring(0, dotPos);
        final suffix = rest.substring(dotPos + 1);
        final arrowPos = pairStr.indexOf('→');
        if (arrowPos < 0) return;
        final from = pairStr.substring(0, arrowPos);
        final to = pairStr.substring(arrowPos + 3); // skip `→` (3 bytes in UTF-8)
        final key = '$from→$to';
        pairs[key] ??= {'from': from, 'to': to, 'count': 0, 'latency_ms': 0.0, 'errors': 0};
        final numVal = value is num ? value.toDouble() : (double.tryParse(value.toString()) ?? 0.0);
        if (suffix == 'count') pairs[key]!['count'] = numVal;
        if (suffix == 'latency_ms') pairs[key]!['latency_ms'] = numVal;
        if (suffix == 'errors') pairs[key]!['errors'] = numVal;
    });
    return pairs.values.toList()
      ..sort((a, b) => (a['from'] as String).compareTo(b['from'] as String));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: Sentin8Colors.royalGold)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson)),
      );
    }
    if (_metrics.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No metrics data available')),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Sentin8Text.h2),
          const SizedBox(height: 12),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 32,
        columns: const [
          DataColumn(label: Text('Status', style: Sentin8Text.caption)),
          DataColumn(label: Text('From → To', style: Sentin8Text.caption)),
          DataColumn(label: Text('Requests', style: Sentin8Text.caption), numeric: true),
          DataColumn(label: Text('Errors', style: Sentin8Text.caption), numeric: true),
          DataColumn(label: Text('Latency (ms)', style: Sentin8Text.caption), numeric: true),
        ],
        rows: _metrics.map((m) {
          final from = (m['from'] ?? 'unknown').toString();
          final to = (m['to'] ?? 'unknown').toString();
          final reqCount = _toInt(m['count']);
          final errorCount = _toInt(m['errors']);
          final latency = _toDouble(m['latency_ms']);
          final errorRate = reqCount > 0 ? (errorCount / reqCount * 100) : 0.0;
          final status = _sloStatus(errorRate, latency.toInt(), 0);

          return DataRow(
            cells: [
              DataCell(_statusIcon(status)),
              DataCell(Text('${_serviceName(from)} → ${_serviceName(to)}', style: Sentin8Text.body)),
              DataCell(Text(_formatNum(reqCount))),
              DataCell(Text(_formatErrors(errorCount, errorRate))),
              DataCell(Text(_formatLatency(latency))),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Helpers ──

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// SLO status: green (within SLO), yellow (warning), red (over threshold).
  _SloStatus _sloStatus(double errorRate, int latencyMs, int p99) {
    if (errorRate >= _kErrorRateCritical || latencyMs >= _kP95CriticalMs) return _SloStatus.critical;
    if (errorRate >= _kErrorRateWarn || latencyMs >= _kP95WarnMs) return _SloStatus.warning;
    return _SloStatus.healthy;
  }

  Widget _statusIcon(_SloStatus status) {
    final color = switch (status) {
      _SloStatus.healthy => Sentin8Colors.successGold,
      _SloStatus.warning => Sentin8Colors.warningAmber,
      _SloStatus.critical => Sentin8Colors.errorCrimson,
    };
    return Tooltip(
      message: switch (status) {
        _SloStatus.healthy => 'Within SLO',
        _SloStatus.warning => 'Warning: approaching SLO limits',
        _SloStatus.critical => 'Critical: over SLO threshold',
      },
      child: Icon(Icons.circle, color: color, size: 16),
    );
  }

  /// Convert "bff" → "BFF", "ledger" → "Ledger", etc.
  String _serviceName(String s) {
    if (s.endsWith('-server')) {
      final name = s.substring(0, s.length - 7);
      return '${name[0].toUpperCase()}${name.substring(1)}';
    }
    return s[0].toUpperCase() + s.substring(1);
  }

  String _formatNum(int n) => n.toString();

  String _formatErrors(int count, double rate) {
    if (count == 0) return '';
    return '$count (${rate.toStringAsFixed(1)}%)';
  }

  String _formatLatency(double ms) {
    if (ms == 0) return '';
    return '${ms.toStringAsFixed(1)}ms';
  }
}

enum _SloStatus { healthy, warning, critical }