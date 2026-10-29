// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Reusable "click-to-edit" widget for a subdomain or domain prefix.
//
// Shows the full value as a read-only monospace box by default. Clicking
// it switches to edit mode: a TextField for the editable prefix + a
// non-editable suffix (the org-derived part of the hostname), plus two
// icon buttons - "Cancel" reverts the current override, "Set to default"
// restores the platform default (e.g. `auth` for auth, or the
// auto-derived slug from the env name).
//
// Used in:
//   - create_organization_page.dart  (org domain override)
//   - create_environment_page.dart   (env subdomain override)
//   - env_settings_page.dart        (auth subdomain prefix)
//   - feature/auth_shared.dart      (auth domain prefix)
//
// The parent owns the TextEditingController and the value-to-display
// logic so it can implement per-flow behaviors (e.g. auto-deriving the
// value from a name, validating, saving to the server).
import 'package:flutter/material.dart';
import '../theme.dart';

/// State holder for [ClickableSubdomainField]. The parent creates one
/// of these in its State, holds the [TextEditingController], and
/// provides a [defaultValue] to fall back to. The widget manages the
/// "is the user currently editing?" state and the visual switch.
class SubdomainFieldController extends ChangeNotifier {
  final TextEditingController controller;

  String defaultValue;
  bool _editing = false;

  SubdomainFieldController({
    required this.controller,
    required this.defaultValue,
  });

  bool get isEditing => _editing;
  String get currentValue => controller.text.trim().isEmpty
      ? defaultValue
      : controller.text.trim();

  /// Start editing - switches the widget into the TextField mode.
  /// Focus management is left to the parent (e.g. by passing a
  /// `FocusNode` to the underlying [TextField] or by explicitly
  /// calling `FocusScope.of(context).requestFocus(...)` in response
  /// to a parent-supplied callback).
  void startEditing() {
    _editing = true;
    notifyListeners();
  }

  /// Cancel - reverts any in-progress edit back to [defaultValue] and
  /// switches back to read-only mode.
  void cancel() {
    controller.text = defaultValue;
    _editing = false;
    notifyListeners();
  }

  /// "Set to default" - like [cancel] but signals that the user
  /// explicitly wants the platform default rather than the auto-derived
  /// value. The parent can use this hook to persist the reset (e.g.
  /// PUT the default back to the server).
  void resetToDefault() {
    // Move the cursor to the end so subsequent edits land at a
    // sensible position, and set the new value. We use the controller's
    // built-in text setter which notifies all listeners (including
    // any ValueListenableBuilder wrapping the TextField).
    controller.value = TextEditingValue(
      text: defaultValue,
      selection: TextSelection.collapsed(offset: defaultValue.length),
    );
    // Stay in edit mode so the user can see the change; they can click
    // the close icon to leave edit mode. This matches typical UI
    // patterns for "set to default" actions.
    notifyListeners();
  }

  /// Stop editing without reverting - call this from the parent after
  /// it has saved the value to the server.
  void finishEditing() {
    _editing = false;
    notifyListeners();
  }

