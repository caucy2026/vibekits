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
}
