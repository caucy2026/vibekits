import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LMCP/2 唯一文档要求HTTPS指纹和控制授权', () {
    final String root = Directory.current.path;
    final String documentation = File(
      '$root${Platform.pathSeparator}docs${Platform.pathSeparator}'
      '50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md',
    ).readAsStringSync();

    expect(documentation, contains('https-streamable-http'));
    expect(documentation, contains('instanceKeyFingerprint'));
    expect(documentation, contains('239.255.42.99'));
    expect(documentation, contains('权限申请'));
    expect(documentation, contains('kemi.files.send'));
    expect(documentation, contains('Harness 的长期评分'));
    expect(documentation, contains('不再对外公告无证书 `http-jsonrpc`'));
  });

  test('历史兼容 Sidecar 仍不携带凭据', () {
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
