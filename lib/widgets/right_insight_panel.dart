// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// RightInsightPanel - Dash right insight rail (Story 13.1.4).
//
// Shows AI suggestions, operational alerts, and a recent audit-event feed.
// Rendered as the end drawer of the main Scaffold in the authenticated shell.

import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// A single AI suggestion card.
class InsightSuggestion {
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  const InsightSuggestion({
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onAction,
  });
}

/// A single operational alert.
class InsightAlert {
  final String title;
  final String detail;
  final Sentin8BadgeTone tone;

  const InsightAlert({
    required this.title,
    required this.detail,
    this.tone = Sentin8BadgeTone.warning,
  });
}

/// A single audit event entry.
class InsightAuditEvent {
  final String actor;
  final String action;
  final String at;
  final Sentin8BadgeTone tone;

  const InsightAuditEvent({
    required this.actor,
    required this.action,
    required this.at,
    this.tone = Sentin8BadgeTone.neutral,
  });
}

/// The right insight panel widget.
class RightInsightPanel extends StatelessWidget {
  final List<InsightSuggestion> suggestions;
  final List<InsightAlert> alerts;
  final List<InsightAuditEvent> auditEvents;

  const RightInsightPanel({
    super.key,
    this.suggestions = const [],
    this.alerts = const [],
    this.auditEvents = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: Sentin8DesignTokens.carbonBlack,
      child: ListView(
        padding: const EdgeInsets.all(Sentin8DesignTokens.space4),
        children: [
          _section('AI suggestions', Icons.auto_awesome_outlined,
              suggestions.map(_suggestionCard).toList()),
          const SizedBox(height: Sentin8DesignTokens.space4),
          _section('Alerts', Icons.warning_amber_outlined,
              alerts.map(_alertCard).toList()),
          const SizedBox(height: Sentin8DesignTokens.space4),
          _section('Recent activity', Icons.history,
              auditEvents.map(_auditRow).toList()),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: Sentin8DesignTokens.softGold, size: 18),
          const SizedBox(width: Sentin8DesignTokens.space2),
          Text(title, style: Sentin8Typography.h2),
        ]),
        const SizedBox(height: Sentin8DesignTokens.space2),
        ...children,
      ],
    );
  }

  Widget _suggestionCard(InsightSuggestion s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sentin8DesignTokens.space2),
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: Sentin8Typography.body),
            const SizedBox(height: Sentin8DesignTokens.space1),
            Text(s.description, style: Sentin8Typography.caption),
            const SizedBox(height: Sentin8DesignTokens.space2),
            Sentin8OutlineButton(label: s.actionLabel, onPressed: s.onAction),
          ],
        ),
      ),
    );
  }

  Widget _alertCard(InsightAlert a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sentin8DesignTokens.space2),
      child: GlassPanel(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: Sentin8Typography.body),
                  Text(a.detail, style: Sentin8Typography.caption),
                ],
              ),
            ),
            Sentin8Badge(label: a.tone.name, tone: a.tone),
          ],
        ),
      ),
    );
  }

  Widget _auditRow(InsightAuditEvent e) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Sentin8Badge(label: e.tone.name, tone: e.tone),
      title: Text('${e.actor} · ${e.action}', style: Sentin8Typography.body),
      subtitle: Text(e.at, style: Sentin8Typography.caption),
    );
  }
}