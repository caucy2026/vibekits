import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_link_status.dart';
import 'package:vibekits/features/local_models/presentation/harness_connection_badge.dart';

void main() {
  test(
    'either authenticated remote or simulator link lights Harness green',
    () {
      for (var connectedIndex = 0; connectedIndex < 4; connectedIndex++) {
        final links = List<bool>.filled(4, false)..[connectedIndex] = true;
        expect(
          isHarnessConnectionLive(
            remoteControllerConnected: links[0],
            remoteLinkConnected: links[1],
            simulatorControllerConnected: links[2],
            simulatorTargetConnected: links[3],
          ),
          isTrue,
        );
      }
      expect(
        isHarnessConnectionLive(
          remoteControllerConnected: false,
          remoteLinkConnected: false,
          simulatorControllerConnected: false,
          simulatorTargetConnected: false,
        ),
        isFalse,
      );
    },
  );

  testWidgets('Harness light follows authenticated remote connection', (
    tester,
  ) async {
    RustDeskHarnessLinkStatusHub.disconnected();
    addTearDown(RustDeskHarnessLinkStatusHub.disconnected);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HarnessConnectionBadge(running: true, child: Text('Harness')),
        ),
      ),
    );
    expect(
      tester.widget<Badge>(find.byType(Badge)).backgroundColor,
      isNot(Colors.green),
    );

    RustDeskHarnessLinkStatusHub.remoteDataConnected('regression-peer');
    await tester.pump();
    expect(
      tester.widget<Badge>(find.byType(Badge)).backgroundColor,
      Colors.green,
    );

    RustDeskHarnessLinkStatusHub.remoteDataDisconnected('regression-peer');
    await tester.pump();
    expect(
      tester.widget<Badge>(find.byType(Badge)).backgroundColor,
      isNot(Colors.green),
    );
  });
}
