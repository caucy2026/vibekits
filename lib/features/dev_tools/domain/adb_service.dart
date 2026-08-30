import 'dart:async';
import 'dart:io';

import 'adb_server_endpoint.dart';
import 'harness_tool_activity_store.dart';

enum AdbDeviceState { device, unauthorized, offline, unknown }

class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.model,
    this.product,
    this.device,
    this.transportId,
    this.source = const AdbDeviceSource(endpoint: AdbServerEndpoint.local()),
  });

  final String serial;
  final AdbDeviceState state;
  final String? model;
  final String? product;
  final String? device;
  final String? transportId;
  final AdbDeviceSource source;

  bool get ready => state == AdbDeviceState.device;

  AdbDevice withSource(AdbServerEndpoint endpoint) => AdbDevice(
    serial: serial,
    state: state,
    model: model,
    product: product,
    device: device,
    transportId: transportId,
    source: AdbDeviceSource(endpoint: endpoint),
  );
}

class AdbInstallation {
  const AdbInstallation({required this.executable, required this.version});

  final String executable;
  final String version;
}

class AdbSnapshot {
  const AdbSnapshot({
    required this.installation,
    required this.devices,
    this.endpoint = const AdbServerEndpoint.local(),
  });

  final AdbInstallation installation;
  final List<AdbDevice> devices;
  final AdbServerEndpoint endpoint;

  AdbSnapshot withEndpoint(AdbServerEndpoint value) => AdbSnapshot(
    installation: installation,
    devices: <AdbDevice>[
      for (final AdbDevice device in devices) device.withSource(value),
    ],
    endpoint: value,
  );
}

class AdbCommandResult {
  const AdbCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class AdbCommandAudit {
  const AdbCommandAudit({
    required this.toolId,
    required this.toolName,
    required this.target,
    this.recorder,
  });

  final String toolId;
  final String toolName;
  final String target;
  final HarnessToolActivityRecorder? recorder;
}

typedef AdbCommandRunner = Future<AdbCommandResult> Function(
  String executable,
  List<String> arguments,
);

abstract final class AdbService {
  static String bundledExecutablePath() {
    final String executableDirectory = File(Platform.resolvedExecutable)
        .parent
        .path;
    return '$executableDirectory${Platform.pathSeparator}tools'
        '${Platform.pathSeparator}adb${Platform.pathSeparator}'
        '${Platform.isWindows ? 'adb.exe' : 'adb'}';
  }

  static Future<AdbSnapshot> discoverAndList({
    String? preferredExecutable,
    AdbCommandRunner? runner,
    AdbCommandAudit? listAudit,
    AdbServerEndpoint endpoint = const AdbServerEndpoint.local(),
  }) async {
    final AdbCommandRunner execute = runner ?? runCommand;
    final String executable = preferredExecutable?.trim().isNotEmpty == true
        ? File(preferredExecutable!).absolute.path
        : await _discoverExecutable(execute);
    final AdbInstallation installation = await inspectExecutable(
      executable,
      runner: execute,
      endpoint: endpoint,
    );
    final List<AdbDevice> devices = await listDevices(
      installation.executable,
      runner: runner,
      audit: runner == null ? listAudit : null,
      endpoint: endpoint,
    );
    return AdbSnapshot(
      installation: installation,
      devices: devices,
      endpoint: endpoint,
    );
  }

  static Future<AdbInstallation> inspectExecutable(
    String executable, {
    AdbCommandRunner? runner,
    AdbServerEndpoint endpoint = const AdbServerEndpoint.local(),
  }) async {
    final String path = File(executable).absolute.path;
    final String basename = path
        .split(Platform.pathSeparator)
        .last
        .toLowerCase();
    if (basename != 'adb' && basename != 'adb.exe') {
      throw const FormatException('请选择官方 Platform-Tools 中的 adb 可执行文件');
    }
    if (!await File(path).exists()) {
      throw StateError('ADB 不存在：$path');
    }
    final AdbCommandResult result = runner == null
        ? await runCommand(path, const <String>['version'], endpoint: endpoint)
        : await runner(path, endpoint.applyTo(const <String>['version']));
    if (result.exitCode != 0) {
      throw StateError(_commandError('读取 ADB 版本失败', result));
    }
    final RegExpMatch? match = RegExp(
      r'Android Debug Bridge version\s+([^\s]+)',
      caseSensitive: false,
    ).firstMatch(result.stdout);
    if (match == null) throw StateError('无法识别 ADB 版本输出');
    return AdbInstallation(executable: path, version: match.group(1)!);
  }

