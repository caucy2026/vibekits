import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/app/app.dart';
import 'package:vibekits/app/app_settings.dart';
import 'package:vibekits/app/main_shell.dart';
import 'package:vibekits/features/documents/presentation/documents_tab.dart';
import 'package:vibekits/features/local_models/presentation/local_models_tab.dart';

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
    await pressCtrlWithKey(LogicalKeyboardKey.keyF);
    expect(find.byType(TextField), findsOneWidget);

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
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('宽窗口使用侧边工作台导航', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VibekitsApp());

    expect(find.byKey(const Key('primary-navigation')), findsOneWidget);
    expect(find.byKey(const Key('primary-navigation-compact')), findsNothing);
    expect(find.text('LOCAL TOOLKIT'), findsOneWidget);
  });

  testWidgets('1024 宽窗口自动使用紧凑顶部导航', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 700);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VibekitsApp());

    expect(find.byKey(const Key('primary-navigation')), findsNothing);
    expect(find.byKey(const Key('primary-navigation-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色主题可渲染完整主界面', (WidgetTester tester) async {
    final AppSettingsController settings = AppSettingsController();
    settings.value = const AppSettings(themeMode: ThemeMode.dark);
    addTearDown(settings.dispose);

    await tester.pumpWidget(VibekitsApp(settingsController: settings));

    final BuildContext context = tester.element(find.byType(MainShell));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(find.text('系统就绪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统打开文档时自动路由到文档模块', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_open');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File source = File(
      '${sandbox.path}${Platform.pathSeparator}startup.dart',
    )..writeAsStringSync('void startupRouteWorks() {}');

    await tester.pumpWidget(VibekitsApp(initialFilePath: source.path));
    await tester.pumpAndSettle();

    expect(find.text('文档阅读'), findsWidgets);
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      source.path,
    );
    expect(find.text('打开压缩包'), findsNothing);
  });

  testWidgets('拖入文件后自动选择文档工具并立即打开', (WidgetTester tester) async {
    final StreamController<List<String>> drops =
        StreamController<List<String>>.broadcast();
    addTearDown(() async {
      await drops.close();
    });
    final File source = File('pubspec.yaml').absolute;

    await tester.pumpWidget(VibekitsApp(droppedFiles: drops.stream));
    drops.add(<String>[source.path]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('文档阅读'), findsWidgets);
    expect(find.textContaining('已用文档阅读打开 pubspec.yaml'), findsOneWidget);
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      source.path,
    );
    final Key? firstRequestKey = tester
        .widget<DocumentsTab>(find.byType(DocumentsTab))
        .key;
    drops.add(<String>[source.path]);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).key,
      isNot(firstRequestKey),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('本地模型页只展示已实现的管理能力', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_models_ui',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: LocalModelsTab(directory: sandbox.path)),
    );
    await tester.pumpAndSettle();

    expect(find.text('导入模型'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
    expect(find.textContaining('仅管理本地文件'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.textContaining('待接入'), findsNothing);
  });
}
