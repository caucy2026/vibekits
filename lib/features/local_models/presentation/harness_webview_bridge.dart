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
  final StreamController<String> _navigationDiagnostics =
      StreamController<String>.broadcast();

  win.WebviewController? _windows;
  mac.WebViewController? _macos;
  bool _initialized = false;

  Stream<dynamic> get messages => _messages.stream;
  Stream<void> get pageFinished => _pageFinished.stream;
  Stream<String> get navigationDiagnostics => _navigationDiagnostics.stream;
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
      await controller.setOnConsoleMessage((mac.JavaScriptConsoleMessage message) {
        if (message.level != mac.JavaScriptLogLevel.error &&
            message.level != mac.JavaScriptLogLevel.warning) {
          return;
        }
        _navigationDiagnostics.add(
          'console ${message.level.name} ${message.message}',
        );
      });
      await controller.addJavaScriptChannel(
        'VibekitsHost',
        onMessageReceived: (mac.JavaScriptMessage message) {
          _messages.add(message.message);
        },
      );
      await controller.setNavigationDelegate(
        mac.NavigationDelegate(
          onPageStarted: (String url) =>
              _navigationDiagnostics.add('started ${_safeUrl(url)}'),
          onPageFinished: (String url) {
            _navigationDiagnostics.add('finished ${_safeUrl(url)}');
            _pageFinished.add(null);
          },
          onHttpError: (mac.HttpResponseError error) {
            _navigationDiagnostics.add(
              'http ${error.response?.statusCode ?? 0} '
              '${_safeUrl(error.request?.uri.toString() ?? '')}',
            );
          },
          onWebResourceError: (mac.WebResourceError error) {
            if (error.isForMainFrame == false) return;
            _navigationDiagnostics.add(
              'resource ${error.errorCode} ${_safeUrl(error.url ?? '')} '
              '${error.description}',
            );
          },
        ),
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

  /// Removes only accumulated DSH browser-auth cookies when they are large
  /// enough to make the loopback server reject every request with HTTP 431.
  /// Project, conversation, plugin, cache and local-storage data are untouched.
  Future<bool> pruneOversizedHarnessAuthentication() async {
    final win.WebviewController? windows = _windows;
    if (windows != null) {
      // This WebView2 controller is dedicated to Harness. Stable-port reuse
      // prevents future growth, while one cleanup repairs older installations.
      await windows.clearCookies();
      return true;
    }
    if (_macos != null) {
      final mac.WebViewCookieManager manager = mac.WebViewCookieManager();
      final List<mac.WebViewCookie> cookies = await manager.getCookies(
        domain: Uri.parse('http://127.0.0.1/'),
      );
      final List<mac.WebViewCookie> harnessCookies = cookies
          .where(
            (mac.WebViewCookie cookie) => cookie.name.startsWith('dsh-auth-'),
          )
          .toList(growable: false);
      final int headerBytes = harnessCookies.fold<int>(
        0,
        (int total, mac.WebViewCookie cookie) =>
            total + cookie.name.length + cookie.value.length + 3,
      );
      if (harnessCookies.length < 24 && headerBytes < 6 * 1024) return false;
      await manager.clearCookies();
      return true;
    }
    throw StateError('Harness WebView 尚未初始化');
  }

  static String _safeUrl(String value) {
    final Uri? url = Uri.tryParse(value);
    if (url == null || !url.hasScheme) return value;
    return url.replace(query: '', fragment: '').toString();
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
    _navigationDiagnostics.close();
  }
}
