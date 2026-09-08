import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_commands.dart';

HarnessRemoteCommand command({String id = 'c1', String text = 'test'}) =>
    HarnessRemoteCommand(
      id: id,
      workspaceId: 'w1',
      sessionId: 's1',
      operation: 'prompt',
      arguments: {'text': text},
    );

void main() {
  test('concurrent retries execute once and preserve feedback', () async {
    var calls = 0;
    final done = Completer<Map<String, Object?>>();
    final gate = HarnessRemoteCommandGate(
      authorize: (_, _) async => true,
      execute: (_) {
        calls++;
        return done.future;
      },
    );
    final first = gate.dispatch('peer-a', command());
    final retry = gate.dispatch('peer-a', command());
    done.complete({'taskId': 'task-1', 'state': 'accepted'});
    expect(await first, await retry);
    expect(calls, 1);
    await expectLater(
      gate.dispatch('peer-a', command(text: 'different')),
      throwsStateError,
    );
  });

  test('authorization revocation blocks cached results too', () async {
    var allowed = true;
    final gate = HarnessRemoteCommandGate(
      authorize: (_, _) async => allowed,
      execute: (_) async => {'text': 'private'},
    );
    await gate.dispatch('peer-a', command());
    allowed = false;
    await expectLater(gate.dispatch('peer-a', command()), throwsStateError);
  });

  test('peer identities isolate identical command IDs', () async {
    var calls = 0;
    final gate = HarnessRemoteCommandGate(
      authorize: (_, _) async => true,
      execute: (_) async => {'count': ++calls},
    );
    await gate.dispatch('a', command());
    await gate.dispatch('b', command());
    expect(calls, 2);
  });

  test('failed command retry never executes it again', () async {
    var calls = 0;
    final gate = HarnessRemoteCommandGate(
      authorize: (_, _) async => true,
      execute: (_) async {
        calls++;
        throw StateError('execution failed');
      },
    );
    await expectLater(gate.dispatch('a', command()), throwsStateError);
    await expectLater(gate.dispatch('a', command()), throwsStateError);
    expect(calls, 1);
  });

  test(
    'bounded ledger rejects new commands without evicting old ones',
    () async {
      final gate = HarnessRemoteCommandGate(
        capacity: 1,
        authorize: (_, _) async => true,
        execute: (_) async => {'ok': true},
      );
      final result = await gate.dispatch('a', command());
      result['ok'] = false;
      expect((await gate.dispatch('a', command()))['ok'], true);
      await expectLater(
        gate.dispatch('a', command(id: 'c2')),
        throwsStateError,
      );
    },
  );
}
