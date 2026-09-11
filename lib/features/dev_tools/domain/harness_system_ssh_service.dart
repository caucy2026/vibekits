import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

final class HarnessSystemSshSnapshot {
  const HarnessSystemSshSnapshot({
    required this.supported,
    required this.enabled,
    this.endpoint = '',
    this.username = '',
    this.changed = false,
    this.message = '',
  });

  final bool supported;
  final bool enabled;
  final String endpoint;
  final String username;
  final bool changed;
  final String message;
}

typedef HarnessSystemSshSetter =
    Future<HarnessSystemSshSnapshot> Function(bool enabled);
typedef HarnessSystemSshInspector = Future<HarnessSystemSshSnapshot> Function();

/// Explicit macOS Remote Login bridge used by the simulator-target switch.
///
/// The native side accepts only one boolean and invokes macOS' own privileged
/// authorization UI. VibeKits never receives, stores, or forwards the local
/// administrator password.
abstract final class HarnessSystemSshService {
  static const MethodChannel _channel = MethodChannel(
    'vibekits/simulator_host',
  );

  static HarnessSystemSshSetter? testSetter;

  static Future<HarnessSystemSshSnapshot> inspect() async {
    if (!Platform.isMacOS) {
      return const HarnessSystemSshSnapshot(
        supported: false,
        enabled: false,
        message: '当前平台暂不支持系统 SSH 仿真入口',
      );
    }
    final bool listening = await _isLoopbackSshListening();
    final String username = Platform.environment['USER']?.trim() ?? '';
    final String address = await _preferredLanAddress();
    return HarnessSystemSshSnapshot(
      supported: true,
      enabled: listening,
      endpoint: listening && address.isNotEmpty ? '$address:22' : '',
      username: username,
      message: listening ? 'macOS 系统远程登录已打开' : 'macOS 系统远程登录已关闭',
    );
  }

  static Future<HarnessSystemSshSnapshot> setEnabled(bool enabled) async {
    final override = testSetter;
    if (override != null) return override(enabled);
    final before = await inspect();
    if (!before.supported) throw UnsupportedError(before.message);
    if (before.enabled == enabled) return before;

    final Map<Object?, Object?>? response = await _channel
        .invokeMapMethod<Object?, Object?>('setRemoteLoginEnabled', enabled);
    if (response?['ok'] != true) {
      throw StateError(
        response?['message']?.toString() ?? 'macOS 系统 SSH 状态更新失败',
      );
    }
    for (int attempt = 0; attempt < 20; attempt++) {
      final current = await inspect();
      if (current.enabled == enabled) {
        return HarnessSystemSshSnapshot(
          supported: current.supported,
          enabled: current.enabled,
          endpoint: current.endpoint,
          username: current.username,
          changed: true,
          message: current.message,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(enabled ? '系统已授权，但 SSH 端口 22 尚未就绪' : 'SSH 服务尚未停止');
  }

  static Future<bool> _isLoopbackSshListening() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        22,
        timeout: const Duration(milliseconds: 350),
      );
      await socket.close();
      return true;
    } on Object {
      return false;
    }
  }

  static Future<String> _preferredLanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final addresses = interfaces
          .expand((interface) => interface.addresses)
          .map((address) => address.address)
          .where(_isPrivateIpv4)
          .toList(growable: false);
      return addresses.isEmpty ? '' : addresses.first;
    } on Object {
      return '';
    }
  }

  static bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  static void resetForTesting() => testSetter = null;
}
