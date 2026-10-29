// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// RoleSelector - autocomplete + add-or-create editor for app-declared
// security roles.
//
// Each role is a row with:
//   * Name (text input with autocomplete suggestions from the
//     server's existing roles - `auth_roles` in the target
//     org/env).
//   * Optional description (single-line text input).
//   * A nested [ScopeSelector] for the role's granted scopes.
//   * A remove (trash) icon to delete the row.
//
// Visual model:
//   ┌────────────────────────────────────────────────────────────┐
//   │ Role 1                                                  [×]│
//   │ Name:        [ebank-customer*       ▾]                       │
//   │ Description: [Customer role]                                  │
//   │ Scopes:      [input + add]                                   │
//   │              [chip ×] [chip ×]                               │
//   │                                                              │
//   │ Role 2                                                  [×]│
//   │ ...                                                         │
//   │                                                              │
//   │ [ + Add Role ]                                              │
//   └────────────────────────────────────────────────────────────┘
//
// The optional trailing `*` on a role name (e.g. `ebank-customer*`)
// marks the role as the **default signup role** - new users
// registering via this app are auto-assigned to it. We preserve the
// marker across edits so the parent's serializer can emit the
// `default_signup_role` field separately.
//
// The widget owns a `List<_RoleDraft>` and reports changes via
// [onChanged]. The parent's serializer is responsible for turning
// each `_RoleDraft` into the wire-format `ListingRole` (name +
// description + scopes, plus the global default-signup marker).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'scope_selector.dart';

/// Internal draft model. Kept private so callers can't accidentally
/// mutate it from outside the widget.
class _RoleDraft {
  String name;
  String? description;
  List<String> scopes;
  /// Names of other roles in this listing whose scopes should be
  /// merged into this role's permissions at install time. Empty
  /// by default. See `ListingRole.includes` on the app.
  List<String> includes;
  _RoleDraft({
    required this.name,
    this.description,
    List<String>? scopes,
    List<String>? includes,
  })  : scopes = scopes ?? <String>[],
        includes = includes ?? <String>[];
}

/// Public payload returned to the parent. Matches the shape of the
/// app `ListingRole` model: a flat object with `name`,
/// optional `description`, `scopes`, and `includes`. The
/// default-signup marker is reported via [defaultSignupName] so the
/// parent can emit the `default_signup_role` field separately.
class RoleDraft {
  final String name;
  final String? description;
  final List<String> scopes;
  /// Names of other roles in the same listing whose scopes
  /// should be merged into this role's permissions at install
  /// time (see `ListingRole.includes`). The server resolves
  /// cycles and missing references; the UI prevents them by
  /// only offering already-defined roles.
  final List<String> includes;
  const RoleDraft({
    required this.name,
    this.description,
    required this.scopes,
    this.includes = const [],
  });
}

class RoleSelector extends StatefulWidget {
  /// Initial roles (e.g. loaded from the existing listing).
  final List<RoleDraft> initialRoles;

  /// Name of the default signup role (if any). A trailing `*` on the
  /// role name in [initialRoles] is treated equivalently.
  final String? defaultSignupName;

  /// Suggestions for the role-name autocomplete. Typically loaded
  /// from `GET /v1/admin/roles` on the target org/env. When null,
  /// the autocomplete offers an empty list (only manual entry).
  final List<String>? nameSuggestions;

  /// Scope suggestions forwarded to the nested [ScopeSelector].
  /// When null, the built-in platform scope list is used.
  final List<String>? scopeSuggestions;

  /// Optional async fetcher forwarded to the nested [ScopeSelector]s.
  /// See [ScopeSelector.fetchSuggestions] - typically points to
  /// `Sentin8Services.fetchScopeCatalog` to source the platform
  /// scope catalog from sys.
  final Future<List<String>> Function()? fetchScopeSuggestions;

  /// Optional label for the whole selector (rendered above the rows).
  final String? label;

  /// Helper text shown below the role list.
  final String? helperText;

  /// Called whenever the list of roles changes (or any role's
  /// fields change). The first arg is the full role list; the
  /// second is the name of the default signup role (or null).
  final void Function(List<RoleDraft> roles, String? defaultSignup)?
      onChanged;

  /// Fixed width for the selector (use in narrow dialogs).
  final double? width;

  /// When false, hide the per-role `Description` field.  Useful for
  /// callers that don't support a description on the wire (e.g.
  /// auth `roles` have no description column).  Default true.
  final bool showDescription;