  static Future<List<AdbDevice>> listDevices(
    String executable, {
    AdbCommandRunner? runner,
    AdbCommandAudit? audit,
    AdbServerEndpoint endpoint = const AdbServerEndpoint.local(),
  }) async {
    final AdbCommandResult result = runner == null
        ? await runCommand(
            executable,
            const <String>['devices', '-l'],
            audit: audit,
            endpoint: endpoint,
          )
        : await runner(
            executable,
            endpoint.applyTo(const <String>['devices', '-l']),
          );
    if (result.exitCode != 0) {
      throw StateError(_commandError('刷新 ADB 设备失败', result));
    }
    return parseDevices(result.stdout, endpoint: endpoint);
  }

  static Future<String> connect(
    String executable,
    String address, {
    AdbCommandRunner? runner,
    AdbCommandAudit? audit,
    AdbServerEndpoint endpoint = const AdbServerEndpoint.local(),
  }) async {
    final String target = normalizeWirelessAddress(address);
    final AdbCommandResult result = runner == null
        ? await runCommand(
            executable,
            <String>['connect', target],
            audit: audit,
            endpoint: endpoint,
          )
        : await runner(
            executable,
            endpoint.applyTo(<String>['connect', target]),
          );
    final String output = '${result.stdout}\n${result.stderr}'.trim();
    if (result.exitCode != 0 ||
        (!output.toLowerCase().contains('connected to') &&
            !output.toLowerCase().contains('already connected'))) {
      throw StateError(
        output.isEmpty ? '连接 ADB 设备失败（exit ${result.exitCode}）' : output,
      );
    }
    return output;
  }

  static String normalizeWirelessAddress(String value) {
    String address = value.trim();
    if (address.isEmpty || address.contains(RegExp(r'[\s/\\]'))) {
      throw const FormatException('请输入设备 IP，例如 192.168.3.63');
    }
    final int? hostAlias = int.tryParse(address);
    if (hostAlias != null && hostAlias >= 1 && hostAlias <= 254) {
      address = '192.168.3.$hostAlias';
    }
    final int colonCount = ':'.allMatches(address).length;
    final String target = colonCount == 0 ? '$address:5555' : address;
    final RegExpMatch? match = RegExp(r'^([A-Za-z0-9.-]+):(\d{1,5})$')
        .firstMatch(target);
    if (match == null) throw const FormatException('设备地址格式无效');
    final int port = int.parse(match.group(2)!);
    if (port < 1 || port > 65535) throw const FormatException('ADB 端口无效');
    return target;
  }

  static List<String> parseUserCommand(String source) {
    final String input = source.trim();
    if (input.isEmpty) throw const FormatException('请输入 ADB 命令');
    final List<String> arguments = <String>[];
    final StringBuffer current = StringBuffer();
    String? quote;
    void commit() {
      if (current.isEmpty) return;
      arguments.add(current.toString());
      current.clear();
    }

    for (final int rune in input.runes) {
      final String character = String.fromCharCode(rune);
      if (quote != null) {
        if (character == quote) {
          quote = null;
        } else {
          current.write(character);
        }
      } else if (character == '"' || character == "'") {
        quote = character;
      } else if (character.trim().isEmpty) {
        commit();
      } else {
        current.write(character);
      }
    }
    if (quote != null) throw const FormatException('命令中的引号没有闭合');
    commit();
    if (arguments.isEmpty) throw const FormatException('请输入 ADB 命令');
    final String operation = arguments.first.toLowerCase();
    if (const <String>{'-s', '-d', '-e'}.contains(operation)) {
      throw const FormatException('设备已由列表锁定，不要在命令中再次指定设备');
    }
    if (const <String>{
      'start-server',
      'kill-server',
      'server',
      'connect',
      'disconnect',
    }.contains(operation)) {
      throw const FormatException('该管理命令请使用页面上的连接或刷新操作');
    }
    const Set<String> adbOperations = <String>{
      'shell',
      'exec-out',
      'install',
      'uninstall',
      'push',
      'pull',
      'logcat',
      'bugreport',
      'reboot',
      'root',
      'unroot',
      'remount',
      'forward',
      'reverse',
      'tcpip',
      'sync',
      'sideload',
      'emu',
    };
    return adbOperations.contains(operation)
        ? arguments
        : <String>['shell', ...arguments];
  }

