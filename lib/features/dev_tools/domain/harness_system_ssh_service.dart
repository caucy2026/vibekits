import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
typedef HarnessSystemSshProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

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

  static Future<Map<String, Object?>> identity({
    HarnessSystemSshProcessRunner? runner,
    HarnessSystemSshInspector? inspector,
  }) async {
    final snapshot = await (inspector ?? inspect)();
    if (!snapshot.enabled) throw StateError('系统 SSH 端口 22 尚未就绪');
    final run = runner ?? Process.run;
    final result = await run('/usr/bin/ssh-keygen', const <String>[
      '-lf',
      '/etc/ssh/ssh_host_ed25519_key.pub',
      '-E',
      'sha256',
    ]);
    if (result.exitCode != 0) throw StateError('无法读取 SSH 主机指纹');
    final match = RegExp(
      r'\b(SHA256:[A-Za-z0-9+/=]+)\b',
    ).firstMatch('${result.stdout}');
    if (match == null) throw StateError('SSH 主机指纹格式无效');
    return <String, Object?>{
      'enabled': true,
      'username': snapshot.username,
      'hostKeyFingerprint': match.group(1),
      'remotePort': 22,
    };
  }

  static Future<Map<String, Object?>> authorizePublicKey({
    required String peerId,
    required String publicKey,
    HarnessSystemSshProcessRunner? runner,
    HarnessSystemSshInspector? inspector,
    Directory? homeDirectory,
  }) async {
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(peerId.trim())) {
      throw const FormatException('控制端设备 ID 无效');
    }
    final parts = publicKey.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first != 'ssh-ed25519') {
      throw const FormatException('只接受 Ed25519 SSH 公钥');
    }
    late final List<int> keyBytes;
    try {
      keyBytes = base64Decode(parts[1]);
    } on FormatException {
      throw const FormatException('SSH 公钥编码无效');
    }
    if (keyBytes.length < 32 || keyBytes.length > 1024) {
      throw const FormatException('SSH 公钥长度无效');
    }
    final snapshot = await (inspector ?? inspect)();
    if (!snapshot.enabled) throw StateError('系统 SSH 端口 22 尚未就绪');
    final home =
        homeDirectory?.absolute.path ??
        (Platform.environment['HOME']?.trim() ?? '');
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final sshDirectory = Directory('$home/.ssh');
    await sshDirectory.create(recursive: true);
    final authorizedKeys = File('${sshDirectory.path}/authorized_keys');
    final markerDigest = sha256.convert(keyBytes).toString().substring(0, 16);
    final marker = 'vibekits-simulator-${peerId.trim()}-$markerDigest';
    final existing = await authorizedKeys.exists()
        ? await authorizedKeys.readAsLines()
        : <String>[];
    final retained = existing
        .where(
          (line) =>
              !line.contains('vibekits-simulator-${peerId.trim()}-') &&
              !line.contains('ssh-ed25519 ${parts[1]}'),
        )
        .toList(growable: true);
    retained.add(
      'from="127.0.0.1",no-agent-forwarding,no-port-forwarding,no-X11-forwarding '
      'ssh-ed25519 ${parts[1]} $marker',
    );
    final temporary = File('${authorizedKeys.path}.vibekits-$pid.tmp');
    await temporary.writeAsString('${retained.join('\n')}\n', flush: true);
    final run = runner ?? Process.run;
    final directoryMode = await run('/bin/chmod', <String>[
      '700',
      sshDirectory.path,
    ]);
    final fileMode = await run('/bin/chmod', <String>['600', temporary.path]);
    if (directoryMode.exitCode != 0 || fileMode.exitCode != 0) {
      await temporary.delete();
      throw StateError('无法设置 SSH 授权文件权限');
    }
    await temporary.rename(authorizedKeys.path);
    return <String, Object?>{
      ...await identity(runner: run, inspector: inspector),
      'authorized': true,
      'peerId': peerId.trim(),
      'keyMarker': marker,
    };
  }

  static Future<Map<String, Object?>> publicKeyStatus({
    required String peerId,
    required String publicKey,
    Directory? homeDirectory,
  }) async {
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(peerId.trim())) {
      throw const FormatException('控制端设备 ID 无效');
    }
    final parts = publicKey.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first != 'ssh-ed25519') {
      throw const FormatException('只接受 Ed25519 SSH 公钥');
    }
    late final List<int> keyBytes;
    try {
      keyBytes = base64Decode(parts[1]);
    } on FormatException {
      throw const FormatException('SSH 公钥编码无效');
    }
    final markerDigest = sha256.convert(keyBytes).toString().substring(0, 16);
    final marker = 'vibekits-simulator-${peerId.trim()}-$markerDigest';
    final home =
        homeDirectory?.absolute.path ??
        (Platform.environment['HOME']?.trim() ?? '');
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final authorizedKeys = File('$home/.ssh/authorized_keys');
    final authorized =
        await authorizedKeys.exists() &&
        (await authorizedKeys.readAsString()).contains(marker);
    return <String, Object?>{
      'authorized': authorized,
      'peerId': peerId.trim(),
      'keyMarker': marker,
    };
  }

  static Future<Map<String, Object?>> revokePublicKeys({
    required String peerId,
    Directory? homeDirectory,
  }) async {
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(peerId.trim())) {
      throw const FormatException('控制端设备 ID 无效');
    }
    final home =
        homeDirectory?.absolute.path ??
        (Platform.environment['HOME']?.trim() ?? '');
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final authorizedKeys = File('$home/.ssh/authorized_keys');
    if (!await authorizedKeys.exists()) {
      return <String, Object?>{'revoked': true, 'removed': 0};
    }
    final existing = await authorizedKeys.readAsLines();
    final retained = existing
        .where((line) => !line.contains('vibekits-simulator-${peerId.trim()}-'))
        .toList(growable: false);
    final removed = existing.length - retained.length;
    await authorizedKeys.writeAsString(
      retained.isEmpty ? '' : '${retained.join('\n')}\n',
      flush: true,
    );
    return <String, Object?>{
      'revoked': true,
      'removed': removed,
      'peerId': peerId.trim(),
    };
  }

  static Future<Map<String, Object?>> revokeAllManagedPublicKeys({
    Directory? homeDirectory,
  }) async {
    final home =
        homeDirectory?.absolute.path ??
        (Platform.environment['HOME']?.trim() ?? '');
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final authorizedKeys = File('$home/.ssh/authorized_keys');
    if (!await authorizedKeys.exists()) {
      return <String, Object?>{'revoked': true, 'removed': 0};
    }
    final existing = await authorizedKeys.readAsLines();
    final retained = existing
        .where((line) => !line.contains('vibekits-simulator-'))
        .toList(growable: false);
    final removed = existing.length - retained.length;
    await authorizedKeys.writeAsString(
      retained.isEmpty ? '' : '${retained.join('\n')}\n',
      flush: true,
    );
    return <String, Object?>{'revoked': true, 'removed': removed};
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
