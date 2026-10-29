// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:Dash
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Dash - Test bridge for e2e automation.
//
// E2e tests interact with the app ONLY through the UI - clicking
// buttons, typing into fields, and calling these test bridge functions
// which trigger the same Flutter widget code as clicking the submit
// button. No direct API/fetch calls are made from the test.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

// Global handler for creating App store listings.
// Set by AppStorePage's initState.
// Args: (appName, appSlug, description, backendUrl, scopes?, roles?, defaultSignupRole?)
//   - scopes: optional comma- or space-separated OAuth scopes
//   - roles: optional newline-separated role defs (`name:scope1,scope2`)
//   - defaultSignupRole: optional role name to mark as default signup
void Function(
  String,
  String,
  String,
  String, [
  String?,
  String?,
  String?,
])?
    _createListingHandler;

// Last created listing ID - set by AppStorePage after _createListing()
// completes. Read by e2e tests via window.sentin8TestLastListingId.
String? _lastListingId;

// Last route name the Navigator generated - set by main.dart's
// _generateRoute. Read by e2e tests via window.sentin8TestGetLastRoute:
// the authoritative view of which page the app is actually showing
// (the browser URL can lag the Navigator on programmatic pushes).
String? _lastRoute;

// Called by the Flutter app in main() to expose the bridge on window.
void registerTestBridge() {
  final w = web.window as JSObject;

  // window.sentin8TestCreateListing = function(appName, appSlug, description,
  //     backendUrl, scopes?, roles?, defaultSignupRole?) { ... }
  w.setProperty(
    'sentin8TestCreateListing'.toJS,
    ((String appName, String appSlug, String description, String backendUrl,
        [String? scopes, String? roles, String? defaultSignupRole]) {
      if (_createListingHandler != null) {
        _createListingHandler!(appName, appSlug, description, backendUrl,
            scopes, roles, defaultSignupRole);
        return true;
      }
      return false;
    }).toJS,
  );

  // window.sentin8TestGetLastListingId = function() { return _lastListingId; }
  w.setProperty(
    'sentin8TestGetLastListingId'.toJS,
    (() {
      return _lastListingId ?? '';
    }).toJS,
  );

  // window.sentin8TestGetLastRoute = function() { return _lastRoute; }
  w.setProperty(
    'sentin8TestGetLastRoute'.toJS,
    (() {
      return _lastRoute ?? '';
    }).toJS,
  );

  // window.sentin8TestSignOut = function() { AuthProvider.signOut(); }
  // This triggers the same sign-out flow as clicking "Sign Out" in
  // the user menu (BFF /auth/sign-out + Auth /v1/sign-out + redirect
  // to /sign-in). Used by e2e tests that can't reliably click the
  // GestureDetector-wrapped user menu in semantics.
  w.setProperty(
    'sentin8TestSignOut'.toJS,
    (() {
      signOutViaBridge();
      return true;
    }).toJS,
  );
}

// Bridge handler for sentin8TestSignOut. Set by main() to call
// AuthProvider.instance.signOut(). The handler is null by default
// so the test bridge is a no-op until main() wires it up.
void Function()? _signOutBridgeHandler;

/// Set the last route name (called by main.dart's _generateRoute).
void setLastRouteBridge(String name) {
  _lastRoute = name;
}

/// Set the sign-out bridge handler. Called by main() after AuthProvider
/// is available. e2e tests call window.sentin8TestSignOut() to sign out
/// the same way as clicking the user menu → "Sign Out" item.
void setSignOutBridgeHandler(void Function()? handler) {
  _signOutBridgeHandler = handler;
}

void signOutViaBridge() {
  if (_signOutBridgeHandler != null) {
    _signOutBridgeHandler!();
  }
}

/// Set the handler for sentin8TestCreateListing. Called by AppStorePage.
void setCreateListingHandler(
  void Function(
    String,
    String,
    String,
    String, [
    String?,
    String?,
    String?,
  ])? handler,
) {
  _createListingHandler = handler;
}

/// Set the last created listing ID. Called by AppStorePage after creation.
void setLastListingId(String? id) {
  _lastListingId = id;
}