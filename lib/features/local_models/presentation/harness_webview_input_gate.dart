import 'dart:io';

import 'package:flutter/services.dart';

/// Process-wide gate for the native WKWebView pointer router.
///
/// Flutter dialogs are composited above the AppKit platform view, but they are
/// not AppKit subviews. The native mouse monitor can therefore mistake wheel
/// and click events over a Flutter modal for WebView input. Every app-level
/// overlay must acquire this ref-counted gate and release it when dismissed.
abstract final class HarnessWebViewInputGate {
  static const MethodChannel _channel = MethodChannel('vibekits/harness_input');
  static int _depth = 0;
  static bool _workspaceActive = true;
  static bool? _lastAppliedEnabled;
  static Future<void> Function(bool enabled)? testSetter;

  static int get depth => _depth;

  static bool get workspaceActive => _workspaceActive;

  /// Native WKWebView instances can remain in the AppKit view hierarchy while
  /// their Flutter workspace is offstage in an IndexedStack. Keep the native
  /// mouse router disabled unless Harness is the selected top-level page;
  /// otherwise an invisible WebView can consume clicks meant for App Center,
  /// About, or another Flutter workspace.
  static Future<void> setWorkspaceActive(bool active) async {
    if (_workspaceActive == active && _lastAppliedEnabled != null) return;
    _workspaceActive = active;
    await _applyEffectiveState();
  }

  static Future<void> acquire() async {
    _depth += 1;
    if (_depth == 1) await _applyEffectiveState();
  }

  static Future<void> release() async {
    if (_depth == 0) return;
    _depth -= 1;
    if (_depth == 0) await _applyEffectiveState();
  }

  static Future<T?> runWithOverlay<T>(Future<T?> Function() present) async {
    await acquire();
    try {
      return await present();
    } finally {
      await release();
    }
  }

  static Future<void> _setEnabled(bool enabled) async {
    final override = testSetter;
    if (override != null) {
      await override(enabled);
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('setWebViewInputEnabled', enabled);
    } on MissingPluginException {
      // Non-desktop tests and old hosts have no native pointer router.
    } on PlatformException {
      // A pointer-routing diagnostic failure must never prevent a dialog.
    }
  }

  static Future<void> _applyEffectiveState() async {
    final bool enabled = _workspaceActive && _depth == 0;
    if (_lastAppliedEnabled == enabled) return;
    _lastAppliedEnabled = enabled;
    await _setEnabled(enabled);
  }

  static void resetForTesting() {
    _depth = 0;
    _workspaceActive = true;
    _lastAppliedEnabled = null;
    testSetter = null;
  }
}
