import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/mihomo_controller_service.dart';
import 'package:vibekits/features/dev_tools/domain/network_virtualization_service.dart';
import 'package:vibekits/features/dev_tools/domain/system_proxy_service.dart';

void main() {
  const String release = String.fromEnvironment('VIBEKITS_LIVE_RELEASE');
  final bool enabled = Platform.isWindows && release.trim().isNotEmpty;

  test('Harness 用内置 Mihomo/QEMU 完成系统代理恢复与虚拟机启停', () async {
    final Directory evidence = Directory(
      '${Directory.current.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}acceptance${Platform.pathSeparator}network-vm',
    );
    await evidence.create(recursive: true);
    final String config =
        '${Directory.current.path}${Platform.pathSeparator}test'
        '${Platform.pathSeparator}fixtures${Platform.pathSeparator}'
        'mihomo_direct_acceptance.yaml';
    final String disk = '${evidence.path}${Platform.pathSeparator}smoke.qcow2';
    if (await File(disk).exists()) await File(disk).delete();
    final SystemProxyService proxy = SystemProxyService();
    final SystemProxySnapshot before = await proxy.inspect();
    Future<void> noLifecycle(int _) async {}
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      runtimeToolRoot: '$release${Platform.pathSeparator}tools',
      runtimeBindProcessTree: noLifecycle,
      runtimeReleaseProcessTree: noLifecycle,
    );
    Future<Map<String, Object?>> invoke(
      String toolId,
      Map<String, Object?> arguments,
    ) async {
      final HarnessToolCallResult result = await bridge.invoke(
        toolId: toolId,
        arguments: arguments,
        approve: (_) async => true,
      );
      if (!result.ok) throw StateError('$toolId 失败：${result.error}');
      return result.data ?? const <String, Object?>{};
    }

    try {
      await invoke(VibekitsHarnessToolBridge.proxyStartId, <String, Object?>{
        'configPath': config,
        'dataDirectory': evidence.path,
        'systemProxyPort': 17890,
      });
      for (final String name in const <String>[
        'Country.mmdb',
        'geoip.dat',
        'geosite.dat',
      ]) {
        expect(
          File('${evidence.path}${Platform.pathSeparator}$name').existsSync(),
          isTrue,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final Socket socket = await Socket.connect(
        '127.0.0.1',
        17890,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      final MihomoControllerService controller = MihomoControllerService(
        Uri.parse('http://127.0.0.1:19090'),
      );
      expect((await controller.snapshot()).mode, 'direct');
      await controller.setMode('rule');
      expect((await controller.snapshot()).mode, 'rule');
      final SystemProxySnapshot applied = await proxy.inspect();
      expect(applied.enabled, isTrue);
      expect(applied.server, '127.0.0.1:17890');

      final Map<String, Object?> created = await invoke(
        VibekitsHarnessToolBridge.vmCreateDiskId,
        <String, Object?>{'path': disk, 'sizeGiB': 1},
      );
      expect(created['format'], 'qcow2');
      await invoke(VibekitsHarnessToolBridge.vmStartId, <String, Object?>{
        'diskPath': disk,
        'memoryMiB': 256,
        'cpuCount': 1,
        'headless': true,
      });
      await Future<void>.delayed(const Duration(seconds: 1));
      final Map<String, Object?> status = await invoke(
        VibekitsHarnessToolBridge.runtimeStatusId,
        const <String, Object?>{},
      );
      expect(status['mihomoRunning'], isTrue);
      expect(status['qemuRunning'], isTrue);
    } finally {
      await invoke(
        VibekitsHarnessToolBridge.vmStopId,
        const <String, Object?>{},
      );
      await invoke(VibekitsHarnessToolBridge.proxyStopId, <String, Object?>{
        'dataDirectory': evidence.path,
      });
      await proxy.restore(dataDirectory: evidence.path);
      await NetworkVirtualizationService.stopAll();
    }
    final SystemProxySnapshot restored = await proxy.inspect();
    expect(restored.enabled, before.enabled);
    expect(restored.server, before.server);
    expect(restored.bypass, before.bypass);
  }, skip: enabled ? false : '设置 VIBEKITS_LIVE_RELEASE 后执行真实运行时验收');
}
