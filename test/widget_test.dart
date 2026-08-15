import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/app/app.dart';

void main() {
  testWidgets('启动后显示五个 Tab 与第一个页面', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    for (final String title in <String>[
      '解压缩',
      'Windows 清理',
      '文档阅读',
      '开发工具',
      '本地模型',
    ]) {
      // 激活 Tab 的标题会同时出现在标签栏和页面标题中，因此至少存在一个。
      expect(find.text(title), findsWidgets);
    }

    // 默认展示 T1 解压缩页面。
    expect(find.text('打开压缩包'), findsOneWidget);
    // 其余页面处于离屏状态。
    expect(find.text('开始扫描'), findsNothing);
  });

  testWidgets('点击 Tab 切换页面', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    await tester.tap(find.text('Windows 清理'));
    await tester.pumpAndSettle();

    expect(find.text('开始扫描'), findsOneWidget);
    expect(find.text('打开压缩包'), findsNothing);
  });

  testWidgets('Ctrl+数字键切换 Tab', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    Future<void> pressCtrlWithKey(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await pressCtrlWithKey(LogicalKeyboardKey.digit3);
    expect(find.text('打开文件'), findsOneWidget);

    await pressCtrlWithKey(LogicalKeyboardKey.digit4);
    expect(find.text('执行'), findsOneWidget);

    await pressCtrlWithKey(LogicalKeyboardKey.digit1);
    expect(find.text('打开压缩包'), findsOneWidget);
  });

  testWidgets('Ctrl+, 打开设置对话框', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
  });
}
