import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_message_queue.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vibekits-queue-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('queues are isolated by workspace and session', () async {
    int sequence = 0;
    final HarnessMessageQueueRepository repository =
        HarnessMessageQueueRepository(
          root: root,
          idFactory: () => 'item-${++sequence}',
        );
    await repository.enqueue(
      workspaceId: 'workspace-a',
      sessionId: 'session-a',
      text: 'first',
    );
    await repository.enqueue(
      workspaceId: 'workspace-a',
      sessionId: 'session-b',
      text: 'second',
    );

    expect(
      (await repository.load(
        workspaceId: 'workspace-a',
        sessionId: 'session-a',
      )).single.text,
      'first',
    );
    expect(
      (await repository.load(
        workspaceId: 'workspace-a',
        sessionId: 'session-b',
      )).single.text,
      'second',
    );
  });

  test('edit reorder and delete only operate on queued items', () async {
    int sequence = 0;
    final HarnessMessageQueueRepository repository =
        HarnessMessageQueueRepository(
          root: root,
          idFactory: () => 'item-${++sequence}',
        );
    final first = await repository.enqueue(
      workspaceId: 'workspace',
      sessionId: 'session',
      text: 'one',
    );
    final second = await repository.enqueue(
      workspaceId: 'workspace',
      sessionId: 'session',
      text: 'two',
    );
    await repository.edit(
      workspaceId: 'workspace',
      sessionId: 'session',
      itemId: second.id,
      text: 'two edited',
    );
    await repository.move(
      workspaceId: 'workspace',
      sessionId: 'session',
      itemId: second.id,
      delta: -1,
    );
    await repository.remove(
      workspaceId: 'workspace',
      sessionId: 'session',
      itemId: first.id,
    );

    final items = await repository.load(
      workspaceId: 'workspace',
      sessionId: 'session',
    );
    expect(items.single.id, second.id);
    expect(items.single.text, 'two edited');
  });

  test(
    'dispatch uses stable idempotency key and redacts accepted body',
    () async {
      final HarnessMessageQueueRepository repository =
          HarnessMessageQueueRepository(root: root, idFactory: () => 'message');
      await repository.enqueue(
        workspaceId: 'workspace',
        sessionId: 'session',
        text: 'run exactly once',
      );
      String? receivedKey;
      final scheduler = HarnessMessageQueueScheduler(
        repository: repository,
        workspaceId: 'workspace',
        sessionId: 'session',
        submit: (String text, String idempotencyKey) async {
          expect(text, 'run exactly once');
          receivedKey = idempotencyKey;
          return true;
        },
      );

      expect(await scheduler.dispatchNext(), isTrue);
      expect(receivedKey, 'session:message');
      final running = await repository.load(
        workspaceId: 'workspace',
        sessionId: 'session',
        recover: false,
      );
      expect(running.single.status, HarnessQueueStatus.running);
      expect(running.single.text, isEmpty);
    },
  );

  test(
    'restart recovers dispatching but never duplicates accepted running item',
    () async {
      int sequence = 0;
      final HarnessMessageQueueRepository repository =
          HarnessMessageQueueRepository(
            root: root,
            idFactory: () => 'item-${++sequence}',
          );
      final first = await repository.enqueue(
        workspaceId: 'workspace',
        sessionId: 'session',
        text: 'dispatching',
      );
      await repository.enqueue(
        workspaceId: 'workspace',
        sessionId: 'session',
        text: 'next',
      );
      expect(
        (await repository.claimNext(
          workspaceId: 'workspace',
          sessionId: 'session',
        ))?.id,
        first.id,
      );

      final recovered = await repository.load(
        workspaceId: 'workspace',
        sessionId: 'session',
      );
      expect(recovered.first.status, HarnessQueueStatus.queued);

      final claimedAgain = await repository.claimNext(
        workspaceId: 'workspace',
        sessionId: 'session',
      );
      await repository.markAccepted(
        workspaceId: 'workspace',
        sessionId: 'session',
        itemId: claimedAgain!.id,
      );
      final afterRestart = await repository.load(
        workspaceId: 'workspace',
        sessionId: 'session',
      );
      expect(afterRestart, hasLength(1));
      expect(afterRestart.single.text, 'next');
    },
  );

  test('approval waiting and busy states block automatic dispatch', () async {
    final HarnessMessageQueueRepository repository =
        HarnessMessageQueueRepository(root: root, idFactory: () => 'message');
    await repository.enqueue(
      workspaceId: 'workspace',
      sessionId: 'session',
      text: 'later',
    );
    int calls = 0;
    final scheduler = HarnessMessageQueueScheduler(
      repository: repository,
      workspaceId: 'workspace',
      sessionId: 'session',
      submit: (_, _) async {
        calls += 1;
        return true;
      },
    );
    scheduler.updateHarnessState(busy: true, approvalWaiting: false);
    expect(await scheduler.dispatchNext(), isFalse);
    scheduler.updateHarnessState(busy: false, approvalWaiting: true);
    expect(await scheduler.dispatchNext(), isFalse);
    expect(calls, 0);
  });

  test('queued remote prompt dispatches when Harness becomes ready', () async {
    final repository = HarnessMessageQueueRepository(
      root: root,
      idFactory: () => 'remote-message',
    );
    final dispatched = Completer<String>();
    final scheduler = HarnessMessageQueueScheduler(
      repository: repository,
      workspaceId: 'workspace',
      sessionId: 'session',
      submit: (text, _) async {
        dispatched.complete(text);
        return true;
      },
    );
    scheduler.updateHarnessState(busy: true, approvalWaiting: false);
    await repository.enqueue(
      workspaceId: 'workspace',
      sessionId: 'session',
      text: 'remote request',
      source: HarnessMessageSource.remotePeer,
    );
    expect(await scheduler.dispatchNext(), isFalse);
    scheduler.updateHarnessState(busy: false, approvalWaiting: false);
    expect(
      await dispatched.future.timeout(const Duration(seconds: 1)),
      'remote request',
    );
  });
}
