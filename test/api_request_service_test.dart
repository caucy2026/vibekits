import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/api_request_service.dart';

void main() {
  late HttpServer server;
  late Uri baseUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('POST 方法、请求头和 UTF-8 Body 真实往返', () async {
    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'method': request.method,
          'token': request.headers.value('x-test'),
          'body': body,
        }),
      );
      await request.response.close();
    });

    final ApiResponseData response = await ApiRequestService.execute(
      ApiRequestSpec(
        method: 'POST',
        url: '$baseUrl/echo',
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'X-Test': 'safe',
        },
        body: '{"hello":"世界"}',
      ),
    );

    expect(response.statusCode, 200);
    expect(response.body, contains('"method":"POST"'));
    expect(response.body, contains('"token":"safe"'));
    expect(response.body, contains('世界'));
  });

  test('响应超过上限会停止读取并返回明确错误', () async {
    server.listen((HttpRequest request) async {
      request.response.add(List<int>.filled(2048, 65));
      await request.response.close();
    });
    await expectLater(
      ApiRequestService.execute(
        ApiRequestSpec(
          method: 'GET',
          url: '$baseUrl/large',
          maxResponseBytes: 1024,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('拒绝非 HTTP URL、URL 凭据和请求头注入', () {
    expect(
      () =>
          const ApiRequestSpec(method: 'GET', url: 'file:///secret').validate(),
      throwsFormatException,
    );
    expect(
      () => const ApiRequestSpec(
        method: 'GET',
        url: 'https://user:pass@example.com',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const ApiRequestSpec(
        method: 'GET',
        url: 'https://example.com',
        headers: <String, String>{'X-Test': 'ok\r\nInjected: yes'},
      ).validate(),
      throwsFormatException,
    );
  });
}
