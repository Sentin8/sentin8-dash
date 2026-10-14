// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// ScopeSelector — autocomplete + add-or-create selector for OAuth scopes.
//
// Renders a text input with autocomplete suggestions. Typing filters
// the suggestions; pressing Enter / Tab / clicking an option adds it
// as a chip. The user can also type a brand-new scope (one not in the
// suggestion list) and add it — the widget accepts any DNS-label style
// string (`service:resource:action`).
//
// Selected scopes are shown as removable chips below the input, in
// the order they were added. Duplicates are rejected.
//
// Used in:
//   - app registration (oauth_defaults.scopes)
//   - role editor (auth_roles.permissions) — see [RoleSelector].
//
// The widget is intentionally presentational: it owns a local
// `List<String>` of selected scopes and exposes a `ValueChanged<List<String>>`
// callback so the parent can persist / serialize them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// A reasonable default set of Sentin8 platform scopes. Apps can pick
/// from this list via the autocomplete, or type their own
/// (e.g. `myapp:read`, `myapp:write`).
///
/// The list is intentionally non-exhaustive — it covers the most
/// common platform resources so the user has somewhere to start,
/// but the widget never restricts the user to this list. New scopes
/// entered manually are added as-is.
const _kDefaultScopeSuggestions = <String>[
  // Auth (identity / access)
  'sentin8:auth:actor:issue',
  'sentin8:auth:admin:read',
  'sentin8:auth:admin:write',
  // Storage
  'sentin8:storage:buckets:read',
  'sentin8:storage:buckets:write',
  'sentin8:storage:objects:read',
  'sentin8:storage:objects:write',
  // DB
  'sentin8:db:tables:read',
  'sentin8:db:tables:write',
  'sentin8:db:schemas:read',
  'sentin8:db:schemas:write',
  // App
  'sentin8:app:listings:read',
  'sentin8:app:listings:write',
  'sentin8:app:installs:read',
  'sentin8:app:installs:write',
];

/// Validates that [s] is a non-empty DNS-label style scope string.
/// We require at least one `:` separator (so `service:resource` or
/// `service:resource:action` are accepted) and disallow whitespace +
/// common punctuation that would break OAuth header parsing.
final _scopePattern = RegExp(r'^[a-z0-9]([a-z0-9._-]*[a-z0-9])?:[a-z0-9]([a-z0-9._-]*[a-z0-9])?(:[a-z0-9]([a-z0-9._-]*[a-z0-9])?)?$');

bool _isValidScope(String s) {
  if (s.isEmpty) return false;
  if (s.length > 128) return false;
  return _scopePattern.hasMatch(s);
}

/// ScopeSelector — autocomplete + add-or-create selector for OAuth scopes.
///
/// Owns its own `List<String>` of selected scopes (initialized from
/// [initialScopes]) and reports changes via [onChanged]. The parent
/// can also pass an explicit [suggestions] list (e.g. loaded from the
/// server) — otherwise the built-in [_kDefaultScopeSuggestions] is used.
///
/// Visual model:
///   ┌────────────────────────────────────┐
///   │ [input + autocomplete dropdown]  [Add]│
///   └────────────────────────────────────┘
///   [chip ×]  [chip ×]  [chip ×]
class ScopeSelector extends StatefulWidget {
  /// Initial selected scopes. Defaults to empty.
  final List<String> initialScopes;

  /// Optional static suggestions for the autocomplete. When null and
  /// [fetchSuggestions] is also null, the built-in
  /// [_kDefaultScopeSuggestions] is used.
  final List<String>? suggestions;

  /// Optional async fetcher for the suggestion list. Called once in
  /// `initState`; the result replaces [suggestions] and the built-in
  /// defaults. Use this to source the platform's scope catalog from
  /// sys (`GET /v1/scopes/catalog`) instead of duplicating the list
  /// on the client. If the future rejects, the widget logs the error
  /// and falls back to [suggestions] / built-in defaults.
  final Future<List<String>> Function()? fetchSuggestions;

