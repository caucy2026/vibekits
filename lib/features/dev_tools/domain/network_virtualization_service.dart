import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BundledRuntimeStatus {
  const BundledRuntimeStatus({
    required this.name,
    required this.executable,
    required this.available,
    required this.version,
  });

  final String name;
  final String executable;
  final bool available;
  final String version;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'executable': executable,
    'available': available,
    'version': version,
  };
}

class ManagedToolProcess {
  ManagedToolProcess(this.process, this.label) {
    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_append);
    stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_append);
    exitCode = process.exitCode.then((int code) {
      _append('$label 已退出（代码 $code）');
      return code;
    });
  }

  final Process process;
  final String label;
  late final StreamSubscription<String> stdoutSubscription;
  late final StreamSubscription<String> stderrSubscription;
  late final Future<int> exitCode;
  final List<String> _lines = <String>[];

  bool get running => process.pid > 0;
  List<String> get lines => List<String>.unmodifiable(_lines);

  void _append(String line) {
    _lines.add(line);
    if (_lines.length > 500) _lines.removeRange(0, _lines.length - 500);
  }

  Future<void> stop() async {
    process.kill();
    try {
      await exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}

/// Self-contained process boundary for the bundled Mihomo and QEMU runtimes.
/// No command is routed through a shell and all user paths are passed as
/// individual process arguments.
abstract final class NetworkVirtualizationService {
  static ManagedToolProcess? _mihomo;
  static ManagedToolProcess? _qemu;

  static String get _toolRoot =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tools';

  static String get mihomoExecutable =>
      '$_toolRoot${Platform.pathSeparator}'
      'mihomo${Platform.pathSeparator}${Platform.isWindows ? 'mihomo.exe' : 'mihomo'}';

  static String get qemuExecutable =>
      '$_toolRoot${Platform.pathSeparator}'
      'qemu${Platform.pathSeparator}${Platform.isWindows ? 'qemu-system-x86_64.exe' : 'qemu-system-x86_64'}';

  static String get qemuImgExecutable =>
      '$_toolRoot${Platform.pathSeparator}'
      'qemu${Platform.pathSeparator}${Platform.isWindows ? 'qemu-img.exe' : 'qemu-img'}';

  static Future<BundledRuntimeStatus> inspectMihomo() =>
      _inspect('Clash Verge（Mihomo）', mihomoExecutable, <String>['-v']);

  static Future<BundledRuntimeStatus> inspectQemu() =>
      _inspect('QEMU', qemuExecutable, <String>['--version']);

  static Future<BundledRuntimeStatus> _inspect(
    String name,
    String executable,
    List<String> arguments,
  ) async {
    final File file = File(executable);
    if (!await file.exists()) {
      return BundledRuntimeStatus(
        name: name,
        executable: executable,
        available: false,
        version: '发布包未包含运行时',
      );
    }
    try {
      final ProcessResult result = await Process.run(
        executable,
        arguments,
      ).timeout(const Duration(seconds: 4));
      final String text = '${result.stdout}\n${result.stderr}'.trim();
      return BundledRuntimeStatus(
        name: name,
        executable: executable,
        available: result.exitCode == 0,
        version: text.split(RegExp(r'[\r\n]+')).firstOrNull ?? '未知版本',
      );
    } on Object catch (error) {
      return BundledRuntimeStatus(
        name: name,
        executable: executable,
        available: false,
        version: '运行失败：$error',
      );
    }
  }

  static Future<ManagedToolProcess> startMihomo({
    required String configPath,
    required String dataDirectory,
  }) async {
    if (_mihomo != null) throw StateError('Mihomo 已在运行');
    final File config = File(configPath).absolute;
    if (!await config.exists()) throw StateError('配置文件不存在');
    if (!RegExp(r'\.(ya?ml)$', caseSensitive: false).hasMatch(config.path)) {
      throw const FormatException('Clash 配置必须是 YAML 文件');
    }
    if (!await File(mihomoExecutable).exists()) {
      throw StateError('发布包缺少 Mihomo 运行时：$mihomoExecutable');
    }
    final Directory data = Directory(dataDirectory).absolute;
    await data.create(recursive: true);
    final Process process = await Process.start(
      mihomoExecutable,
      <String>['-d', data.path, '-f', config.path],
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    final ManagedToolProcess managed = ManagedToolProcess(process, 'Mihomo');
    _mihomo = managed;
    unawaited(
      managed.exitCode.whenComplete(() {
        if (identical(_mihomo, managed)) _mihomo = null;
      }),
    );
    return managed;
  }

  static Future<void> stopMihomo() async {
    final ManagedToolProcess? current = _mihomo;
    _mihomo = null;
    if (current != null) await current.stop();
  }

  static Future<ManagedToolProcess> startQemu({
    String? diskPath,
    String? isoPath,
    int memoryMiB = 2048,
    int cpuCount = 2,
  }) async {
    if (_qemu != null) throw StateError('虚拟机已在运行');
    if (diskPath?.trim().isEmpty != false && isoPath?.trim().isEmpty != false) {
      throw const FormatException('请选择虚拟磁盘或安装镜像');
    }
    if (!await File(qemuExecutable).exists()) {
      throw StateError('发布包缺少 QEMU 运行时：$qemuExecutable');
    }
    final List<String> arguments = <String>[
      '-name',
      'Vibekits VM',
      '-m',
      memoryMiB.clamp(256, 32768).toString(),
      '-smp',
      cpuCount.clamp(1, 16).toString(),
      '-boot',
      'menu=on',
      '-nic',
      'user,model=e1000',
      '-usb',
      '-device',
      'usb-tablet',
    ];
    if (diskPath?.trim().isNotEmpty == true) {
      final File disk = File(diskPath!).absolute;
      if (!await disk.exists()) throw StateError('虚拟磁盘不存在');
      arguments.addAll(<String>['-hda', disk.path]);
    }
    if (isoPath?.trim().isNotEmpty == true) {
      final File iso = File(isoPath!).absolute;
      if (!await iso.exists()) throw StateError('安装镜像不存在');
      arguments.addAll(<String>['-cdrom', iso.path]);
    }
    final Process process = await Process.start(
      qemuExecutable,
      arguments,
      workingDirectory: File(qemuExecutable).parent.path,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    final ManagedToolProcess managed = ManagedToolProcess(process, 'QEMU');
    _qemu = managed;
    unawaited(
      managed.exitCode.whenComplete(() {
        if (identical(_qemu, managed)) _qemu = null;
      }),
    );
    return managed;
  }

  static Future<void> stopQemu() async {
    final ManagedToolProcess? current = _qemu;
    _qemu = null;
    if (current != null) await current.stop();
  }

  static Map<String, Object?> status() => <String, Object?>{
    'mihomoRunning': _mihomo != null,
    'mihomoPid': _mihomo?.process.pid,
    'mihomoLog': _mihomo?.lines ?? const <String>[],
    'qemuRunning': _qemu != null,
    'qemuPid': _qemu?.process.pid,
    'qemuLog': _qemu?.lines ?? const <String>[],
  };
}