  /// Update the default value (e.g. when the parent re-derives it from
  /// a name change).
  void updateDefault(String newDefault) {
    defaultValue = newDefault;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

/// A clickable field that shows `{prefix}.{suffix}` (e.g. a subdomain
/// in front of a fixed env domain). Click to edit; cancel to revert to
/// the auto-derived value; "set to default" to restore the platform
/// default.
///
/// This is a [StatefulWidget] so it can hold an internal [FocusNode]
/// for the edit-mode [TextField] and request focus on it the frame
/// after the widget switches to edit mode. Focus management on
/// Done/Cancel (where focus should go next) is left to the parent  - 
/// the widget only ensures the edit field itself is focused while
/// editing, which is the minimal focus behavior the user expects
/// when they click the edit icon.
class ClickableSubdomainField extends StatefulWidget {
  /// Owns the controller + editing state. Parent creates one of these
  /// and passes it to the widget.
  final SubdomainFieldController state;

  /// The full value to display in read-only mode. e.g. `auth.staging.ibank.local`.
  final String value;

  /// The non-editable suffix shown inside the TextField in edit mode.
  /// e.g. `.staging.ibank.local`. Include the leading `.`.
  final String? suffix;

  /// Hint text for the editable TextField. e.g. `auth` or `prod`.
  final String hintText;

  /// Tooltip for the "set to default" icon button. e.g.
  /// `Restore default (auth)`.
  final String resetTooltip;

  /// Optional callback when the user types in the editable TextField.
  /// Use this to keep the parent state in sync (e.g. mark "manually
  /// edited" so the auto-derivation stops).
  final ValueChanged<String>? onChanged;

  /// Optional callback fired after the "set to default" icon is tapped
  /// (in either read-only or edit mode). The shared widget has already
  /// reset the controller to [SubdomainFieldController.defaultValue];
  /// use this to persist the reset (e.g. PUT the default back to the
  /// server). If null, the reset is local-only and the user has to
  /// click the surrounding "Save" button to persist.
  final VoidCallback? onReset;

  const ClickableSubdomainField({
    super.key,
    required this.state,
    required this.value,
    required this.suffix,
    required this.hintText,
    required this.resetTooltip,
    this.onChanged,
    this.onReset,
  });

  @override
  State<ClickableSubdomainField> createState() => _ClickableSubdomainFieldState();
}

class _ClickableSubdomainFieldState extends State<ClickableSubdomainField> {
  /// Internal FocusNode for the edit-mode TextField. We create and
  /// dispose it here so the widget owns its lifecycle. When the user
  /// clicks the edit icon (triggering `startEditing`), we schedule a
  /// post-frame callback to request focus on this node - the
  /// TextField is mounted by then and accepts focus cleanly.
  late final FocusNode _editFocusNode;

  /// Internal FocusNode for the read-only Edit button. After the
  /// user finishes editing (Done or Cancel), we move focus here so
  /// it stays on the domain field instead of jumping back to the
  /// Organization Name field (or any other previously-focused form
  /// field). This gives the user a predictable focus target after
  /// exiting edit mode.
  late final FocusNode _readOnlyFocusNode;

  @override
  void initState() {
    super.initState();
    _editFocusNode = FocusNode();
    _readOnlyFocusNode = FocusNode();
    // Listen to the controller so we can request focus the frame
    // after the widget switches to edit mode. The listener fires
    // on every notifyListeners() call (including value changes),
    // but we only act when the editing flag transitions.
    widget.state.addListener(_onStateChanged);
  }

  bool _wasEditing = false;

  void _onStateChanged() {
    final isEditing = widget.state.isEditing;
    if (isEditing && !_wasEditing) {
      // Just entered edit mode - request focus on the edit field
      // after the next frame so the TextField is mounted first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.state.isEditing) {
          _editFocusNode.requestFocus();
        }
      });
    } else if (!isEditing && _wasEditing) {
      // Just exited edit mode (Done or Cancel). Move focus to the
      // read-only Edit button so it stays on the domain field
      // instead of jumping back to the Organization Name field.
      // We schedule it for the next frame so the _ReadOnlyField
      // is mounted first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.state.isEditing) {
          _readOnlyFocusNode.requestFocus();
        }
      });
    }
    _wasEditing = isEditing;
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _editFocusNode.dispose();
    _readOnlyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        if (state.isEditing) {
          return _EditField(
            controller: state.controller,
            focusNode: _editFocusNode,
            suffix: widget.suffix,
            hintText: widget.hintText,
            resetTooltip: widget.resetTooltip,
            onChanged: widget.onChanged,
            // The green tick icon commits the edit and switches
            // back to read-only mode WITHOUT reverting the typed
            // value. Focus management on exit is left to the
            // parent - this widget only ensures the edit field
            // is focused while editing.
            onCancel: state.finishEditing,
            // Cancel - exits edit mode AND reverts the typed value
            // to the platform default. The "Restore platform default"
            // label only made sense from the read-only view; in edit
            // mode the same action is labelled "Cancel" because the
            // user's mental model is "abandon my edits and go back
            // to the read-only view". Focus management on exit is
            // left to the parent.
            onReset: () {
              state.cancel();
              widget.onReset?.call();
            },
          );
        }
        return _ReadOnlyField(
          value: widget.value,
          onEdit: state.startEditing,
          onReset: () {
            state.resetToDefault();
            widget.onReset?.call();
          },
          resetTooltip: widget.resetTooltip,
          editFocusNode: _readOnlyFocusNode,
        );
      },
    );
  }
}

