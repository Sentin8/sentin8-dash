// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Dash - BFF WebSocket client (Story 12.4.24)
//
// Connects to BFF /ws for real-time log alerts, metrics, and live map updates.
// Subscribes to sentin8:log.alert.* and sentin8:stat.alert.* events pushed by BFF's Bus
// consumer. Also handles sentin8:log.entry events for the live log tail.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

class BffWebSocket {
  final String bffBaseUrl;
  web.WebSocket? _socket;
  bool _connected = false;
  bool _reconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  List<String> _subscribeTypes = const [];

  // Event callbacks
  void Function(Map<String, dynamic>)? onLogEntry;
  void Function(Map<String, dynamic>)? onLogAlert;
  void Function(Map<String, dynamic>)? onStatAlert;
  void Function(Map<String, dynamic>)? onMetricsSnapshot;
  void Function(Map<String, dynamic>)? onTrafficSnapshot;
  void Function(Map<String, dynamic>)? onDelegationResult;
  void Function(Map<String, dynamic>)? onNotification;
  void Function(Map<String, dynamic>)? onOrgCreated;
  void Function(Map<String, dynamic>)? onEnvCreated;
  void Function(Map<String, dynamic>)? onOrgUpdated;
  void Function(Map<String, dynamic>)? onEnvUpdated;
  void Function()? onConnected;
  void Function()? onDisconnected;

  BffWebSocket({required this.bffBaseUrl});

  bool get isConnected => _connected;

  /// Connect and subscribe to the given event types.
  void connect(List<String> subscribeTypes) {
    if (_connected || _reconnecting) return;
    _subscribeTypes = subscribeTypes;
    final wsUrl = bffBaseUrl.replaceAll('https://', 'wss://').replaceAll('http://', 'ws://');
    final url = '$wsUrl/ws';
    try {
      _socket = web.WebSocket(url);
      _socket!.onOpen.listen((_) {
        _connected = true;
        _reconnectAttempts = 0;
        _reconnecting = false;
        _send({'action': 'subscribe', 'types': subscribeTypes});
        onConnected?.call();
      });
      _socket!.onMessage.listen((event) {
        final data = event.data;
        if (data != null) {
          try {
            final str = (data as dynamic).toString();
            final msg = jsonDecode(str) as Map<String, dynamic>;
            final type = msg['type'] as String?;
            if (type == null) return;
            // Dispatch to the appropriate callback.
            if (type == 'sentin8:log.entry') {
              onLogEntry?.call(msg);
            } else if (type == 'sentin8:log.metrics.snapshot') {
              onMetricsSnapshot?.call(msg);
            } else if (type == 'sentin8:stat.traffic.snapshot') {
              onTrafficSnapshot?.call(msg);
            } else if (type.startsWith('sentin8:log.alert.')) {
              onLogAlert?.call(msg);
            } else if (type.startsWith('sentin8:stat.alert.')) {
              onStatAlert?.call(msg);
            } else if (type == 'sentin8:notification.received') {
              onNotification?.call(msg);
            } else if (type == 'sentin8:delegation.result') {
              onDelegationResult?.call(msg);
            } else if (type == 'sentin8:sys.org.created') {
              onOrgCreated?.call(msg);
            } else if (type == 'sentin8:sys.env.created') {
              onEnvCreated?.call(msg);
            } else if (type == 'sentin8:sys.org.updated') {
              onOrgUpdated?.call(msg);
            } else if (type == 'sentin8:sys.env.updated') {
              onEnvUpdated?.call(msg);
            }
          } catch (_) {}
        }
      });
      _socket!.onClose.listen((_) {
        _connected = false;
        onDisconnected?.call();
        _scheduleReconnect();
      });
      _socket!.onError.listen((_) {
        _connected = false;
        _scheduleReconnect();
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts > 5 ? 30 : 1 << _reconnectAttempts);
    _reconnectTimer = Timer(delay, () {
      _reconnecting = false;
      connect(_subscribeTypes);
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (_connected && _socket != null) {
      _socket!.send(jsonEncode(msg).toJS);
    }
  }

  /// Update subscriptions without reconnecting.
  void subscribe(List<String> types) {
    _subscribeTypes = types;
    _send({'action': 'subscribe', 'types': types});
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.close();
    _socket = null;
    _connected = false;
  }
}