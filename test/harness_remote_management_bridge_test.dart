import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_management_bridge.dart';

void main() {
  test('首次没有配对范围时保持最小监听并进入等待态', () async {
    final Object owner = Object();
    HarnessRemoteManagementBridge.bind(
      owner: owner,
      startHost: () async {
        throw StateError('REMOTE_PAIRING_SCOPE_NOT_PERSISTED');
      },
      stopHost: () async {},
      localWorkspaceIds: () => const <String>{},
    );
    addTearDown(() => HarnessRemoteManagementBridge.unbind(owner));

    await expectLater(HarnessRemoteManagementBridge.startHost(), completes);
  });

  test('配对载体或后端真实失败仍向上返回并保持失败关闭', () async {
    final Object owner = Object();
    HarnessRemoteManagementBridge.bind(
      owner: owner,
      startHost: () async {
        throw StateError('REMOTE_CARRIER_NOT_REGISTERED');
      },
      stopHost: () async {},
      localWorkspaceIds: () => const <String>{},
    );
    addTearDown(() => HarnessRemoteManagementBridge.unbind(owner));

    await expectLater(
      HarnessRemoteManagementBridge.startHost(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('REMOTE_CARRIER_NOT_REGISTERED'),
        ),
      ),
    );
  });
}
