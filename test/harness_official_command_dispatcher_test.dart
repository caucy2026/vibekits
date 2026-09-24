import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_command_dispatcher.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';

void main() {
  test('remote prompt uses official session API with stable request ID', () async {
    final adapter = _Adapter();
    await HarnessOfficialCommandDispatcher(adapter).prompt(
      sessionId: 'session-1',
      requestId: 'request-1',
      text: '清理闲置缓存',
    );
    expect(adapter.envelope?['method'], 'session.prompt');
    expect(adapter.envelope?['payload'], <String, Object?>{
      'sessionId': 'session-1',
      'requestId': 'request-1',
      'mode': 'queue',
      'text': '清理闲置缓存',
    });
  });

  test('official rejection is not reported as accepted', () async {
    final adapter = _Adapter(ok: false);
    await expectLater(
      HarnessOfficialCommandDispatcher(adapter).prompt(
        sessionId: 'session-1',
        requestId: 'request-1',
        text: '清理闲置缓存',
      ),
      throwsStateError,
    );
  });
}

class _Adapter implements HarnessRemoteApiAdapter {
  _Adapter({this.ok = true});

  final bool ok;
  Map<String, dynamic>? envelope;

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> value, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    envelope = value;
    return <String, dynamic>{
      'result': <String, Object?>{'ok': ok, 'value': <String, Object?>{}},
    };
  }

  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async => [];

  @override
  Future<void> close() async {}
}
