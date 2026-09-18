import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_store.dart';

void main() {
  late Directory temporary;
  late HarnessContinuationStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('continuations-');
    store = HarnessContinuationStore(home: temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('round trips records and resolves direct source and children', () async {
    final record = HarnessContinuationRecord(
      id: 'relation-1',
      workspace: '/tmp/project/../project',
      sourceSessionId: 'source-1',
      continuationSessionId: 'child-1',
      sourceTitleSnapshot: '原任务',
      summary: '目标：继续修复\n下一步：运行测试',
      sourceMessageCursor: '42',
      createdAt: DateTime.utc(2026, 9, 19),
      updatedAt: DateTime.utc(2026, 9, 19, 1),
    );

    await store.upsert(record);

    expect(
      (await store.sourceFor('/tmp/project', 'child-1'))?.sourceSessionId,
      'source-1',
    );
    expect(
      (await store.childrenFor(
        '/tmp/project',
        'source-1',
      )).map((item) => item.continuationSessionId),
      ['child-1'],
    );
    expect((await store.load()).single.schemaVersion, 1);
  });

  test('missing and corrupt files load as an empty collection', () async {
    expect(await store.load(), isEmpty);
    await File('${temporary.path}/continuations.json').writeAsString('{no');
    expect(await store.load(), isEmpty);
  });

  test('rejects an oversized summary before writing', () async {
    final record = HarnessContinuationRecord(
      id: 'relation-1',
      workspace: '/tmp/project',
      sourceSessionId: 'source-1',
      continuationSessionId: 'child-1',
      sourceTitleSnapshot: '原任务',
      summary: 'x' * (HarnessContinuationStore.maxSummaryCharacters + 1),
      sourceMessageCursor: '42',
      createdAt: DateTime.utc(2026, 9, 19),
      updatedAt: DateTime.utc(2026, 9, 19),
    );

    await expectLater(store.upsert(record), throwsFormatException);
    expect(await store.load(), isEmpty);
  });

  test('keeps relationship records when either session disappears', () async {
    final record = HarnessContinuationRecord(
      id: 'relation-1',
      workspace: '/tmp/project',
      sourceSessionId: 'missing-source',
      continuationSessionId: 'missing-child',
      sourceTitleSnapshot: '已删除的任务',
      summary: '继续处理。',
      sourceMessageCursor: '8',
      createdAt: DateTime.utc(2026, 9, 19),
      updatedAt: DateTime.utc(2026, 9, 19),
    );
    await store.upsert(record);

    final loaded = await store.load();
    expect(loaded.single.id, record.id);
    expect(loaded.single.sourceSessionId, 'missing-source');
    expect(loaded.single.continuationSessionId, 'missing-child');
  });
}
