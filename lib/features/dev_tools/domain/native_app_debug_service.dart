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

  /// Returns the bounded accessibility tree for one exact running app.
  /// The native implementation runs inside the signed VibeKits process so the
  /// one-time macOS Accessibility grant belongs to VibeKits itself.
  static Future<Map<String, Object?>> inspectApplicationUi({
    String bundleId = '',
    String appName = '',
    bool promptPermission = false,
    int maxDepth = 8,
    int maxNodes = 400,
  }) async {
    _requireSoftwareManagementAuthorization();
    if (!Platform.isMacOS) {
      throw UnsupportedError('当前平台尚不支持应用控件树仿真');
    }
    final target = _validatedUiTarget(bundleId: bundleId, appName: appName);
    final response = await _deviceDebugChannel
        .invokeMapMethod<Object?, Object?>(
          'inspectApplicationUI',
          <String, Object?>{
            ...target,
            'promptPermission': promptPermission,
            'maxDepth': maxDepth.clamp(1, 12),
            'maxNodes': maxNodes.clamp(1, 1000),
          },
        );
    return _nativeMap(response, '目标 Mac 控件树读取失败');
  }

  /// Performs one narrowly scoped UI operation on one exact running app.
  /// Semantic selectors are required for press/setValue. Coordinate click is
  /// retained only as a bounded last resort and must stay inside its window.
  static Future<Map<String, Object?>> performApplicationUiAction({
    String bundleId = '',
    String appName = '',
    required String action,
    String identifier = '',
    String title = '',
    String role = '',
    String value = '',
    String key = '',
    double? x,
    double? y,
  }) async {
    _requireSoftwareManagementAuthorization();
    if (!Platform.isMacOS) {
      throw UnsupportedError('当前平台尚不支持应用控件操作');
    }
    final target = _validatedUiTarget(bundleId: bundleId, appName: appName);
    final operation = action.trim();
    const supported = <String>{
      'activate',
      'press',
      'setValue',
      'typeText',
      'key',
      'click',
    };
    if (!supported.contains(operation)) {
      throw const FormatException('不支持的应用控件动作');
    }
    final safeIdentifier = _safeUiValue(identifier, maxLength: 256);
    final safeTitle = _safeUiValue(title, maxLength: 256);
    final safeRole = _safeUiValue(role, maxLength: 80);
    final safeValue = _safeUiValue(value, maxLength: 4096, allowNewlines: true);
    final safeKey = _safeUiValue(key, maxLength: 32).toLowerCase();
    if ((operation == 'press' || operation == 'setValue') &&
        safeIdentifier.isEmpty &&
        safeTitle.isEmpty &&
        safeRole.isEmpty) {
      throw const FormatException('控件操作必须提供 identifier、title 或 role');
    }
    if (operation == 'key' &&
        !const <String>{
          'enter',
          'escape',
          'tab',
          'backspace',
          'delete',
          'up',
          'down',
          'left',
          'right',
        }.contains(safeKey)) {
      throw const FormatException('不支持的按键');
    }
    if (operation == 'click' && (x == null || y == null)) {
      throw const FormatException('坐标点击必须同时提供 x 和 y');
    }
    final response = await _deviceDebugChannel
        .invokeMapMethod<Object?, Object?>(
          'performApplicationUIAction',
          <String, Object?>{
            ...target,
            'action': operation,
            if (safeIdentifier.isNotEmpty) 'identifier': safeIdentifier,
            if (safeTitle.isNotEmpty) 'title': safeTitle,
            if (safeRole.isNotEmpty) 'role': safeRole,
            if (operation == 'setValue' || operation == 'typeText')
              'value': safeValue,
            if (operation == 'key') 'key': safeKey,
            'x': ?x,
            'y': ?y,
          },
        );
    return _nativeMap(response, '目标 Mac 控件操作失败');
  }

  static Map<String, Object?> _validatedUiTarget({
    required String bundleId,
    required String appName,
  }) {
    final safeBundleId = _safeUiValue(bundleId, maxLength: 256);
    final safeAppName = _safeUiValue(appName, maxLength: 256);
    if (safeBundleId.isEmpty && safeAppName.isEmpty) {
      throw const FormatException('必须提供目标 App 的 bundleId 或 appName');
    }
    if (safeBundleId.isNotEmpty &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]+$').hasMatch(safeBundleId)) {
      throw const FormatException('bundleId 格式无效');
    }
    return <String, Object?>{
      if (safeBundleId.isNotEmpty) 'bundleId': safeBundleId,
      if (safeAppName.isNotEmpty) 'appName': safeAppName,
    };
  }

  static String _safeUiValue(
    String value, {
    required int maxLength,
    bool allowNewlines = false,
  }) {
    final result = value.trim();
    if (result.length > maxLength || result.contains('\u0000')) {
      throw const FormatException('控件参数包含非法字符或过长');
    }
    if (!allowNewlines && result.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('控件参数不能包含换行');
    }
    return result;
  }

  static Map<String, Object?> _nativeMap(
    Map<Object?, Object?>? value,
    String failure,
  ) {
    if (value == null) throw StateError(failure);
    return Map<String, Object?>.from(value);
  }

  static Future<Map<String, Object?>> captureScreenshot({
    NativeDebugProcessRunner? runner,
  }) async {
    _requireSoftwareManagementAuthorization();
    if (Platform.isMacOS) {
      try {
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
      } on MissingPluginException {
        return _captureMacScreenshotWithCli(runner ?? Process.run);
      } on Object catch (error) {
        if (!error.toString().contains(
          'Binding has not yet been initialized',
        )) {
          rethrow;
        }
        return _captureMacScreenshotWithCli(runner ?? Process.run);
      }
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
          '\$path=${_powerShellLiteral(path)}; '
          r'''Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $i=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($i); $g.CopyFromScreen($b.Left,$b.Top,0,0,$i.Size); $i.Save($path,[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $i.Dispose()''';
      final result = await (runner ?? Process.run)(
        'powershell.exe',
        _windowsPowerShellArguments(script),
      ).timeout(const Duration(seconds: 20));
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

  static Future<Map<String, Object?>> _captureMacScreenshotWithCli(
    NativeDebugProcessRunner run,
  ) async {
    final home = Platform.environment['HOME']?.trim() ?? '';
    if (home.isEmpty) throw StateError('无法定位当前用户目录');
    final directory = Directory(
      '$home/Library/Application Support/Vibekits/simulator-screenshots',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/screen-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final result = await run('/usr/sbin/screencapture', <String>[
      '-x',
      '-t',
      'png',
      file.path,
    ]).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0 || !await file.exists()) {
      throw StateError('目标 Mac 后台截图失败：${result.stderr}');
    }
    return <String, Object?>{
      'ok': true,
      'platform': 'macos',
      'path': file.path,
      'bytes': await file.length(),
      'sha256': (await sha256.bind(file.openRead()).first).toString(),
      'singleFrame': true,
      'captureBackend': 'screencapture',
    };
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
        Map<String, Object?> identity;
        try {
          identity = await _readMacBundleIdentity(entity.path, run);
        } on Object {
          // One damaged or partially installed bundle must not hide every
          // healthy application or block an unrelated signed deployment.
          continue;
        }
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
    Directory? destinationRoot,
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
        destinationRoot: destinationRoot,
      );
    }
    if (Platform.isWindows) {
      if (!package.path.toLowerCase().endsWith('.msi')) {
        throw const FormatException('Windows 软件安装只接受已签名 MSI');
      }
      final signatureScript =
          '\$path=${_powerShellLiteral(package.path)}; '
          r'''$s=Get-AuthenticodeSignature -LiteralPath $path; "$($s.Status)|$($s.SignerCertificate.Subject)"''';
      final signature = await run(
        'powershell.exe',
        _windowsPowerShellArguments(signatureScript),
      ).timeout(const Duration(seconds: 20));
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
      final processNeedle = needle.toLowerCase().endsWith('.exe')
          ? needle.substring(0, needle.length - 4)
          : needle;
      final script =
          '\$q=${_powerShellLiteral(processNeedle)}; \$m=$boundedLimit; '
          r'''Get-Process -ErrorAction SilentlyContinue | Where-Object { [string]::IsNullOrEmpty($q) -or $_.ProcessName.IndexOf($q,[System.StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First $m ProcessName,Id,Path,CPU,WorkingSet64 | ConvertTo-Json -Compress''';
      final result = await run(
        'powershell.exe',
        _windowsPowerShellArguments(script),
      ).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0) {
        throw StateError('进程读取失败：${result.stderr}');
      }
      final rows = <Map<String, Object?>>[];
      final output = '${result.stdout}'.trim();
      if (output.isNotEmpty) {
        final decoded = jsonDecode(output);
        final values = decoded is List ? decoded : <Object?>[decoded];
        for (final value in values.whereType<Map>()) {
          final item = Map<String, Object?>.from(value);
          rows.add(<String, Object?>{
            'name': item['ProcessName'],
            'pid': item['Id'],
            'path': item['Path'],
            'cpuSeconds': item['CPU'],
            'workingSetBytes': item['WorkingSet64'],
          });
        }
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
          '\$n=${_powerShellLiteral(name)}; \$s=$duration; \$m=$lineLimit; '
          r'''$ProgressPreference='SilentlyContinue'; $ErrorActionPreference='SilentlyContinue'; $events=@(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddSeconds(-$s)} -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -like "*$n*" -or $_.Message -like "*$n*" } | Select-Object -First $m TimeCreated,LevelDisplayName,ProviderName,Id,Message); if($events.Count -eq 0){'[]'}else{$events | ConvertTo-Json -Compress}; exit 0''';
      final result = await run(
        'powershell.exe',
        _windowsPowerShellArguments(script),
      ).timeout(const Duration(seconds: 20));
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
      final processName = value.toLowerCase().endsWith('.exe')
          ? value.substring(0, value.length - 4)
          : value;
      final script =
          '\$name=${_powerShellLiteral(processName)}; '
          r'''Get-Process -Name $name -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop''';
      result = await run('powershell.exe', _windowsPowerShellArguments(script));
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
    Directory? destinationRoot,
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
    // Finder/ditto ZIPs include AppleDouble metadata under __MACOSX. It is
    // not another application payload; keep rejecting every other extra root.
    final payloadEntries = entries
        .where(
          (entry) => entry != '__MACOSX/' && !entry.startsWith('__MACOSX/'),
        )
        .toList(growable: false);
    final topLevelApps = payloadEntries
        .map((entry) => entry.split('/').first)
        .where((entry) => entry.endsWith('.app'))
        .toSet();
    if (topLevelApps.length != 1 ||
        payloadEntries.any(
          (entry) => !entry.startsWith('${topLevelApps.single}/'),
        )) {
      throw StateError('macOS 安装包必须只包含一个顶层 .app');
    }
    final extracted = await run('/usr/bin/ditto', <String>[
      '-x',
      '-k',
      package.path,
      extractRoot.path,
    ]);
    if (extracted.exitCode != 0) throw StateError('macOS 安装包解压失败');
    // `unzip -Z1` 会按本地字符集转写非 ASCII 条目名（中文被写成 '?'），而 ditto
    // 还原的是归档里的原始 UTF-8 字节，两者对同一个 App 并不一致：拿列表名拼路径
    // 必然找不到已解压目录，中文 App 因此被误判为“缺少 App”。以磁盘真实解压结果为准。
    final replacement = await _resolveExtractedMacBundle(extractRoot);
    final bundleName = replacement.path.split('/').last;
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
        ? Directory(
            '${destinationRoot?.path ?? '$home/Applications'}/$bundleName',
          )
        : Directory('${existing.single['path']}');
    await destination.parent.create(recursive: true);
    Directory? backup;
    if (await destination.exists()) {
      backup = Directory('${root.path}/$transaction-rollback.app');
      await _moveVerifiedMacBundle(destination, backup, run);
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
        await _moveVerifiedMacBundle(backup, destination, run);
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

  /// 解析 ditto 真正解压出来的顶层 .app 目录。
  ///
  /// Info-ZIP（`unzip -Z1`）会按本地字符集转写非 ASCII 条目名，中文 App 名会被
  /// 写成 '?'，而 ditto 还原的是归档里的原始 UTF-8 字节，两者对同一个 App 并不
  /// 一致。因此列表名只用于结构校验，绝不能当作磁盘路径使用；这里只认实际解压
  /// 结果，并继续要求顶层恰好存在一个 .app。
  static Future<Directory> _resolveExtractedMacBundle(
    Directory extractRoot,
  ) async {
    final bundles = <Directory>[];
    await for (final entity in extractRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      if (!entity.path.split('/').last.endsWith('.app')) continue;
      bundles.add(entity);
    }
    if (bundles.length != 1) throw StateError('macOS 安装包缺少 App');
    return bundles.single;
  }

  static Future<void> _moveVerifiedMacBundle(
    Directory source,
    Directory destination,
    NativeDebugProcessRunner run,
  ) async {
    try {
      await source.rename(destination.path);
      return;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 18) rethrow;
    }

    final copied = await run('/usr/bin/ditto', <String>[
      source.path,
      destination.path,
    ]);
    if (copied.exitCode != 0) {
      if (await destination.exists()) await destination.delete(recursive: true);
      throw StateError('跨磁盘 App 备份失败');
    }
    final verified = await run('/usr/bin/codesign', <String>[
      '--verify',
      '--deep',
      '--strict',
      destination.path,
    ]);
    if (verified.exitCode != 0) {
      await destination.delete(recursive: true);
      throw StateError('跨磁盘 App 备份签名复验失败');
    }
    await source.delete(recursive: true);
  }

  static Future<Map<String, Object?>> _readMacBundleIdentity(
    String bundlePath,
    NativeDebugProcessRunner run,
  ) async {
    final plistPath = '$bundlePath/Contents/Info.plist';
    final plist = await run('/usr/bin/plutil', <String>[
      '-convert',
      'json',
      '-o',
      '-',
      plistPath,
    ]);
    if (plist.exitCode == 0) {
      try {
        final decoded = jsonDecode('${plist.stdout}');
        if (decoded is Map) {
          final values = Map<String, Object?>.from(decoded);
          final bundleId = '${values['CFBundleIdentifier'] ?? ''}'.trim();
          if (bundleId.isNotEmpty) {
            final displayName = '${values['CFBundleDisplayName'] ?? ''}'.trim();
            return <String, Object?>{
              'bundleId': bundleId,
              'name': displayName.isNotEmpty
                  ? displayName
                  : '${values['CFBundleName'] ?? ''}'.trim(),
              'version': '${values['CFBundleShortVersionString'] ?? ''}'.trim(),
              'build': '${values['CFBundleVersion'] ?? ''}'.trim(),
            };
          }
        }
      } on FormatException {
        // Fall back to PlistBuddy for legacy or malformed command output.
      }
    }

    Future<String> read(String key) async {
      final result = await run('/usr/libexec/PlistBuddy', <String>[
        '-c',
        'Print :$key',
        plistPath,
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

  static String _powerShellLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static List<String> _windowsPowerShellArguments(String script) => <String>[
    '-NoProfile',
    '-NonInteractive',
    '-EncodedCommand',
    base64Encode(<int>[
      for (final unit in script.codeUnits) ...<int>[unit & 0xff, unit >> 8],
    ]),
  ];

  static String _bounded(String value) =>
      value.length <= 8192 ? value : value.substring(value.length - 8192);
}
