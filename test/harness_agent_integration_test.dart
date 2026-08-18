import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  test('官方 Harness 使用本地模型端点完成一次真实任务', () async {
    final HttpServer model = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => model.close(force: true));
    final List<String> modelRequests = <String>[];
    model.listen((HttpRequest request) async {
      expect(request.uri.path, '/chat/completions');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-key',
      );
      modelRequests.add(await utf8.decoder.bind(request).join());
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream; charset=utf-8',
      );
      if (modelRequests.length == 1) {
        expect(modelRequests.first, contains('mcp__vibekits__sha256'));
        request.response.write(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"id":"call_sha","function":{"name":"mcp__vibekits__sha256",'
          '"arguments":"{\\"input\\":\\"abc\\"}"}}]},'
          '"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,'
          '"completion_tokens":3}}\n\n',
        );
      } else {
        request.response.write(
          'data: {"choices":[{"delta":{"content":"VIBEKITS_FULL_STACK_OK"},'
          '"finish_reason":"stop"}],"usage":{"prompt_tokens":20,'
          '"completion_tokens":3}}\n\n',
        );
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final HarnessAgentHandle handle = await DeepSeekHarnessService.startAgent(
      HarnessAgentRequest(
        workspace: Directory.current.path,
        prompt: '完成最小联调',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${model.port}',
      ),
    );
    final StringBuffer output = StringBuffer();
    final StreamSubscription<String> subscription = handle.output.listen(
      output.write,
    );
    addTearDown(subscription.cancel);
    addTearDown(() async {
      if (handle.running) await handle.stop();
    });
    final int code = await handle.exitCode.timeout(
      const Duration(seconds: 60),
      onTimeout: () async {
        await handle.stop();
        return 124;
      },
    );
    expect(code, 0, reason: output.toString());
    expect(output.toString(), contains('VIBEKITS_FULL_STACK_OK'));
    expect(modelRequests.length, greaterThanOrEqualTo(2));
    expect(
      modelRequests
          .skip(1)
          .any((String request) => request.contains('ba7816bf8f01cfea')),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 75)));
}
