import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'adb_service.dart';

typedef ResourceProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class SystemResourceProbeController {
  Process? _activeProcess;
  bool _cancelled = false;

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (_cancelled) throw const ProcessException('', <String>[], '探针已取消');
    final Process process = await Process.start(executable, arguments);
    _activeProcess = process;
    final Future<List<int>> stdoutBytes = process.stdout.fold<List<int>>(
      <int>[],
      (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
    );
    final Future<List<int>> stderrBytes = process.stderr.fold<List<int>>(
      <int>[],
      (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
    );
    try {
      final int exitCode = await process.exitCode.timeout(
        const Duration(seconds: 24),
        onTimeout: () {
          process.kill();
          throw TimeoutException('系统资源探针执行超时');
        },
      );
      return ProcessResult(
        process.pid,
        exitCode,
        systemEncoding.decode(await stdoutBytes),
        systemEncoding.decode(await stderrBytes),
      );
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _activeProcess?.kill();
    _activeProcess = null;
  }
}

class ResourceProcessSample {
  const ResourceProcessSample({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memoryBytes,
  });

  final int pid;
  final String name;
  final double cpuPercent;
  final int memoryBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'name': name,
    'cpuPercent': cpuPercent,
    'memoryBytes': memoryBytes,
  };
}

class ResourceStorageSample {
  const ResourceStorageSample({
    required this.name,
    required this.totalBytes,
    required this.freeBytes,
  });

  final String name;
  final int totalBytes;
  final int freeBytes;

  double get usedPercent =>
      totalBytes <= 0 ? 0 : (totalBytes - freeBytes) * 100 / totalBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'totalBytes': totalBytes,
    'usedBytes': totalBytes - freeBytes,
    'freeBytes': freeBytes,
    'usedPercent': usedPercent,
  };
}

class SystemResourceSnapshot {
  const SystemResourceSnapshot({
    required this.platform,
    required this.target,
    required this.capturedAt,
    required this.cpuPercent,
    required this.logicalProcessors,
    required this.loadAverage,
    required this.memoryTotalBytes,
    required this.memoryAvailableBytes,
    required this.gpuNames,
    required this.gpuPercent,
    required this.gpuMemoryTotalBytes,
    required this.gpuMemoryUsedBytes,
    required this.storage,
    required this.processes,
    required this.warnings,
    required this.evidence,
  });

  final String platform;
  final String target;
  final DateTime capturedAt;
  final double cpuPercent;
  final int logicalProcessors;
  final double? loadAverage;
  final int memoryTotalBytes;
  final int memoryAvailableBytes;
  final List<String> gpuNames;
  final double? gpuPercent;
  final int? gpuMemoryTotalBytes;
  final int? gpuMemoryUsedBytes;
  final List<ResourceStorageSample> storage;
  final List<ResourceProcessSample> processes;
  final List<String> warnings;
  final List<String> evidence;

  int get memoryUsedBytes => memoryTotalBytes - memoryAvailableBytes;
  double get memoryUsedPercent =>
      memoryTotalBytes <= 0 ? 0 : memoryUsedBytes * 100 / memoryTotalBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'target': target,
    'capturedAt': capturedAt.toIso8601String(),
    'cpu': <String, Object?>{
      'usedPercent': cpuPercent,
      'logicalProcessors': logicalProcessors,
      if (loadAverage != null) 'loadAverage': loadAverage,
    },
    'memory': <String, Object?>{
      'totalBytes': memoryTotalBytes,
      'usedBytes': memoryUsedBytes,
      'availableBytes': memoryAvailableBytes,
      'usedPercent': memoryUsedPercent,
    },
    'gpu': <String, Object?>{
      'names': gpuNames,
      if (gpuPercent != null) 'usedPercent': gpuPercent,
      if (gpuMemoryTotalBytes != null) 'memoryTotalBytes': gpuMemoryTotalBytes,
      if (gpuMemoryUsedBytes != null) 'memoryUsedBytes': gpuMemoryUsedBytes,
      if (gpuPercent == null) 'note': '当前平台未提供可靠的 GPU 利用率',
    },
    'storage': storage
        .map((ResourceStorageSample value) => value.toJson())
        .toList(),
    'topProcesses': processes
        .map((ResourceProcessSample value) => value.toJson())
        .toList(),
    'warnings': warnings,
    'evidence': evidence,
  };
}

