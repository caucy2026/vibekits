import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/network_download_service.dart';

void main() {
  late HttpServer server;
  late Directory output;

  setUp(() async {
    output = await Directory.systemTemp.createTemp('vibekits-download-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    await output.delete(recursive: true);
  });

  test('流式下载 APK 并返回路径、大小和 SHA-256', () async {
    final List<int> bytes = <int>[
      0x50,
      0x4b,
      0x03,
      0x04,
      ...List<int>.filled(64, 7),
    ];
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.binary;
      request.response.add(bytes);
      await request.response.close();
    });

    final NetworkDownloadResult result = await const NetworkDownloadService()
        .download(
          NetworkDownloadRequest(
            url: Uri.parse('http://127.0.0.1:${server.port}/sample.apk'),
            outputDirectory: output.path,
          ),
        );

    expect(result.bytes, bytes.length);
    expect(result.sha256, crypto.sha256.convert(bytes).toString());
    expect(result.artifactType, 'android-apk');
    expect(await File(result.outputPath).readAsBytes(), bytes);
    expect(output.listSync().whereType<File>(), hasLength(1));
  });

  test('APK 内容无效时拒绝并清除 part 文件', () async {
    server.listen((HttpRequest request) async {
      request.response.write('<html>download denied</html>');
      await request.response.close();
    });

    expect(
      () => const NetworkDownloadService().download(
        NetworkDownloadRequest(
          url: Uri.parse('http://127.0.0.1:${server.port}/error.apk'),
          outputDirectory: output.path,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(output.listSync(), isEmpty);
  });

  test('Harness 下载工具使用配置目录并形成可执行接口', () async {
    final List<int> bytes = <int>[0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4];
    server.listen((HttpRequest request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      downloadDirectory: output.path,
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.networkDownloadId,
      arguments: <String, Object?>{
        'url': 'http://127.0.0.1:${server.port}/from-harness.apk',
      },
      approve: (HarnessToolApprovalRequest request) async => true,
    );

    expect(result.ok, isTrue, reason: result.error);
    expect(result.data?['artifactType'], 'android-apk');
    expect(File(result.data!['outputPath']! as String).existsSync(), isTrue);
    expect(
      bridge.exportCatalog()['tools'].toString(),
      contains(VibekitsHarnessToolBridge.networkDownloadId),
    );
  });
}
