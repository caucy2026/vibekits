import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

void main() {
  test(
    'network virtualization ToolSpec and Harness contracts stay aligned',
    () {
      final ToolSpec spec = allDevToolRegistry.singleWhere(
        (ToolSpec value) => value.id == 'network_virtualization',
      );
      final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
      final Set<String> catalog = bridge.executableCatalog
          .map((HarnessToolDefinition value) => value.id)
          .toSet();
      expect(spec.harnessToolIds, isNotEmpty);
      expect(catalog, containsAll(spec.harnessToolIds));
      expect(
        spec.harnessToolIds,
        containsAll(<String>[
          'vibekits.proxy.system_apply',
          'vibekits.proxy.system_restore',
          'vibekits.vm.create_disk',
        ]),
      );
      expect(devToolRegistry[1].id, 'network_virtualization');
    },
  );

  test('runtime status is a real executable Harness call', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.runtimeStatusId,
      arguments: const <String, Object?>{},
      approve: (_) async => true,
    );
    expect(result.ok, isTrue);
    expect(result.data, containsPair('mihomoRunning', false));
    expect(result.data, containsPair('qemuRunning', false));
  });
}
