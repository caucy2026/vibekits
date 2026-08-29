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

  test('第三方接入包包含清单Schema和无凭据发现Sidecar', () {
    final String root = Directory.current.path;
    final String sidecar = File(
      '$root${Platform.pathSeparator}tool${Platform.pathSeparator}'
      'lmcp_reference_peer.mjs',
    ).readAsStringSync();
    final String schema = File(
      '$root${Platform.pathSeparator}docs${Platform.pathSeparator}schemas'
      '${Platform.pathSeparator}lmcp-app-manifest-1.0.schema.json',
    ).readAsStringSync();

    expect(sidecar, contains("const GROUP = '239.255.42.99'"));
    expect(sidecar, contains('--validate-only'));
    expect(sidecar, contains('pairingRequired must be true'));
    expect(sidecar, isNot(contains('Bearer')));
    expect(schema, contains('https-streamable-http'));
    expect(schema, contains('certificateSha256'));
  });
}
