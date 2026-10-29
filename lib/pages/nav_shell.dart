// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Dash navigation shell - left rail with feature nav and breadcrumb header.
//
// The sidebar is dynamic: it highlights the active item based on the current
// route, auto-expands parent items whose children match the current route.
// Org-scoped routes show only org-level nav items; env-scoped routes show
// the full feature-area tree.
//
// The header shows a clickable breadcrumb: Org Name > Env Name > Page Title.
// Org and env names are resolved from Sys (display names, not UUIDs).
// There is no org/env selection box in the sidebar.
//
// The left rail is collapsible: clicking the logo toggles between 260px
// (expanded, with labels) and 72px (collapsed, icons only). The collapsed
// state is persisted in localStorage.
//
// The user menu shows the user's name (from BFF session) and a popup
// with Settings and Sign Out items.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;
import '../theme.dart';
import '../auth_provider.dart';
import 'package:sentin8/sentin8.dart' hide Sentin8Colors, Sentin8Text, Sentin8Spacing, Sentin8ColorsDark, GlassPanel;
import '../widgets/icon_lookup.dart';

/// Navigation item in the left rail. Items with [children] are expandable
/// parent nodes; items without children are leaf nodes.
class NavItem {
  final String label;
  final IconData icon;
  final String route;
  final List<NavItem>? children;
  const NavItem(
      {required this.label,
      required this.icon,
      required this.route,
      this.children});

  /// Exact route match - used for active highlighting so only the
  /// deepest/last visible nav item is highlighted, not its parents.
  bool isActiveRoute(String currentRoute) => currentRoute == route;

  bool matches(String currentRoute) {
    if (currentRoute == route) return true;
    return currentRoute.startsWith('$route/');
  }

  bool matchesDeep(String currentRoute) {
    if (matches(currentRoute)) return true;
    if (children != null) {
      for (final child in children!) {
        if (child.matchesDeep(currentRoute)) return true;
      }
    }
    return false;
  }
}

/// The main Dash layout shell with a left rail navigation.
class DashShell extends StatefulWidget {
  final String orgId;
  final String envId;
  final String title;
  final Widget child;
  final List<NavItem>? extraNav;

  /// When true, the shell renders the platform-scoped nav (global Log)
  /// instead of org/env nav. Used by the `/log` platform routes.
  final bool platformScoped;

  const DashShell({
    super.key,
    required this.orgId,
    required this.envId,
    required this.title,
    required this.child,
    this.extraNav,
    this.platformScoped = false,
  });

  @override
  State<DashShell> createState() => _DashShellState();
}

