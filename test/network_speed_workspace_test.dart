import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/presentation/network_speed_workspace.dart';

void main() {
  testWidgets('renders professional speed-test metrics and controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NetworkSpeedWorkspace())),
    );

    expect(find.text('公网带宽测速'), findsOneWidget);
    expect(find.text('延迟'), findsOneWidget);
    expect(find.text('抖动'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('上传'), findsOneWidget);
    expect(find.byKey(const Key('network-speed-start')), findsOneWidget);
    expect(find.text('测量方法'), findsOneWidget);
    final LinearProgressIndicator progress = tester.widget(
      find.byKey(const Key('network-speed-progress')),
    );
    expect(progress.value, 0);
  });
}