abstract final class SystemResourceService {
  static Future<SystemResourceSnapshot> inspectLocal({
    ResourceProcessRunner? processRunner,
  }) async {
    if (Platform.isWindows) {
      return _inspectWindows(processRunner ?? Process.run);
    }
    if (Platform.isAndroid) {
      final ProcessResult result = await (processRunner ?? Process.run)(
        '/system/bin/sh',
        <String>['-c', _androidProbeScript],
      );
      if (result.exitCode != 0) {
        throw StateError('安卓资源探测失败：${result.stderr}');
      }
      return parseAndroidProbe('${result.stdout}', target: '本机 Android');
    }
    if (Platform.isMacOS) {
      return _inspectMac(processRunner ?? Process.run);
    }
    throw UnsupportedError('当前平台尚未实现资源诊断');
  }

  static Future<SystemResourceSnapshot> inspectAndroidDevice({
    required String serial,
    String? adbExecutable,
  }) async {
    final String target = serial.trim();
    if (target.isEmpty) throw const FormatException('缺少 Android 设备序列号');
    final AdbCommandResult result = await AdbService.runCommand(
      adbExecutable ?? AdbService.bundledExecutablePath(),
      <String>['-s', target, 'shell', 'sh', '-c', _androidProbeScript],
      timeout: const Duration(seconds: 12),
    );
    if (result.exitCode != 0) {
      throw StateError('ADB 资源探测失败：${result.stderr.trim()}');
    }
    return parseAndroidProbe(result.stdout, target: target);
  }

