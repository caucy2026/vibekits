import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/presentation/documents_tab.dart';

void main() {
  testWidgets('文档打开记录可恢复并一键清空', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<String>? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsTab(
            initialRecentPaths: const <String>[
              r'C:\Docs\README.md',
              r'C:\Logs\app.log',
            ],
            onRecentPathsChanged: (List<String> paths) async => saved = paths,
          ),
        ),
      ),
    );

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('app.log'), findsOneWidget);
    await tester.tap(find.byTooltip('清空打开记录'));
    await tester.pumpAndSettle();

    expect(find.text('暂无记录'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('支持格式完整可查看且已打开文档可以关闭', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_document_close_',
    );
    final File source = File(
      '${sandbox.path}${Platform.pathSeparator}README.md',
    )..writeAsStringSync('# Preview');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsTab(
            initialPath: source.path,
            bytesReader: (_) async => Uint8List.fromList('# Preview'.codeUnits),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (
      int attempt = 0;
      attempt < 50 &&
          find.byKey(const Key('document-close')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byTooltip('关闭当前文档'), findsOneWidget);
    await tester.tap(find.byKey(const Key('document-close')));
    await tester.pump();
    expect(find.text('未打开文档'), findsOneWidget);
    expect(find.text('查看全部支持格式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('document-supported-formats')));
    await tester.pumpAndSettle();
    expect(find.textContaining('支持的文档格式'), findsOneWidget);
    expect(find.textContaining('.txt'), findsWidgets);
    expect(find.textContaining('.md'), findsWidgets);
    expect(find.textContaining('.json'), findsOneWidget);
    expect(find.textContaining('.epub'), findsOneWidget);
    expect(find.textContaining('.bin'), findsOneWidget);
    expect(find.textContaining('makefile'), findsOneWidget);
  });
}
