import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/dev_tools/domain/file_hash_service.dart';
import 'package:vibekits/features/dev_tools/domain/serial_port_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';
import 'package:vibekits/features/dev_tools/presentation/utility_collection_workspace.dart';

void main() {
  Future<Finder> pumpTools(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevToolsTab())),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, 'Base64');
    await tester.pump();
    expect(find.text('Base64 编码'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '转换与检查'));
    await tester.pumpAndSettle();
    expect(find.text('Base64 编码'), findsOneWidget);
    return find.byKey(const Key('utility-input'));
  }

  testWidgets('新增语义版本比较可从转换工作区直接执行', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UtilityCollectionWorkspace(initialToolId: 'semver_compare'),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('utility-input')), '2.0.0');
    await tester.enterText(find.widgetWithText(TextField, '另一个版本'), '1.9.9');
    await tester.tap(find.text('执行'));
    await tester.pump();
    expect(find.textContaining('greater'), findsOneWidget);
  });

  testWidgets('程序员计算器默认打开且输入即算', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevToolsTab())),
    );
    expect(find.text('程序员计算器'), findsWidgets);
    final Finder input = find.byKey(const Key('programmer-calculator-input'));
    expect(input, findsOneWidget);

    await tester.enterText(input, '0xFF + 1');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('calculator-DEC')),
        matching: find.text('256'),
      ),
      findsOneWidget,
    );
    expect(find.text('100'), findsOneWidget);

    await tester.tap(find.text('QWORD  64 位'));
    await tester.pump();
    await tester.tap(find.text('BYTE  8 位').last);
    await tester.pumpAndSettle();
    expect(find.text('QWORD  64 位'), findsNothing);
    expect(find.byTooltip('复制当前结果'), findsOneWidget);
  });

  testWidgets('工具列表明确显示 Clash Verge 和轻量虚拟机', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevToolsTab())),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, 'Clash Verge');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Clash Verge / 虚拟机'));
    await tester.pump();
    expect(
      find.byKey(const Key('current-tool-harness-activity')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('dev-tools-sidebar')),
        matching: find.byKey(const Key('current-tool-harness-activity')),
      ),
      findsNothing,
    );
    expect(find.text('Clash Verge'), findsWidgets);
    expect(find.text('轻量虚拟机'), findsOneWidget);
    expect(find.byKey(const Key('mihomo-start')), findsOneWidget);
    await tester.tap(find.text('轻量虚拟机'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qemu-start')), findsOneWidget);
  });

  testWidgets('DEV-002 执行并将结果继续作为输入', (WidgetTester tester) async {
    final Finder input = await pumpTools(tester);

    await tester.enterText(input, 'Hello');
    await tester.tap(find.text('执行'));
    await tester.pump();

    // 输出区显示 Base64 结果。
    expect(find.text('SGVsbG8='), findsOneWidget);

    await tester.tap(find.text('结果作为输入'));
    await tester.pump();

    // 交换后原输出进入输入框，输出区被清空。
    expect(find.text('SGVsbG8='), findsOneWidget);
  });

  testWidgets('DEV-003 转换失败保留输入', (WidgetTester tester) async {
    final Finder input = await pumpTools(tester);

    // 选择 Base64 解码工具。
    final Finder decoder = find.byKey(
      const ValueKey<String>('utility-base64_decode'),
    );
    final Finder strip = find.byKey(
      const ValueKey<String>('utility-tool-strip-编码转换'),
    );
    for (
      int attempt = 0;
      attempt < 8 && decoder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(strip, const Offset(-480, 0));
      await tester.pump();
    }
    await tester.tap(decoder);
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

    await tester.tap(find.byTooltip('清空'));
    await tester.pump();
    expect(find.text('SGVsbG8='), findsNothing);
  });

  testWidgets('代码统计融合在转换与检查并提供目录选择', (WidgetTester tester) async {
    await pumpTools(tester);
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, '代码统计');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '转换与检查'));
    await tester.pumpAndSettle();

    expect(find.text('代码统计'), findsWidgets);
    expect(
      find.byKey(const Key('code-statistics-pick-directory')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('utility-run')), findsOneWidget);
  });

  testWidgets('重复文件入口打开专用扫描工作区', (WidgetTester tester) async {
    await pumpTools(tester);
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, '重复文件');
    await tester.pump();
    final Finder entry = find.widgetWithText(ListTile, '重复文件');
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('duplicates-pick-directory')), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);
    expect(find.text('执行'), findsNothing);
  });

  testWidgets('串口入口从统一工具列表打开完整工作区', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            serialPortLister: () async => <SerialPortDescriptor>[],
          ),
        ),
      ),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, '串口');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '串口调试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('serial-port-name')), findsOneWidget);
    expect(find.byKey(const Key('serial-baud-rate')), findsOneWidget);
    expect(find.byKey(const Key('serial-open')), findsOneWidget);
    expect(find.text('执行'), findsNothing);
  });

  testWidgets('文件哈希选择后自动计算并显示 SHA-256', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_hash_ui');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File source = File('${sandbox.path}${Platform.pathSeparator}abc.txt')
      ..writeAsStringSync('abc');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            fileHashPickFiles: () async => <String>[source.path],
            fileHashCalculator:
                (
                  String path,
                  FileHashAlgorithm algorithm,
                  FileHashCancellation cancellation,
                  FileHashProgress onProgress,
                ) async {
                  onProgress(3, 3);
                  return FileHashResult(
                    path: path,
                    algorithm: algorithm,
                    totalBytes: 3,
                    digest: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
                  );
                },
          ),
        ),
      ),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, '文件哈希');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '文件哈希'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hash-pick-files')), findsOneWidget);
    expect(find.text('SHA-256'), findsOneWidget);
    expect(find.text('执行'), findsNothing);

    await tester.tap(find.byKey(const Key('hash-pick-files')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('abc.txt'), findsOneWidget);
    expect(
      find.text(
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      ),
      findsOneWidget,
    );
  });
}