  static Future<SystemResourceSnapshot> _inspectWindows(
    ResourceProcessRunner runner,
  ) async {
    final ProcessResult result = await runner('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      _windowsProbeScript,
    ]).timeout(const Duration(seconds: 25));
    if (result.exitCode != 0) {
      throw StateError('Windows 资源探测失败：${result.stderr}');
    }
    final Object? decoded = jsonDecode('${result.stdout}'.trim());
    if (decoded is! Map) throw const FormatException('Windows 资源返回格式无效');
    return parseWindowsJson(decoded.cast<String, Object?>());
  }

  static SystemResourceSnapshot parseWindowsJson(Map<String, Object?> raw) {
    final int total = _integer(raw['memoryTotalBytes']);
    final int available = _integer(raw['memoryAvailableBytes']);
    final List<ResourceProcessSample> processes = <ResourceProcessSample>[
      for (final Object? item
          in (raw['processes'] as List? ?? const <Object?>[]))
        if (item is Map)
          ResourceProcessSample(
            pid: _integer(item['pid']),
            name: '${item['name'] ?? '未知进程'}',
            cpuPercent: _number(item['cpuPercent']),
            memoryBytes: _integer(item['memoryBytes']),
          ),
    ];
    final List<ResourceStorageSample> storage = <ResourceStorageSample>[
      for (final Object? item in (raw['storage'] as List? ?? const <Object?>[]))
        if (item is Map)
          ResourceStorageSample(
            name: '${item['name'] ?? ''}',
            totalBytes: _integer(item['totalBytes']),
            freeBytes: _integer(item['freeBytes']),
          ),
    ];
    final double cpu = _number(raw['cpuPercent']).clamp(0, 100);
    final double? gpu = raw['gpuPercent'] == null
        ? null
        : _number(raw['gpuPercent']).clamp(0, 100);
    return _snapshot(
      platform: 'windows',
      target: '${raw['target'] ?? '本机 Windows'}',
      cpuPercent: cpu,
      logicalProcessors: _integer(raw['logicalProcessors']),
      memoryTotalBytes: total,
      memoryAvailableBytes: available,
      gpuNames: (raw['gpuNames'] as List? ?? const <Object?>[])
          .map((Object? value) => '$value')
          .where((String value) => value.isNotEmpty)
          .toList(),
      gpuPercent: gpu,
      gpuMemoryTotalBytes: _nullableInteger(raw['gpuMemoryTotalBytes']),
      gpuMemoryUsedBytes: _nullableInteger(raw['gpuMemoryUsedBytes']),
      storage: storage,
      processes: processes,
      evidence: const <String>[
        '.NET ComputerInfo',
        'Get-Process 两次采样',
        '.NET DriveInfo',
        'Windows Display Adapter 注册表',
      ],
    );
  }

  static SystemResourceSnapshot parseAndroidProbe(
    String source, {
    required String target,
  }) {
    String section(String name) {
      final RegExp expression = RegExp(
        '__${name}__\\s*([\\s\\S]*?)(?=__[A-Z0-9]+__|\$)',
      );
      return expression.firstMatch(source)?.group(1)?.trim() ?? '';
    }

    final Map<String, int> memory = <String, int>{};
    for (final String line in section('MEM').split(RegExp(r'\r?\n'))) {
      final Match? match = RegExp(r'^([^:]+):\s*(\d+)\s*kB').firstMatch(line);
      if (match != null) {
        memory[match.group(1)!] = int.parse(match.group(2)!) * 1024;
      }
    }
    final String loadText = section('LOAD');
    final double? load = double.tryParse(
      loadText.split(RegExp(r'\s+')).firstOrNull ?? '',
    );
    final int processors =
        int.tryParse(
          section('CORES').split(RegExp(r'\s+')).firstOrNull ?? '',
        ) ??
        1;
    final List<ResourceProcessSample> processes = _parseAndroidTop(
      section('TOP'),
    );
    final List<ResourceStorageSample> storage = _parseDf(section('DF'));
    final String gpuText = section('GPU');
    final double? gpu = double.tryParse(
      RegExp(r'(\d+(?:\.\d+)?)').firstMatch(gpuText)?.group(1) ?? '',
    );
    final String model =
        section('MODEL').split(RegExp(r'\r?\n')).firstOrNull ?? '';
    final double? sampledCpu = _androidCpuPercent(
      section('CPU1'),
      section('CPU2'),
    );
    return _snapshot(
      platform: 'android',
      target: model.isEmpty ? target : '$target · $model',
      cpuPercent:
          sampledCpu ??
          (load == null ? 0 : (load * 100 / processors).clamp(0, 100)),
      logicalProcessors: processors,
      loadAverage: load,
      memoryTotalBytes: memory['MemTotal'] ?? 0,
      memoryAvailableBytes:
          memory['MemAvailable'] ??
          ((memory['MemFree'] ?? 0) + (memory['Cached'] ?? 0)),
      gpuNames: const <String>[],
      gpuPercent: gpu?.clamp(0, 100),
      storage: storage,
      processes: processes,
      evidence: const <String>[
        '/proc/stat（两次采样）',
        '/proc/meminfo',
        '/proc/loadavg',
        'top',
        'df /data',
        'KGSL gpu_busy_percentage（设备支持时）',
      ],
    );
  }

  static Future<SystemResourceSnapshot> _inspectMac(
    ResourceProcessRunner runner,
  ) async {
    final List<ProcessResult> results = await Future.wait(
      <Future<ProcessResult>>[
        runner('/usr/sbin/sysctl', <String>[
          '-n',
          'hw.memsize',
          'hw.logicalcpu',
        ]),
        runner('/usr/bin/vm_stat', const <String>[]),
        runner('/bin/ps', <String>['-Ao', 'pid=,comm=,%cpu=,rss=', '-r']),
        runner('/bin/df', <String>['-k', '/']),
        runner('/usr/bin/uptime', const <String>[]),
      ],
    ).timeout(const Duration(seconds: 10));
    if (results.any((ProcessResult value) => value.exitCode != 0)) {
      throw StateError('macOS 资源探测失败');
    }
    final List<String> sysctl = '${results[0].stdout}'.trim().split(
      RegExp(r'\s+'),
    );
    final int total = int.tryParse(sysctl.firstOrNull ?? '') ?? 0;
    final int cores = int.tryParse(sysctl.length > 1 ? sysctl[1] : '') ?? 1;
    final String vm = '${results[1].stdout}';
    final int pageSize =
        int.tryParse(
          RegExp(r'page size of (\d+) bytes').firstMatch(vm)?.group(1) ?? '',
        ) ??
        4096;
    int pages(String label) =>
        int.tryParse(
          RegExp('$label:\\s+(\\d+)').firstMatch(vm)?.group(1) ?? '',
        ) ??
        0;
    final int available =
        (pages('Pages free') +
            pages('Pages inactive') +
            pages('Pages speculative')) *
        pageSize;
    final List<ResourceProcessSample> processes = <ResourceProcessSample>[];
    for (final String line
        in '${results[2].stdout}'.split(RegExp(r'\r?\n')).take(15)) {
      final Match? match = RegExp(
        r'^\s*(\d+)\s+(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s*$',
      ).firstMatch(line);
      if (match == null) continue;
      processes.add(
        ResourceProcessSample(
          pid: int.parse(match.group(1)!),
          name: match.group(2)!.trim(),
          cpuPercent: double.parse(match.group(3)!).clamp(0, 100),
          memoryBytes: int.parse(match.group(4)!) * 1024,
        ),
      );
    }
    final String uptime = '${results[4].stdout}';
    final double? load = double.tryParse(
      RegExp(r'load averages?:\s*([\d.]+)').firstMatch(uptime)?.group(1) ?? '',
    );
    return _snapshot(
      platform: 'macos',
      target: '本机 macOS',
      cpuPercent: load == null ? 0 : (load * 100 / cores).clamp(0, 100),
      logicalProcessors: cores,
      loadAverage: load,
      memoryTotalBytes: total,
      memoryAvailableBytes: available,
      gpuNames: const <String>[],
      storage: _parseDf('${results[3].stdout}'),
      processes: processes,
      evidence: const <String>['sysctl', 'vm_stat', 'ps', 'df', 'uptime'],
    );
  }

  static SystemResourceSnapshot _snapshot({
    required String platform,
    required String target,
    required double cpuPercent,
    required int logicalProcessors,
    double? loadAverage,
    required int memoryTotalBytes,
    required int memoryAvailableBytes,
    required List<String> gpuNames,
    double? gpuPercent,
    int? gpuMemoryTotalBytes,
    int? gpuMemoryUsedBytes,
    required List<ResourceStorageSample> storage,
    required List<ResourceProcessSample> processes,
    required List<String> evidence,
  }) {
    final List<String> warnings = <String>[];
    if (cpuPercent >= 90) warnings.add('CPU 持续接近满载，应结合 Top 进程连续采样。');
    final double memoryPercent = memoryTotalBytes <= 0
        ? 0
        : (memoryTotalBytes - memoryAvailableBytes) * 100 / memoryTotalBytes;
    if (memoryPercent >= 90) warnings.add('可用内存不足 10%，可能出现换页和界面卡顿。');
    if (gpuPercent != null && gpuPercent >= 95) {
      warnings.add('GPU 接近满载，需检查渲染、视频编解码或计算任务。');
    }
    for (final ResourceStorageSample disk in storage) {
      if (disk.totalBytes > 0 && disk.freeBytes / disk.totalBytes < 0.05) {
        warnings.add('${disk.name} 剩余不足 5%，会影响更新、编译和虚拟内存。');
      }
    }
    if (warnings.isEmpty) warnings.add('单次快照未发现明显资源瓶颈；间歇卡顿应连续采样。');
    return SystemResourceSnapshot(
      platform: platform,
      target: target,
      capturedAt: DateTime.now(),
      cpuPercent: cpuPercent,
      logicalProcessors: logicalProcessors,
      loadAverage: loadAverage,
      memoryTotalBytes: memoryTotalBytes,
      memoryAvailableBytes: memoryAvailableBytes.clamp(0, memoryTotalBytes),
      gpuNames: List<String>.unmodifiable(gpuNames),
      gpuPercent: gpuPercent,
      gpuMemoryTotalBytes: gpuMemoryTotalBytes,
      gpuMemoryUsedBytes: gpuMemoryUsedBytes,
      storage: List<ResourceStorageSample>.unmodifiable(storage),
      processes: List<ResourceProcessSample>.unmodifiable(processes),
      warnings: List<String>.unmodifiable(warnings),
      evidence: List<String>.unmodifiable(evidence),
    );
  }

  static List<ResourceProcessSample> _parseAndroidTop(String source) {
    final List<ResourceProcessSample> result = <ResourceProcessSample>[];
    for (final String line in source.split(RegExp(r'\r?\n'))) {
      final List<String> fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 4) continue;
      final int? pid = int.tryParse(fields.first);
      final int percentIndex = fields.indexWhere(
        (String value) => value.endsWith('%'),
      );
      if (pid == null || percentIndex < 0) continue;
      final double? cpu = double.tryParse(
        fields[percentIndex].replaceAll('%', ''),
      );
      if (cpu == null) continue;
      result.add(
        ResourceProcessSample(
          pid: pid,
          name: fields.last,
          cpuPercent: cpu.clamp(0, 100),
          memoryBytes: 0,
        ),
      );
      if (result.length >= 12) break;
    }
    return result;
  }

  static double? _androidCpuPercent(String first, String second) {
    List<int>? counters(String source) {
      final List<String> values = source.trim().split(RegExp(r'\s+'));
      if (values.length < 5 || values.first != 'cpu') return null;
      final List<int> parsed = <int>[];
      for (final String value in values.skip(1)) {
        final int? number = int.tryParse(value);
        if (number == null) return null;
        parsed.add(number);
      }
      return parsed;
    }

    final List<int>? before = counters(first);
    final List<int>? after = counters(second);
    if (before == null || after == null || before.length != after.length) {
      return null;
    }
    int totalDelta = 0;
    for (int index = 0; index < before.length; index += 1) {
      totalDelta += after[index] - before[index];
    }
    if (totalDelta <= 0) return null;
    final int idleBefore = before[3] + (before.length > 4 ? before[4] : 0);
    final int idleAfter = after[3] + (after.length > 4 ? after[4] : 0);
    return ((totalDelta - (idleAfter - idleBefore)) * 100 / totalDelta).clamp(
      0,
      100,
    );
  }

  static List<ResourceStorageSample> _parseDf(String source) {
    final List<ResourceStorageSample> result = <ResourceStorageSample>[];
    for (final String line in source.split(RegExp(r'\r?\n')).skip(1)) {
      final List<String> fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 5) continue;
      final int? totalKiB = int.tryParse(fields[1]);
      final int? availableKiB = int.tryParse(fields[3]);
      if (totalKiB == null || availableKiB == null) continue;
      result.add(
        ResourceStorageSample(
          name: fields.last,
          totalBytes: totalKiB * 1024,
          freeBytes: availableKiB * 1024,
        ),
      );
    }
    return result;
  }

  static int _integer(Object? value) => switch (value) {
    int number => number,
    num number => number.round(),
    _ => int.tryParse('$value') ?? 0,
  };

  static int? _nullableInteger(Object? value) =>
      value == null ? null : _integer(value);
  static double _number(Object? value) => switch (value) {
    num number => number.toDouble(),
    _ => double.tryParse('$value') ?? 0,
  };

  static const String _androidProbeScript = r'''
echo __MEM__; cat /proc/meminfo
echo __LOAD__; cat /proc/loadavg
echo __CORES__; getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c '^processor' /proc/cpuinfo
echo __CPU1__; head -n 1 /proc/stat; sleep 1
echo __CPU2__; head -n 1 /proc/stat
echo __TOP__; top -b -n 1 -o %CPU -m 12 2>/dev/null || top -n 1 -m 12 2>/dev/null
echo __DF__; df -k /data 2>/dev/null
echo __GPU__; cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null
echo __MODEL__; getprop ro.product.model
''';

  static const String _windowsProbeScript = r'''
$ErrorActionPreference='SilentlyContinue'
Add-Type -AssemblyName Microsoft.VisualBasic
$info=New-Object Microsoft.VisualBasic.Devices.ComputerInfo
$logical=[Math]::Max(1,[int]$env:NUMBER_OF_PROCESSORS)
$first=@{}
Get-Process | ForEach-Object {$first[$_.Id]=[double]$_.CPU}
$interval=0.45
Start-Sleep -Milliseconds 450
$samples=@()
$cpuTotal=0.0
Get-Process | ForEach-Object {
  $before=$first[$_.Id]
  $delta=if($null -eq $before){0}else{[Math]::Max(0,[double]$_.CPU-$before)}
  $percent=[Math]::Min(100,[Math]::Round($delta/$interval/$logical*100,1))
  $cpuTotal+=$percent
  $samples+=[pscustomobject]@{pid=[int]$_.Id;name=$_.ProcessName;cpuPercent=$percent;memoryBytes=[int64]$_.WorkingSet64}
}
$top=$samples | Sort-Object @{Expression={$_.cpuPercent};Descending=$true},@{Expression={$_.memoryBytes};Descending=$true} | Select-Object -First 15
$disks=[System.IO.DriveInfo]::GetDrives() | Where-Object {$_.DriveType -eq 'Fixed' -and $_.IsReady} | ForEach-Object {[pscustomobject]@{name=$_.Name.TrimEnd('\');totalBytes=[int64]$_.TotalSize;freeBytes=[int64]$_.AvailableFreeSpace}}
$videoKeys=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Video\*\0000' | Where-Object {$_.DriverDesc}
$gpuNames=@($videoKeys | ForEach-Object {$_.DriverDesc} | Select-Object -Unique)
$gpuMemory=($videoKeys | ForEach-Object {if($_.'HardwareInformation.MemorySize'){[int64]$_.'HardwareInformation.MemorySize'}else{0}} | Measure-Object -Sum).Sum
# GPU Engine performance counters are optional and can block indefinitely on
# machines where the provider is absent or rebuilding. Names and installed
# memory remain useful evidence; utilization is reported as unavailable so a
# secondary metric can never stall the complete physical resource snapshot.
[pscustomobject]@{target=$env:COMPUTERNAME;cpuPercent=[Math]::Min(100,[Math]::Round($cpuTotal,1));logicalProcessors=$logical;memoryTotalBytes=[int64]$info.TotalPhysicalMemory;memoryAvailableBytes=[int64]$info.AvailablePhysicalMemory;gpuNames=$gpuNames;gpuPercent=$null;gpuMemoryTotalBytes=if($gpuMemory){[int64]$gpuMemory}else{$null};gpuMemoryUsedBytes=$null;storage=@($disks);processes=@($top)} | ConvertTo-Json -Depth 5 -Compress
''';
}
