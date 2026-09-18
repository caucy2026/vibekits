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
    final List<String> taskRequests = <String>[];
    int nativeApprovals = 0;
    model.listen((HttpRequest request) async {
      expect(request.uri.path, '/v1/messages');
      expect(request.headers.value('x-api-key'), 'test-key');
      final String requestBody = await utf8.decoder.bind(request).join();
      modelRequests.add(requestBody);
      final Map<String, dynamic> requestJson =
          jsonDecode(requestBody) as Map<String, dynamic>;
      final List<dynamic> messages = requestJson['messages'] as List<dynamic>;
      final String latestMessage = jsonEncode(messages.last);
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream; charset=utf-8',
      );
      void event(String type, Map<String, Object?> data) {
        request.response.write('event: $type\n');
        request.response.write('data: ${jsonEncode(data)}\n\n');
      }

      void startMessage() {
        event('message_start', <String, Object?>{
          'type': 'message_start',
          'message': <String, Object?>{
            'id': 'msg_vibekits_test',
            'type': 'message',
            'role': 'assistant',
            'model': 'deepseek-chat',
            'content': <Object?>[],
            'stop_reason': null,
            'usage': <String, Object?>{'input_tokens': 12, 'output_tokens': 0},
          },
        });
      }

      void finishMessage(String stopReason) {
        event('message_delta', <String, Object?>{
          'type': 'message_delta',
          'delta': <String, Object?>{'stop_reason': stopReason},
          'usage': <String, Object?>{'output_tokens': 7},
        });
        event('message_stop', <String, Object?>{'type': 'message_stop'});
      }

      void textResponse(String value) {
        startMessage();
        event('content_block_start', <String, Object?>{
          'type': 'content_block_start',
          'index': 0,
          'content_block': <String, Object?>{'type': 'text', 'text': ''},
        });
        event('content_block_delta', <String, Object?>{
          'type': 'content_block_delta',
          'index': 0,
          'delta': <String, Object?>{'type': 'text_delta', 'text': value},
        });
        event('content_block_stop', <String, Object?>{
          'type': 'content_block_stop',
          'index': 0,
        });
        finishMessage('end_turn');
      }

      if (latestMessage.contains(
        'Create a concise title for an AI coding-assistant session',
      )) {
        textResponse('最小联调');
      } else if (requestBody.contains('mcp__vibekits__sha256') &&
          !requestBody.contains('ba7816bf8f01cfea')) {
        taskRequests.add(requestBody);
        startMessage();
        final List<Map<String, Object?>> tools = <Map<String, Object?>>[
          <String, Object?>{
            'id': 'call_sha',
            'name': 'mcp__vibekits__sha256',
            'input': <String, Object?>{'input': 'abc'},
          },
          <String, Object?>{
            'id': 'call_native',
            'name': Platform.isWindows ? 'pwsh' : 'bash',
            'input': <String, Object?>{
              'command': Platform.isWindows
                  ? 'Set-Content -LiteralPath native-approved.txt -Value VIBEKITS_NATIVE_OK'
                  : 'printf VIBEKITS_NATIVE_OK > native-approved.txt',
              'description': 'Verify native approval bridge',
              'sandbox_permissions': 'danger-full-access',
              'justification':
                  'Verify the App permission selection reaches native Harness tools.',
            },
          },
        ];
        for (int index = 0; index < tools.length; index++) {
          final Map<String, Object?> tool = tools[index];
          final Object? input = tool.remove('input');
          event('content_block_start', <String, Object?>{
            'type': 'content_block_start',
            'index': index,
            'content_block': <String, Object?>{
              'type': 'tool_use',
              ...tool,
              'input': <String, Object?>{},
            },
          });
          event('content_block_delta', <String, Object?>{
            'type': 'content_block_delta',
            'index': index,
            'delta': <String, Object?>{
              'type': 'input_json_delta',
              'partial_json': jsonEncode(input),
            },
          });
          event('content_block_stop', <String, Object?>{
            'type': 'content_block_stop',
            'index': index,
          });
        }
        finishMessage('tool_use');
      } else {
        taskRequests.add(requestBody);
        textResponse('VIBEKITS_FULL_STACK_OK');
      }
      await request.response.close();
    });

    final HarnessAgentHandle handle = await DeepSeekHarnessService.startAgent(
      HarnessAgentRequest(
        workspace: workspace.path,
        prompt: '完成最小联调',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${model.port}',
        harnessHomeDirectory:
            '${workspace.path}${Platform.pathSeparator}harness-home',
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
    expect(
      code,
      0,
      reason:
          '${output.toString()}\n'
          'modelRequests=${modelRequests.length} '
          'taskRequests=${taskRequests.length} '
          'nativeApprovals=$nativeApprovals',
    );
    expect(output.toString(), contains('VIBEKITS_FULL_STACK_OK'));
    expect(taskRequests.length, greaterThanOrEqualTo(2));
    expect(
      taskRequests
          .skip(1)
          .any((String request) => request.contains('ba7816bf8f01cfea')),
      isTrue,
    );
    final List<dynamic> finalMessages =
        (jsonDecode(taskRequests.last) as Map<String, dynamic>)['messages']
            as List<dynamic>;
    expect(
      nativeApprovals,
      1,
      reason:
          '${output.toString()}\n'
          '${jsonEncode(finalMessages.skip(finalMessages.length > 4 ? finalMessages.length - 4 : 0).toList())}',
    );
    expect(
      await File(
        '${workspace.path}${Platform.pathSeparator}native-approved.txt',
      ).readAsString(),
      contains('VIBEKITS_NATIVE_OK'),
    );
  }, timeout: const Timeout(Duration(seconds: 75)));

  test('官方 Harness 长任务可停止并清理进程', () async {
    final Directory workspace = await Directory.systemTemp.createTemp(
      'vibekits_harness_stop_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final HttpServer model = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => model.close(force: true));
    final Completer<void> requestSeen = Completer<void>();
    final Completer<void> releaseResponse = Completer<void>();
    model.listen((HttpRequest request) async {
      if (!requestSeen.isCompleted) requestSeen.complete();
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream; charset=utf-8',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"RUNNING"}}]}\n\n',
      );
      await request.response.flush();
      await releaseResponse.future;
      try {
        await request.response.close();
      } on Object {
        // The stopped Harness is expected to close its HTTP client first.
      }
    });
    addTearDown(() {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
    });

    final HarnessAgentHandle handle = await DeepSeekHarnessService.startAgent(
      HarnessAgentRequest(
        workspace: workspace.path,
        prompt: '保持运行直到停止测试结束',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${model.port}',
        harnessHomeDirectory:
            '${workspace.path}${Platform.pathSeparator}harness-home',
        approveTool: (_) async => true,
      ),
    );
    addTearDown(() async {
      if (handle.running) await handle.stop();
    });
    await requestSeen.future.timeout(const Duration(seconds: 30));
    expect(handle.running, isTrue);
    await handle.stop().timeout(const Duration(seconds: 10));
    expect(handle.running, isFalse);
    await handle.exitCode.timeout(const Duration(seconds: 5));
    if (!releaseResponse.isCompleted) releaseResponse.complete();
  }, timeout: const Timeout(Duration(seconds: 55)));
}
