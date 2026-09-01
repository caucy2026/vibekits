import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_directory.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';

void main() {
  const String target = String.fromEnvironment('VIBEKITS_LIVE_LMCP_INSTANCE');

  test(
    '真实 LMCP 节点可晚发现、验签目录并调用只读工具',
    () async {
      final LanPeerDiscoveryService discovery = LanPeerDiscoveryService();
      final McpCapabilityDirectory directory = McpCapabilityDirectory(
        discoveryService: discovery,
      );
      addTearDown(directory.dispose);
      addTearDown(discovery.stop);

      await discovery.start(
        instanceId: 'com.vibekits.acceptance:READONLY01',
        name: 'VibeKits acceptance observer',
        capabilityDigest: 'readonly-live-acceptance',
        exposureEnabled: false,
      );
      await directory.start(appBridge: VibekitsHarnessToolBridge());

      McpDeviceCapability? device;
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        final List<McpDeviceCapability> matches = directory.snapshot.lan
            .where((McpDeviceCapability item) => item.id == target)
            .toList(growable: false);
        if (matches.isNotEmpty &&
            matches.single.callable &&
            matches.single.tools.any(
              (McpToolInterface tool) =>
                  tool.name == 'kemi.benchmark.last_result',
            )) {
          device = matches.single;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      expect(device, isNotNull, reason: '目标节点未在 20 秒内成为可调用目录');
      final Map<String, Object?> result = await directory.invokeLanTool(
        instanceId: target,
        toolName: 'kemi.benchmark.last_result',
      );
      final Object? structured = result['structuredContent'];
      expect(structured, isA<Map<Object?, Object?>>());
      expect(jsonEncode(structured), isNot(contains('AUTH_SCOPE_REQUIRED')));

      // Keep CI output useful without logging endpoint credentials or TLS
      // material. The structured business evidence remains asserted above.
      // ignore: avoid_print
      print(
        jsonEncode(<String, Object?>{
          'instanceId': device!.id,
          'appVersion': device.appVersion,
          'catalogRevision': device.catalogRevision,
          'toolName': 'kemi.benchmark.last_result',
          'callable': device.callable,
          'structuredContent': structured,
        }),
      );
    },
    skip: target.isEmpty
        ? '设置 VIBEKITS_LIVE_LMCP_INSTANCE 后执行真实只读 LMCP 验收'
        : false,
  );
}
