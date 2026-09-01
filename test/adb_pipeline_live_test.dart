import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  const String target = String.fromEnvironment('VIBEKITS_LIVE_ADB_TARGET');
  const String executable = String.fromEnvironment(
    'VIBEKITS_LIVE_ADB_EXECUTABLE',
  );

  test(
    '真实设备通过 Harness 规范化 dumpsys grep 且单次成功',
    () async {
      final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
        adbExecutable: executable,
      );
      final HarnessToolCallResult connected = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.adbConnectId,
        arguments: const <String, Object?>{'address': target},
        approve: (_) async => true,
      );
      expect(connected.ok, isTrue, reason: connected.error);

      final HarnessToolCallResult result = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.adbShellId,
        arguments: const <String, Object?>{
          'serial': target,
          'arguments': <String>[
            'dumpsys',
            'display',
            '|',
            'grep',
            '-E',
            r'DisplayDeviceInfo|mDisplayId|DisplayDeviceInfo\("Built-in size',
          ],
        },
        approve: (_) async => true,
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(result.data?['pipelineNormalized'], isTrue);
      expect((result.data?['stdout'] ?? '').toString(), isNotEmpty);
      expect(result.data?['executedArguments'], <String>[
        'shell',
        'dumpsys',
        'display',
      ]);
    },
    skip: target.isEmpty || executable.isEmpty
        ? '需要真实 ADB 目标和 Release 内置 ADB 路径'
        : false,
  );
}
