import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/git_repository_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('Git 工作区一次选择后展示变更、Diff 和日志', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int inspections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            gitPickDirectory: () async => r'D:\project',
            gitInspect: (String path) async {
              inspections++;
              return const GitRepositorySnapshot(
                root: r'D:\project',
                branch: 'main...origin/main',
                status: ' M lib/main.dart',
                diff: '-old\n+new',
                log: 'abc123\t2026-08-16\tupdate',
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
    await tester.enterText(search, 'Git 工作区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Git 工作区'));
    await tester.pump();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(inspections, 1);
    expect(find.textContaining('lib/main.dart'), findsOneWidget);

    await tester.tap(find.text('Diff'));
    await tester.pump();
    expect(find.textContaining('-old'), findsOneWidget);
    await tester.tap(find.text('日志'));
    await tester.pump();
    expect(find.textContaining('update'), findsOneWidget);
  });
}