  /// When false, hide the per-role `Includes` (role-composition)
  /// section.  Useful when the model doesn't support includes (e.g.
  /// auth `roles` don't).  Default true.
  final bool showIncludes;

  /// When true, allow the user to mark a role as the default
  /// signup role by appending `*` to the name.  When false, the
  /// `*` marker is hidden from the name field.  Default true.
  /// Auth use cases typically don't need a "default signup"
  /// concept, so set this to false.
  final bool showDefaultSignupMarker;

  /// When true, the user is creating a single role.  The
  /// "+ Add Role" button and the per-row remove button are
  /// hidden.  The widget still renders one role row (using
  /// [initialRoles] which should have exactly one entry).
  /// Default false.  Auth create pages typically use this.
  final bool singleRoleMode;

  /// Optional list of pre-existing role names to offer in the
  /// `Includes` picker.  When null (the default) the picker only
  /// shows roles defined *above* the current row - the listing
  /// use case.  When non-null, the picker shows these names
  /// instead - useful for the auth use case where the user
  /// creates a single new role and wants to include
  /// pre-existing roles whose permissions should be merged.
  final List<String>? includeSuggestions;

  const RoleSelector({
    super.key,
    this.initialRoles = const [],
    this.defaultSignupName,
    this.nameSuggestions,
    this.scopeSuggestions,
    this.fetchScopeSuggestions,
    this.label,
    this.helperText,
    this.onChanged,
    this.width,
    this.showDescription = true,
    this.showIncludes = true,
    this.showDefaultSignupMarker = true,
    this.singleRoleMode = false,
    this.includeSuggestions,
  });

  @override
  State<RoleSelector> createState() => _RoleSelectorState();
}

class _RoleSelectorState extends State<RoleSelector> {
  late List<_RoleDraft> _roles;
  String? _defaultSignup;
  String? _error;

  /// Per-role `TextEditingController`s for the name + description
  /// fields.  We own them in state so they survive rebuilds  - 
  /// `TextField` would otherwise reset to the widget's initial
  /// `text:` on every rebuild, wiping any user edits the moment
  /// the parent calls `setState`.  Indexes match `_roles`.
  late List<TextEditingController> _nameCtrls;
  late List<TextEditingController> _descCtrls;

  static final _namePattern =
      RegExp(r'^[a-z0-9]([a-z0-9._:-]*[a-z0-9])?$');

  @override
  void initState() {
    super.initState();
    _roles = widget.initialRoles
        .map((g) => _RoleDraft(
              name: g.name,
              description: g.description,
              scopes: List<String>.from(g.scopes),
              includes: List<String>.from(g.includes),
            ))
        .toList();
    _defaultSignup = widget.defaultSignupName;
    _nameCtrls = _roles
        .map((g) => TextEditingController(text: g.name))
        .toList();
    _descCtrls = _roles
        .map((g) => TextEditingController(text: g.description ?? ''))
        .toList();
  }

  @override
  void didUpdateWidget(covariant RoleSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync our internal draft only if the parent passed new
    // initialRoles that we haven't already mirrored. We compare
    // both against the current internal state AND against the
    // previous public initialRoles to avoid clobbering local edits.
    if (!_draftsMatch(_roles, widget.initialRoles) &&
        !_draftsMatch(_roles, oldWidget.initialRoles)) {
      _roles = widget.initialRoles
          .map((g) => _RoleDraft(
                name: g.name,
                description: g.description,
                scopes: List<String>.from(g.scopes),
                includes: List<String>.from(g.includes),
              ))
          .toList();
      // Re-seed the controllers so a fresh `initialRoles` from
      // the parent (e.g. switching from create-mode to edit-mode)
      // actually shows up in the textboxes.  Only do this when we
      // actually replaced `_roles`; otherwise leave the existing
      // text intact.
      _resizeCtrls();
    }
    if (widget.defaultSignupName != oldWidget.defaultSignupName) {
      _defaultSignup = widget.defaultSignupName;
    }
  }

