import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../cleaner/domain/installed_application_service.dart';
import 'harness_simulator_access_settings.dart';

typedef NativeDebugProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Bounded, shell-free diagnostics for applications running on the simulator
/// target itself. These operations are exposed only through the simulator MCP
/// endpoint while its explicit target-side switch is enabled.
abstract final class NativeAppDebugService {
  static const String protectedBundleId = 'com.caucy.vibekits';
  static const MethodChannel _deviceDebugChannel = MethodChannel(
    'vibekits/device_debug',
  );

  static Future<bool> screenCaptureAuthorized() async {
    if (Platform.isWindows) return true;
    if (!Platform.isMacOS) return false;
    try {
      return await _deviceDebugChannel.invokeMethod<bool>(
            'screenCapturePermissionStatus',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> requestScreenCaptureAuthorization() async {
    if (Platform.isWindows) return true;
    if (!Platform.isMacOS) return false;
    return await _deviceDebugChannel.invokeMethod<bool>(
          'requestScreenCapturePermission',
        ) ??
        false;
  }

  static Future<Map<String, Object?>> captureScreenshot({
    NativeDebugProcessRunner? runner,
  }) async {
    _requireSoftwareManagementAuthorization();
    if (Platform.isMacOS) {
      final response = await _deviceDebugChannel
          .invokeMapMethod<Object?, Object?>('captureScreen');
      if (response?['ok'] != true || response?['path'] is! String) {
        throw StateError('目标 Mac 截图失败');
      }
      final file = File('${response!['path']}');
      if (!await file.exists()) throw StateError('目标 Mac 截图文件不存在');
      final digest = (await sha256.bind(file.openRead()).first).toString();
      return <String, Object?>{
        'ok': true,
        'platform': 'macos',
        'path': file.path,
        'width': response['width'],
        'height': response['height'],
        'bytes': await file.length(),
        'sha256': digest,
        'singleFrame': true,
      };
    }
    if (Platform.isWindows) {
      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'vibekits-simulator-screenshots',
      );
      await directory.create(recursive: true);
      final path =
          '${directory.path}${Platform.pathSeparator}'
          'screen-${DateTime.now().millisecondsSinceEpoch}.png';
      final script =
          r'''Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $i=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($i); $g.CopyFromScreen($b.Left,$b.Top,0,0,$i.Size); $i.Save($args[0],[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $i.Dispose()''';
      final result = await (runner ?? Process.run)('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
        path,
      ]).timeout(const Duration(seconds: 20));
      final file = File(path);
      if (result.exitCode != 0 || !await file.exists()) {
        throw StateError('目标 Windows 截图失败');
      }
      return <String, Object?>{
        'ok': true,
        'platform': 'windows',
        'path': file.path,
        'bytes': await file.length(),
        'sha256': (await sha256.bind(file.openRead()).first).toString(),
        'singleFrame': true,
      };
    }
    throw UnsupportedError('当前平台不支持远程仿真截图');
  }

  static Future<Map<String, Object?>> listApplications({
    String query = '',
    int limit = 100,
    NativeDebugProcessRunner? runner,
  }) async {
    final needle = _safeQuery(query).toLowerCase();
    final boundedLimit = limit.clamp(1, 200);
    if (Platform.isWindows) {
      final apps = await InstalledApplicationService.load();
      return <String, Object?>{
        'platform': 'windows',
        'applications': <Map<String, Object?>>[
          for (final app in apps)
            if (needle.isEmpty ||
                app.name.toLowerCase().contains(needle) ||
                app.publisher.toLowerCase().contains(needle))
              <String, Object?>{
                'identity': app.id,
                'name': app.name,
                'publisher': app.publisher,
                'version': app.version,
                'installLocation': app.installLocation,
                'canUninstall': app.canUninstall,
              },
        ].take(boundedLimit).toList(growable: false),
      };
    }
    if (!Platform.isMacOS) {
      throw UnsupportedError('当前平台不支持应用清单仿真');
    }
    final run = runner ?? Process.run;
    final roots = <Directory>[
      Directory('/Applications'),
      Directory('${Platform.environment['HOME'] ?? ''}/Applications'),
    ];
    final applications = <Map<String, Object?>>[];
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory || !entity.path.endsWith('.app')) continue;
        final identity = await _readMacBundleIdentity(entity.path, run);
        final searchable = '${identity['name']} ${identity['bundleId']}'
            .toLowerCase();
        if (needle.isNotEmpty && !searchable.contains(needle)) continue;
        applications.add(<String, Object?>{
          ...identity,
          'path': entity.path,
          'canUninstall': identity['bundleId'] != protectedBundleId,
        });
        if (applications.length >= boundedLimit) break;
      }
      if (applications.length >= boundedLimit) break;
    }
    return <String, Object?>{
      'platform': 'macos',
      'applications': applications,
      'truncated': applications.length >= boundedLimit,
    };
  }

  static Future<Map<String, Object?>> installApplication({
    required String packagePath,
    required String expectedSha256,
    required String expectedIdentity,
    NativeDebugProcessRunner? runner,
    Directory? stagingRoot,
  }) async {
    _requireSoftwareManagementAuthorization();
    final package = File(packagePath).absolute;
    final checksum = expectedSha256.trim().toLowerCase();
    final identity = _safeQuery(expectedIdentity, required: true);
    if (!await package.exists() || !package.isAbsolute) {
      throw const FormatException('安装包必须是目标机上已下载的绝对文件路径');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException('安装包 SHA-256 无效');
    }
    final actual = (await sha256.bind(package.openRead()).first)
        .toString()
        .toLowerCase();
    if (actual != checksum) throw const FormatException('安装包 SHA-256 校验失败');
    final run = runner ?? Process.run;
    if (Platform.isMacOS) {
      if (!package.path.toLowerCase().endsWith('.zip')) {
        throw const FormatException('macOS 软件安装只接受包含单一 .app 的 ZIP');
      }
      return _installMacApplication(
        package: package,
        expectedBundleId: identity,
        checksum: actual,
        run: run,
        stagingRoot: stagingRoot,
      );
    }
    if (Platform.isWindows) {
      if (!package.path.toLowerCase().endsWith('.msi')) {
        throw const FormatException('Windows 软件安装只接受已签名 MSI');
      }
      final signature = await run('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''$s=Get-AuthenticodeSignature -LiteralPath $args[0]; "$($s.Status)|$($s.SignerCertificate.Subject)"''',
        package.path,
      ]).timeout(const Duration(seconds: 20));
      final signatureText = '${signature.stdout}'.trim();
      if (signature.exitCode != 0 || !signatureText.startsWith('Valid|')) {
        throw StateError('Windows 安装包签名无效');
      }
      if (!signatureText.toLowerCase().contains(identity.toLowerCase())) {
        throw StateError('Windows 安装包签名发布者与授权身份不匹配');
      }
      final installed = await run('msiexec.exe', <String>[
        '/i',
        package.path,
        '/qn',
        '/norestart',
      ]).timeout(const Duration(minutes: 10));
      if (installed.exitCode != 0) {
        throw StateError('Windows 软件安装失败：${installed.exitCode}');
      }
      return <String, Object?>{
        'ok': true,
        'platform': 'windows',
        'packagePath': package.path,
        'sha256': actual,
        'publisher': identity,
        'signature': signatureText,
      };
    }
    throw UnsupportedError('当前平台不支持软件安装仿真');
  }

  static Future<Map<String, Object?>> uninstallApplication({
    required String identity,
    NativeDebugProcessRunner? runner,
  }) async {
    _requireSoftwareManagementAuthorization();
    final targetIdentity = _safeQuery(identity, required: true);
    if (targetIdentity == protectedBundleId) {
      throw StateError('不能通过通用卸载工具移除正在提供仿真通道的 VibeKits');
    }
    if (Platform.isWindows) {
      final apps = await InstalledApplicationService.load();
      final matches = apps
          .where((app) => app.id == targetIdentity)
          .toList(growable: false);
      if (matches.length != 1 || !matches.single.canUninstall) {
        throw StateError('未找到唯一且可卸载的 Windows 应用身份');
      }
      final started = await InstalledApplicationService.launchUninstaller(
        matches.single,
      );
      if (!started) throw StateError('Windows 卸载程序未能启动');
      return <String, Object?>{
        'ok': true,
        'platform': 'windows',
        'identity': targetIdentity,
        'state': 'uninstaller_started',
        'note': '目标系统仍可显示卸载程序自身的确认界面',
      };
    }
    if (!Platform.isMacOS) {
      throw UnsupportedError('当前平台不支持软件卸载仿真');
    }
    final run = runner ?? Process.run;
    final listed = await listApplications(query: '', limit: 200, runner: run);
    final apps = (listed['applications']! as List)
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .where((app) => app['bundleId'] == targetIdentity)
        .toList(growable: false);
    if (apps.length != 1) throw StateError('未找到唯一的 macOS App 身份');
    final source = Directory('${apps.single['path']}');
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final trash = Directory('$home/.Trash');
    await trash.create(recursive: true);
    final name = source.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final destination = Directory(
      '${trash.path}/${DateTime.now().millisecondsSinceEpoch}-$name',
    );
    await source.rename(destination.path);
    return <String, Object?>{
      'ok': true,
      'platform': 'macos',
      'identity': targetIdentity,
      'removedFrom': source.path,
      'recoverablePath': destination.path,
      'state': 'moved_to_trash',
    };
  }

  static Future<Map<String, Object?>> inspectProcesses({
    String query = '',
    int limit = 50,
    NativeDebugProcessRunner? runner,
  }) async {
    final needle = _safeQuery(query);
    final boundedLimit = limit.clamp(1, 200);
    final run = runner ?? Process.run;
    if (Platform.isMacOS) {
      final result = await run('/bin/ps', const <String>[
        '-axo',
        'pid=,ppid=,%cpu=,%mem=,etime=,command=',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) {
        throw StateError('进程读取失败：${result.stderr}');
      }
      final rows = <Map<String, Object?>>[];
      for (final line in '${result.stdout}'.split('\n')) {
        final match = RegExp(
          r'^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\S+)\s+(.+)$',
        ).firstMatch(line);
        if (match == null) continue;
        final command = match.group(6)!;
        if (needle.isNotEmpty &&
            !command.toLowerCase().contains(needle.toLowerCase())) {
          continue;
        }
        rows.add(<String, Object?>{
          'pid': int.parse(match.group(1)!),
          'parentPid': int.parse(match.group(2)!),
          'cpuPercent': double.parse(match.group(3)!),
          'memoryPercent': double.parse(match.group(4)!),
          'elapsed': match.group(5),
          'command': command,
        });
        if (rows.length >= boundedLimit) break;
      }
      return <String, Object?>{
        'platform': 'macos',
        'query': needle,
        'processes': rows,
        'truncated': rows.length >= boundedLimit,
      };
    }
    if (Platform.isWindows) {
      final result = await run('tasklist.exe', const <String>[
        '/FO',
        'CSV',
        '/NH',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) {
        throw StateError('进程读取失败：${result.stderr}');
      }
      final rows = <Map<String, Object?>>[];
      final csv = RegExp(r'^"([^"]+)","(\d+)","([^"]*)","([^"]*)","([^"]*)"');
      for (final line in '${result.stdout}'.split('\n')) {
        final match = csv.firstMatch(line.trim());
        if (match == null) continue;
        final name = match.group(1)!;
        if (needle.isNotEmpty &&
            !name.toLowerCase().contains(needle.toLowerCase())) {
          continue;
        }
        rows.add(<String, Object?>{
          'name': name,
          'pid': int.parse(match.group(2)!),
          'session': match.group(3),
          'memory': match.group(5),
        });
        if (rows.length >= boundedLimit) break;
      }
      return <String, Object?>{
        'platform': 'windows',
        'query': needle,
        'processes': rows,
        'truncated': rows.length >= boundedLimit,
      };
    }
    throw UnsupportedError('当前平台不支持整机进程仿真');
  }

  static Future<Map<String, Object?>> readLogs({
    required String processName,
    int seconds = 300,
    int maxLines = 500,
    NativeDebugProcessRunner? runner,
  }) async {
    final name = _safeQuery(processName, required: true);
    final duration = seconds.clamp(1, 3600);
    final lineLimit = maxLines.clamp(1, 2000);
    final run = runner ?? Process.run;
    if (Platform.isMacOS) {
      final escaped = name.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final result = await run('/usr/bin/log', <String>[
        'show',
        '--style',
        'compact',
        '--last',
        '${duration}s',
        '--predicate',
        'process == "$escaped" OR processImagePath CONTAINS[c] "$escaped"',
      ]).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) {
        throw StateError('日志读取失败：${result.stderr}');
      }
      final all = '${result.stdout}'.split('\n');
      final selected = all.length <= lineLimit
          ? all
          : all.sublist(all.length - lineLimit);
      return <String, Object?>{
        'platform': 'macos',
        'processName': name,
        'seconds': duration,
        'lines': selected,
        'truncated': all.length > selected.length,
        'source': 'macOS Unified Log',
      };
    }
    if (Platform.isWindows) {
      final script =
          r'''$n=$args[0]; $s=[int]$args[1]; $m=[int]$args[2]; Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddSeconds(-$s)} -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -like "*$n*" -or $_.Message -like "*$n*" } | Select-Object -First $m TimeCreated,LevelDisplayName,ProviderName,Id,Message | ConvertTo-Json -Compress''';
      final result = await run('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
        name,
        '$duration',
        '$lineLimit',
      ]).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) {
        throw StateError('日志读取失败：${result.stderr}');
      }
      return <String, Object?>{
        'platform': 'windows',
        'processName': name,
        'seconds': duration,
        'eventsJson': '${result.stdout}'.trim(),
        'source': 'Windows Application Event Log',
      };
    }
    throw UnsupportedError('当前平台不支持整机日志仿真');
  }

  static Future<Map<String, Object?>> controlApplication({
    required String action,
    required String target,
    NativeDebugProcessRunner? runner,
  }) async {
    final operation = action.trim().toLowerCase();
    if (operation != 'launch' && operation != 'stop') {
      throw const FormatException('action 只能是 launch 或 stop');
    }
    final value = _safeQuery(target, required: true);
    final run = runner ?? Process.run;
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = operation == 'launch'
          ? await run('/usr/bin/open', <String>['-a', value])
          : await run('/usr/bin/pkill', <String>['-TERM', '-x', value]);
    } else if (Platform.isWindows) {
      if (operation == 'launch') {
        if (!value.toLowerCase().endsWith('.exe') || !File(value).isAbsolute) {
          throw const FormatException('Windows 启动目标必须是绝对 .exe 路径');
        }
        final process = await Process.start(value, const <String>[]);
        return <String, Object?>{
          'platform': 'windows',
          'action': operation,
          'target': value,
          'pid': process.pid,
        };
      }
      result = await run('taskkill.exe', <String>['/IM', value, '/T']);
    } else {
      throw UnsupportedError('当前平台不支持应用启停仿真');
    }
    return <String, Object?>{
      'platform': Platform.operatingSystem,
      'action': operation,
      'target': value,
      'exitCode': result.exitCode,
      'stdout': _bounded('${result.stdout}'),
      'stderr': _bounded('${result.stderr}'),
      'ok': result.exitCode == 0,
    };
  }

  static Future<Map<String, Object?>> readCrashReports({
    required String appName,
    int limit = 5,
  }) async {
    final name = _safeQuery(appName, required: true).toLowerCase();
    final boundedLimit = limit.clamp(1, 20);
    if (Platform.isMacOS) {
      final roots = <Directory>[
        Directory(
          '${Platform.environment['HOME'] ?? ''}/Library/Logs/DiagnosticReports',
        ),
        Directory('/Library/Logs/DiagnosticReports'),
      ];
      final files = <File>[];
      for (final root in roots) {
        if (!root.existsSync()) continue;
        await for (final entity in root.list(followLinks: false)) {
          if (entity is File &&
              entity.uri.pathSegments.last.toLowerCase().contains(name)) {
            files.add(entity);
          }
        }
      }
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      final reports = <Map<String, Object?>>[];
      for (final file in files.take(boundedLimit)) {
        final stat = await file.stat();
        final handle = await file.open();
        try {
          final readLength = stat.size.clamp(0, 64 * 1024);
          final bytes = await handle.read(readLength);
          reports.add(<String, Object?>{
            'name': file.uri.pathSegments.last,
            'modifiedAt': stat.modified.toUtc().toIso8601String(),
            'size': stat.size,
            'content': utf8.decode(bytes, allowMalformed: true),
            'truncated': stat.size > bytes.length,
          });
        } finally {
          await handle.close();
        }
      }
      return <String, Object?>{
        'platform': 'macos',
        'appName': appName.trim(),
        'reports': reports,
      };
    }
    if (Platform.isWindows) {
      final roots = <Directory>[
        Directory('${Platform.environment['LOCALAPPDATA'] ?? ''}/CrashDumps'),
      ];
      final reports = <Map<String, Object?>>[];
      for (final root in roots) {
        if (!root.existsSync()) continue;
        final files = await root
            .list(followLinks: false)
            .where(
              (entity) =>
                  entity is File &&
                  entity.uri.pathSegments.last.toLowerCase().contains(name),
            )
            .cast<File>()
            .toList();
        files.sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
        for (final file in files.take(boundedLimit)) {
          final stat = await file.stat();
          reports.add(<String, Object?>{
            'name': file.uri.pathSegments.last,
            'modifiedAt': stat.modified.toUtc().toIso8601String(),
            'size': stat.size,
            'path': file.path,
          });
        }
      }
      return <String, Object?>{
        'platform': 'windows',
        'appName': appName.trim(),
        'reports': reports,
        'note': 'Windows dump 为二进制文件，返回元数据供后续受控文件工具读取',
      };
    }
    throw UnsupportedError('当前平台不支持崩溃报告读取');
  }

  static Future<Map<String, Object?>> _installMacApplication({
    required File package,
    required String expectedBundleId,
    required String checksum,
    required NativeDebugProcessRunner run,
    Directory? stagingRoot,
  }) async {
    final Directory root =
        stagingRoot ??
        Directory('${Directory.systemTemp.path}/vibekits-app-deployments');
    await root.create(recursive: true);
    final String transaction = DateTime.now().microsecondsSinceEpoch.toString();
    final Directory extractRoot = Directory(
      '${root.path}/$transaction-extract',
    );
    await extractRoot.create(recursive: true);
    final listed = await run('/usr/bin/unzip', <String>['-Z1', package.path]);
    if (listed.exitCode != 0) throw StateError('无法读取 macOS 安装包目录');
    final entries = '${listed.stdout}'
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty ||
        entries.any(
          (entry) =>
              entry.startsWith('/') ||
              entry.contains('\\') ||
              entry.split('/').contains('..'),
        )) {
      throw StateError('macOS 安装包包含不安全路径');
    }
    final topLevelApps = entries
        .map((entry) => entry.split('/').first)
        .where((entry) => entry.endsWith('.app'))
        .toSet();
    if (topLevelApps.length != 1 ||
        entries.any((entry) => !entry.startsWith('${topLevelApps.single}/'))) {
      throw StateError('macOS 安装包必须只包含一个顶层 .app');
    }
    final extracted = await run('/usr/bin/ditto', <String>[
      '-x',
      '-k',
      package.path,
      extractRoot.path,
    ]);
    if (extracted.exitCode != 0) throw StateError('macOS 安装包解压失败');
    final replacement = Directory('${extractRoot.path}/${topLevelApps.single}');
    if (!await replacement.exists()) throw StateError('macOS 安装包缺少 App');
    final replacementIdentity = await _readMacBundleIdentity(
      replacement.path,
      run,
    );
    if (replacementIdentity['bundleId'] != expectedBundleId) {
      throw StateError('macOS App 包名与授权身份不匹配');
    }
    final signature = await run('/usr/bin/codesign', <String>[
      '--verify',
      '--deep',
      '--strict',
      '--verbose=2',
      replacement.path,
    ]);
    if (signature.exitCode != 0) throw StateError('macOS App 代码签名验证失败');
    final policy = await run('/usr/sbin/spctl', <String>[
      '-a',
      '-t',
      'exec',
      '-vv',
      replacement.path,
    ]);
    if (policy.exitCode != 0) throw StateError('macOS App 未通过 Gatekeeper');

    final listedApps = await listApplications(
      query: '',
      limit: 200,
      runner: run,
    );
    final existing = (listedApps['applications']! as List)
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .where((app) => app['bundleId'] == expectedBundleId)
        .toList(growable: false);
    if (existing.length > 1) throw StateError('目标机存在多个相同包名 App，拒绝覆盖');
    final String home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final destination = existing.isEmpty
        ? Directory('$home/Applications/${topLevelApps.single}')
        : Directory('${existing.single['path']}');
    await destination.parent.create(recursive: true);
    Directory? backup;
    if (await destination.exists()) {
      backup = Directory('${root.path}/$transaction-rollback.app');
      await destination.rename(backup.path);
    }
    try {
      final copied = await run('/usr/bin/ditto', <String>[
        replacement.path,
        destination.path,
      ]);
      if (copied.exitCode != 0) throw StateError('macOS App 复制失败');
      final installedSignature = await run('/usr/bin/codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        destination.path,
      ]);
      if (installedSignature.exitCode != 0) {
        throw StateError('安装后的 macOS App 签名复验失败');
      }
    } on Object {
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      if (backup != null && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
    return <String, Object?>{
      'ok': true,
      'platform': 'macos',
      'identity': expectedBundleId,
      'name': replacementIdentity['name'],
      'version': replacementIdentity['version'],
      'installedPath': destination.path,
      'sha256': checksum,
      'rollbackPath': backup?.path,
      'state': 'installed',
    };
  }

  static Future<Map<String, Object?>> _readMacBundleIdentity(
    String bundlePath,
    NativeDebugProcessRunner run,
  ) async {
    Future<String> read(String key) async {
      final result = await run('/usr/libexec/PlistBuddy', <String>[
        '-c',
        'Print :$key',
        '$bundlePath/Contents/Info.plist',
      ]);
      return result.exitCode == 0 ? '${result.stdout}'.trim() : '';
    }

    final bundleId = await read('CFBundleIdentifier');
    if (bundleId.isEmpty) throw StateError('App 缺少 CFBundleIdentifier');
    return <String, Object?>{
      'bundleId': bundleId,
      'name': (await read('CFBundleDisplayName')).isNotEmpty
          ? await read('CFBundleDisplayName')
          : await read('CFBundleName'),
      'version': await read('CFBundleShortVersionString'),
      'build': await read('CFBundleVersion'),
    };
  }

  static void _requireSoftwareManagementAuthorization() {
    if (!HarnessSimulatorAccessSettings.enabled) {
      throw StateError('目标机尚未打开远程仿真授权');
    }
  }

  static String _safeQuery(String value, {bool required = false}) {
    final result = value.trim();
    if (required && result.isEmpty) throw const FormatException('目标不能为空');
    if (result.length > 256 || result.contains(RegExp(r'[\r\n\x00]'))) {
      throw const FormatException('目标包含非法字符或过长');
    }
    return result;
  }

  static String _bounded(String value) =>
      value.length <= 8192 ? value : value.substring(value.length - 8192);
}
