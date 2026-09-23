import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_summarizer.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';

void main() {
  for (final failPrompt in [false, true]) {
    test('summary helper stays archived; prompt failure=$failPrompt', () async {
      final adapter = _Adapter(failPrompt);
      final result = HarnessContinuationSummarizer(adapter: adapter).summarize(
        workspaceId: 'workspace',
        sourceSessionId: 'source',
        sourceTitle: 'source title',
        sourceMaterial: 'test handoff',
      );
      if (failPrompt) {
        await expectLater(result, throwsStateError);
      } else {
        expect(await result, contains('目标'));
      }
      expect(adapter.methods.take(3), [
        'session.create',
        'workspace.archiveSession',
        'session.prompt',
      ]);
      expect(adapter.methods.last, 'workspace.archiveSession');
      expect(adapter.methods, isNot(contains('session.delete')));
      expect(adapter.archivedIds, everyElement('helper'));
    });
  }
}

class _Adapter implements HarnessRemoteApiAdapter {
  _Adapter(this.failPrompt);
  final bool failPrompt;
  final methods = <String>[];
  final archivedIds = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final method = envelope['method'] as String;
    methods.add(method);
    if (method == 'session.prompt' && failPrompt)
      throw StateError('fixture failure');
    if (method == 'workspace.archiveSession') {
      archivedIds.add((envelope['payload'] as Map)['sessionId'] as String);
    }
    return {
      'result': {
        'ok': true,
        'value': {
          if (method == 'session.create') 'sessionId': 'helper',
          if (method == 'session.history')
            'records': [
              {
                'type': 'assistant/message',
                'data': '目标 约束 已完成 关键决定 文件与版本 验证结果 未完成项 已知问题 下一步',
              },
            ],
        },
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async => [];
  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) => const Stream.empty();
  @override
  Future<void> close() async {}
}
