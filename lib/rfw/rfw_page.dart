// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// RFW Page — stateful page widget that fetches an RFW definition from a vertical
// service, renders it, and handles form submissions.
//
// This is the main entry point for vertical admin pages in Sentin8:Dash.
// The dash route `/env/{envId}/{service}/{page}` (env-scoped) or
// `/org/{orgId}/{service}/{page}` (org-scoped) resolves to this widget.

import 'package:flutter/material.dart';
import 'package:sentin8/sentin8.dart' hide Sentin8Colors, Sentin8Text, Sentin8Spacing, Sentin8ColorsDark, GlassPanel;
import '../services.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/icon_lookup.dart';

/// The RFW page widget — fetches and renders a remote admin UI page.
class RfwPage extends StatefulWidget {
  final String orgId;
  final String envId;
  final String service;
  final String page;
  final Sentin8Services? services;
  final String? Function(String)? baseUrlFor;
  final Map<String, dynamic>? extraProps;

  const RfwPage({
    super.key,
    required this.orgId,
    required this.envId,
    required this.service,
    required this.page,
    required this.services,
    required this.baseUrlFor,
    this.extraProps,
  });

  @override
  State<RfwPage> createState() => _RfwPageState();
}

class _RfwPageState extends State<RfwPage> {
  static final _cache = RfwCache();

  /// BFF transport/gateway failures are transient on fresh envs: the
  /// upstream's prod hostname has no TLS cert yet and loses the first
  /// handshake race (the on-demand Acme fetch lands ~100ms later; the
  /// BFF surfaces the lost race as a 502). Retryable like the 403
  /// propagation window.
  static bool _isTransientGatewayError(Object e) {
    final s = e.toString();
    return s.contains('502') || s.contains('503') || s.contains('504');
  }