/// The read-only display - a monospace box showing the full value with
/// an edit pencil icon. In read-only mode there is also a "set to
/// default" icon button so the user can quickly reset without entering
/// edit mode.
class _ReadOnlyField extends StatelessWidget {
  final String value;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final String resetTooltip;
  /// Focus node for the Edit IconButton. The parent sets focus here
  /// after exiting edit mode so focus stays on the domain field.
  final FocusNode? editFocusNode;
  const _ReadOnlyField({
    required this.value,
    required this.onEdit,
    required this.onReset,
    required this.resetTooltip,
    this.editFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // The text is purely display - NOT a tap target. The edit
          // pencil icon (right side) is the only entry point into edit
          // mode. This prevents the click-to-edit InkWell from
          // stealing focus from the surrounding form fields (e.g. the
          // Organization Name field above) when the user is just
          // scanning or reading the value. The previous design wrapped
          // the whole text in an InkWell, which caused clicks anywhere
          // on the read-only display to trigger `startEditing` AND
          // shift focus to the first form field - a confusing UX and a
          // blocker for automated tests that clicked the read-only text.
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: Sentin8Colors.glassBorder),
              borderRadius: BorderRadius.circular(Sentin8Radii.medium),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Sentin8Spacing.xs),
        // The edit icon is the only clickable affordance that
        // switches the field into edit mode. Rendered as an
        // IconButton (matching the reset IconButton next to it) so
        // the two affordances have the same hit target, padding,
        // and tooltip behaviour - keeping the visual rhythm of the
        // row consistent.
        IconButton(
          tooltip: 'Edit',
          onPressed: onEdit,
          focusNode: editFocusNode,
          icon: const Icon(Icons.edit_outlined, color: Sentin8Colors.royalGold),
        ),
        const SizedBox(width: Sentin8Spacing.xs),
        IconButton(
          tooltip: resetTooltip,
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt, color: Sentin8Colors.royalGold),
        ),
      ],
    );
  }
}

/// The edit field - TextField for the editable prefix, non-editable
/// suffix inside the field border, then two icon buttons: "set to
/// default" and "cancel" (close).
class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? suffix;
  final String hintText;
  final String resetTooltip;
  final ValueChanged<String>? onChanged;
  final VoidCallback onCancel;
  final VoidCallback onReset;
  const _EditField({
    required this.controller,
    this.focusNode,
    required this.suffix,
    required this.hintText,
    required this.resetTooltip,
    required this.onChanged,
    required this.onCancel,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap the TextField in a ValueListenableBuilder so it picks
        // up programmatic text changes from the controller (e.g. the
        // "set to default" button). Without this, Flutter's TextField
        // ignores controller.text updates when the field is focused.
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return TextField(
                // Use a STABLE key - do NOT key the TextField on the
                // controller's value. The previous ValueKey('subdomain-${value.text}')
                // approach caused the TextField to be rebuilt on every
                // keystroke (because onChanged fires per character),
                // which dropped focus and reset the cursor. The
                // controller already drives the visible value, so the
                // TextField state stays in sync without the key trick.
                // (Programmatic value changes via controller.value = ...
                // still propagate through the controller's listeners.)
                key: const ValueKey<String>('subdomain-edit'),
                controller: controller,
                // The focus node is supplied by the
                // _ClickableSubdomainFieldState, which requests focus
                // on it the frame after the widget enters edit mode.
                // We do NOT use `autofocus: true` here because it
                // races with the previously-focused element on
                // Flutter Web CanvasKit - the explicit post-frame
                // requestFocus in the State is more reliable.
                focusNode: focusNode,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                  suffixText: suffix,
                  suffixStyle: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: Sentin8Spacing.xs),
        // Cancel - exits edit mode and reverts the typed value to
        // the default. This is the same semantic as before (the
        // resetTooltip/reset IconButton), but labelled "Cancel"
        // because the user's mental model in edit mode is "I want
        // to abandon my edits and go back to the read-only view",
        // not "I want to set the value to the platform default".
        // The "Restore platform default" label only made sense
        // from the read-only view, where the same button resets a
        // non-default value back to the platform default.
        IconButton(
          tooltip: 'Cancel',
          onPressed: onReset,
          icon: const Icon(Icons.close, color: Sentin8Colors.royalGold),
        ),
        IconButton(
          tooltip: 'Done',
          onPressed: onCancel,
          icon: const Icon(Icons.check, color: Sentin8Colors.royalGold),
        ),
      ],
    );
  }
}
