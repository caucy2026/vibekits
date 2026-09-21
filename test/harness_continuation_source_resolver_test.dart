import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_source_resolver.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';

void main() {
  test('resolves a title-only official Harness row to real ids', () async {
    final adapter = _FakeAdapter();
    final source = await HarnessContinuationSourceResolver(
      adapter,
    ).resolve(requestedTitle: '远程仿真安全测试23小时');
    expect(source.workspaceId, 'workspace-real');
    expect(source.sessionId, 'session-real');
    expect(source.title, '远程仿真安全测试');
  });
}

class _FakeAdapter implements HarnessRemoteApiAdapter {
  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'workspaceId': 'workspace-real',
          'title': 'harness',
          'sessionIds': <String>['session-other', 'session-real'],
        },
      ];

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) async => <String, dynamic>{
    'result': <String, dynamic>{
      'ok': true,
      'value': <String, dynamic>{
        'projections': <String, dynamic>{
          'values': <String, dynamic>{
            'title': envelope['payload']['sessionId'] == 'session-real'
                ? '远程仿真安全测试'
                : '别的会话',
          },
        },
      },
    },
  };

  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) => const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> close() async {}
}
