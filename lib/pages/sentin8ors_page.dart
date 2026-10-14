// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8ors page — list, invite, manage roles.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../auth_provider.dart';
import 'nav_shell.dart';

class Sentin8orsPage extends StatefulWidget {
  final String orgId;
  const Sentin8orsPage({super.key, required this.orgId});
  @override
  State<Sentin8orsPage> createState() => _Sentin8orsPageState();
}

class _Sentin8orsPageState extends State<Sentin8orsPage> {
  List<dynamic>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final auth = AuthProvider.instance;
      final res = await auth.services!.sys.get('/v1/org/${widget.orgId}/memberships');
      // The Sys API returns a bare JSON array; _decode wraps it as {'data': [...]}.
      final members = res['data'] as List<dynamic>? ?? res['memberships'] as List<dynamic>? ?? [];
      // Show the list immediately with raw userIds.
      if (mounted) setState(() => _members = members);
      // Then enrich each member with email/name from Auth in the background.
      _enrichMembers(members);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _enrichMembers(List<dynamic> members) async {
    final auth = AuthProvider.instance;
    final enriched = <Map<String, dynamic>>[];
    for (final m in members) {
      final entry = Map<String, dynamic>.from(m as Map);
      final userId = entry['user_id'] as String?;
      if (userId != null && userId.isNotEmpty) {
        try {
          final userRes = await auth.services!.auth.get('/v1/admin/users/$userId');
          entry['email'] = userRes['email'] as String? ?? userId;
          final fn = userRes['first_name'] as String? ?? '';
          final ln = userRes['last_name'] as String? ?? '';
          final name = '$fn $ln'.trim();
          if (name.isNotEmpty) entry['display_name'] = name;
        } catch (_) {
          entry['email'] = userId;
        }
      }
      enriched.add(entry);
    }
    if (mounted) setState(() => _members = enriched);
  }

  @override
  Widget build(BuildContext context) {
    return DashShell(
      orgId: widget.orgId,
      envId: '',
      title: 'Sentin8ors',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Row(
                children: [
                  Text('Sentin8ors', style: Sentin8Text.h1),
                  const Spacer(),
                  FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add), label: Text('Invite')),
                ],
              ),
              const SizedBox(height: Sentin8Spacing.xl),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Sentin8Colors.errorCrimson))
              else if (_members == null)
                const CircularProgressIndicator(color: Sentin8Colors.royalGold)
              else if (_members!.isEmpty)
                Text('No sentin8ors yet.', style: Sentin8Text.bodySecondary)
              else
                ..._members!.map((m) {
                  final member = m as Map<String, dynamic>;
                  final role = member['role'] as String? ?? 'member';
                  final email = member['email'] as String? ?? member['user_id'] as String? ?? 'Unknown';
                  final displayName = member['display_name'] as String?;
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Sentin8Colors.royalGold, child: Icon(Icons.person, color: Sentin8Colors.obsidianBlack)),
                      title: Text(displayName ?? email),
                      subtitle: displayName != null ? Text(email) : null,
                      trailing: StatusBadge(label: role, type: role == 'owner' ? StatusType.role : StatusType.active),
                    ),
                  );
                }),
          ],
        ),
      ),
    );
  }
}