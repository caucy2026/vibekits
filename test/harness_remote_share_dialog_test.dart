import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/presentation/official_harness_workspace.dart';

void main() {
  test('remote connector reuses an already selected device ID', () {
    expect(
      selectHarnessRemoteRoutingId(
        enteredId: ' ',
        simulatorRoutingId: '1554650784',
        activeRemoteRoutingId: '9464730211',
      ),
      '1554650784',
    );
    expect(
      selectHarnessRemoteRoutingId(
        enteredId: ' 24955106 ',
        simulatorRoutingId: '1554650784',
      ),
      '24955106',
    );
  });

  test('stale certificate transport failures enter secure re-pairing', () {
    expect(
      shouldRepairRememberedHarnessPeer(
        StateError('REMOTE_OUTCOME_UNKNOWN: REMOTE_DISCONNECTED'),
      ),
      isTrue,
    );
    expect(
      shouldRepairRememberedHarnessPeer(StateError('REMOTE_PERMISSION_DENIED')),
      isFalse,
    );
  });

  testWidgets('PAD controller-only mode never exposes or starts inbound host', (
    tester,
  ) async {
    var hostStarts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarnessRemoteShareDialog(
            configuredExecutable: '/definitely/missing/relay',
            webClientUrl: '',
            embedded: true,
            controllerOnly: true,
            onPaired: () async => hostStarts++,
            onHostStopped: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('连接远程设备'), findsOneWidget);
    expect(
      find.byKey(const Key('harness-coordination-peer-id')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('harness-simulator-connect')), findsOneWidget);
    expect(find.text('协同'), findsOneWidget);
    expect(find.text('仿真'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('harness-coordination-first-connect-options')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('harness-coordination-force-relay')),
      findsOneWidget,
    );
    expect(find.text('允许别人协助本机'), findsNothing);
    expect(find.text('本机 Harness ID'), findsNothing);
    expect(
      find.byKey(const Key('harness-coordination-main-workspace')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(hostStarts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote assistance content stays bounded on a compact display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 602);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => HarnessRemoteShareDialog(
                    configuredExecutable: '/definitely/missing/relay',
                    webClientUrl: '',
                    onPaired: () async {},
                    onHostStopped: () async {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Harness 远程协助'), findsOneWidget);
    expect(find.text('远程协助已关闭'), findsOneWidget);
    expect(find.text('本机 Harness ID'), findsOneWidget);
    expect(
      find.byKey(const Key('harness-simulator-access-enabled')),
      findsOneWidget,
    );
    expect(find.text('允许作为仿真机'), findsOneWidget);
    // Desktop target mode is shared, while initiating assistance is currently
    // a macOS/PAD role. A Windows target must not fail its UI contract merely
    // because it intentionally omits the macOS-only controller fields.
    expect(
      find.byKey(const Key('harness-remote-peer-id')),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
    expect(
      find.byKey(const Key('harness-remote-peer-password')),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
    final scrollable = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollable, findsOneWidget);
    expect(tester.getSize(scrollable).height, lessThanOrEqualTo(434));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote assistance never spans a dual-screen continuous canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => HarnessRemoteShareDialog(
                  configuredExecutable: '/definitely/missing/relay',
                  webClientUrl: '',
                  onPaired: () async {},
                  onHostStopped: () async {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 200));

    final scrollable = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getSize(scrollable).height, lessThanOrEqualTo(430));
    expect(tester.getTopLeft(find.byType(AlertDialog)).dy, lessThan(80));
    expect(tester.takeException(), isNull);
  });
}
