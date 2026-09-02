import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mac;
import 'package:webview_windows/webview_windows.dart' as win;

/// Small platform bridge for the official DSH Web workspace.
///
/// The Web application remains the only owner of plugin, workspace, session,
/// model and permission state. This class only adapts the native WebView API;
/// it must not reproduce any official Harness UI or persistence in Flutter.
class HarnessWebViewBridge {
  final StreamController<dynamic> _messages =
      StreamController<dynamic>.broadcast();
  final StreamController<void> _pageFinished =
      StreamController<void>.broadcast();

  win.WebviewController? _windows;
  mac.WebViewController? _macos;
  bool _initialized = false;

  Stream<dynamic> get messages => _messages.stream;
  Stream<void> get pageFinished => _pageFinished.stream;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.isWindows) {
      final win.WebviewController controller = win.WebviewController();
      await controller.initialize();
      controller.webMessage.listen(_messages.add);
      controller.loadingState.listen((win.LoadingState state) {
        if (state == win.LoadingState.navigationCompleted) {
          _pageFinished.add(null);
        }
      });
      _windows = controller;
      _initialized = true;
      return;
    }
    if (Platform.isMacOS) {
      final mac.WebViewController controller = mac.WebViewController(
        onPermissionRequest: (mac.WebViewPermissionRequest request) {
          // DSH runs on loopback and does not need camera/microphone/location.
          // Clipboard integration is provided by the Flutter host shortcuts.
          request.deny();
        },
      );
      await controller.setJavaScriptMode(mac.JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'VibekitsHost',
        onMessageReceived: (mac.JavaScriptMessage message) {
          _messages.add(message.message);
        },
      );
      await controller.setNavigationDelegate(
        mac.NavigationDelegate(onPageFinished: (_) => _pageFinished.add(null)),
      );
      _macos = controller;
      _initialized = true;
      return;
    }
    throw UnsupportedError('官方 Harness Web 仅支持 Windows 与 macOS');
  }

  Future<void> loadUrl(Uri url) async {
    final win.WebviewController? windows = _windows;
    if (windows != null) {
      await windows.loadUrl(url.toString());
      return;
    }
    final mac.WebViewController? macos = _macos;
    if (macos != null) {
      await macos.loadRequest(url);
      return;
    }
    throw StateError('Harness WebView 尚未初始化');
  }

  Future<dynamic> executeScript(String script) async {
    final win.WebviewController? windows = _windows;
    if (windows != null) return windows.executeScript(script);
    final mac.WebViewController? macos = _macos;
    if (macos != null) return macos.runJavaScriptReturningResult(script);
    throw StateError('Harness WebView 尚未初始化');
  }

  Future<void> executeScriptVoid(String script) async {
    final win.WebviewController? windows = _windows;
    if (windows != null) {
      await windows.executeScript(script);
      return;
    }
    final mac.WebViewController? macos = _macos;
    if (macos != null) {
      await macos.runJavaScript(script);
      return;
    }
    throw StateError('Harness WebView 尚未初始化');
  }

  Widget build({win.PermissionRequestedDelegate? permissionRequested}) {
    final win.WebviewController? windows = _windows;
    if (windows != null) {
      return win.Webview(windows, permissionRequested: permissionRequested);
    }
    final mac.WebViewController? macos = _macos;
    if (macos != null) {
      // This must stay unwrapped by Flutter pointer listeners in the caller.
      // WKWebView is responsible for native macOS mouse and wheel delivery.
      return mac.WebViewWidget(controller: macos);
    }
    return const SizedBox.shrink();
  }

  void dispose() {
    _windows?.dispose();
    _messages.close();
    _pageFinished.close();
  }
}
