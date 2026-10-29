// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Material icon lookup - code point based, no mapping needed.
//
// Flutter's IconData is just an int code point into the MaterialIcons font.
// In vertical-registry.json, use the icon's code point:
//   "icon": "0xe232"   ← hex (preferred)
//   "icon": 5794        ← decimal
//
// Browse code points at https://api.flutter.dev/flutter/material/Icons-class.html

import 'package:flutter/material.dart';

/// Lookup a Material icon from a code point string.
/// Accepts hex ("0xe232") or decimal ("5794").
/// Falls back to [Icons.extension_outlined] if invalid.
IconData iconForName(String? name) {
  if (name == null || name.isEmpty) return Icons.extension_outlined;
  if (name.startsWith('0x')) {
    final cp = int.tryParse(name.substring(2), radix: 16);
    if (cp != null) return IconData(cp, fontFamily: 'MaterialIcons');
  }
  final cp = int.tryParse(name);
  if (cp != null && cp > 0x100) {
    return IconData(cp, fontFamily: 'MaterialIcons');
  }
  return Icons.extension_outlined;
}