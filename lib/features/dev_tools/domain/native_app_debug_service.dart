import 'dart:convert';
import 'dart:io';

typedef NativeDebugProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Bounded, shell-free diagnostics for applications running on the simulator
/// target itself. These operations are exposed only through the simulator MCP
/// endpoint while its explicit target-side switch is enabled.
abstract final class NativeAppDebugService {
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
