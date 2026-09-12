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

/// Explicit system SSH bridge used by the simulator-target switch.
///
/// macOS uses the native authorization bridge. Windows invokes one fixed,
/// encoded PowerShell maintenance script through UAC. VibeKits never receives,
/// stores, or forwards the local administrator password.
abstract final class HarnessSystemSshService {
  static const MethodChannel _channel = MethodChannel(
    'vibekits/simulator_host',
  );

  static HarnessSystemSshSetter? testSetter;

  static Future<HarnessSystemSshSnapshot> inspect() async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return const HarnessSystemSshSnapshot(
        supported: false,
        enabled: false,
        message: '当前平台暂不支持系统 SSH 仿真入口',
      );
    }
    final bool listening = await _isLoopbackSshListening();
    final String username = _currentUsername();
    final String address = await _preferredLanAddress();
    final String platformName = Platform.isWindows ? 'Windows' : 'macOS';
    return HarnessSystemSshSnapshot(
      supported: true,
      enabled: listening,
      endpoint: listening && address.isNotEmpty ? '$address:22' : '',
      username: username,
      message: listening
          ? '$platformName 系统 SSH 已打开'
          : '$platformName 系统 SSH 已关闭',
    );
  }

  static Future<HarnessSystemSshSnapshot> setEnabled(bool enabled) async {
    final override = testSetter;
    if (override != null) return override(enabled);
    final before = await inspect();
    if (!before.supported) throw UnsupportedError(before.message);
    if (before.enabled == enabled) return before;

    if (Platform.isMacOS) {
      final Map<Object?, Object?>? response = await _channel
          .invokeMapMethod<Object?, Object?>('setRemoteLoginEnabled', enabled);
      if (response?['ok'] != true) {
        throw StateError(
          response?['message']?.toString() ?? 'macOS 系统 SSH 状态更新失败',
        );
      }
    } else if (Platform.isWindows) {
      await _setWindowsSshEnabled(enabled);
    } else {
      throw UnsupportedError(before.message);
    }
    final int attempts = Platform.isWindows ? 120 : 20;
    final Duration interval = Platform.isWindows
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 150);
    for (int attempt = 0; attempt < attempts; attempt++) {
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
      await Future<void>.delayed(interval);
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
    final result = await run(_sshKeygenExecutable(), <String>[
      '-lf',
      _hostPublicKeyPath(),
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
    final home = homeDirectory?.absolute.path ?? _userHome();
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
    final bool permissionsReady = await _secureAuthorizedKeysFiles(
      run: run,
      directory: sshDirectory,
      file: temporary,
      username: snapshot.username,
    );
    if (!permissionsReady) {
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
    final home = homeDirectory?.absolute.path ?? _userHome();
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
    final home = homeDirectory?.absolute.path ?? _userHome();
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
    final home = homeDirectory?.absolute.path ?? _userHome();
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

  static String _currentUsername() => Platform.isWindows
      ? (Platform.environment['USERNAME']?.trim() ?? '')
      : (Platform.environment['USER']?.trim() ?? '');

  static String _userHome() => Platform.isWindows
      ? (Platform.environment['USERPROFILE']?.trim() ?? '')
      : (Platform.environment['HOME']?.trim() ?? '');

  static String _windowsDirectory() =>
      Platform.environment['WINDIR']?.trim().isNotEmpty == true
      ? Platform.environment['WINDIR']!.trim()
      : r'C:\Windows';

  static String _sshKeygenExecutable() => Platform.isWindows
      ? '${_windowsDirectory()}\\System32\\OpenSSH\\ssh-keygen.exe'
      : '/usr/bin/ssh-keygen';

  static String _hostPublicKeyPath() => Platform.isWindows
      ? '${Platform.environment['ProgramData']?.trim().isNotEmpty == true ? Platform.environment['ProgramData']!.trim() : r'C:\ProgramData'}\\ssh\\ssh_host_ed25519_key.pub'
      : '/etc/ssh/ssh_host_ed25519_key.pub';

  static Future<void> _setWindowsSshEnabled(bool enabled) async {
    final String powerShell =
        '${_windowsDirectory()}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final String script = enabled
        ? r'''$ErrorActionPreference = 'Stop'
$capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1'
if ($capability.State -ne 'Installed') {
  Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1' | Out-Null
}
$keygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
& $keygen -A
if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd
'''
        : r'''$ErrorActionPreference = 'Stop'
$service = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($null -ne $service) {
  if ($service.Status -ne 'Stopped') { Stop-Service -Name sshd -Force }
  Set-Service -Name sshd -StartupType Manual
}
''';
    final String encoded = base64Encode(_utf16Le(script));
    final String wrapper =
        "\$process = Start-Process -FilePath '$powerShell' -Verb RunAs -Wait "
        "-PassThru -ArgumentList @('-NoProfile','-NonInteractive',"
        "'-ExecutionPolicy','Bypass','-EncodedCommand','$encoded'); "
        'exit \$process.ExitCode';
    final ProcessResult result = await Process.run(powerShell, <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      wrapper,
    ]).timeout(const Duration(minutes: 3));
    if (result.exitCode != 0) {
      throw StateError(
        enabled ? 'Windows OpenSSH 启动未获授权或执行失败' : 'Windows OpenSSH 停止失败',
      );
    }
  }

  static List<int> _utf16Le(String value) => <int>[
    for (final int unit in value.codeUnits) ...<int>[unit & 0xff, unit >> 8],
  ];

  static Future<bool> _secureAuthorizedKeysFiles({
    required HarnessSystemSshProcessRunner run,
    required Directory directory,
    required File file,
    required String username,
  }) async {
    if (!Platform.isWindows) {
      final directoryMode = await run('/bin/chmod', <String>[
        '700',
        directory.path,
      ]);
      final fileMode = await run('/bin/chmod', <String>['600', file.path]);
      return directoryMode.exitCode == 0 && fileMode.exitCode == 0;
    }
    if (username.trim().isEmpty) return false;
    final directoryMode = await run('icacls.exe', <String>[
      directory.path,
      '/inheritance:r',
      '/grant:r',
      '$username:(OI)(CI)F',
      '*S-1-5-18:(OI)(CI)F',
    ]);
    final fileMode = await run('icacls.exe', <String>[
      file.path,
      '/inheritance:r',
      '/grant:r',
      '$username:F',
      '*S-1-5-18:F',
    ]);
    return directoryMode.exitCode == 0 && fileMode.exitCode == 0;
  }

  static void resetForTesting() => testSetter = null;
}
