import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_diff_service.dart';
import 'package:vibekits/features/dev_tools/presentation/file_diff_workspace.dart';

void main() {
  testWidgets('文件 Diff 输入两个路径后展示统计并可只看差异', (WidgetTester tester) async {
    Future<FileDiffResult> comparer({
      required String leftPath,
      required String rightPath,
      required bool ignoreWhitespace,
      required bool ignoreCase,
    }) async => FileDiffResult(
      leftPath: leftPath,
      rightPath: rightPath,
      leftEncoding: 'UTF-8',
      rightEncoding: 'UTF-8',
      leftBytes: 8,
      rightBytes: 8,
      lines: const <FileDiffLine>[
        FileDiffLine(
          kind: FileDiffLineKind.equal,
          text: 'same',
          leftLine: 1,
          rightLine: 1,
        ),
        FileDiffLine(kind: FileDiffLineKind.removed, text: 'old', leftLine: 2),
        FileDiffLine(kind: FileDiffLineKind.added, text: 'new', rightLine: 2),
      ],
      addedLines: 1,
      removedLines: 1,
      unchangedLines: 1,
      exactMinimalDiff: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FileDiffWorkspace(compare: comparer)),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '左侧原文件'), 'a.txt');
    await tester.enterText(find.widgetWithText(TextField, '右侧新文件'), 'b.txt');
    await tester.tap(find.byKey(const Key('file-diff-run')));
    await tester.pumpAndSettle();

    expect(find.textContaining('新增 1 行'), findsOneWidget);
    expect(find.text('same'), findsOneWidget);
    expect(find.text('old'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    await tester.tap(find.text('只看差异'));
    await tester.pump();
    expect(find.text('same'), findsNothing);
    expect(find.text('old'), findsOneWidget);
  });
}
