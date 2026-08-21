import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_node_helper_protocol.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 21, 12);
  String repeated(String value) => List<String>.filled(64, value).join();
  WindowsNodeHelperRequest request({
    List<String> actions = const <String>['windows.sshd.start_and_enable'],
    Map<String, Object?> parameters = const <String, Object?>{},
    String nonce = 'nonce_1234567890123456',
  }) => WindowsNodeHelperRequest(
    protocolVersion: WindowsNodeHelperRequest.currentProtocolVersion,
    operation: WindowsNodeHelperOperation.apply,
    planId: 'plan_12345678',
    planDigest: repeated('a'),
    inspectionDigest: repeated('b'),
    nonce: nonce,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 10)),
    actionIds: actions,
    parameters: parameters,
  );

  test('协议摘要稳定且禁止未知动作和任意脚本参数', () {
    final WindowsNodeHelperRequest first = request(
      parameters: <String, Object?>{'cidr': '192.168.3.0/24', 'port': 22},
    );
    final WindowsNodeHelperRequest reordered = request(
      parameters: <String, Object?>{'port': 22, 'cidr': '192.168.3.0/24'},
    );
    expect(first.digest, reordered.digest);
    expect(
      () => request(actions: <String>['windows.unknown.action']),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => request(
        parameters: <String, Object?>{
          'nested': <String, Object?>{'script': 'Remove-Item C:\\'},
        },
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('过期、摘要格式错误和 nonce 重放全部被拒绝', () {
    final WindowsNodeHelperReplayGuard guard = WindowsNodeHelperReplayGuard();
    final WindowsNodeHelperRequest valid = request();
    guard.accept(valid, now: now.add(const Duration(minutes: 1)));
    expect(
      () => guard.accept(valid, now: now.add(const Duration(minutes: 1))),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => WindowsNodeHelperProtocol.validateRequest(
        valid,
        now: now.add(const Duration(minutes: 11)),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('一次性回执必须绑定协议、请求摘要、nonce 和白名单动作', () {
    final WindowsNodeHelperRequest valid = request();
    final WindowsNodeHelperReceipt receipt = WindowsNodeHelperReceipt.fromJson(
      <String, Object?>{
        'protocolVersion': 1,
        'requestDigest': valid.digest,
        'nonce': valid.nonce,
        'receiptId': 'receipt_12345678',
        'completedAt': now.add(const Duration(seconds: 2)).toIso8601String(),
        'actions': <Map<String, Object?>>[
          <String, Object?>{
            'actionId': 'windows.sshd.start_and_enable',
            'status': 'succeeded',
            'beforeDigest': repeated('c'),
            'afterDigest': repeated('d'),
            'detail': 'Running / Automatic',
            'elapsedMilliseconds': 1200,
          },
        ],
      },
    );
    expect(
      () => WindowsNodeHelperProtocol.validateReceipt(valid, receipt),
      returnsNormally,
    );
    final WindowsNodeHelperReceipt tampered = WindowsNodeHelperReceipt.fromJson(
      <String, Object?>{
        'protocolVersion': 1,
        'requestDigest': valid.digest,
        'nonce': 'different_nonce_123456789',
        'receiptId': 'receipt_12345678',
        'completedAt': now.toIso8601String(),
        'actions': <Object?>[],
      },
    );
    expect(
      () => WindowsNodeHelperProtocol.validateReceipt(valid, tampered),
      throwsA(isA<FormatException>()),
    );
  });
}