  static List<AdbDevice> parseDevices(
    String source, {
    AdbServerEndpoint endpoint = const AdbServerEndpoint.local(),
  }) {
    final List<AdbDevice> result = <AdbDevice>[];
    for (final String raw in source.split(RegExp(r'\r?\n'))) {
      final String line = raw.trim();
      if (line.isEmpty || line.startsWith('List of devices attached')) continue;
      final List<String> fields = line.split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      final Map<String, String> metadata = <String, String>{};
      for (final String field in fields.skip(2)) {
        final int separator = field.indexOf(':');
        if (separator <= 0) continue;
        metadata[field.substring(0, separator)] = field.substring(
          separator + 1,
        );
      }
      result.add(
        AdbDevice(
          serial: fields[0],
          state: switch (fields[1]) {
            'device' => AdbDeviceState.device,
            'unauthorized' => AdbDeviceState.unauthorized,
            'offline' => AdbDeviceState.offline,
            _ => AdbDeviceState.unknown,
          },
          model: metadata['model'],
          product: metadata['product'],
          device: metadata['device'],
          transportId: metadata['transport_id'],
          source: AdbDeviceSource(endpoint: endpoint),
        ),
      );
    }
    return result;
  }

  static Future<AdbCommandResult> runCommand(
    String executable,
    List<String> arguments, {
    AdbCommandAudit? audit,
    Duration timeout = const Duration(seconds: 10),
    AdbServerEndpoint endpoint = const AdbServerEndpoint.local(),
  }) async {
    final DateTime startedAt = DateTime.now();
    final List<String> effectiveArguments = endpoint.applyTo(arguments);
    final Process process = await Process.start(
      executable,
      effectiveArguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final Future<String> stdout = process.stdout
        .transform(systemEncoding.decoder)
        .join();
    final Future<String> stderr = process.stderr
        .transform(systemEncoding.decoder)
        .join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw StateError('ADB 命令 ${timeout.inSeconds} 秒未完成，已终止');
    }
    final AdbCommandResult result = AdbCommandResult(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
    if (audit != null) {
      await (audit.recorder ?? HarnessToolActivityStore.record)(
        toolId: audit.toolId,
        toolName: audit.toolName,
        target: audit.target,
        arguments: <String, Object?>{
          'executable': File(executable).absolute.path,
          'arguments': List<String>.unmodifiable(effectiveArguments),
          'adbServer': endpoint.toAuditFields(),
        },
        result: <String, Object?>{
          'exitCode': result.exitCode,
          'stdout': result.stdout,
          'stderr': result.stderr,
          'evidenceSource': 'adb-process',
        },
        status: result.exitCode == 0
            ? HarnessToolActivityStatus.succeeded
            : HarnessToolActivityStatus.failed,
        startedAt: startedAt,
      );
    }
    return result;
  }

  static Future<String> _discoverExecutable(AdbCommandRunner runner) async {
    final List<String> candidates = <String>[
      bundledExecutablePath(),
      for (final String? root in <String?>[
        Platform.environment['ANDROID_SDK_ROOT'],
        Platform.environment['ANDROID_HOME'],
      ])
        if (root?.trim().isNotEmpty == true)
          '${root!.trim()}${Platform.pathSeparator}platform-tools${Platform.pathSeparator}${Platform.isWindows ? 'adb.exe' : 'adb'}',
    ];
    for (final String candidate in candidates) {
      if (await File(candidate).exists()) return File(candidate).absolute.path;
    }
    final String locator = Platform.isWindows ? 'where.exe' : 'which';
    final AdbCommandResult located = await runner(locator, <String>['adb']);
    if (located.exitCode == 0) {
      final String first = located.stdout
          .split(RegExp(r'\r?\n'))
          .map((String value) => value.trim())
          .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
      if (first.isNotEmpty && await File(first).exists()) {
        return File(first).absolute.path;
      }
    }
    throw StateError('应用内置 ADB 不完整，请重新安装 Vibekits。');
  }
}

String _commandError(String prefix, AdbCommandResult result) {
  final String detail = result.stderr.trim().isNotEmpty
      ? result.stderr.trim()
      : result.stdout.trim();
  return detail.isEmpty
      ? '$prefix（exit ${result.exitCode}）'
      : '$prefix：$detail';
}
