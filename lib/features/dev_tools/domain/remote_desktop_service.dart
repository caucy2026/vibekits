import 'dart:io';

enum RemoteDesktopPlatform { windows, macos, unsupported }

class RemoteDesktopTarget {
  const RemoteDesktopTarget({required this.host, required this.port});

  final String host;
  final int port;

  void validate() {
    final String value = host.trim();
    if (value.isEmpty ||
        value.length > 253 ||
        value.startsWith('-') ||
        value.codeUnits.any((int unit) => unit <= 0x20 || unit == 0x7f) ||
        !RegExp(r'^[A-Za-z0-9._:%-]+$').hasMatch(value) ||
        value.contains('/') ||
        value.contains('\\')) {
      throw const FormatException('远程桌面主机格式无效');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('远程桌面端口必须在 1 到 65535 之间');
    }
  }

  String get authority {
    final String value = host.trim();
    return value.contains(':') ? '[$value]:$port' : '$value:$port';
  }
}

class RemoteDesktopLaunchRequest {
  const RemoteDesktopLaunchRequest({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

typedef DetachedProcessLauncher = Future<void> Function(
  String executable,
  List<String> arguments,
);

abstract final class RemoteDesktopService {
  static RemoteDesktopPlatform get currentPlatform => Platform.isWindows
      ? RemoteDesktopPlatform.windows
      : Platform.isMacOS
      ? RemoteDesktopPlatform.macos
      : RemoteDesktopPlatform.unsupported;

  static int defaultPort([RemoteDesktopPlatform? platform]) =>
      (platform ?? currentPlatform) == RemoteDesktopPlatform.macos
      ? 5900
      : 3389;

  static RemoteDesktopLaunchRequest buildRequest(
    RemoteDesktopTarget target, {
    RemoteDesktopPlatform? platform,
  }) {
    target.validate();
    return switch (platform ?? currentPlatform) {
      RemoteDesktopPlatform.windows => RemoteDesktopLaunchRequest(
        executable: 'mstsc.exe',
        arguments: <String>['/v:${target.authority}'],
      ),
      RemoteDesktopPlatform.macos => RemoteDesktopLaunchRequest(
        executable: '/usr/bin/open',
        arguments: <String>['vnc://${target.authority}'],
      ),
      RemoteDesktopPlatform.unsupported => throw UnsupportedError(
        '当前系统不支持系统远程桌面',
      ),
    };
  }

  static Future<void> launch(
    RemoteDesktopTarget target, {
    RemoteDesktopPlatform? platform,
    DetachedProcessLauncher? launcher,
  }) async {
    final RemoteDesktopPlatform resolvedPlatform = platform ?? currentPlatform;
    final RemoteDesktopLaunchRequest request = buildRequest(
      target,
      platform: resolvedPlatform,
    );
    try {
      await (launcher ?? _launchDetached)(
        request.executable,
        request.arguments,
      );
    } on ProcessException {
      throw StateError(
        resolvedPlatform == RemoteDesktopPlatform.windows
            ? '请在 Windows 系统可选功能中启用“远程桌面连接”'
            : 'macOS 系统屏幕共享客户端不可用',
      );
    }
  }

  static Future<void> _launchDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }
}
