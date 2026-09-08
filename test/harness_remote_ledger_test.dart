import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_commands.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_ledger.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harness-ledger-test-');
    file = File('${directory.path}/commands.jsonl');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  HarnessRemoteCommand command({String id = 'one', String text = 'hello'}) =>
      HarnessRemoteCommand(
        id: id,
        workspaceId: 'workspace',
        sessionId: 'session',
        operation: 'session.prompt',
        arguments: {'sessionId': 'session', 'text': text},
      );

  test('restart returns committed reply without repeating execution', () async {
    var calls = 0;
    var ledger = await HarnessRemoteLedger.open(file);
    final first = await ledger.execute(
      'peer',
      command(),
      () async => {'n': ++calls},
    );
    first['n'] = 200;
    await ledger.close();
    ledger = await HarnessRemoteLedger.open(file);
    expect(
      await ledger.execute('peer', command(), () async => {'n': ++calls}),
      {'n': 1},
    );
    expect(calls, 1);
    await ledger.close();
    expect(await file.readAsString(), isNot(contains('hello')));
  });

  test(
    'concurrent duplicate executes once and arguments cannot reuse ID',
    () async {
      final ledger = await HarnessRemoteLedger.open(file);
      final release = Completer<void>();
      var calls = 0;
      Future<Map<String, Object?>> action() async {
        calls++;
        await release.future;
        return {'ok': true};
      }

      final one = ledger.execute('peer', command(), action);
      final two = ledger.execute('peer', command(), action);
      await expectLater(
        ledger.execute('peer', command(text: 'different'), action),
        throwsStateError,
      );
      release.complete();
      expect(await one, await two);
      expect(calls, 1);
      await ledger.close();
    },
  );

  test(
    'failed execution remains unknown after restart, never blindly repeats',
    () async {
      var ledger = await HarnessRemoteLedger.open(file);
      await expectLater(
        ledger.execute('peer', command(), () async {
          throw StateError('disconnected after sending');
        }),
        throwsStateError,
      );
      await ledger.close();
      ledger = await HarnessRemoteLedger.open(file);
      var repeated = false;
      await expectLater(
        ledger.execute('peer', command(), () async {
          repeated = true;
          return {};
        }),
        throwsA(
          predicate((e) => e.toString().contains('REMOTE_OUTCOME_UNKNOWN')),
        ),
      );
      expect(repeated, false);
      await ledger.close();
    },
  );

  test(
    'persisted pending claim blocks replay after process interruption',
    () async {
      final ledger = await HarnessRemoteLedger.open(file);
      final release = Completer<void>();
      final entered = Completer<void>();
      final run = ledger.execute('peer', command(), () async {
        entered.complete();
        await release.future;
        return {'ok': true};
      });
      await entered.future;
      // Copy a crash-time disk image after fsync and before the reply commit.
      final crash = await file.copy('${directory.path}/crash.jsonl');
      release.complete();
      await run;
      await ledger.close();
      final recovered = await HarnessRemoteLedger.open(crash);
      await expectLater(
        recovered.execute('peer', command(), () async => {}),
        throwsStateError,
      );
      await recovered.close();
    },
  );

  test('capacity is durable and identities are isolated', () async {
    var ledger = await HarnessRemoteLedger.open(file, capacity: 2);
    expect(await ledger.execute('a', command(), () async => {'peer': 'a'}), {
      'peer': 'a',
    });
    expect(await ledger.execute('b', command(), () async => {'peer': 'b'}), {
      'peer': 'b',
    });
    await ledger.close();
    ledger = await HarnessRemoteLedger.open(file, capacity: 2);
    await expectLater(
      ledger.execute('c', command(), () async => {}),
      throwsStateError,
    );
    await ledger.close();
  });

  test('torn journal fails closed', () async {
    await file.writeAsString('{"key":');
    await expectLater(HarnessRemoteLedger.open(file), throwsStateError);
  });
}
