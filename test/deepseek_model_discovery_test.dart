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

  for (final (status, expected) in <(int, String)>[
    (401, '401：API Key 未通过认证'),
    (403, '403：当前密钥无权访问'),
  ]) {
    test('模型列表将 HTTP $status 的认证原因明确返回', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = status;
        await request.response.close();
      });
      await expectLater(
        DeepSeekHarnessService.listModels(
          'test-key',
          'http://127.0.0.1:${server.port}',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains(expected),
          ),
        ),
      );
    });
  }

  test('移动端逐段显示真实推理与回复', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final workspace = await Directory.systemTemp.createTemp('harness-stream-');
    addTearDown(() async {
      await server.close(force: true);
      await workspace.delete(recursive: true);
    });
    server.listen((request) async {
      expect(request.uri.path, '/chat/completions');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['stream'], true);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"reasoning_content":"先建立棋盘"}}]}\n\n',
        ),
      );
      await request.response.flush();
      request.response.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"reasoning_content":"，再处理碰撞"}}]}\n\n',
        ),
      );
      request.response.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"完成测试"}}]}\n\n'),
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final handle = DeepSeekHarnessService.startNativeToolAgent(
      HarnessAgentRequest(
        workspace: workspace.path,
        prompt: '测试',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowedToolIds: const <String>{'not-registered'},
      ),
    );
    final events = (handle as HarnessAgentEventSource).events.toList();
    final output = handle.output.toList();
    expect(await handle.exitCode, 0);
    expect(await output, <String>['完成测试']);
    expect(
      (await events)
          .where((event) => event.kind == HarnessAgentEventKind.reasoning)
          .map((event) => event.text)
          .join(),
      '先建立棋盘，再处理碰撞',
    );
  });

  test('长推理累计超过 64 MiB 时仍继续接收最终结果', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final workspace = await Directory.systemTemp.createTemp('harness-long-sse-');
    addTearDown(() async {
      await server.close(force: true);
      await workspace.delete(recursive: true);
    });
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType('text', 'event-stream');
      final String event =
          'data: ${jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'delta': <String, String>{
                  'reasoning_content': 'r' * (1024 * 1024),
                },
              },
            ],
          })}\n\n';
      for (var index = 0; index < 65; index++) {
        request.response.add(utf8.encode(event));
        await request.response.flush();
      }
      request.response.add(utf8.encode(
        'data: {"choices":[{"delta":{"content":"最终结果"}}]}\n\n'
        'data: [DONE]\n\n',
      ));
      await request.response.close();
    });
    final handle = DeepSeekHarnessService.startNativeToolAgent(
      HarnessAgentRequest(
        workspace: workspace.path,
        prompt: '长推理测试',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowedToolIds: const <String>{'not-registered'},
      ),
    );
    final events = (handle as HarnessAgentEventSource).events.toList();
    final output = handle.output.toList();
    expect(await handle.exitCode, 0);
    expect((await output).join(), '最终结果');
    final reasoningEvents = (await events)
        .where((event) => event.kind == HarnessAgentEventKind.reasoning)
        .map((event) => event.text)
        .toList();
    expect(reasoningEvents.length, greaterThan(65));
    expect(reasoningEvents.every((text) => text.length <= 8192), isTrue);
    expect(reasoningEvents.join(), contains('继续显示最新过程'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('移动端遇到模型服务暂时繁忙后有限重试并保留结果', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final workspace = await Directory.systemTemp.createTemp('harness-503-');
    addTearDown(() async {
      await server.close(force: true);
      await workspace.delete(recursive: true);
    });
    var requests = 0;
    server.listen((request) async {
      requests++;
      await utf8.decoder.bind(request).join();
      if (requests == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('Service is too busy');
      } else {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.add(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"已恢复"}}]}\n\n'
            'data: [DONE]\n\n',
          ),
        );
      }
      await request.response.close();
    });
    final handle = DeepSeekHarnessService.startNativeToolAgent(
      HarnessAgentRequest(
        workspace: workspace.path,
        prompt: '测试短暂 503',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowedToolIds: const <String>{'not-registered'},
      ),
    );
    final output = handle.output.toList();
    expect(await handle.exitCode, 0);
    expect(requests, 2);
    expect(await output, <String>['已恢复']);
  });
}
