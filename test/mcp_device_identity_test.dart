import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_device_identity.dart';

void main() {
  test('VibeKits 设备身份稳定且名称包含硬件识别码', () {
    final McpDeviceIdentity first = McpDeviceIdentity.forVibekits();
    final McpDeviceIdentity second = McpDeviceIdentity.forVibekits();

    expect(first.hardwareCode, matches(RegExp(r'^[A-F0-9]{10}$')));
    expect(first.instanceId, 'com.vibekits.desktop:${first.hardwareCode}');
    expect(first.displayName, contains(first.hardwareCode));
    expect(first.displayName, startsWith('VibeKits@'));
    expect(second.instanceId, first.instanceId);
  });

  test('MCP 开关状态可持久化', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-exposure-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final McpExposurePreferences preferences = McpExposurePreferences(
      file: File('${root.path}${Platform.pathSeparator}exposure.json'),
    );

    expect(await preferences.loadEnabled(), isFalse);
    await preferences.saveEnabled(false);
    expect(await preferences.loadEnabled(), isFalse);
    await preferences.saveEnabled(true);
    expect(await preferences.loadEnabled(), isTrue);
  });

  test('旧版已开启状态在未确认新风险说明前不恢复', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-legacy-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final File file = File(
      '${root.path}${Platform.pathSeparator}exposure.json',
    );
    await file.writeAsString('{"version":1,"enabled":true}');

    expect(await McpExposurePreferences(file: file).loadEnabled(), isFalse);
  });
}
