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
  static bool _surfaceActive = true;
  static bool? _lastAppliedInputEnabled;
  static bool? _lastAppliedVisible;
  static Future<void> Function(bool enabled)? testSetter;

  static int get depth => _depth;

  static bool get workspaceActive => _workspaceActive;

  static bool get surfaceActive => _surfaceActive;

  /// Native WKWebView instances can remain in the AppKit view hierarchy while
  /// their Flutter workspace is offstage in an IndexedStack. Keep the native
  /// mouse router disabled unless Harness is the selected top-level page;
  /// otherwise an invisible WebView can consume clicks meant for App Center,
  /// About, or another Flutter workspace.
  static Future<void> setWorkspaceActive(bool active) async {
    if (_workspaceActive == active &&
        _lastAppliedInputEnabled != null &&
        _lastAppliedVisible != null) {
      return;
    }
    _workspaceActive = active;
    await _applyEffectiveState();
  }

  /// Tracks the inner Harness/OCR switch. macOS AppKit platform views can
  /// remain painted above an offstage child of IndexedStack, so disabling the
  /// mouse router alone is insufficient: the native WKWebView must be hidden
  /// while OCR is selected and restored when Harness becomes active again.
  static Future<void> setSurfaceActive(bool active) async {
    if (_surfaceActive == active &&
        _lastAppliedInputEnabled != null &&
        _lastAppliedVisible != null) {
      return;
    }
    _surfaceActive = active;
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

  static Future<void> _setInputEnabled(bool enabled) async {
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

  static Future<void> _setVisible(bool visible) async {
    if (!Platform.isMacOS || testSetter != null) return;
    try {
      await _channel.invokeMethod<void>('setWebViewVisible', visible);
    } on MissingPluginException {
      // Non-desktop tests and old hosts have no native platform view.
    } on PlatformException {
      // Visibility recovery must not interrupt the surrounding workspace.
    }
  }

  static Future<void> _applyEffectiveState() async {
    final bool visible = _workspaceActive && _surfaceActive;
    final bool inputEnabled = visible && _depth == 0;
    if (_lastAppliedInputEnabled != inputEnabled) {
      _lastAppliedInputEnabled = inputEnabled;
      await _setInputEnabled(inputEnabled);
    }
    if (_lastAppliedVisible != visible) {
      _lastAppliedVisible = visible;
      await _setVisible(visible);
    }
  }

  static void resetForTesting() {
    _depth = 0;
    _workspaceActive = true;
    _surfaceActive = true;
    _lastAppliedInputEnabled = null;
    _lastAppliedVisible = null;
    testSetter = null;
  }
}
