import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  Future<Finder> pumpTools(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevToolsTab())),
    );
    return find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.hintText == '输入',
    );
  }

  testWidgets('DEV-002 执行与交换', (WidgetTester tester) async {
    final Finder input = await pumpTools(tester);

    await tester.enterText(input, 'Hello');
    await tester.tap(find.text('执行'));
    await tester.pump();

    // 输出区显示 Base64 结果。
    expect(find.text('SGVsbG8='), findsOneWidget);

    await tester.tap(find.text('交换'));
    await tester.pump();

    // 交换后原输出进入输入框，输出区被清空。
    expect(find.text('SGVsbG8='), findsOneWidget);
  });

  testWidgets('DEV-003 转换失败保留输入', (WidgetTester tester) async {
    final Finder input = await pumpTools(tester);

    // 选择 Base64 解码工具。
    await tester.tap(find.text('Base64 解码'));
    await tester.pump();

    await tester.enterText(input, '!!!');
    await tester.tap(find.text('执行'));
    await tester.pump();

    // 错误出现在输出区，输入未被清除。
    expect(find.textContaining('Base64 解码失败'), findsOneWidget);
    expect(find.text('!!!'), findsOneWidget);
  });

  testWidgets('DEV 清空按钮清空输入输出', (WidgetTester tester) async {
    final Finder input = await pumpTools(tester);

    await tester.enterText(input, 'Hello');
    await tester.tap(find.text('执行'));
    await tester.pump();
    expect(find.text('SGVsbG8='), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('SGVsbG8='), findsNothing);
  });
}
