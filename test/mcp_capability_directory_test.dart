import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_directory.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';

void main() {
  test('实时目录读取本机提供者并保持三层 Harness 查询顺序', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-directory-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
    );
    addTearDown(directory.dispose);

    await File('${root.path}${Platform.pathSeparator}vendor.json')
        .writeAsString(
          jsonEncode(<String, Object?>{
            'instanceId': 'vendor-01',
            'name': 'Vendor MCP',
            'appId': 'com.vendor.mcp',
            'appVersion': '2.1.0',
            'transport': 'stdio',
            'endpoint': r'D:\apps\vendor-mcp.exe',
            'catalogRevision': 'sha256:one',
            'tools': <Object?>[
              <String, Object?>{
                'name': 'vendor.lookup',
                'title': '查询设备',
                'description': '按设备 ID 查询实时状态。',
                'inputSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'deviceId': <String, Object?>{'type': 'string'},
                  },
                  'required': <String>['deviceId'],
                },
              },
            ],
          }),
        );

    await directory.start(appBridge: VibekitsHarnessToolBridge());
    final McpCapabilitySnapshot snapshot = await directory.snapshotForTask();

    expect(snapshot.app, hasLength(1));
    expect(snapshot.local, hasLength(1));
    expect(snapshot.local.single.tools.single.name, 'vendor.lookup');
    expect(snapshot.local.single.tools.single.inputSchema['required'], <String>[
      'deviceId',
    ]);
    expect(snapshot.inHarnessSearchOrder.first.tier, McpCapabilityTier.app);
    expect(snapshot.inHarnessSearchOrder[1].tier, McpCapabilityTier.local);
  });

  test('非法或不完整注册文件不会进入工具目录', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-invalid-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
    );
    addTearDown(directory.dispose);
    await File('${root.path}${Platform.pathSeparator}broken.json')
        .writeAsString('{broken');
    await File('${root.path}${Platform.pathSeparator}missing-tools.json')
        .writeAsString(jsonEncode(<String, Object?>{'instanceId': 'x'}));

    await directory.start(appBridge: VibekitsHarnessToolBridge());
    expect(directory.snapshot.local, isEmpty);
  });
}
