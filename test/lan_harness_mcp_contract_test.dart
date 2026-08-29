import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('局域网MCP使用SSH强制命令且不暴露回环Token', () {
    final String root = Directory.current.path;
    final String script = File(
      '$root${Platform.pathSeparator}tool${Platform.pathSeparator}'
      'start_vibekits_mcp_ssh.ps1',
    ).readAsStringSync();
    final String documentation = File(
      '$root${Platform.pathSeparator}docs${Platform.pathSeparator}'
      '44_LAN_HARNESS_MCP_ACCESS.md',
    ).readAsStringSync();

    expect(script, contains('SSH_CONNECTION'));
    expect(script, contains('Test-PrivateIPv4'));
    expect(script, contains('start_vibekits_mcp.ps1'));
    expect(documentation, contains('restrict,command='));
    expect(documentation, contains('StrictHostKeyChecking=yes'));
    expect(documentation, contains('控制授权'));
    expect(documentation, isNot(contains('tool-bridge.json` 中的')));
  });
}
