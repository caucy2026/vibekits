import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel processLifecycle = MethodChannel(
    'vibekits/process_lifecycle',
  );
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(processLifecycle, (MethodCall call) async {
          if (call.method == 'bindProcessTree') return true;
          return null;
        });
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(processLifecycle, null);
  });

  test('官方 Harness 使用本地模型端点完成一次真实任务', () async {
    final Directory workspace = await Directory.systemTemp.createTemp(
      'vibekits_harness_native_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final HttpServer model = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => model.close(force: true));
    final List<String> modelRequests = <String>[];
    int nativeApprovals = 0;
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
          'data: ${jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'delta': <String, Object?>{
                  'tool_calls': <Object?>[
                    <String, Object?>{
                      'index': 0,
                      'id': 'call_sha',
                      'function': <String, Object?>{
                        'name': 'mcp__vibekits__sha256',
                        'arguments': jsonEncode(<String, Object?>{'input': 'abc'}),
                      },
                    },
                    <String, Object?>{
                      'index': 1,
                      'id': 'call_pwsh',
                      'function': <String, Object?>{
                        'name': 'pwsh',
                        'arguments': jsonEncode(<String, Object?>{'command': 'Set-Content -LiteralPath native-approved.txt '
                            '-Value VIBEKITS_NATIVE_OK', 'description': 'Verify native approval bridge', 'sandbox_permissions': 'danger-full-access', 'justification': 'Verify the App permission selection reaches '
                            'native Harness tools.'}),
                      },
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
            'usage': <String, Object?>{'prompt_tokens': 12, 'completion_tokens': 7},
          })}\n\n',
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
        workspace: workspace.path,
        prompt: '完成最小联调',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${model.port}',
        approveTool: (_) async {
          nativeApprovals++;
          return true;
        },
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
    final List<dynamic> finalMessages =
        (jsonDecode(modelRequests.last) as Map<String, dynamic>)['messages']
            as List<dynamic>;
    expect(
      nativeApprovals,
      1,
      reason:
          '${output.toString()}\n'
          '${jsonEncode(finalMessages.skip(finalMessages.length - 4).toList())}',
    );
    expect(
      await File(
        '${workspace.path}${Platform.pathSeparator}native-approved.txt',
      ).readAsString(),
      contains('VIBEKITS_NATIVE_OK'),
    );
  }, timeout: const Timeout(Duration(seconds: 75)));
}
