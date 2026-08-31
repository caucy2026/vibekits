import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_inbound_call_hub.dart';

void main() {
  test('每次调用全局可观察、参数脱敏且终态满足最短展示时间', () async {
    final LmcpInboundCallHub hub = LmcpInboundCallHub(
      minimumVisibleDuration: const Duration(milliseconds: 120),
    );
    addTearDown(hub.dispose);
    final List<List<LmcpInboundCallSnapshot>> events =
        <List<LmcpInboundCallSnapshot>>[];
    final StreamSubscription<List<LmcpInboundCallSnapshot>> subscription = hub
        .changes
        .listen(events.add);
    addTearDown(subscription.cancel);

    final LmcpInboundCallHandle call = hub.begin(
      traceId: 'trace-visible',
      callerAppId: 'com.newlink.kemi',
      callerInstanceId: 'com.newlink.kemi:device-a',
      callerAddress: '192.168.3.8',
      toolId: 'files.send',
      toolName: '发送文件',
      arguments: <String, Object?>{
        'path': '/tmp/demo.txt',
        'accessToken': 'must-never-appear',
      },
      scopeSummary: '已授权 writesData · files.send',
    );

    expect(hub.snapshots, hasLength(1));
    expect(events, isNotEmpty);
    expect(hub.snapshots.single.callerLabel, contains('com.newlink.kemi'));
    expect(hub.snapshots.single.argumentSummary, contains('<已脱敏>'));
    expect(
      hub.snapshots.single.argumentSummary,
      isNot(contains('must-never-appear')),
    );

    call.succeed();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(hub.snapshots.single.phase, LmcpInboundCallPhase.succeeded);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(hub.snapshots, isEmpty);
  });

  test('生产默认提示时间为三秒', () async {
    final LmcpInboundCallHub hub = LmcpInboundCallHub();
    addTearDown(hub.dispose);
    expect(hub.minimumVisibleDuration, const Duration(seconds: 3));
  });

  test('强制关闭立即发布取消信号并在边界执行资源清理', () async {
    final LmcpInboundCallHub hub = LmcpInboundCallHub(
      minimumVisibleDuration: Duration.zero,
    );
    addTearDown(hub.dispose);
    final LmcpInboundCallHandle call = hub.begin(
      traceId: 'trace-stop',
      callerAppId: 'com.newlink.kemi',
      callerInstanceId: 'device-b',
      callerAddress: '192.168.3.9',
      toolId: 'files.send',
      toolName: '发送文件',
      arguments: const <String, Object?>{},
      scopeSummary: 'writesData',
    );
    final Completer<void> releaseCleanup = Completer<void>();
    bool cleanupStarted = false;
    call.cancellation.addCleanupHook(() async {
      cleanupStarted = true;
      await releaseCleanup.future;
    });

    final Future<void> forceClose = hub.forceClose(call.traceId);
    await call.cancellation.whenCancelled.timeout(
      const Duration(milliseconds: 100),
    );
    expect(cleanupStarted, isTrue);
    expect(call.cancellation.isCancelled, isTrue);
    expect(
      () => call.cancellation.throwIfCancelled(),
      throwsA(isA<LmcpUserTerminatedException>()),
    );

    releaseCleanup.complete();
    await forceClose;
  });
}