class _DashShellState extends State<DashShell> {
  String _orgName = '';
  String _envName = '';
  String _envUrl = '';
  String _orgUrl = '';
  String _userName = '';
  List<VerticalService> _verticalServices = [];
  bool _railCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadNames();
    _loadRailState();
    AuthProvider.instance.addListener(_onAuthProviderChange);
  }

  @override
  void dispose() {
    AuthProvider.instance.removeListener(_onAuthProviderChange);
    super.dispose();
  }

  int _lastFeatureVersion = 0;
  void _onAuthProviderChange() {
    final v = AuthProvider.instance.featureVersion;
    if (v != _lastFeatureVersion) {
      _lastFeatureVersion = v;
      _reloadServices();
    }
  }

  Future<void> _reloadServices() async {
    try {
      // Load registered module services (admin_ui discovery) from Sys.
      // This returns all registered vertical + platform services with their
      // admin_ui page definitions, filtered by feature enablement.
      // For env-scoped routes, only env_id is passed - org_id is resolved
      // server-side from env_id (env_id is globally unique).
      // For org-scoped routes, only org_id is passed.
      final envParam = widget.envId.isNotEmpty ? '?env_id=${widget.envId}' : '';
      final orgParam = widget.envId.isEmpty && widget.orgId.isNotEmpty ? '?org_id=${widget.orgId}' : '';
      final modulesRes = await AuthProvider.instance.services!.sys.get(
          '/v1/verticals/services$envParam$orgParam');
      if (mounted) {
        final modulesList =
            modulesRes is List ? modulesRes : modulesRes['data'];
        if (modulesList is List) {
          _verticalServices = VerticalService.fromJsonList(modulesList);
        }
        setState(() {});
      }
    } catch (_) {}
  }

  void _loadRailState() {
    try {
      final val = web.window.localStorage.getItem('dash.rail.collapsed');
      if (val != null && val == 'true') {
        setState(() => _railCollapsed = true);
      }
    } catch (_) {}
  }

  void _toggleRail() {
    setState(() => _railCollapsed = !_railCollapsed);
    try {
      web.window.localStorage
          .setItem('dash.rail.collapsed', _railCollapsed.toString());
    } catch (_) {}
  }

  Future<void> _loadNames() async {
    final auth = AuthProvider.instance;
    // For env-scoped routes, orgId may be empty - we resolve org_id
    // from the env response (env_id is globally unique).
    // For org-scoped routes, orgId is from the URL.

    // Fetch env display name + slug from Sys (only when env-scoped)
    String resolvedOrgId = widget.orgId;
    if (widget.envId.isNotEmpty) {
      try {
        final envRes = await auth.services!.sys
            .get('/v1/env/${widget.envId}');
        if (mounted) {
          final envSlug = envRes['slug'] as String? ?? '';
          // If orgId was empty, resolve it from the env response.
          if (resolvedOrgId.isEmpty) {
            resolvedOrgId = envRes['org_id'] as String? ?? '';
          }
          // Fetch org display name + slug using the resolved orgId.
          String orgSlug = '';
          if (resolvedOrgId.isNotEmpty) {
            try {
              final orgRes = await auth.services!.sys.get('/v1/org/$resolvedOrgId');
              orgSlug = orgRes['slug'] as String? ?? '';
              if (mounted) {
                setState(() {
                  _orgName = orgRes['display_name'] as String? ?? resolvedOrgId;
                  _orgUrl = auth.orgDomain(slug: orgSlug);
                });
              }
            } catch (_) {
              if (mounted) setState(() => _orgName = resolvedOrgId);
            }
          }
          final orgRoot = auth.orgDomain(slug: orgSlug);
          final envDomain = envSlug.isEmpty
              ? ''
              : auth.envDomain(orgDomain: orgRoot, envSlug: envSlug);
          setState(() {
            _envName = envRes['display_name'] as String? ?? widget.envId;
            _envUrl = envDomain;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _envName = widget.envId);
      }
    } else if (widget.orgId.isNotEmpty) {
      // Org-scoped route - fetch org display name + slug from Sys.
      try {
        final orgRes = await auth.services!.sys.get('/v1/org/${widget.orgId}');
        if (mounted) {
          final orgSlug = orgRes['slug'] as String? ?? '';
          setState(() {
            _orgName = orgRes['display_name'] as String? ?? widget.orgId;
            _orgUrl = auth.orgDomain(slug: orgSlug);
          });
        }
      } catch (_) {
        if (mounted) setState(() => _orgName = widget.orgId);
      }
    }
    // Load module services for dynamic sidebar - works at both org and env
    // scope. At org scope, env_id is omitted so the sys handler returns
    // features with org-level enablement (platform services default on).
    _reloadServices();
    // Get user name from BFF session (via browser fetch, same-origin cookie)
    try {
      final response = await web.window
          .fetch(
            '${auth.bffBaseUrl}/auth/session'.toJS,
            web.RequestInit(method: 'GET', credentials: 'include'),
          )
          .toDart;
      if (response.status == 200) {
        final raw = (await response.text().toDart).toDart;
        final res = jsonDecode(raw) as Map<String, dynamic>;
        final user = res['user'] as Map<String, dynamic>?;
        if (user != null && mounted) {
          // BFF returns userId; try to get display name from Auth via proxy
          final userId = user['id'] as String? ?? '';
          if (userId.isNotEmpty) {
            try {
              final userRes =
                  await auth.services!.auth.get('/v1/admin/users/$userId');
              if (mounted) {
                final fn = userRes['first_name'] as String? ?? '';
                final ln = userRes['last_name'] as String? ?? '';
                final email = userRes['email'] as String? ?? '';
                final name = '$fn $ln'.trim();
                setState(() => _userName = name.isNotEmpty ? name : email);
              }
            } catch (_) {
              if (mounted) setState(() => _userName = userId);
            }
          } else {
            if (mounted) setState(() => _userName = 'User');
          }
        }
      } else {
        if (mounted) setState(() => _userName = 'User');
      }
    } catch (_) {
      if (mounted) setState(() => _userName = 'User');
    }
  }

  bool get _isEnvScoped => widget.envId.isNotEmpty;
  bool get _isOrgScoped => widget.orgId.isNotEmpty && widget.envId.isEmpty;

  /// Nav items shown at the platform / org-list level (no org selected).
  /// Platform admins also get a global Log entry (sys realm).
  List<NavItem> get _orgListNavItems {
    return [
      NavItem(label: 'System', icon: Icons.dashboard_outlined, route: '/org'),
      // All service nav items are built dynamically from the module registry.
      ..._buildDynamicServiceNav('', ''),
    ];
  }

  List<NavItem> get _platformNavItems {
    return [
      NavItem(label: 'System', icon: Icons.dashboard_outlined, route: '/org'),
      // All service nav items are built dynamically from the module registry.
      ..._buildDynamicServiceNav('', ''),
    ];
  }

  List<NavItem> get _orgNavItems {
    final orgLabel = 'Organization${_orgName.isNotEmpty ? ' ($_orgName)' : ''}';
    return [
      NavItem(label: 'System', icon: Icons.dashboard_outlined, route: '/org'),
      NavItem(label: orgLabel, icon: Icons.business, route: '/home?org=${widget.orgId}'),
      NavItem(label: 'Sentin8ors', icon: Icons.people_outlined, route: '/sentin8ors?org=${widget.orgId}'),
      NavItem(label: 'Settings', icon: Icons.settings_outlined, route: '/settings?org=${widget.orgId}'),
      NavItem(label: 'Branding', icon: Icons.palette_outlined, route: '/branding?org=${widget.orgId}'),
      // ── Dynamic module services (RFW - discovered at runtime) ──────────
      // Services are env-scoped - no dynamic service nav at org level.
    ];
  }

  /// Build dynamic nav items from the module services registry.
  /// Routes use query params: /{service}/{page}?env={envId} (env-scoped).
  /// All services are env-scoped - there are no org-scoped service routes.
  List<NavItem> _buildDynamicServiceNav(String orgId, String envId) {
    if (envId.isEmpty) return [];
    final scopeParams = '?env=$envId';
    return _verticalServices
        .where((m) => m.enabled)
        .map((m) {
      final firstPage = m.pages.isNotEmpty ? m.pages.first.route : 'overview';
      final serviceRoute = '/${m.service}/$firstPage$scopeParams';
      // Derive module-prefixed label (e.g. "Bank8:FDX" from "bank8:fdx").
      // Colon identity (architecture-principles.md §6.0) with legacy
      // hyphen fallback.
      final modPrefix = m.service.split(':').first.split('-').first;
      final navLabel = modPrefix.isEmpty || modPrefix == m.service
          ? m.label
          : '${modPrefix[0].toUpperCase()}${modPrefix.substring(1)}:${m.label}';
      if (m.pages.length <= 1) {
        return NavItem(
          label: navLabel,
          icon: iconForName(m.icon),
          route: serviceRoute,
        );
      }
      return NavItem(
        label: navLabel,
        icon: iconForName(m.icon),
        route: serviceRoute,
        children: m.pages
            .map((p) => NavItem(
                  label: p.label,
                  icon: iconForName(p.icon),
                  route: '/${m.service}/${p.route}$scopeParams',
                ))
            .toList(),
      );
    }).toList();
  }

  List<NavItem> get _envNavItems {
    final orgLabel = 'Organization${_orgName.isNotEmpty ? ' ($_orgName)' : ''}';
    final envLabel = 'Environment${_envName.isNotEmpty ? ' ($_envName)' : ''}';
    return [
      NavItem(label: 'System', icon: Icons.dashboard_outlined, route: '/org'),
      NavItem(label: orgLabel, icon: Icons.business_outlined, route: '/home?org=${widget.orgId}'),
      NavItem(label: envLabel, icon: Icons.layers_outlined, route: '/home?env=${widget.envId}'),
      NavItem(label: 'Settings', icon: Icons.settings_outlined, route: '/settings?env=${widget.envId}'),
      NavItem(label: 'Branding', icon: Icons.palette_outlined, route: '/branding?env=${widget.envId}'),
      NavItem(label: 'Audit', icon: Icons.history_outlined, route: '/audit?env=${widget.envId}'),
      // ── Dynamic module services (RFW - discovered at runtime) ──────────
      ..._buildDynamicServiceNav(widget.orgId, widget.envId),
      if (widget.extraNav != null) ...widget.extraNav!,
    ];
  }

  /// Whether the current route is an RFW service page (e.g. /auth/users)
  /// vs a native org/env page (e.g. /home, /settings, /branding).
  bool _isRfwServicePage(String route) {
    final uri = Uri.parse(route);
    final segments = uri.pathSegments;
    if (segments.isEmpty) return false;
    // RFW service pages have 2+ segments (e.g. auth/overview, app/store).
    // Native org/env pages have 1 segment (e.g. home, settings, branding).
    if (segments.length >= 2) return true;
    const nativePages = {'home', 'settings', 'branding', 'audit', 'sentin8ors', 'env', 'org', 'sign-in', 'sign-out', 'bootstrap'};
    return !nativePages.contains(segments[0]);
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '';
    final navItems = widget.platformScoped
        ? _platformNavItems
        : _isEnvScoped
            ? _envNavItems
            : _isOrgScoped
                ? _orgNavItems
                : _orgListNavItems;
    final railWidth = _railCollapsed ? 72.0 : 260.0;

    return Scaffold(
      body: Row(
        children: [
          // Left rail
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: railWidth,
            decoration: const BoxDecoration(
              color: Sentin8Colors.carbonBlack,
              border:
                  Border(right: BorderSide(color: Sentin8Colors.glassBorder)),
            ),
            child: Column(
              children: [
                // Logo - click to toggle rail
                GestureDetector(
                  onTap: _toggleRail,
                  child: Container(
                    height: 64,
                    padding: EdgeInsets.symmetric(
                      horizontal: _railCollapsed ? 16.0 : Sentin8Spacing.md,
                    ),
                    alignment: _railCollapsed
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: _railCollapsed
                        ? SvgPicture.asset(
                            'assets/logos/sentin8-logo.svg',
                            height: 32,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SvgPicture.asset(
                                'assets/logos/sentin8-logo.svg',
                                height: 28,
                              ),
                              const SizedBox(width: Sentin8Spacing.sm),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Sentin8',
                                  style: GoogleFonts.quicksand(
                                    fontSize: 28,
                                    color: Sentin8Colors.royalGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const Divider(height: 1, color: Sentin8Colors.glassBorder),
                // Nav items
                Expanded(
                  child: _NavTree(
                    items: navItems,
                    currentRoute: currentRoute,
                    collapsed: _railCollapsed,
                  ),
                ),
                const Divider(height: 1, color: Sentin8Colors.glassBorder),
                // User menu
                _UserMenu(
                  userName: _userName,
                  collapsed: _railCollapsed,
                ),
              ],
            ),
          ),
          // Main content - header bar + page content.
          Expanded(
            child: Column(
              children: [
                // Org:Env:Service header bar - clickable breadcrumbs with icons.
                if (!widget.platformScoped && _orgName.isNotEmpty)
                  _HeaderBar(
                    orgId: widget.orgId,
                    envId: widget.envId,
                    orgName: _orgName,
                    envName: _envName,
                    envUrl: _envUrl,
                    orgUrl: _orgUrl,
                    serviceName: widget.title,
                    currentRoute: currentRoute,
                    verticalServices: _verticalServices,
                  ),
                // Scope tabs - only on native org/env pages, not RFW service
                // pages (which have their own service-level tab bar).
                if (!widget.platformScoped && _orgName.isNotEmpty && !_isRfwServicePage(currentRoute))
                  _ScopeTabs(
                    orgId: widget.orgId,
                    envId: widget.envId,
                    isEnvScoped: _isEnvScoped,
                    currentRoute: currentRoute,
                    orgName: _orgName,
                    envName: _envName,
                    verticalServices: _verticalServices,
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height,
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recursive nav tree. When collapsed, shows only icons with tooltips.
class _NavTree extends StatefulWidget {
  final List<NavItem> items;
  final String currentRoute;
  final bool collapsed;
  const _NavTree(
      {required this.items,
      required this.currentRoute,
      required this.collapsed});

  @override
  State<_NavTree> createState() => _NavTreeState();
}

class _NavTreeState extends State<_NavTree> {
  final Set<String> _expandedLabels = {};

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Sentin8Spacing.sm),
      children: widget.items.map((item) => _buildItem(item, 0)).toList(),
    );
  }

  Widget _buildItem(NavItem item, int depth) {
    final hasChildren = item.children != null && item.children!.isNotEmpty;
    // Exact match - only the deepest visible item is highlighted.
    final isActive = item.isActiveRoute(widget.currentRoute);
    final shouldExpand = hasChildren &&
        (item.matchesDeep(widget.currentRoute) ||
            _expandedLabels.contains(item.label));

    if (!hasChildren) {
      return _NavLeaf(
          item: item,
          isActive: isActive,
          depth: depth,
          collapsed: widget.collapsed);
    }

    if (widget.collapsed) {
      // In collapsed mode, parent items act as leaf items (no expansion).
      // Highlight when the parent itself matches or any child matches,
      // so the user can see which section the active route belongs to.
      final childActive = item.children != null &&
          item.children!.any((c) => c.isActiveRoute(widget.currentRoute));
      final collapsedActive = isActive || childActive;
      return Tooltip(
        message: item.label,
        child: _NavLeaf(
            item: item, isActive: collapsedActive, depth: 0, collapsed: true),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavParent(
          item: item,
          isActive: isActive,
          depth: depth,
          isExpanded: shouldExpand,
          onToggle: () {
            setState(() {
              if (_expandedLabels.contains(item.label)) {
                _expandedLabels.remove(item.label);
              } else {
                _expandedLabels.add(item.label);
              }
            });
          },
        ),
        if (shouldExpand)
          ...item.children!.map((child) => _buildItem(child, depth + 1)),
      ],
    );
  }
}

class _NavLeaf extends StatelessWidget {
  final NavItem item;
  final bool isActive;
  final int depth;
  final bool collapsed;
  const _NavLeaf(
      {required this.item,
      required this.isActive,
      required this.depth,
      required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(item.icon,
        size: 20,
        color: isActive ? Sentin8Colors.royalGold : Sentin8Colors.textMuted);

    if (collapsed) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, item.route),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Sentin8Spacing.sm),
            alignment: Alignment.center,
            decoration: isActive
                ? const BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            color: Sentin8Colors.royalGold, width: 3)),
                  )
                : null,
            child: icon,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, item.route),
        child: Container(
          padding: EdgeInsets.only(
            left: Sentin8Spacing.md + depth * 16.0,
            right: Sentin8Spacing.md,
            top: Sentin8Spacing.sm,
            bottom: Sentin8Spacing.sm,
          ),
          decoration: isActive
              ? const BoxDecoration(
                  border: Border(
                      left:
                          BorderSide(color: Sentin8Colors.royalGold, width: 3)),
                )
              : null,
          child: Row(
            children: [
              Icon(item.icon,
                  size: 18,
                  color: isActive
                      ? Sentin8Colors.royalGold
                      : Sentin8Colors.textMuted),
              const SizedBox(width: Sentin8Spacing.sm),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive
                        ? Sentin8Colors.royalGold
                        : Sentin8Colors.textSecondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavParent extends StatelessWidget {
  final NavItem item;
  final bool isActive;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggle;
  const _NavParent({
    required this.item,
    required this.isActive,
    required this.depth,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '';
    // Highlight the parent when it exactly matches OR when a direct
    // child matches (so the active leaf + its immediate parent are both
    // highlighted, but not more distant ancestors).
    final childActive = item.children != null &&
        item.children!.any((c) => c.isActiveRoute(currentRoute));
    final highlight = item.isActiveRoute(currentRoute) || childActive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        child: Container(
          padding: EdgeInsets.only(
            left: Sentin8Spacing.md + depth * 16.0,
            right: Sentin8Spacing.md,
            top: Sentin8Spacing.sm,
            bottom: Sentin8Spacing.sm,
          ),
          decoration: highlight
              ? const BoxDecoration(
                  border: Border(
                      left:
                          BorderSide(color: Sentin8Colors.royalGold, width: 3)),
                )
              : null,
          child: Row(
            children: [
              Icon(item.icon,
                  size: 18,
                  color: highlight
                      ? Sentin8Colors.royalGold
                      : Sentin8Colors.textMuted),
              const SizedBox(width: Sentin8Spacing.sm),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: highlight
                        ? Sentin8Colors.royalGold
                        : Sentin8Colors.textSecondary,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Icon(
                isExpanded ? Icons.expand_less : Icons.chevron_right,
                size: 18,
                color: Sentin8Colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar with clickable breadcrumb.
/// User menu at the bottom of the left rail. Shows avatar + user name.
/// Clicking opens a popup with Settings and Sign Out.
class _UserMenu extends StatelessWidget {
  final String userName;
  final bool collapsed;
  const _UserMenu({required this.userName, required this.collapsed});

  String get _initials {
    if (userName.isEmpty || userName == 'User') return '?';
    final parts = userName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return userName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return GestureDetector(
        onTap: () => _showPopup(context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Sentin8Spacing.sm),
          alignment: Alignment.center,
          child: CircleAvatar(
            backgroundColor: Sentin8Colors.royalGold,
            radius: 16,
            child: Text(_initials,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Sentin8Colors.obsidianBlack)),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showPopup(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Sentin8Spacing.md, vertical: Sentin8Spacing.sm),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Sentin8Colors.royalGold,
              radius: 16,
              child: Text(_initials,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Sentin8Colors.obsidianBlack)),
            ),
            const SizedBox(width: Sentin8Spacing.sm),
            Expanded(
              child: Text(
                userName,
                style: const TextStyle(
                    fontSize: 13, color: Sentin8Colors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPopup(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy - size.height * 2,
        offset.dx + size.width,
        offset.dy,
      ),
      color: Sentin8Colors.carbonBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Sentin8Colors.glassBorder),
      ),
      items: [
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined,
                  size: 18, color: Sentin8Colors.textSecondary),
              SizedBox(width: 12),
              Text('Settings',
                  style: TextStyle(
                      fontSize: 14, color: Sentin8Colors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'sign-out',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: Sentin8Colors.errorCrimson),
              SizedBox(width: 12),
              Text('Sign Out',
                  style: TextStyle(
                      fontSize: 14, color: Sentin8Colors.errorCrimson)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'sign-out') {
        Navigator.pushNamed(context, '/sign-out');
      } else if (value == 'settings') {
        // TODO: navigate to user settings page
      }
    });
  }
}

/// Scope-level tab bar for org-scoped and env-scoped pages.
/// Shows Overview, Settings, Branding (org) or Overview, Settings, Branding,
/// Audit (env) as tabs. Tapping navigates to the corresponding route.
class _ScopeTabs extends StatelessWidget {
  final String orgId;
  final String envId;
  final bool isEnvScoped;
  final String currentRoute;
  final String orgName;
  final String envName;
  final List<VerticalService> verticalServices;

  const _ScopeTabs({
    required this.orgId,
    required this.envId,
    required this.isEnvScoped,
    required this.currentRoute,
    required this.orgName,
    required this.envName,
    required this.verticalServices,
  });

  @override
  Widget build(BuildContext context) {
    final firstLabel = isEnvScoped
        ? (envName.isNotEmpty ? envName : 'Environment')
        : (orgName.isNotEmpty ? orgName : 'Organization');
    final firstIcon = isEnvScoped ? Icons.layers_outlined : Icons.business_outlined;

    // No org-scoped service tabs - auth and storage are env-scoped only.
    // For env-scoped routes, only ?env= is used (org_id resolved server-side).
    final scopeParams = isEnvScoped
        ? '?env=$envId'
        : '?org=$orgId';
    final serviceTabs = isEnvScoped
        ? verticalServices
            .where((m) => m.enabled)
            .where((m) => m.pages.any((p) => !p.route.contains('/')))
            .map((m) {
          final firstPage = m.pages.firstWhere((p) => !p.route.contains('/')).route;
          return _ScopeTab(
            label: m.label,
            icon: iconForName(m.icon),
            route: '/${m.service}/$firstPage$scopeParams',
          );
        }).toList()
        : <_ScopeTab>[];

    final tabs = isEnvScoped
        ? [
            _ScopeTab(label: firstLabel, icon: firstIcon, route: '/home?env=$envId'),
            _ScopeTab(label: 'Settings', icon: Icons.settings_outlined, route: '/settings?env=$envId'),
            _ScopeTab(label: 'Branding', icon: Icons.palette_outlined, route: '/branding?env=$envId'),
            _ScopeTab(label: 'Audit', icon: Icons.history_outlined, route: '/audit?env=$envId'),
            ...serviceTabs,
          ]
        : [
            _ScopeTab(label: firstLabel, icon: firstIcon, route: '/home?org=$orgId'),
            _ScopeTab(label: 'Sentin8ors', icon: Icons.people_outlined, route: '/sentin8ors?org=$orgId'),
            _ScopeTab(label: 'Settings', icon: Icons.settings_outlined, route: '/settings?org=$orgId'),
            _ScopeTab(label: 'Branding', icon: Icons.palette_outlined, route: '/branding?org=$orgId'),
            ...serviceTabs,
          ];

    // Determine active tab from current route.
    final route = ModalRoute.of(context)?.settings.name ?? '';
    final activeIndex = tabs.indexWhere((t) => route.startsWith(t.route));

    return DefaultTabController(
      initialIndex: activeIndex >= 0 ? activeIndex : 0,
      length: tabs.length,
      child: SizedBox(
        width: double.infinity,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          onTap: (i) {
            if (i != activeIndex) {
              Navigator.pushNamed(context, tabs[i].route);
            }
          },
          tabs: tabs.map((t) => Tab(icon: Icon(t.icon, size: 16), text: t.label)).toList(),
        ),
      ),
    );
  }
}

class _ScopeTab {
  final String label;
  final IconData icon;
  final String route;
  const _ScopeTab({required this.label, required this.icon, required this.route});
}

/// Header bar showing org:env:service breadcrumbs with icons and URL.
/// Each part is clickable. The URL shown is the most specific available
/// (service > env > org).
class _HeaderBar extends StatelessWidget {
  final String orgId;
  final String envId;
  final String orgName;
  final String envName;
  final String envUrl;
  final String orgUrl;
  final String serviceName;
  final String currentRoute;
  final List<VerticalService> verticalServices;

  const _HeaderBar({
    required this.orgId,
    required this.envId,
    required this.orgName,
    required this.envName,
    required this.envUrl,
    required this.orgUrl,
    required this.serviceName,
    required this.currentRoute,
    required this.verticalServices,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if we're on an RFW service page.
    final uri = Uri.parse(currentRoute);
    final segments = uri.pathSegments;
    final isServicePage = segments.length >= 2;

    // Find the service module for label + icon.
    final mod = verticalServices
        .where((m) => m.service == serviceName)
        .firstOrNull;
    final serviceLabel = mod?.label ?? serviceName;
    final serviceIcon = mod?.icon ?? 'extension';

    // Compute the service URL: {service}.{envUrl} or {service}.{orgUrl}
    // For now, use the env URL as the base.
    String displayUrl = '';
    if (isServicePage && envUrl.isNotEmpty) {
      displayUrl = '$serviceName.$envUrl';
    } else if (envUrl.isNotEmpty) {
      displayUrl = envUrl;
    }

    const goldStyle = TextStyle(
      color: Sentin8Colors.royalGold,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: Color(0x80D4AF37),
    );
    const mutedStyle = TextStyle(
      color: Sentin8Colors.textMuted,
      fontSize: 13,
    );
    const urlStyle = TextStyle(
      color: Sentin8Colors.textMuted,
      fontSize: 12,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sentin8Spacing.lg, vertical: 8),
      decoration: const BoxDecoration(
        color: Sentin8Colors.carbonBlack,
        border: Border(bottom: BorderSide(color: Sentin8Colors.glassBorder)),
      ),
      child: Row(
        children: [
          // Org
          Icon(Icons.business_outlined, size: 14, color: Sentin8Colors.royalGold),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => Navigator.pushNamed(context, '/home?org=$orgId'),
            child: Text(orgName, style: goldStyle),
          ),
          // Env
          if (envName.isNotEmpty) ...[
            Text(':', style: mutedStyle),
            const SizedBox(width: 2),
            Icon(Icons.layers_outlined, size: 14, color: Sentin8Colors.royalGold),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => Navigator.pushNamed(context, '/home?env=$envId'),
              child: Text(envName, style: goldStyle),
            ),
          ],
          // Service
          if (isServicePage) ...[
            Text(':', style: mutedStyle),
            const SizedBox(width: 2),
            Icon(iconForName(serviceIcon), size: 14, color: Sentin8Colors.royalGold),
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                final scopeParams = envId.isNotEmpty
                    ? '?env=$envId'
                    : '?org=$orgId';
                Navigator.pushNamed(context, '/$serviceName/overview$scopeParams');
              },
              child: Text(serviceLabel, style: goldStyle),
            ),
          ],
          // URL
          if (displayUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('($displayUrl)', style: urlStyle),
          ],
        ],
      ),
    );
  }
}