  /// Label shown above the input (optional).
  final String? label;

  /// Helper text shown below the input (optional).
  final String? helperText;

  /// Placeholder for the empty input.
  final String hintText;

  /// Called whenever the selected-scopes list changes. The list is
  /// a fresh, mutable copy so the parent can store / serialize it
  /// without worrying about widget-internal mutations.
  final ValueChanged<List<String>>? onChanged;

  /// Fixed width for the whole selector (use in narrow dialogs).
  /// When null, the selector expands to fill the available width.
  final double? width;

  const ScopeSelector({
    super.key,
    this.initialScopes = const [],
    this.suggestions,
    this.fetchSuggestions,
    this.label,
    this.helperText,
    this.hintText = 'Type a scope (e.g. auth:admin:read)',
    this.onChanged,
    this.width,
  });

  @override
  State<ScopeSelector> createState() => _ScopeSelectorState();
}

class _ScopeSelectorState extends State<ScopeSelector> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  late List<String> _scopes;
  String? _error;
  // Resolved suggestion list — starts as null, populated by the
  // async fetcher (if provided) in [initState]. When null, the
  // build falls back to [widget.suggestions] or the built-in
  // [_kDefaultScopeSuggestions].
  List<String>? _fetchedSuggestions;

  @override
  void initState() {
    super.initState();
    _scopes = List<String>.from(widget.initialScopes);
    // Kick off the async fetch (if any).  We don't await it here —
    // [build] shows the built-in defaults until the fetch resolves
    // and calls [setState].
    final fetcher = widget.fetchSuggestions;
    if (fetcher != null) {
      fetcher().then((scopes) {
        if (!mounted) return;
        setState(() => _fetchedSuggestions = scopes);
      }).catchError((Object e, StackTrace st) {
        // Log and stay on the fallback list — the widget is fully
        // usable with the built-in suggestions.
        // ignore: avoid_print
        print('ScopeSelector: fetchSuggestions failed: $e');
      });
    }
  }

  @override
  void didUpdateWidget(covariant ScopeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent replaces the initial-scopes list (e.g. after an
    // async load), re-sync the local list. We compare by length +
    // contents so we don't churn on every parent rebuild.
    if (!_listEquals(widget.initialScopes, _scopes) &&
        !_listEquals(widget.initialScopes, oldWidget.initialScopes)) {
      _scopes = List<String>.from(widget.initialScopes);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> get _allSuggestions {
    // Resolution order:
    //   1. async-fetched list from [widget.fetchSuggestions] (the
    //      platform catalog served by sys) — only set once the
    //      future resolves in [initState];
    //   2. static [widget.suggestions] passed in by the parent;
    //   3. built-in [_kDefaultScopeSuggestions] fallback.
    //
    // Always include currently-selected scopes (even custom ones) so
    // the user can re-select / edit them via the autocomplete.
    final base = _fetchedSuggestions ?? widget.suggestions ?? _kDefaultScopeSuggestions;
    final set = <String>{..._scopes, ...base};
    return set.toList();
  }

  void _emit() {
    widget.onChanged?.call(List<String>.from(_scopes));
  }

  /// Attempt to add [raw] as a scope (or a comma-separated list of
  /// scopes).  Returns true if at least one valid scope was added.
  /// Invalid tokens are reported in [_error] so the user can fix them.
  bool _add(String raw) {
    // Allow the user to paste a comma- or space-separated list of
    // scopes; we split on both delimiters so e.g. pasting
    // "a:b:c, d:e:f" yields two scopes.  Empty tokens are skipped.
    final tokens = raw
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      setState(() => _error = 'Scope cannot be empty');
      return false;
    }
    final added = <String>[];
    String? firstInvalid;
    for (final t in tokens) {
      if (!_isValidScope(t)) {
        firstInvalid ??= t;
        continue;
      }
      if (_scopes.contains(t)) continue; // skip duplicates silently
      _scopes.add(t);
      added.add(t);
    }
    if (added.isEmpty) {
      setState(() {
        if (firstInvalid != null) {
          _error = 'Use a DNS label: service:resource[:action]';
        } else {
          _error = 'All scopes already added';
        }
      });
      return false;
    }
    setState(() {
      _error = null;
      // Clear the input only if every token was accepted. If some
      // were invalid, leave the input as-is so the user can edit it.
      if (added.length == tokens.length) {
        _input.clear();
      } else {
        _input.text = tokens
            .where((t) => !added.contains(t))
            .join(' ');
      }
    });
    _emit();
    return true;
  }

  void _remove(String s) {
    setState(() {
      _scopes.remove(s);
      _error = null;
    });
    _emit();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: Sentin8Text.label),
          const SizedBox(height: Sentin8Spacing.xs),
        ],
        // Input row: autocomplete + Add button.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RawAutocomplete<String>(
                textEditingController: _input,
                focusNode: _focus,
                optionsBuilder: (TextEditingValue value) {
                  final q = value.text.trim().toLowerCase();
                  final all = _allSuggestions;
                  if (q.isEmpty) {
                    // Show the first handful of suggestions so the
                    // dropdown is informative even on empty input.
                    return all.take(8);
                  }
                  return all.where((s) =>
                      s.toLowerCase().contains(q) &&
                      !_scopes.contains(s));
                },
                onSelected: (s) {
                  if (_add(s)) {
                    _focus.requestFocus();
                  }
                },
                fieldViewBuilder: (
                  BuildContext context,
                  TextEditingController textEditingController,
                  FocusNode focusNode,
                  VoidCallback onFieldSubmitted,
                ) {
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      helperText: widget.helperText,
                      errorText: _error,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    // On Enter / submit: add the typed value (even if
                    // not in the suggestions) and keep focus so the
                    // user can add more.
                    onSubmitted: (_) {
                      if (_add(textEditingController.text)) {
                        onFieldSubmitted();
                      }
                    },
                    // Allow comma- and space-separated input so
                    // the user can paste a list of scopes and press
                    // Enter to add them all at once.  Empty tokens
                    // are dropped by [_add].
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-z0-9._:\-,\s]'),
                      ),
                    ],
                  );
                },
                optionsViewBuilder: (
                  BuildContext context,
                  void Function(String) onSelected,
                  Iterable<String> options,
                ) {
                  final opts = options.toList();
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(Sentin8Radii.small),
                      color: Sentin8Colors.carbonBlack,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 240,
                          maxWidth: 480,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: opts.length,
                          itemBuilder: (context, i) {
                            final s = opts[i];
                            return InkWell(
                              onTap: () => onSelected(s),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Sentin8Spacing.md,
                                  vertical: Sentin8Spacing.sm,
                                ),
                                child: Text(
                                  s,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Sentin8Colors.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: Sentin8Spacing.sm),
            // "Add" button — explicit affordance for adding a typed
            // (possibly brand-new) scope. The autocomplete covers
            // the common case, but this is the escape hatch.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  if (_add(_input.text)) {
                    _focus.requestFocus();
                  }
                },
                icon: const Icon(Icons.add, size: 16),
                label: Text('Add'),
              ),
            ),
          ],
        ),
        // Selected-scope chips.
        if (_scopes.isNotEmpty) ...[
          const SizedBox(height: Sentin8Spacing.sm),
          Wrap(
            spacing: Sentin8Spacing.xs,
            runSpacing: Sentin8Spacing.xs,
            children: [
              for (final s in _scopes)
                InputChip(
                  label: Text(
                    s,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  onDeleted: () => _remove(s),
                  deleteIconColor: Sentin8Colors.errorCrimson,
                  backgroundColor: Sentin8Colors.matteGraphite,
                  side: const BorderSide(color: Sentin8Colors.glassBorder),
                ),
            ],
          ),
        ],
      ],
    );
    if (widget.width != null) {
      return SizedBox(width: widget.width, child: body);
    }
    return body;
  }
}
