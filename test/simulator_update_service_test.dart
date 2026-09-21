import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lan_mcp_tool_server.dart';
import 'package:vibekits/features/dev_tools/domain/simulator_update_service.dart';

void main() {
  test('仿真候选上传固定走独立 MCP 端口', () async {
    final source = await File(
      'lib/features/dev_tools/domain/harness_simulator_controller.dart',
    ).readAsString();
    expect(
      source,
      contains(
        "'http://127.0.0.1:\${session.mcpLocalPort}\${SimulatorUpdateService.uploadPath}'",
      ),
    );
    expect(
      source,
      isNot(
        contains(
          "'http://127.0.0.1:\${session.localPort}\${SimulatorUpdateService.uploadPath}'",
        ),
      ),
    );
  });

  test('Universal 候选校验不依赖目标机安装 Xcode 工具', () {
    final ByteData header = ByteData(48)
      ..setUint32(0, 0xcafebabe, Endian.big)
      ..setUint32(4, 2, Endian.big)
      ..setUint32(8, 0x01000007, Endian.big)
      ..setUint32(28, 0x0100000c, Endian.big);
    expect(
      SimulatorUpdateService.parseUniversalMachOCpuTypes(
        header.buffer.asUint8List(),
      ),
      <int>{0x01000007, 0x0100000c},
    );
    expect(
      SimulatorUpdateService.parseUniversalMachOCpuTypes(
        Uint8List.fromList(<int>[0xcf, 0xfa, 0xed, 0xfe]),
      ),
      isEmpty,
    );
  });

  test('仿真候选接受 ditto AppleDouble 元数据但拒绝第二个载荷', () {
    expect(
      SimulatorUpdateService.isAllowedArchiveEntry(
        '__MACOSX/Vibekits.app/Contents/._Info.plist',
      ),
      isTrue,
    );
    expect(
      SimulatorUpdateService.isAllowedArchiveEntry(
        'Vibekits.app/Contents/MacOS/Vibekits',
      ),
      isTrue,
    );
    expect(
      SimulatorUpdateService.isAllowedArchiveEntry('Other.app/Contents'),
      isFalse,
    );
    expect(
      SimulatorUpdateService.isAllowedArchiveEntry('__MACOSX/Other.app/._x'),
      isFalse,
    );
  });

  test('上传令牌单次使用且绑定 ZIP 大小和 SHA-256', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits_update_test_',
    );
    addTearDown(() => root.delete(recursive: true));
    final service = SimulatorUpdateService(stagingRoot: root);
    final List<int> bytes = utf8.encode('signed candidate fixture');
    final String checksum = sha256.convert(bytes).toString();
    final prepared = await service.begin(
      expectedBytes: bytes.length,
      expectedSha256: checksum,
      fileName: 'Vibekits-test.zip',
    );
    final String token = prepared['uploadToken']! as String;

    final staged = await service.receive(
      stream: Stream<List<int>>.value(bytes),
      uploadToken: token,
      contentLength: bytes.length,
    );
    expect(staged['staged'], isTrue);
    expect(staged['token'], token);
    expect(staged['sha256'], checksum);
    expect((await service.status())['uploadIntentActive'], isFalse);

    await expectLater(
      service.receive(
        stream: Stream<List<int>>.value(bytes),
        uploadToken: token,
        contentLength: bytes.length,
      ),
      throwsFormatException,
    );
  }, skip: !Platform.isMacOS);

  test('仿真专用回环端点接受一次性令牌并返回同一候选令牌', () async {
    final List<int> bytes = utf8.encode('loopback simulator candidate');
    final String checksum = sha256.convert(bytes).toString();
    final prepared = await SimulatorUpdateService.instance.begin(
      expectedBytes: bytes.length,
      expectedSha256: checksum,
      fileName: 'Vibekits-loopback-test.zip',
    );
    final String token = prepared['uploadToken']! as String;
    final server = await LanMcpToolServer.start(
      bindAddress: InternetAddress.loopbackIPv4,
      allowSimulatorUpdateUpload: true,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.putUrl(
      Uri.parse(
        'http://127.0.0.1:${server.port}${SimulatorUpdateService.uploadPath}',
      ),
    );
    request.headers.set('x-vibekits-upload-token', token);
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final Object? rawDecoded = jsonDecode(
      await utf8.decoder.bind(response).join(),
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(rawDecoded, isA<Map>());
    final decoded = Map<String, Object?>.from(rawDecoded! as Map);
    expect(decoded['token'], token);
    expect(decoded['sha256'], checksum);
  }, skip: !Platform.isMacOS);

  test('通用 LAN MCP 端点拒绝候选包上传', () async {
    final server = await LanMcpToolServer.start(
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.putUrl(
      Uri.parse(
        'http://127.0.0.1:${server.port}${SimulatorUpdateService.uploadPath}',
      ),
    );
    request.contentLength = 0;
    final response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.forbidden);
    expect(body, contains('simulator_update_upload_disabled'));
  });

  test('仿真开关公开完整诊断与签名升级工具', () {
    final bridge = VibekitsHarnessToolBridge();
    addTearDown(bridge.dispose);
    final ids = bridge.executableCatalog.map((tool) => tool.id).toSet();
    expect(
      ids,
      containsAll(<String>{
        VibekitsHarnessToolBridge.deviceProcessesId,
        VibekitsHarnessToolBridge.deviceLogsId,
        VibekitsHarnessToolBridge.deviceCrashReportsId,
        VibekitsHarnessToolBridge.deviceAppControlId,
        VibekitsHarnessToolBridge.deviceUpdateBeginId,
        VibekitsHarnessToolBridge.deviceUpdateStatusId,
        VibekitsHarnessToolBridge.deviceUpdateApplyId,
        VibekitsHarnessToolBridge.simulatorInstallCandidateId,
      }),
    );
  });
}
