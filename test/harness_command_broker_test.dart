import 'dart:async';
import 'dart:convert';

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
          <String, Object?>{
            'type': 'assistant/message',
            'seq': 5,
            'role': 'assistant',
            'text': 'working',
          },
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

  test(
    'wait observes a completed status even if its event already passed',
    () async {
      final controller = StreamController<Map<String, Object?>>.broadcast();
      final registration = HarnessCommandBroker.instance.register(
        prompt: (_, requestId) async => <String, Object?>{
          'requestId': requestId,
        },
        status: (sessionId) async => <String, Object?>{
          'sessionId': sessionId,
          'cursor': 2,
          'state': 'completed',
        },
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
        const Duration(seconds: 1),
      );
      expect(result, containsPair('changed', true));
      expect(result, containsPair('state', 'completed'));
    },
  );

  test('history is cursor scoped and bounded for remote transport', () async {
    final controller = StreamController<Map<String, Object?>>.broadcast();
    final registration = HarnessCommandBroker.instance.register(
      prompt: (_, requestId) async => <String, Object?>{'requestId': requestId},
      status: (_) async => <String, Object?>{},
      history: (_, _) async => <String, Object?>{
        'cursor': 200,
        'records': <Object?>[
          <String, Object?>{'type': 'old', 'seq': 4, 'data': 'ignored'},
          for (var seq = 5; seq < 200; seq++)
            <String, Object?>{
              'type': 'tool/output',
              'seq': seq,
              'data': 'x' * 40000,
            },
        ],
        'hasMore': false,
        'projections': <String, Object?>{'huge': 'y' * 1200000},
      },
      cancel: (_) async => <String, Object?>{},
      changes: controller.stream,
    );
    addTearDown(() async {
      registration.unregister();
      await controller.close();
    });

    final result = await HarnessCommandBroker.instance.history('s', 4);
    final records = result['records']! as List<Object?>;
    expect(records, isNotEmpty);
    expect(records.length, lessThanOrEqualTo(64));
    expect((records.first! as Map)['seq'], 5);
    expect((records.first! as Map)['truncated'], isTrue);
    expect(result['cursor'], (records.last! as Map)['seq']);
    expect(result['hasMore'], isTrue);
    expect(result, isNot(contains('projections')));
    expect(utf8.encode(jsonEncode(result)).length, lessThan(300 * 1024));
  });

  test('history returns official event envelopes after cursor', () async {
    final controller = StreamController<Map<String, Object?>>.broadcast();
    final registration = HarnessCommandBroker.instance.register(
      prompt: (_, requestId) async => <String, Object?>{'requestId': requestId},
      status: (_) async => <String, Object?>{},
      history: (_, _) async => <String, Object?>{
        'records': <Object?>[
          <String, Object?>{
            'type': 'event',
            'event': <String, Object?>{
              'type': 'assistant/message',
              'seq': 12,
              'time': 123,
              'data': <String, Object?>{'text': 'done'},
            },
          },
        ],
        'hasMore': false,
      },
      cancel: (_) async => <String, Object?>{},
      changes: controller.stream,
    );
    addTearDown(() async {
      registration.unregister();
      await controller.close();
    });

    final result = await HarnessCommandBroker.instance.history('s', 11);
    expect(result['cursor'], 12);
    expect(result['records'], hasLength(1));
    expect(
      (((result['records'] as List).single as Map)['event'] as Map)['data'],
      <String, Object?>{'text': 'done'},
    );
  });
}
