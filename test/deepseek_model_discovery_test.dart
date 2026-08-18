import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  test('使用 Key 从兼容端点读取真实模型列表', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      expect(request.uri.path, '/models');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-key',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'data': <Map<String, String>>[
            <String, String>{'id': 'deepseek-reasoner'},
            <String, String>{'id': 'deepseek-chat'},
          ],
        }),
      );
      await request.response.close();
    });
    expect(
      await DeepSeekHarnessService.listModels(
        'test-key',
        'http://127.0.0.1:${server.port}',
      ),
      <String>['deepseek-chat', 'deepseek-reasoner'],
    );
  });
}
