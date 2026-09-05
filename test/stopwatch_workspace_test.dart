import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/presentation/stopwatch_workspace.dart';
import 'package:vibekits/features/dev_tools/domain/time_tools.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  test('Harness 秒表接口按百分之一秒截断格式化', () {
    final ToolResult result = TimeTools.stopwatchFormat('3661.239');
    expect(result, isA<ToolSuccess>());
    expect((result as ToolSuccess).output, '01:01:01.23');
  });

  test('秒表按一秒一百分格式化且不四舍五入', () {
    expect(formatStopwatchDuration(Duration.zero), '00:00:00.00');
    expect(
      formatStopwatchDuration(
        const Duration(hours: 2, minutes: 3, seconds: 4, milliseconds: 569),
      ),
      '02:03:04.56',
    );
  });

  testWidgets('秒表提供表盘、数字、开始暂停、计次和复位', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StopwatchWorkspace())),
    );

    expect(find.bySemanticsLabel('秒表表盘'), findsOneWidget);
    expect(find.text('00:00:00.00'), findsOneWidget);
    expect(find.text('1 秒 = 100 份 · 精度 0.01 秒'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('stopwatch-lap')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('stopwatch-toggle')));
    await tester.pump();
    expect(find.text('暂停'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('stopwatch-lap')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('stopwatch-lap')));
    await tester.pump();
    expect(find.text('计次 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stopwatch-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stopwatch-reset')));
    await tester.pump();
    expect(find.text('00:00:00.00'), findsOneWidget);
    expect(find.text('计次 1'), findsNothing);
  });
}
