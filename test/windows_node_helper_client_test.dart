import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_node_helper_client.dart';
import 'package:vibekits/features/dev_tools/domain/windows_node_helper_protocol.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 21, 12);
  String hash(String value) => List<String>.filled(64, value).join();
  WindowsNodeHelperRequest request() => WindowsNodeHelperRequest(
    protocolVersion: 1,
    operation: WindowsNodeHelperOperation.apply,
    planId: 'plan_12345678',
    planDigest: hash('a'),
    inspectionDigest: hash('b'),
    nonce: 'nonce_1234567890123456',
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 10)),
    actionIds: const <String>['windows.sshd.start_and_enable'],
  );

  late Directory directory;
  late File helper;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('vk_node_helper_');
    helper = File('${directory.path}${Platform.pathSeparator}helper.exe')
      ..writeAsBytesSync(<int>[77, 90]);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  WindowsNodeHelperIdentity identity({
    bool signatureValid = true,
    String publisher = 'Vibekits Test Publisher',
    String? sha,
    int protocolVersion = 1,
  }) => WindowsNodeHelperIdentity(
    signatureValid: signatureValid,
    publisher: publisher,
    sha256: sha ?? hash('c'),
    fileVersion: '1.0.0',
    protocolVersion: protocolVersion,
  );

  test('签名、发布者、哈希和协议任一不匹配都拒绝启动', () async {
    for (final WindowsNodeHelperIdentity invalid in <WindowsNodeHelperIdentity>[
      identity(signatureValid: false),
      identity(publisher: 'Unknown Publisher'),
      identity(sha: hash('d')),
      identity(protocolVersion: 2),
    ]) {
      bool launched = false;
      final WindowsNodeHelperClient client = WindowsNodeHelperClient(
        helper: helper,
        expectedPublisher: 'Vibekits Test Publisher',
        expectedSha256: hash('c'),
        inspectIdentity: (_) async => invalid,
        launch: (_, _) async {
          launched = true;
          return const WindowsNodeHelperLaunchResult(
            exitCode: 0,
            stdout: '{}',
            stderr: '',
          );
        },
        clock: () => now,
      );
      await expectLater(
        client.execute(request()),
        throwsA(isA<WindowsNodeHelperException>()),
      );
      expect(launched, isFalse);
    }
  });

  test('有效签名二进制返回绑定请求的一次性回执', () async {
    final WindowsNodeHelperRequest pending = request();
    final WindowsNodeHelperClient client = WindowsNodeHelperClient(
      helper: helper,
      expectedPublisher: 'Vibekits Test Publisher',
      expectedSha256: hash('c'),
      inspectIdentity: (_) async => identity(),
      launch: (_, String requestJson) async {
        expect(
          jsonDecode(requestJson),
          containsPair('requestDigest', pending.digest),
        );
        return WindowsNodeHelperLaunchResult(
          exitCode: 0,
          stdout: jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'requestDigest': pending.digest,
            'nonce': pending.nonce,
            'receiptId': 'receipt_12345678',
            'completedAt': now.toIso8601String(),
            'actions': <Map<String, Object?>>[
              <String, Object?>{
                'actionId': 'windows.sshd.start_and_enable',
                'status': 'succeeded',
                'beforeDigest': hash('d'),
                'afterDigest': hash('e'),
                'detail': 'Running',
                'elapsedMilliseconds': 300,
              },
            ],
          }),
          stderr: '',
        );
      },
      clock: () => now,
    );
    final WindowsNodeHelperReceipt receipt = await client.execute(pending);
    expect(
      receipt.actions.single.status,
      WindowsNodeHelperActionStatus.succeeded,
    );
    await expectLater(client.execute(pending), throwsA(isA<FormatException>()));
  });

  test('UAC 拒绝、取消和超时保持不同失败状态', () async {
    Future<WindowsNodeHelperFailure> failureFor(
      WindowsNodeHelperLaunchResult result,
    ) async {
      final WindowsNodeHelperClient client = WindowsNodeHelperClient(
        helper: helper,
        expectedPublisher: 'Vibekits Test Publisher',
        expectedSha256: hash('c'),
        inspectIdentity: (_) async => identity(),
        launch: (_, _) async => result,
        clock: () => now,
      );
      try {
        await client.execute(request());
        fail('expected failure');
      } on WindowsNodeHelperException catch (error) {
        return error.failure;
      }
    }

    expect(
      await failureFor(
        const WindowsNodeHelperLaunchResult(
          exitCode: 1,
          stdout: '',
          stderr: '',
          uacDenied: true,
        ),
      ),
      WindowsNodeHelperFailure.uacDenied,
    );
    expect(
      await failureFor(
        const WindowsNodeHelperLaunchResult(
          exitCode: 1,
          stdout: '',
          stderr: '',
          cancelled: true,
        ),
      ),
      WindowsNodeHelperFailure.cancelled,
    );
    expect(
      await failureFor(
        const WindowsNodeHelperLaunchResult(
          exitCode: 1,
          stdout: '',
          stderr: '',
          timedOut: true,
        ),
      ),
      WindowsNodeHelperFailure.timeout,
    );
  });
}
