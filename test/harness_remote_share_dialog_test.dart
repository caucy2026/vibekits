import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/presentation/official_harness_workspace.dart';

void main() {
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
    expect(find.byKey(const Key('harness-remote-peer-id')), findsOneWidget);
    expect(
      find.byKey(const Key('harness-remote-peer-password')),
      findsOneWidget,
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