  AdminUiPage? _pageDef;
  bool _loading = true;
  String? _error;
  List<VerticalServicePage> _servicePages = [];
  String _serviceLabel = '';
  String _serviceIcon = '';

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(RfwPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when service, page, or extraProps change (e.g. navigating
    // from buckets/new back to buckets after form submission redirect).
    if (oldWidget.service != widget.service ||
        oldWidget.page != widget.page ||
        (oldWidget.extraProps?.toString() ?? '') !=
            (widget.extraProps?.toString() ?? '')) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    // Fetch module features to build the tab bar (service sub-pages).
    // Await so the first build has the service label + icon available.
    await _fetchServicePages();

    // Check cache first. Include the type param in the cache key so
    // different product type forms don't collide.
    final cacheKey = widget.extraProps != null && widget.extraProps!['type'] != null
        ? '${widget.page}?type=${widget.extraProps!['type']}'
        : widget.page;
    final cached = _cache.get(widget.service, cacheKey);
    if (cached != null) {
      setState(() {
        _pageDef = cached;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Transient identity-propagation 403 (policy design §3.1d-1): a
    // freshly created env can deny the first admin-UI loads for ~1-2s
    // (observed up to ~1.6s) until the invalidation event propagates.
    // A 502 rides the same window from the OTHER side: the service's
    // prod hostname has no TLS cert yet on a fresh env and the BFF's
    // first upstream connect loses the handshake race (the on-demand
    // Acme fetch lands ~100ms later); the follow-up connect succeeds.
    // Retry BOTH transient classes with a backoff budget comfortably
    // above either window instead of surfacing the error + Retry button
    // (the rls_guard and org home page use the same tolerance).
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await _fetchPageOnce(cacheKey);
        return; // loaded or handled — no retry needed
      } catch (e) {
        // ignore: avoid_print
        print('rfw_retry: attempt=$attempt error=$e');
        lastError = e;
        final transient =
            e.toString().contains('403') || _isTransientGatewayError(e);
        if (!transient) break;
        if (attempt == 5) break;
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    }
    if (mounted && lastError != null) {
      setState(() {
        _error = lastError.toString();
        _loading = false;
      });
    }
  }

  /// One fetch attempt of the admin-UI page definition (no retry logic).
  /// Throws on transport/HTTP errors so the caller's retry loop can react;
  /// structured error responses set [_error] directly (no throw).
  Future<void> _fetchPageOnce(String cacheKey) async {
    // Create a per-service ApiClient routed through the BFF proxy.
    // The BFF proxy URL pattern is: {bffBaseUrl}/proxy/{service}{path}
    // The BFF handles token exchange and cookie forwarding.
    final bffBaseUrl = AuthProvider.instance.bffBaseUrl;
    final client = ApiClient(
      baseUrl: bffBaseUrl,
      serviceName: widget.service,
      proxyPrefix: '/proxy',
      targetOrgId: widget.envId.isEmpty ? widget.orgId : null,
      targetEnvId: widget.envId.isNotEmpty ? widget.envId : null,
    );

    // Build the admin UI URL, appending query params from extraProps
    // (e.g. ?type=current_account for product creation forms).
    var adminUiPath = '/v1/admin/ui/${widget.page}';
    if (widget.extraProps != null && widget.extraProps!['type'] != null) {
      adminUiPath += '?type=${widget.extraProps!['type']}';
    }

    final response = await client.get(adminUiPath);
    final adminResponse = AdminUiResponse.fromJson(response);

    if (adminResponse.responseType == 'page' && adminResponse.page != null) {
      _cache.put(widget.service, cacheKey, adminResponse.page!);
      setState(() {
        _pageDef = adminResponse.page;
        _loading = false;
      });
    } else if (adminResponse.responseType == 'error') {
      setState(() {
        _error = adminResponse.errorMessage ?? 'Unknown error';
        _loading = false;
      });
    }
  }

  /// Fetch the module features from Sys to get the current service's pages
  /// for the tab bar.
  Future<void> _fetchServicePages() async {
    try {
      await AuthProvider.instance.ready;
      final services = AuthProvider.instance.services;
      if (services == null) return;
      final res = await services.sys.get(
          '/v1/verticals/services${widget.envId.isNotEmpty ? '?env_id=${widget.envId}' : widget.orgId.isNotEmpty ? '?org_id=${widget.orgId}' : ''}');
      List<VerticalService> modules;
      if (res is List) {
        modules = VerticalService.fromJsonList(res);
      } else if (res['data'] is List) {
        modules = VerticalService.fromJsonList(res['data']);
      } else {
        return;
      }
      final mod = modules
          .where((m) => m.enabled && m.service == widget.service)
          .firstOrNull;
      if (mod != null && mounted) {
        setState(() {
          _serviceLabel = mod.label;
          _serviceIcon = mod.icon;
          // Only top-level pages (no '/' in route) are shown as tabs.
          _servicePages = mod.pages.where((p) => !p.route.contains('/')).toList();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: Sentin8Colors.errorCrimson),
            const SizedBox(height: 16),
            Text('Failed to load admin UI', style: Sentin8Text.h2),
            const SizedBox(height: 8),
            Text(_error!, style: Sentin8Text.bodySecondary),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPage, child: Text('Retry')),
          ],
        ),
      );
    }
    if (_pageDef == null) {
      return const Center(child: Text('No content'));
    }

    // Native-widget host registry closure needs the very RfwActions being
    // constructed (the policy simulator's run/save buttons call back through
    // it) — hold it in a single-element container assigned right after
    // construction; the callbacks only run at render time, long after.
    RfwActions? actionsRef;
    final actions = RfwActions(
      fetchData: (endpoint) async {
        final bffBaseUrl = AuthProvider.instance.bffBaseUrl;
        final client = ApiClient(
          baseUrl: bffBaseUrl,
          serviceName: widget.service,
          proxyPrefix: '/proxy',
          targetOrgId: widget.envId.isEmpty ? widget.orgId : null,
          targetEnvId: widget.envId.isNotEmpty ? widget.envId : null,
        );
        // Endpoint forms seen in RFW page defs: '/v1/admin/tables'
        // (absolute), '/certificates', 'certificates' (both treated as
        // admin-relative). Normalize: strip leading slashes, then prepend
        // /v1/admin/ unless the endpoint already carries a version prefix.
        final clean = endpoint.startsWith('/')
            ? endpoint.replaceFirst(RegExp(r'^/+'), '')
            : endpoint;
        final path = clean.startsWith('v1/')
            ? '/$clean'
            : '/v1/admin/$clean';
        final response = await client.get(path);
        // Handle multiple response formats:
        // 1. { "data": [...] } — standard envelope
        // 2. { "users": [...] } — resource-keyed (auth, stat, etc.)
        // 3. [...] — bare array
        if (response['data'] is List) {
          return (response['data'] as List)
              .cast<Map<String, dynamic>>()
              .toList();
        }
        // Try common resource keys
        for (final key in [
          'users',
          'roles',
          'groups',
          'sessions',
          'tables',
          'buckets',
          'streams',
          'consumers',
          'jobs',
          'schedules',
          'workflows',
          'steps',
          'modules',
          'versions',
          'messages',
          'gateways',
          'properties',
          'events',
          'metrics',
          'instances',
          'store',
          'listings',
          'accounts',
          'postings',
          'products',
          'api_keys',
          'api-keys',
          'applications',
          'clients',
          'connections',
          'invitations',
          'memberships',
          'webhooks',
        ]) {
          if (response[key] is List) {
            return (response[key] as List)
                .cast<Map<String, dynamic>>()
                .toList();
          }
        }
        // Response is always a Map from ApiClient.get — no bare array case.
        return [];
      },
      onNavigate: (route) {
        // Navigate to a route relative to the current service.
        // Route is like "users/new" or "install?listing_id={id}" — prepend
        // service and scope params. If the route already has a query string,
        // append scope params with '&' instead of '?'.
        // For env-scoped routes, only ?env= is used (org_id resolved server-side).
        final sep = route.contains('?') ? '&' : '?';
        final scopeParams = widget.envId.isNotEmpty
            ? '${sep}env=${widget.envId}'
            : widget.orgId.isNotEmpty
                ? '${sep}org=${widget.orgId}'
                : '';
        Navigator.of(context)
            .pushNamed('/${widget.service}/$route$scopeParams');
      },
      onRowClick: (rowId) {
        // Row click — navigate to the row's detail page.
      },
      submitForm: (endpoint, body) async {
        final auth = AuthProvider.instance;
        final client = ApiClient(
          baseUrl: auth.bffBaseUrl,
          serviceName: widget.service,
          proxyPrefix: '/proxy',
          targetOrgId: widget.envId.isEmpty ? widget.orgId : null,
          targetEnvId: widget.envId.isNotEmpty ? widget.envId : null,
          csrfToken: auth.csrfToken,
        );
        // Same normalization as fetchData above: absolute /v1/... paths
        // pass through, everything else (with or without a leading slash)
        // gets /v1/admin/ prepended.
        final cleanSubmit = endpoint.startsWith('/')
            ? endpoint.replaceFirst(RegExp(r'^/+'), '')
            : endpoint;
        final path = cleanSubmit.startsWith('v1/')
            ? '/$cleanSubmit'
            : '/v1/admin/$cleanSubmit';
        final response = await client.post(path, body: body);
        return AdminUiResponse.fromJson(response);
      },
      // Raw admin GET/POST for native widgets that need non-list envelopes
      // or custom payload shapes (e.g. the policy simulator's single-set
      // fetch + dry-run). Same admin-relative normalization as above.
      rawGet: (endpoint) async {
        final auth = AuthProvider.instance;
        final client = ApiClient(
          baseUrl: auth.bffBaseUrl,
          serviceName: widget.service,
          proxyPrefix: '/proxy',
          targetOrgId: widget.envId.isEmpty ? widget.orgId : null,
          targetEnvId: widget.envId.isNotEmpty ? widget.envId : null,
        );
        final clean = endpoint.startsWith('/')
            ? endpoint.replaceFirst(RegExp(r'^/+'), '')
            : endpoint;
        final path = clean.startsWith('v1/') ? '/$clean' : '/v1/admin/$clean';
        return client.get(path);
      },
      rawPost: (endpoint, body) async {
        final auth = AuthProvider.instance;
        final client = ApiClient(
          baseUrl: auth.bffBaseUrl,
          serviceName: widget.service,
          proxyPrefix: '/proxy',
          targetOrgId: widget.envId.isEmpty ? widget.orgId : null,
          targetEnvId: widget.envId.isNotEmpty ? widget.envId : null,
          csrfToken: auth.csrfToken,
        );
        final clean = endpoint.startsWith('/')
            ? endpoint.replaceFirst(RegExp(r'^/+'), '')
            : endpoint;
        final path = clean.startsWith('v1/') ? '/$clean' : '/v1/admin/$clean';
        return client.post(path, body: body);
      },
      renderNativeWidget: (widgetName, props, dataEndpoint) {
        // Native widget host registry.
        // The dash ships with built-in widgets for complex interactive pages.
        switch (widgetName) {
          case 'payment_simulator':
            return _PaymentSimulatorPlaceholder(props: props);
          case 'posting_console':
            return _PostingConsolePlaceholder(props: props);
          case 'workflow_visualizer':
            return _WorkflowVisualizerPlaceholder(props: props);
          case 'policy_simulator':
            // Policy Studio editor + simulator (policy design §3.7).
            // Ships from the SDK so every dash-family host renders it.
            return PolicySimulatorWidget(
              props: props,
              dataEndpoint: dataEndpoint,
              actions: actionsRef!,
            );
          default:
            return null;
        }
      },
    );
    actionsRef = actions;

    // Build the tab bar tabs from the service's registered pages (same as sidebar).
    // The first tab (overview) uses the service label and icon instead of "Overview".
    final tabs = _servicePages.map((p) {
      final label = p.route == 'overview' && _serviceLabel.isNotEmpty
          ? _serviceLabel
          : p.label;
      final icon = p.route == 'overview' && _serviceIcon.isNotEmpty
          ? _serviceIcon
          : p.icon;
      return TabEntry(label: label, route: p.route, icon: icon);
    }).toList();
    // Determine the active tab index — match exact route or parent route
    // (e.g. "roles/new" matches the "roles" tab).
    var activeIndex = tabs.indexWhere((t) => t.route == widget.page);
    if (activeIndex < 0) {
      activeIndex = tabs.indexWhere((t) =>
          widget.page == t.route ||
          widget.page.startsWith('${t.route}/'));
    }
    final tabIndex = activeIndex >= 0 ? activeIndex : 0;

    if (tabs.length <= 1) {
      // No tabs — just render the page content directly.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_pageDef!.title, style: Sentin8Text.h1),
                const Spacer(),
                ..._pageDef!.actions.map((action) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ElevatedButton.icon(
                        icon: Icon(iconForName(action.icon)),
                        label: Text(action.label),
                        onPressed: action.route != null
                            ? () => actions.onNavigate(action.route!)
                            : null,
                      ),
                    )),
              ],
            ),
            const SizedBox(height: Sentin8Spacing.xl),
            RfwRenderer(
                widgets: _pageDef!.widgets,
                actions: actions,
                extraProps: widget.extraProps),
          ],
        ),
      );
    }

    return DefaultTabController(
      initialIndex: tabIndex,
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scrollable tab bar — service sub-pages from the module registry.
          // isScrollable: true + tabAlignment: startAlign ensures tabs
          // scroll horizontally when they overflow (important for mobile).
          SizedBox(
            width: double.infinity,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              onTap: (i) {
                if (i != activeIndex) {
                  actions.onNavigate(tabs[i].route);
                }
              },
              tabs: tabs.map((t) => Tab(icon: Icon(iconForName(t.icon), size: 16), text: t.label)).toList(),
            ),
          ),
          const Divider(height: 1),
          // Page content.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sentin8Spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page header with title and actions.
                  Row(
                    children: [
                      Text(_pageDef!.title, style: Sentin8Text.h1),
                      const Spacer(),
                      ..._pageDef!.actions.map((action) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ElevatedButton.icon(
                              icon: Icon(iconForName(action.icon)),
                              label: Text(action.label),
                              onPressed: action.route != null
                                  ? () => actions.onNavigate(action.route!)
                                  : null,
                            ),
                          )),
                    ],
                  ),
                  const SizedBox(height: Sentin8Spacing.xl),
                  // Render the widget tree.
                  RfwRenderer(
                      widgets: _pageDef!.widgets,
                      actions: actions,
                      extraProps: widget.extraProps),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tab entry for the service page tab bar.
class TabEntry {
  final String label;
  final String route;
  final String? icon;
  const TabEntry({required this.label, required this.route, this.icon});
}

// ── Native widget host placeholders ──
// These are placeholders for the native widgets. The real implementations
// will be built in story 22.1.6.

class _PaymentSimulatorPlaceholder extends StatelessWidget {
  final Map<String, dynamic> props;
  const _PaymentSimulatorPlaceholder({required this.props});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.play_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text('Payment Simulator',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
                'Native widget host — interactive payment simulator.\nWill be implemented in story 22.1.6.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _PostingConsolePlaceholder extends StatelessWidget {
  final Map<String, dynamic> props;
  const _PostingConsolePlaceholder({required this.props});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.account_balance, size: 48),
            const SizedBox(height: 12),
            Text('Posting Console',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
                'Native widget host — real-time posting console.\nWill be implemented in story 22.1.6.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _WorkflowVisualizerPlaceholder extends StatelessWidget {
  final Map<String, dynamic> props;
  const _WorkflowVisualizerPlaceholder({required this.props});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.account_tree, size: 48),
            const SizedBox(height: 12),
            Text('Workflow Visualizer',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
                'Native widget host — workflow step visualizer.\nWill be implemented in story 22.1.6.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
