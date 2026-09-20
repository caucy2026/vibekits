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
    // Windows also uses the elevated enable path to repair the per-user
    // AuthorizedKeysFile rule.  Older builds may have installed sshd while
    // leaving administrator accounts on administrators_authorized_keys.
    if (before.enabled == enabled && !(Platform.isWindows && enabled)) {
      return before;
    }

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
    String? fingerprint = RegExp(
      r'\b(SHA256:[A-Za-z0-9+/=]+)\b',
    ).firstMatch('${result.stdout}')?.group(1);
    if (fingerprint == null && Platform.isWindows) {
      // A standard Windows user can run sshd but may be denied direct read
      // access to C:\ProgramData\ssh\ssh_host_ed25519_key.pub. Derive the
      // same OpenSSH SHA-256 fingerprint from the loopback-only key scan
      // instead of asking for elevation or weakening host verification.
      final ProcessResult scan = await run(_sshKeyscanExecutable(), <String>[
        '-T',
        '3',
        '-t',
        'ed25519',
        '127.0.0.1',
      ]);
      if (scan.exitCode == 0) {
        for (final String line in const LineSplitter().convert(
          '${scan.stdout}',
        )) {
          if (line.trimLeft().startsWith('#')) continue;
          final List<String> fields = line.trim().split(RegExp(r'\s+'));
          if (fields.length < 3 || fields[1] != 'ssh-ed25519') continue;
          try {
            final List<int> keyBytes = base64Decode(fields[2]);
            final String digest = base64Encode(
              sha256.convert(keyBytes).bytes,
            ).replaceAll('=', '');
            fingerprint = 'SHA256:$digest';
            break;
          } on FormatException {
            // Ignore malformed scanner rows and fail closed below.
          }
        }
      }
    }
    if (fingerprint == null) {
      throw StateError(result.exitCode == 0 ? 'SSH 主机指纹格式无效' : '无法读取 SSH 主机指纹');
    }
    return <String, Object?>{
      'enabled': true,
      'platform': Platform.operatingSystem,
      'username': snapshot.username,
      'hostKeyFingerprint': fingerprint,
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
    final authorizedKeys = await _resolveAuthorizedKeysFile(
      homeDirectory: homeDirectory,
      runner: runner,
      username: snapshot.username,
    );
    final sshDirectory = authorizedKeys.parent;
    await sshDirectory.create(recursive: true);
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
    if (Platform.isWindows) {
      // File.rename cannot replace an existing file on Windows. The temporary
      // file already has the restricted ACL, so copy its flushed bytes over
      // the destination and remove only that exact temporary file.
      await temporary.copy(authorizedKeys.path);
      await temporary.delete();
    } else {
      await temporary.rename(authorizedKeys.path);
    }
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
    final authorizedKeys = await _resolveAuthorizedKeysFile(
      homeDirectory: homeDirectory,
    );
    final authorized =
        await authorizedKeys.exists() &&
        (await authorizedKeys.readAsString()).contains(marker);
    return <String, Object?>{
      'authorized': authorized,
      'peerId': peerId.trim(),
      'keyMarker': marker,
    };
  }

  /// Returns whether this controller completed the one-time SSH pairing.
  ///
  /// The marker is written only by [authorizePublicKey] after target-side
  /// approval. It lets later sensitive simulator calls reuse that durable
  /// grant even when the native connection-status IPC has already coalesced
  /// the short-lived HTTP port-forward row.
  static Future<bool> hasAuthorizedPeer({
    required String peerId,
    Directory? homeDirectory,
  }) async {
    final String normalizedPeerId = peerId.trim();
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(normalizedPeerId)) {
      return false;
    }
    final File authorizedKeys;
    try {
      authorizedKeys = await _resolveAuthorizedKeysFile(
        homeDirectory: homeDirectory,
      );
    } on Object {
      return false;
    }
    if (!await authorizedKeys.exists()) return false;
    final String markerPrefix = 'vibekits-simulator-$normalizedPeerId-';
    return (await authorizedKeys.readAsLines()).any((String line) {
      final String trimmed = line.trim();
      return trimmed.startsWith('from="127.0.0.1",') &&
          trimmed.contains(' $markerPrefix');
    });
  }

  static Future<Map<String, Object?>> revokePublicKeys({
    required String peerId,
    Directory? homeDirectory,
  }) async {
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(peerId.trim())) {
      throw const FormatException('控制端设备 ID 无效');
    }
    final authorizedKeys = await _resolveAuthorizedKeysFile(
      homeDirectory: homeDirectory,
    );
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
    final authorizedKeys = await _resolveAuthorizedKeysFile(
      homeDirectory: homeDirectory,
    );
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

  static String _sshKeyscanExecutable() => Platform.isWindows
      ? '${_windowsDirectory()}\\System32\\OpenSSH\\ssh-keyscan.exe'
      : '/usr/bin/ssh-keyscan';

  static String _hostPublicKeyPath() => Platform.isWindows
      ? '${Platform.environment['ProgramData']?.trim().isNotEmpty == true ? Platform.environment['ProgramData']!.trim() : r'C:\ProgramData'}\\ssh\\ssh_host_ed25519_key.pub'
      : '/etc/ssh/ssh_host_ed25519_key.pub';

  static Future<File> _resolveAuthorizedKeysFile({
    Directory? homeDirectory,
    HarnessSystemSshProcessRunner? runner,
    String? username,
  }) async {
    final overrideHome = homeDirectory?.absolute.path;
    if (overrideHome != null && overrideHome.isNotEmpty) {
      return File('$overrideHome/.ssh/authorized_keys');
    }
    final home = _userHome();
    if (!Platform.isWindows) {
      if (home.isEmpty) throw StateError('无法定位当前用户目录');
      return File('$home/.ssh/authorized_keys');
    }

    final account = (username ?? _currentUsername()).trim();
    if (account.isEmpty) throw StateError('无法定位当前 Windows SSH 用户');
    final sshd = '${_windowsDirectory()}\\System32\\OpenSSH\\sshd.exe';
    final run = runner ?? Process.run;
    ProcessResult? effective;
    try {
      effective = await run(sshd, <String>[
        '-T',
        '-C',
        'user=$account,host=localhost,addr=127.0.0.1',
      ]).timeout(const Duration(seconds: 3));
    } on Object {
      // Some Windows OpenSSH builds cannot evaluate `sshd -T` from an
      // unelevated desktop process. Fall through to the readable config.
    }
    if (effective?.exitCode == 0) {
      for (final line in const LineSplitter().convert('${effective!.stdout}')) {
        final trimmed = line.trim();
        if (!trimmed.toLowerCase().startsWith('authorizedkeysfile ')) continue;
        final candidates = trimmed
            .substring('authorizedkeysfile '.length)
            .trim()
            .split(RegExp(r'\s+'));
        for (var candidate in candidates) {
          candidate = candidate
              .replaceAll('__PROGRAMDATA__', _programDataDirectory())
              .replaceAll('%h', home)
              .replaceAll('%%', '%');
          if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(candidate)) {
            return File(candidate.replaceAll('/', '\\'));
          }
          if (home.isNotEmpty) {
            return File('$home/${candidate.replaceAll('\\', '/')}');
          }
        }
      }
    }
    final configured = await _authorizedKeysFileFromWindowsConfig(
      account: account,
      home: home,
    );
    if (configured != null) return configured;
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    return File('$home/.ssh/authorized_keys');
  }

  static Future<File?> _authorizedKeysFileFromWindowsConfig({
    required String account,
    required String home,
  }) async {
    final config = File('${_programDataDirectory()}\\ssh\\sshd_config');
    if (!await config.exists()) return null;
    String? globalValue;
    String? exactUserValue;
    bool inExactUserBlock = false;
    for (final rawLine in await config.readAsLines()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(
        r'^Match\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (match != null) {
        final expression = match.group(1)!.trim();
        if (expression.toLowerCase() == 'all') {
          inExactUserBlock = false;
          continue;
        }
        final userMatch = RegExp(
          r'(?:^|\s)User\s+([^\s]+)',
          caseSensitive: false,
        ).firstMatch(expression);
        final users = userMatch
            ?.group(1)
            ?.split(',')
            .map((value) => value.trim().toLowerCase())
            .toSet();
        inExactUserBlock = users?.contains(account.toLowerCase()) ?? false;
        continue;
      }
      final directive = RegExp(
        r'^AuthorizedKeysFile\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (directive == null) continue;
      final value = directive.group(1)!.trim().split(RegExp(r'\s+')).first;
      if (inExactUserBlock) {
        exactUserValue = value;
      } else {
        globalValue ??= value;
      }
    }
    final value = exactUserValue ?? globalValue;
    if (value == null || value.isEmpty) return null;
    final expanded = value
        .replaceAll('__PROGRAMDATA__', _programDataDirectory())
        .replaceAll('%h', home)
        .replaceAll('%%', '%');
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(expanded)) {
      return File(expanded.replaceAll('/', '\\'));
    }
    if (home.isEmpty) return null;
    return File('$home/${expanded.replaceAll('\\', '/')}');
  }

  static String _programDataDirectory() =>
      Platform.environment['ProgramData']?.trim().isNotEmpty == true
      ? Platform.environment['ProgramData']!.trim()
      : r'C:\ProgramData';

  static Future<void> _setWindowsSshEnabled(bool enabled) async {
    final String powerShell =
        '${_windowsDirectory()}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final String script = enabled
        ? r'''$ErrorActionPreference = 'Stop'
$capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' |
  Select-Object -First 1
if ($null -eq $capability) {
  throw 'OpenSSH Server capability not found'
}
if ($capability.State -ne 'Installed') {
  Add-WindowsCapability -Online -Name $capability.Name | Out-Null
}
$keygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
& $keygen -A
if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
$sshdConfigDefault = Join-Path $env:WINDIR 'System32\OpenSSH\sshd_config_default'
if (-not (Test-Path -LiteralPath $sshdConfig)) {
  if (-not (Test-Path -LiteralPath $sshdConfigDefault)) {
    throw 'OpenSSH Server default configuration not found'
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $sshdConfig) |
    Out-Null
  Copy-Item -LiteralPath $sshdConfigDefault -Destination $sshdConfig
}
$account = $env:USERNAME
if ([string]::IsNullOrWhiteSpace($account)) {
  throw 'Current Windows user is unavailable'
}
if (Test-Path -LiteralPath $sshdConfig) {
  $begin = "# BEGIN VibeKits AuthorizedKeys $account"
  $end = "# END VibeKits AuthorizedKeys $account"
  $content = [IO.File]::ReadAllText($sshdConfig)
  $managed = '(?ms)^' + [regex]::Escape($begin) + '.*?^' +
    [regex]::Escape($end) + '\r?\n?'
  $content = [regex]::Replace($content, $managed, '')
  $safeAccount = $account.Replace('"', '\"')
  $block = "$begin`r`nMatch User `"$safeAccount`"`r`n" +
    "    AuthorizedKeysFile %h/.ssh/authorized_keys`r`n" +
    "Match all`r`n$end`r`n"
  $firstMatch = [regex]::Match($content, '(?im)^\s*Match\s+')
  if ($firstMatch.Success) {
    $content = $content.Insert($firstMatch.Index, $block)
  } else {
    $content = $content.TrimEnd() + "`r`n`r`n$block"
  }
  $backup = "$sshdConfig.vibekits.bak"
  Copy-Item -LiteralPath $sshdConfig -Destination $backup -Force
  [IO.File]::WriteAllText($sshdConfig, $content, [Text.UTF8Encoding]::new($false))
  $sshd = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
  & $sshd -t
  if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $sshdConfig -Force
    throw 'sshd_config validation failed; backup restored'
  }
}
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
