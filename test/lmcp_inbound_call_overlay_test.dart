import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_inbound_call_hub.dart';
import 'package:vibekits/features/dev_tools/presentation/lmcp_inbound_call_overlay.dart';

void main() {
  testWidgets('非模态卡展示调用方/工具/状态、详情并可强制关闭', (WidgetTester tester) async {
    final LmcpInboundCallHub hub = LmcpInboundCallHub();
    addTearDown(hub.dispose);
    final LmcpInboundCallHandle call = hub.begin(
      traceId: 'trace-widget',
      callerAppId: 'com.newlink.kemi',
      callerInstanceId: 'KEMI@device-c',
      callerAddress: '192.168.3.10',
      toolId: 'adb.shell',
      toolName: '执行 ADB 命令',
      arguments: <String, Object?>{
        'command': 'getprop ro.product.model',
        'password': 'secret-value',
      },
      scopeSummary: '已授权 controlsDevice · adb.shell',
    );
    bool cleaned = false;
    call.cancellation.addCleanupHook(() => cleaned = true);

    await tester.pumpWidget(
      MaterialApp(
        home: LmcpInboundCallOverlay(
          hub: hub,
          child: const Scaffold(body: Center(child: Text('主界面仍可操作'))),
        ),
      ),
    );

    expect(find.text('主界面仍可操作'), findsOneWidget);
    expect(find.textContaining('com.newlink.kemi'), findsOneWidget);
    expect(find.text('执行 ADB 命令'), findsOneWidget);
    expect(find.text('正在调用'), findsOneWidget);
    expect(find.text('调用信息'), findsOneWidget);
    expect(find.text('强制关闭'), findsOneWidget);

    await tester.tap(find.text('调用信息'));
    await tester.pump();
    expect(find.textContaining('trace-widget'), findsOneWidget);
    expect(find.textContaining('<已脱敏>'), findsOneWidget);
    expect(find.textContaining('secret-value'), findsNothing);

    await tester.tap(find.text('强制关闭'));
    await tester.pump();
    expect(call.cancellation.isCancelled, isTrue);
    expect(cleaned, isTrue);
    expect(
      find.byKey(const ValueKey<String>('lmcp-call-trace-widget')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3, milliseconds: 100));
    expect(
      find.byKey(const ValueKey<String>('lmcp-call-trace-widget')),
      findsNothing,
    );
  });
}
