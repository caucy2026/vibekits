import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_source_resolver.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';

void main() {
  test('provisions the clicked ungrouped cwd when catalog is empty', () async {
    final adapter = _EmptyCatalogAdapter();
    final source = await HarnessContinuationSourceResolver(
      adapter,
    ).resolve(requestedSessionId: 'session-real', requestedTitle: '远程仿真安全测试');
    expect(source.workspaceId, 'workspace-provisioned');
    expect(source.sessionId, 'session-real');
    expect(adapter.provisioned, ['/work/harness']);
    expect(adapter.attached, [
      {'workspaceId': 'workspace-provisioned', 'sessionId': 'session-real'},
    ]);
  });
  test('does not provision an empty catalog from a title alone', () async {
    final adapter = _EmptyCatalogAdapter();
    await expectLater(
      HarnessContinuationSourceResolver(
        adapter,
      ).resolve(requestedTitle: '远程仿真安全测试'),
      throwsFormatException,
    );
    expect(adapter.provisioned, isEmpty);
  });
  test(
    'does not substitute a same-title session for an explicit missing ID',
    () async {
      await expectLater(
        HarnessContinuationSourceResolver(
          _FakeAdapter(),
        ).resolve(requestedSessionId: 'missing-id', requestedTitle: '远程仿真安全测试'),
        throwsFormatException,
      );
    },
  );
  test(
    'rejects ambiguous titles instead of selecting another session',
    () async {
      await expectLater(
        HarnessContinuationSourceResolver(
          _FakeAdapter(duplicate: true),
        ).resolve(requestedTitle: '远程仿真安全测试'),
        throwsFormatException,
      );
    },
  );
  test('reports missing titles rather than silently completing', () async {
    await expectLater(
      HarnessContinuationSourceResolver(
        _FakeAdapter(),
      ).resolve(requestedTitle: '不存在'),
      throwsFormatException,
    );
  });
  test('resolves a title-only official Harness row to real ids', () async {
    final adapter = _FakeAdapter();
    final source = await HarnessContinuationSourceResolver(
      adapter,
    ).resolve(requestedTitle: '远程仿真安全测试23小时');
    expect(source.workspaceId, 'workspace-real');
    expect(source.sessionId, 'session-real');
    expect(source.title, '远程仿真安全测试');
  });
  test(
    'resolves an ungrouped sidebar session from the official list',
    () async {
      final source = await HarnessContinuationSourceResolver(
        _FakeAdapter(ungrouped: true),
      ).resolve(requestedSessionId: 'session-real', requestedTitle: '远程仿真安全测试');
      expect(source.workspaceId, 'workspace-real');
      expect(source.sessionId, 'session-real');
    },
  );
}

class _EmptyCatalogAdapter extends _FakeAdapter
    implements HarnessRemoteWorkspaceProvisioner {
  final provisioned = <String>[];
  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async => [];
  @override
  Future<String> ensureWorkspacePath(String path) async {
    provisioned.add(path);
    return 'workspace-provisioned';
  }
}

class _FakeAdapter implements HarnessRemoteApiAdapter {
  _FakeAdapter({this.duplicate = false, this.ungrouped = false});
  final bool duplicate;
  final bool ungrouped;
  final attached = <Object?>[];
  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'workspaceId': 'workspace-real',
          'title': 'harness',
          'path': '/work/harness',
          'sessionIds': ungrouped
              ? <String>[]
              : <String>['session-other', 'session-real'],
        },
      ];

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (envelope['method'] == 'workspace.insertSessionBefore') {
      throw StateError('Ordering cannot attach an unaccounted session');
    }
    if (envelope['method'] == 'session.create') {
      attached.add(envelope['payload']);
      return <String, dynamic>{
        'result': <String, dynamic>{
          'ok': true,
          'value': <String, dynamic>{
            'sessionId': envelope['payload']['sessionId'],
          },
        },
      };
    }
    return envelope['method'] == 'session.list'
        ? <String, dynamic>{
            'result': <String, dynamic>{
              'ok': true,
              'value': <String, dynamic>{
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'sessionId': 'session-real',
                    'cwd': '/work/harness',
                    'projections': <String, dynamic>{
                      'values': <String, dynamic>{'title': '远程仿真安全测试'},
                    },
                  },
                ],
              },
            },
          }
        : <String, dynamic>{
            'result': <String, dynamic>{
              'ok': true,
              'value': <String, dynamic>{
                'projections': <String, dynamic>{
                  'values': <String, dynamic>{
                    'title':
                        (duplicate ||
                            envelope['payload']['sessionId'] == 'session-real')
                        ? '远程仿真安全测试'
                        : '别的会话',
                  },
                },
              },
            },
          };
  }

  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) => const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> close() async {}
}
