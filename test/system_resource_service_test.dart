import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/system_resource_service.dart';

void main() {
  test('Windows 资源快照保留真实容量并生成瓶颈提示', () {
    final SystemResourceSnapshot snapshot =
        SystemResourceService.parseWindowsJson(<String, Object?>{
          'target': 'DEV-PC',
          'cpuPercent': 96,
          'logicalProcessors': 16,
          'memoryTotalBytes': 16 * 1024 * 1024 * 1024,
          'memoryAvailableBytes': 1024 * 1024 * 1024,
          'gpuNames': <String>['Test GPU'],
          'gpuPercent': 97,
          'storage': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'C:',
              'totalBytes': 100 * 1024 * 1024 * 1024,
              'freeBytes': 3 * 1024 * 1024 * 1024,
            },
          ],
          'processes': <Map<String, Object?>>[
            <String, Object?>{
              'pid': 42,
              'name': 'compiler',
              'cpuPercent': 80,
              'memoryBytes': 2 * 1024 * 1024 * 1024,
            },
          ],
        });

    expect(snapshot.target, 'DEV-PC');
    expect(snapshot.memoryUsedPercent, closeTo(93.75, 0.01));
    expect(snapshot.processes.single.name, 'compiler');
    expect(snapshot.warnings.join(), contains('CPU'));
    expect(snapshot.warnings.join(), contains('内存'));
    expect(snapshot.warnings.join(), contains('GPU'));
    expect(snapshot.warnings.join(), contains('C:'));
  });

  test('Android 使用 proc/stat 两点采样并解析内存磁盘与进程', () {
    final SystemResourceSnapshot snapshot =
        SystemResourceService.parseAndroidProbe('''
__MEM__
MemTotal:       8000000 kB
MemAvailable:   2000000 kB
__LOAD__
4.00 3.00 2.00 1/100 1
__CORES__
8
__CPU1__
cpu  100 0 100 800 0 0 0 0
__CPU2__
cpu  150 0 150 900 0 0 0 0
__TOP__
123 root 45% S 1 1 com.example.busy
__DF__
Filesystem 1K-blocks Used Available Use% Mounted on
/dev/block/data 10000000 9000000 1000000 90% /data
__GPU__
72
__MODEL__
Pixel Test
''', target: '192.168.3.63:5555');

    expect(snapshot.platform, 'android');
    expect(snapshot.target, contains('Pixel Test'));
    expect(snapshot.cpuPercent, closeTo(50, 0.01));
    expect(snapshot.memoryUsedPercent, closeTo(75, 0.01));
    expect(snapshot.gpuPercent, 72);
    expect(snapshot.storage.single.freeBytes, 1000000 * 1024);
    expect(snapshot.processes.single.name, 'com.example.busy');
    expect(snapshot.evidence.first, contains('/proc/stat'));
  });

  test(
    'Windows 本机只读探测返回可信范围',
    () async {
      final SystemResourceSnapshot snapshot =
          await SystemResourceService.inspectLocal();
      expect(snapshot.platform, 'windows');
      expect(snapshot.logicalProcessors, greaterThan(0));
      expect(snapshot.memoryTotalBytes, greaterThan(0));
      expect(
        snapshot.memoryAvailableBytes,
        lessThanOrEqualTo(snapshot.memoryTotalBytes),
      );
      expect(snapshot.cpuPercent, inInclusiveRange(0, 100));
      expect(snapshot.storage, isNotEmpty);
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 35)),
  );

  test(
    '切走或退出资源页会终止仍在运行的 Windows 探针',
    () async {
      final SystemResourceProbeController controller =
          SystemResourceProbeController();
      final Future<ProcessResult> running = controller.run(
        'powershell.exe',
        const <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Sleep -Seconds 30',
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.cancel();
      final ProcessResult result = await running.timeout(
        const Duration(seconds: 3),
      );
      expect(result.exitCode, isNot(0));
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