  /// Make the cached controller lists match `_roles.length`.
  /// Newly appended controllers start empty (matching the create
  /// flow).  Removed ones are disposed.
  void _resizeCtrls() {
    while (_nameCtrls.length > _roles.length) {
      _nameCtrls.removeLast().dispose();
    }
    while (_descCtrls.length > _roles.length) {
      _descCtrls.removeLast().dispose();
    }
    while (_nameCtrls.length < _roles.length) {
      _nameCtrls.add(TextEditingController());
    }
    while (_descCtrls.length < _roles.length) {
      _descCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    for (final c in _descCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // Compare an internal draft list against any iterable of objects
  // that expose the same `name`/`description`/`scopes`/`includes`
  // fields. We compare the relevant fields directly because
  // [RoleDraft] (public) and [_RoleDraft] (private) have the same
  // shape but Dart lists are invariant, so a typed parameter would
  // reject one of the two call sites in [didUpdateWidget].
  static bool _draftsMatch(
      List<_RoleDraft> a, List<RoleDraft> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ai = a[i];
      final bi = b[i];
      if (ai.name != bi.name) return false;
      if (ai.description != bi.description) return false;
      if (ai.scopes.length != bi.scopes.length) return false;
      for (var j = 0; j < ai.scopes.length; j++) {
        if (ai.scopes[j] != bi.scopes[j]) return false;
      }
      if (ai.includes.length != bi.includes.length) return false;
      for (var j = 0; j < ai.includes.length; j++) {
        if (ai.includes[j] != bi.includes[j]) return false;
      }
    }
    return true;
  }

  void _emit() {
    final out = _roles
        .map((g) => RoleDraft(
              name: g.name,
              description: g.description,
              scopes: List<String>.from(g.scopes),
              includes: List<String>.from(g.includes),
            ))
        .toList();
    widget.onChanged?.call(out, _defaultSignup);
  }

  void _addRole() {
    setState(() {
      _roles.add(_RoleDraft(name: ''));
      _nameCtrls.add(TextEditingController());
      _descCtrls.add(TextEditingController());
      _error = null;
    });
    _emit();
  }

  void _removeRole(int idx) {
    final removed = _roles.removeAt(idx);
    // If the removed role was the default signup, clear the marker.
    if (_defaultSignup != null && _defaultSignup == removed.name) {
      _defaultSignup = null;
    }
    // Cascade: drop the removed role's name from every other
    // role's `includes` list so the wire format never references
    // a non-existent role (which the server would reject with a
    // 400 at install time).
    for (final g in _roles) {
      if (g.includes.remove(removed.name)) {
        // No-op - just keep the list in sync.
      }
    }
    setState(() => _error = null);
    _emit();
  }

  /// Validate-and-commit the role name on focus loss / submit.
  /// Strips a trailing `*` (default-signup marker) and updates
  /// [_defaultSignup] accordingly - but only when the widget is in
  /// a mode that supports the marker (app-listing use case).  In
  /// auth use, the marker is meaningless, so we treat the typed
  /// value as a plain DNS-label name.
  void _onNameChanged(int idx, String value) {
    var name = value.trim();
    if (widget.showDefaultSignupMarker) {
      if (name.endsWith('*')) {
        name = name.substring(0, name.length - 1);
        _defaultSignup = name;
      } else if (_defaultSignup == name) {
        // User edited away the marker - clear it.
        _defaultSignup = null;
      }
    }
    setState(() {
      _roles[idx].name = name;
      _error = null;
    });
    _emit();
  }

  void _onDescriptionChanged(int idx, String value) {
    setState(() {
      _roles[idx].description = value.isEmpty ? null : value;
    });
    _emit();
  }

  void _onScopesChanged(int idx, List<String> scopes) {
    setState(() {
      _roles[idx].scopes = scopes;
    });
    _emit();
  }

  /// Validate-and-commit the `includes` list for role [idx].
  /// Self-include is rejected; references to roles that no longer
  /// exist (e.g. after a remove) are filtered out defensively.
  /// In cross-listing mode (when [widget.includeSuggestions] is
  /// set) the include target may be an existing role *outside*
  /// of this widget, so we trust the caller's `includeSuggestions`
  /// as the authoritative allowlist and skip the
  /// in-widget-only roleNames filter.
  void _onIncludesChanged(int idx, List<String> raw) {
    final Set<String> roleNames;
    if (widget.includeSuggestions != null) {
      // Cross-listing: trust the suggestion list as the
      // universe of valid include targets.  No need to
      // require the include to be a sibling in this widget.
      roleNames = widget.includeSuggestions!.toSet();
    } else {
      roleNames =
          _roles.where((g) => g.name.isNotEmpty).map((g) => g.name).toSet();
    }
    final filtered = <String>[];
    for (final inc in raw) {
      if (inc.isEmpty) continue;
      if (inc == _roles[idx].name) continue; // self-include
      if (!roleNames.contains(inc)) continue; // dangling
      if (!filtered.contains(inc)) filtered.add(inc);
    }
    setState(() {
      _roles[idx].includes = filtered;
    });
    _emit();
  }

  /// Returns an error string for the role name field, or null if OK.
  String? _validateName(String name) {
    if (name.isEmpty) return 'Name required';
    if (name.length > 64) return 'Name too long (max 64)';
    if (!_namePattern.hasMatch(name)) {
      return 'Lowercase letters, digits, dot, underscore, hyphen';
    }
    // Uniqueness within the current role list (case-sensitive).
    final dupes = _roles.where((g) => g.name == name).length;
    if (dupes > 1) return 'Duplicate name';
    return null;
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
        if (widget.helperText != null) ...[
          Text(widget.helperText!, style: Sentin8Text.caption),
          const SizedBox(height: Sentin8Spacing.sm),
        ],
        for (var i = 0; i < _roles.length; i++) ...[
          _buildRoleRow(i),
          const SizedBox(height: Sentin8Spacing.sm),
        ],
        // Hide the "+ Add Role" button in single-role mode
        // (auth create flow).  Single-role mode is for
        // creating one role at a time; the user can't add
        // more rows from the form.
        if (!widget.singleRoleMode)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addRole,
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add Role'),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            _error!,
            style: const TextStyle(color: Sentin8Colors.errorCrimson),
          ),
        ],
      ],
    );
    if (widget.width != null) {
      return SizedBox(width: widget.width, child: body);
    }
    return body;
  }

  Widget _buildRoleRow(int idx) {
    final g = _roles[idx];
    final isDefault = _defaultSignup != null && _defaultSignup == g.name;
    return Container(
      padding: const EdgeInsets.all(Sentin8Spacing.md),
      decoration: BoxDecoration(
        color: Sentin8Colors.matteGraphite,
        border: Border.all(
          color: isDefault && widget.showDefaultSignupMarker
              ? Sentin8Colors.royalGold
              : Sentin8Colors.glassBorder,
        ),
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: "Role N" + (optional) remove button.
          // The remove button is hidden in [singleRoleMode]
          // because the user is creating exactly one role and
          // can't drop the row.  The "default signup" suffix is
          // hidden when the widget is in a mode (e.g. auth)
          // that doesn't support that concept.
          Row(
            children: [
              Text(
                (isDefault && widget.showDefaultSignupMarker)
                    ? 'Role ${idx + 1}  (default signup)'
                    : 'Role ${idx + 1}',
                style: Sentin8Text.label,
              ),
              const Spacer(),
              // Hide the per-row remove button in single-role
              // mode (auth create flow).
              if (!widget.singleRoleMode)
                IconButton(
                  tooltip: 'Remove role',
                  onPressed: () => _removeRole(idx),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Sentin8Colors.errorCrimson,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Sentin8Spacing.xs),
          // Name field with autocomplete.
          _buildNameField(idx, g),
          if (widget.showDescription) ...[
            const SizedBox(height: Sentin8Spacing.sm),
            // Description field.  We use a cached controller
            // from [_descCtrls] so the text survives rebuilds
            // and so the initial value (from `g.description`)
            // shows up when editing an existing role.
            TextField(
              controller: _descCtrls[idx],
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _onDescriptionChanged(idx, v),
            ),
          ],
          const SizedBox(height: Sentin8Spacing.sm),
          // Scopes selector.
          ScopeSelector(
            initialScopes: g.scopes,
            suggestions: widget.scopeSuggestions,
            fetchSuggestions: widget.fetchScopeSuggestions,
            label: 'Scopes',
            hintText: 'Scope (e.g. auth:admin:read)',
            onChanged: (scopes) => _onScopesChanged(idx, scopes),
          ),
          if (widget.showIncludes) ...[
            const SizedBox(height: Sentin8Spacing.sm),
            // Includes - names of OTHER roles in this listing whose
            // scopes should be merged into this role's permissions at
            // install time.  The picker only offers roles defined
            // above this one in the list (excluding the current row)
            // so self-include and dangling refs are impossible.
            _buildIncludesField(idx, g),
          ],
        ],
      ),
    );
  }

  /// Build an autocomplete-select picker for the role's
  /// `includes` list.  Two modes:
  ///
  /// 1. **App-listing mode** (the default).  Only roles defined
  ///    *above* this row in the same [RoleSelector] are offered
  ///    as candidates.  This makes self-include and dangling
  ///    references impossible by construction.
  /// 2. **Auth / cross-listing mode**.  When the caller passes
  ///    [RoleSelector.includeSuggestions], the picker searches
  ///    those pre-existing role names instead.  The caller is
  ///    responsible for resolving the included roles'
  ///    permissions (typically by fetching them on save).
  ///
  /// In both modes the picker uses a `RawAutocomplete<String>` so
  /// the user can type to filter a long list.  Selected roles are
  /// shown as removable chips below the input.
  Widget _buildIncludesField(int idx, _RoleDraft g) {
    final List<String> candidates;
    final String emptyMessage;
    final String hintText;
    if (widget.includeSuggestions != null) {
      // Cross-listing / auth mode.  Exclude the current
      // role's own name (in case the user typed it before
      // picking includes) so self-include is impossible.
      final selfName = g.name;
      candidates = widget.includeSuggestions!
          .where((n) => n.isNotEmpty && n != selfName)
          .toList();
      emptyMessage = 'No existing roles available.';
      hintText = 'Type to search existing roles…';
    } else {
      // Listing mode.  Offer roles defined above this row.
      candidates = <String>[];
      for (var i = 0; i < idx; i++) {
        final n = _roles[i].name;
        if (n.isNotEmpty) candidates.add(n);
      }
      emptyMessage = 'Define another role above first to add its scopes here.';
      hintText = 'Type a role name defined above…';
    }
    final selected = List<String>.from(g.includes);
    final selfName = g.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roles', style: Sentin8Text.label),
        const SizedBox(height: Sentin8Spacing.xs),
        if (candidates.isEmpty) ...[
          Text(
            emptyMessage,
            style: Sentin8Text.bodySecondary.copyWith(fontSize: 12),
          ),
        ] else ...[
          // Autocomplete input + chip list of selected roles.
          _IncludesAutocomplete(
            candidates: candidates,
            selected: selected,
            selfName: selfName,
            hintText: hintText,
            onAdded: (name) {
              if (name.isEmpty || name == selfName) return;
              if (selected.contains(name)) return;
              final next = List<String>.from(selected)..add(name);
              _onIncludesChanged(idx, next);
            },
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: Sentin8Spacing.sm),
            // Selected roles shown as removable chips. Tapping
            // the X drops that include.  We also show a faint
            // "(unknown)" badge for any name that's not in the
            // candidate set anymore (e.g. a role was deleted
            // server-side) so the user can clean up.
            Wrap(
              spacing: Sentin8Spacing.xs,
              runSpacing: Sentin8Spacing.xs,
              children: [
                for (final name in selected)
                  InputChip(
                    label: Text(
                      candidates.contains(name) ? name : '$name (missing)',
                    ),
                    onDeleted: () {
                      final next = List<String>.from(selected)
                        ..remove(name);
                      _onIncludesChanged(idx, next);
                    },
                    deleteIconColor: Sentin8Colors.royalGold,
                    backgroundColor: candidates.contains(name)
                        ? Sentin8Colors.royalGold.withOpacity(0.18)
                        : Sentin8Colors.errorCrimson.withOpacity(0.18),
                    side: const BorderSide(color: Sentin8Colors.glassBorder),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Sentin8Spacing.xs),
          Text(
            'Selected roles\' scopes are merged into this role at install. Self-reference and cycles are not allowed.',
            style: Sentin8Text.bodySecondary.copyWith(fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildNameField(int idx, _RoleDraft g) {
    // The displayed text shows the trailing `*` for the default-signup
    // role so the marker is visible in the UI - but only when the
    // widget is in a mode that supports default-signup (app listing
    // use case).  Auth roles don't have a default-signup concept,
    // so we hide the marker there.
    //
    // We use the cached `TextEditingController` from
    // [_nameCtrls] so the text survives rebuilds.  When the
    // default-signup marker flips on/off, sync the controller
    // text to match.
    final showMarker = widget.showDefaultSignupMarker;
    final displayName =
        g.name + (showMarker && _defaultSignup == g.name ? '*' : '');
    final ctrl = _nameCtrls[idx];
    if (ctrl.text != displayName) {
      // Don't disturb the cursor if the user is actively editing
      // - only overwrite when we know the displayed value would
      // actually be different (e.g. marker flip).
      final sel = ctrl.selection;
      ctrl.value = TextEditingValue(
        text: displayName,
        selection: sel.isValid
            ? sel
            : TextSelection.collapsed(offset: displayName.length),
      );
    }
    return RawAutocomplete<String>(
      textEditingController: ctrl,
      optionsBuilder: (TextEditingValue value) {
        final q = value.text.trim().toLowerCase().replaceAll('*', '');
        final base = widget.nameSuggestions ?? const <String>[];
        if (q.isEmpty) return base.take(8);
        return base.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (s) {
        _onNameChanged(idx, s);
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
            labelText: showMarker
                ? 'Role name (append * for default signup)'
                : 'Role name',
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: _validateName(g.name),
            suffixIcon: showMarker && _defaultSignup == g.name
                ? const Icon(Icons.star, color: Sentin8Colors.royalGold, size: 18)
                : null,
          ),
          // Role names are DNS-label style: lowercase, digits, dot,
          // underscore, hyphen, colon.  Trailing `*` is only allowed
          // when default-signup marker is supported by the caller.
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(showMarker ? r'[a-z0-9._\-:*]' : r'[a-z0-9._\-:]'),
            ),
          ],
          onChanged: (v) => _onNameChanged(idx, v),
          onSubmitted: (_) => onFieldSubmitted(),
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
                maxHeight: 200,
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
    );
  }
}
/// Autocomplete-select input used by [RoleSelector] to let the
/// user pick existing roles whose scopes should be merged into
/// this role's permissions at install time.  Mirrors the visual
/// style of the platform scope picker: type to filter a list of
/// candidate role names, press Enter or click a row to add the
/// role as a selected entry.  Selected roles are shown as
/// `InputChip`s in the parent widget (with the `X` button to
/// remove), so this widget only owns the input + dropdown.
class _IncludesAutocomplete extends StatelessWidget {
  /// All candidate role names the user can pick from.  The
  /// parent is responsible for filtering out the current
  /// role's own name and any already-selected names.
  final List<String> candidates;

  /// Already-selected include names.  Used to filter suggestions
  /// (we hide them from the dropdown so the user can't pick
  /// duplicates) and to compute the empty-state placeholder.
  final List<String> selected;

  /// The name of the role this picker belongs to.  We never
  /// offer it as a suggestion (self-include).
  final String selfName;

  /// Placeholder shown in the input when empty.
  final String hintText;

  /// Called when the user picks a name from the dropdown or
  /// presses Enter on a typed value.  The parent is responsible
  /// for filtering (self / duplicates) and committing the
  /// selection to its internal state.  This widget already
  /// rejects empty / self / duplicate values, so [onAdded] only
  /// fires with valid additions.
  final void Function(String name) onAdded;

  const _IncludesAutocomplete({
    required this.candidates,
    required this.selected,
    required this.selfName,
    required this.hintText,
    required this.onAdded,
  });

  @override
  Widget build(BuildContext context) {
    // Filter the candidate list to:
    //   - exclude already-selected names
    //   - exclude the current role's own name (defense in
    //     depth - the parent also excludes this)
    //   - exclude empty strings
    final available = candidates
        .where((n) =>
            n.isNotEmpty && n != selfName && !selected.contains(n))
        .toList();
    return RawAutocomplete<String>(
      optionsBuilder: (TextEditingValue value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) {
          // On empty input, show the first 8 candidates so the
          // dropdown is informative.
          return available.take(8);
        }
        return available.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (s) {
        // User picked from the dropdown.  The callback takes
        // care of validating + committing.
        onAdded(s);
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
            hintText: hintText,
            isDense: true,
            border: const OutlineInputBorder(),
            helperText: available.isEmpty
                ? 'All available roles are already added.'
                : null,
            // Filter out whitespace so the user can paste a
            // list and we'll only accept the first token.
            prefixIcon: const Icon(Icons.search, size: 18),
          ),
          // Allow comma- and space-separated input so the user
          // can paste a list of role names and press Enter to
          // add them all at once.  Empty tokens are dropped.
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'[a-z0-9._:\-,\s]'),
            ),
          ],
          onSubmitted: (_) {
            // Accept comma/space-separated tokens. Each token is
            // resolved against the candidate list (case-sensitive
            // match) and added if it exists and isn't already
            // selected.  Invalid tokens are silently dropped so
            // the user can paste a list and the field self-heals.
            final raw = textEditingController.text;
            final tokens = raw
                .split(RegExp(r'[\s,]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            for (final t in tokens) {
              if (t == selfName) continue;
              if (!available.contains(t)) continue;
              onAdded(t);
            }
            textEditingController.clear();
            onFieldSubmitted();
          },
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        void Function(String) onSelected,
        Iterable<String> options,
      ) {
        final opts = options.toList();
        if (opts.isEmpty) {
          return const SizedBox.shrink();
        }
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
    );
  }
}
