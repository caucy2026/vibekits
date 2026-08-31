import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/github_diagnostics.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('GitHub 诊断逐层展示结果和可执行建议', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            githubDiagnostics: () async => const GithubDiagnosticsReport(
              checks: <DiagnosticCheck>[
                DiagnosticCheck(
                  id: 'dns',
                  label: 'DNS',
                  status: DiagnosticStatus.ok,
                  detail: '140.82.112.4',
                ),
                DiagnosticCheck(
                  id: 'ssh22',
                  label: 'SSH 端口 22',
                  status: DiagnosticStatus.failed,
                  detail: 'blocked',
                ),
              ],
              recommendation: '改用 GitHub 官方 SSH over 443。',
            ),
          ),
        ),
      ),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, 'GitHub');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dev-tool-nav-github_diagnostics')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('github-diagnostics-run')));
    await tester.pumpAndSettle();

    expect(find.text('DNS'), findsOneWidget);
    expect(find.textContaining('140.82'), findsOneWidget);
    expect(find.textContaining('SSH over 443'), findsOneWidget);
  });
}
