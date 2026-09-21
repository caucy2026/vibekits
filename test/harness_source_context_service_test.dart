import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_source_context_service.dart';

void main() {
  test('source lookup is direct, bounded, filtered and redacted', () async {
    final home = await Directory.systemTemp.createTemp('source-context-');
    addTearDown(() => home.delete(recursive: true));
    final store = HarnessContinuationStore(home: home);
    final now = DateTime.utc(2026, 9, 19);
    await store.upsert(
      HarnessContinuationRecord(
        id: 'link-1',
        workspace: '/tmp/workspace-a',
        sourceSessionId: 'source-1',
        continuationSessionId: 'child-1',
        sourceTitleSnapshot: '来源任务',
        summary: '目标与下一步',
        sourceMessageCursor: '8',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final service = HarnessSourceContextService(
      store: store,
      historyLoader: (sessionId, cursor) async => <String, Object?>{
        'cursor': 12,
        'records': <Object?>[
          for (final entry in {9: '无关内容', 10: '修复窗口 token=secret-value', 11: '修复窗口后的验证结果'}.entries)
            {'type': 'event', 'event': {'type': 'user/message', 'seq': entry.key, 'data': {'content': entry.value}}},
          {'type': 'event', 'event': {'type': 'request/header', 'seq': 12, 'data': '窗口隐藏系统提示'}},
        ],
      },
    );

    final result = await service.query(
      workspace: '/tmp/workspace-a',
      continuationSessionId: 'child-1',
      query: '窗口',
      limit: 2,
    );

    expect(result['sourceSessionId'], 'source-1');
    expect(result['sourceTitle'], '来源任务');
    expect(result['records'], hasLength(2));
    expect('$result', isNot(contains('secret-value')));
    expect('$result', contains('[REDACTED]'));
    expect('$result', isNot(contains('隐藏系统提示')));
    await expectLater(
      service.query(
        workspace: '/tmp/workspace-b',
        continuationSessionId: 'child-1',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
