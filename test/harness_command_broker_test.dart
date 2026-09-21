import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_command_broker.dart';

void main() {
  test('rejects prompts when no Harness workspace is active', () async {
    await expectLater(
      HarnessCommandBroker.instance.prompt('install KOffice'),
      throwsA(isA<StateError>()),
    );
  });

  test('routes prompt and exposes status history wait and cancel', () async {
    final controller = StreamController<Map<String, Object?>>.broadcast();
    final registration = HarnessCommandBroker.instance.register(
      prompt: (text, requestId) async => <String, Object?>{
        'accepted': true,
        'workspaceId': 'w',
        'sessionId': 's',
        'requestId': requestId,
        'state': 'queued',
      },
      status: (sessionId) async => <String, Object?>{
        'sessionId': sessionId,
        'state': 'running',
        'cursor': 4,
      },
      history: (sessionId, cursor) async => <String, Object?>{
        'sessionId': sessionId,
        'cursor': 5,
        'records': <Object?>[
          <String, Object?>{'role': 'assistant', 'text': 'working'},
        ],
      },
      cancel: (sessionId) async => <String, Object?>{
        'sessionId': sessionId,
        'state': 'stopped',
      },
      changes: controller.stream,
    );
    addTearDown(() async {
      registration.unregister();
      await controller.close();
    });

    final accepted = await HarnessCommandBroker.instance.prompt('install');
    expect(accepted['accepted'], isTrue);
    expect(accepted['sessionId'], 's');
    expect(
      await HarnessCommandBroker.instance.status('s'),
      containsPair('state', 'running'),
    );
    expect((await HarnessCommandBroker.instance.history('s', 4))['cursor'], 5);

    final wait = HarnessCommandBroker.instance.waitForChange(
      's',
      4,
      const Duration(seconds: 1),
    );
    controller.add(<String, Object?>{
      'sessionId': 's',
      'cursor': 5,
      'state': 'tool_running',
    });
    expect((await wait)['changed'], isTrue);
    expect(
      await HarnessCommandBroker.instance.cancel('s'),
      containsPair('state', 'stopped'),
    );
  });

  test('wait timeout is a successful unchanged result', () async {
    final controller = StreamController<Map<String, Object?>>.broadcast();
    final registration = HarnessCommandBroker.instance.register(
      prompt: (_, requestId) async => <String, Object?>{'requestId': requestId},
      status: (_) async => <String, Object?>{},
      history: (_, _) async => <String, Object?>{},
      cancel: (_) async => <String, Object?>{},
      changes: controller.stream,
    );
    addTearDown(() async {
      registration.unregister();
      await controller.close();
    });
    final result = await HarnessCommandBroker.instance.waitForChange(
      's',
      1,
      const Duration(milliseconds: 10),
    );
    expect(result, containsPair('changed', false));
  });
}
