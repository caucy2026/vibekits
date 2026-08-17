import 'dart:async';
import 'dart:io';

enum AdbDeviceState { device, unauthorized, offline, unknown }

class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.model,
    this.product,
    this.device,
    this.transportId,
  });

  final String serial;
  final AdbDeviceState state;
  final String? model;
  final String? product;
  final String? device;
  final String? transportId;

  bool get ready => state == AdbDeviceState.device;
}

class AdbInstallation {
  const AdbInstallation({required this.executable, required this.version});

  final String executable;
  final String version;
}

class AdbSnapshot {
  const AdbSnapshot({required this.installation, required this.devices});

  final AdbInstallation installation;
  final List<AdbDevice> devices;
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

typedef AdbCommandRunner = Future<AdbCommandResult> Function(
  String executable,
  List<String> arguments,
);

abstract final class AdbService {
  static Future<AdbSnapshot> discoverAndList({
    String? preferredExecutable,
    AdbCommandRunner? runner,
  }) async {
    final AdbCommandRunner execute = runner ?? runCommand;
    final String executable = preferredExecutable?.trim().isNotEmpty == true
        ? File(preferredExecutable!).absolute.path
        : await _discoverExecutable(execute);
    final AdbInstallation installation = await inspectExecutable(
      executable,
      runner: execute,
    );
    final List<AdbDevice> devices = await listDevices(
      installation.executable,
      runner: execute,
    );
    return AdbSnapshot(installation: installation, devices: devices);
  }

  static Future<AdbInstallation> inspectExecutable(
    String executable, {
    AdbCommandRunner? runner,
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
    final AdbCommandResult result = await (runner ?? runCommand)(path, <String>[
      'version',
    ]);
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
  }) async {
    final AdbCommandResult result = await (runner ?? runCommand)(
      executable,
      <String>['devices', '-l'],
    );
    if (result.exitCode != 0) {
      throw StateError(_commandError('刷新 ADB 设备失败', result));
    }
    return parseDevices(result.stdout);
  }

  static List<AdbDevice> parseDevices(String source) {
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
        ),
      );
    }
    return result;
  }

  static Future<AdbCommandResult> runCommand(
    String executable,
    List<String> arguments,
  ) async {
    final Process process = await Process.start(
      executable,
      arguments,
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
      exitCode = await process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill();
      throw StateError('ADB 命令 10 秒未完成，已终止');
    }
    return AdbCommandResult(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  }

  static Future<String> _discoverExecutable(AdbCommandRunner runner) async {
    final List<String> candidates = <String>[
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
    throw StateError('未找到官方 ADB。请安装 Android SDK Platform-Tools，或在设置中选择 adb。');
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
