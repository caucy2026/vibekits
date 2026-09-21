import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_coordinator.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';

void main() {
  late Directory temporary;
  late HarnessContinuationStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('continuation-flow-');
    store = HarnessContinuationStore(home: temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('creates the empty child before summarizing the source', () async {
    final adapter = _FakeAdapter();
    final coordinator = HarnessContinuationCoordinator(
      adapter: adapter,
      store: store,
      pollInterval: Duration.zero,
      timeout: const Duration(seconds: 1),
    );

    final record = await coordinator.create(
      workspace: '/tmp/project',
      workspaceId: 'workspace-1',
      sourceSessionId: 'source-1',
      sourceTitle: '修复任务',
    );

    expect(record.continuationSessionId, 'child-1');
    expect(adapter.renamedTitle, '修复任务 2');
    expect(record.summary, contains('完成真实的派生会话功能'));
    expect(adapter.methods, <String>[
      'session.create',
      'workspace.insertSessionBefore',
      'session.rename',
      'session.history',
      'session.history',
    ]);
    final saved = (await store.load()).single;
    expect(saved.continuationSessionId, record.continuationSessionId);
    expect(saved.sourceSessionId, record.sourceSessionId);
    expect(saved.continuationTitleSnapshot, '修复任务 2');
    expect(saved.summary, record.summary.trim());
  });

  test('announces the real child before persistence verification', () async {
    final adapter = _FakeAdapter();
    final coordinator = HarnessContinuationCoordinator(
      adapter: adapter,
      store: store,
      pollInterval: Duration.zero,
      timeout: const Duration(seconds: 1),
    );
    final observed = <String>[];

    final child = await coordinator.createEmptyChild(
      workspaceId: 'workspace-1',
      sourceTitle: '长任务',
      beforeSessionId: 'source-1',
      onCreated: (sessionId, title) async {
        observed.add('$sessionId|$title|${adapter.methods.join(',')}');
      },
    );

    expect(child, ('child-1', '长任务 2'));
    expect(observed, <String>[
      'child-1|长任务 2|session.create,workspace.insertSessionBefore,session.rename',
    ]);
    expect(adapter.methods.last, 'session.history');
  });

  test(
    'adopts an official UI-created child without creating a duplicate',
    () async {
      final adapter = _FakeAdapter();
      final coordinator = HarnessContinuationCoordinator(
        adapter: adapter,
        store: store,
        pollInterval: Duration.zero,
        timeout: const Duration(seconds: 1),
      );

      final child = await coordinator.prepareExistingChild(
        workspaceId: 'workspace-1',
        childSessionId: 'child-1',
        sourceTitle: '长任务',
        sourceSessionId: 'source-1',
      );

      expect(child, ('child-1', '长任务 2'));
      expect(adapter.methods, isNot(contains('session.create')));
      expect(adapter.methods, <String>[
        'workspace.insertSessionBefore',
        'session.rename',
        'session.history',
      ]);
    },
  );

  test('empty source still creates a bounded structured handoff', () async {
    final adapter = _FakeAdapter(validSummary: false);
    final coordinator = HarnessContinuationCoordinator(
      adapter: adapter,
      store: store,
      pollInterval: Duration.zero,
      timeout: const Duration(milliseconds: 2),
    );

    final record = await coordinator.create(
      workspace: '/tmp/project',
      workspaceId: 'workspace-1',
      sourceSessionId: 'source-1',
      sourceTitle: '任务',
    );
    expect(record.summary, contains('来源会话暂无可提取的对话正文'));
    expect(adapter.methods, contains('session.create'));
  });

  test('relation persistence failure rolls back the empty child', () async {
    final badHome = File('${temporary.path}/not-a-directory');
    await badHome.writeAsString('x');
    final adapter = _FakeAdapter();
    final coordinator = HarnessContinuationCoordinator(
      adapter: adapter,
      store: HarnessContinuationStore(home: Directory(badHome.path)),
      pollInterval: Duration.zero,
      timeout: const Duration(seconds: 1),
    );

    await expectLater(
      coordinator.create(
        workspace: '/tmp/project',
        workspaceId: 'workspace-1',
        sourceSessionId: 'source-1',
        sourceTitle: '任务',
      ),
      throwsA(anything),
    );
    expect(adapter.methods.last, 'session.delete');
  });

  test(
    'a non-responsive official create request exits by the hard timeout',
    () async {
      final coordinator = HarnessContinuationCoordinator(
        adapter: _HangingAdapter(),
        store: store,
        timeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        coordinator.createEmptyChild(
          workspaceId: 'workspace-1',
          sourceTitle: '不会卡死',
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}

class _FakeAdapter implements HarnessRemoteApiAdapter {
  _FakeAdapter({this.validSummary = true});

  final bool validSummary;
  final List<String> methods = <String>[];
  String? renamedTitle;

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final method = envelope['method'] as String;
    methods.add(method);
    if (method == 'session.rename') {
      renamedTitle = (envelope['payload'] as Map)['title']?.toString();
    }
    final Object value = switch (method) {
      'session.history' => <String, Object?>{
        'sessionId': (envelope['payload'] as Map)['sessionId'],
        'cursor': 7,
        'header': <String, Object?>{'title': renamedTitle ?? '来源'},
        'records': validSummary
            ? <Object?>[
                <String, Object?>{
                  'type': 'event',
                  'event': <String, Object?>{
                    'type': 'user/message',
                    'seq': 7,
                    'data': <String, Object?>{'text': '完成真实的派生会话功能'},
                  },
                },
              ]
            : const <Object?>[],
      },
      'session.create' => <String, Object?>{'sessionId': 'child-1'},
      'session.rename' => <String, Object?>{'title': renamedTitle, 'seq': 1},
      _ => <String, Object?>{},
    };
    return <String, dynamic>{
      'type': 'server-response',
      'rpcId': envelope['rpcId'],
      'result': <String, dynamic>{'ok': true, 'value': value},
    };
  }

  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) => const Stream<Map<String, dynamic>>.empty();

  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'workspaceId': 'workspace-1',
          'sessionIds': <String>['source-1', 'child-1'],
        },
      ];

  @override
  Future<void> close() async {}
}

class _HangingAdapter implements HarnessRemoteApiAdapter {
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) => Completer<Map<String, dynamic>>().future.timeout(timeout);

  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) => const Stream<Map<String, dynamic>>.empty();

  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async => const [];

  @override
  Future<void> close() async {}
}
