import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_tools.dart';
import 'package:vibekits/features/dev_tools/presentation/batch_rename_workspace.dart';

void main() {
  testWidgets('批量重命名从选择目录到确认执行完整闭环', (WidgetTester tester) async {
    Future<void> pumpUntil(Finder finder) async {
      for (
        int attempt = 0;
        attempt < 100 && finder.evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        finder,
        findsWidgets,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((Text widget) => widget.data)
            .whereType<String>()
            .join(' | '),
      );
    }

    final Directory temporary = Directory.systemTemp.createTempSync(
      'vk_rename_widget',
    );
    File('${temporary.path}${Platform.pathSeparator}demo.txt')
        .writeAsStringSync('unchanged-content');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BatchRenameWorkspace(
              directoryPicker: () async => temporary.path,
              planBuilder: (
                String directory,
                BatchRenameOptions options,
              ) async => FileTools.buildBatchRenamePlan(directory, options),
              executor: (BatchRenamePlan plan) async =>
                  FileTools.executeBatchRename(plan),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('batch-rename-pick-directory')));
      await pumpUntil(find.text('当前规则不会改变文件名'));

      final Finder prefixField = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == '前缀',
      );
      await tester.enterText(prefixField, 'done_');
      await pumpUntil(find.text('done_demo.txt'));
      expect(find.text('done_demo.txt'), findsOneWidget);
      expect(find.text('1 个文件已通过冲突与名称检查'), findsOneWidget);

      await tester.tap(find.byKey(const Key('batch-rename-execute')));
      await tester.pumpAndSettle();
      expect(find.text('重命名 1 个文件？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('batch-rename-confirm')));
      await pumpUntil(find.text('已重命名 1 个文件'));

      final File renamed = File(
        '${temporary.path}${Platform.pathSeparator}done_demo.txt',
      );
      expect(renamed.existsSync(), isTrue);
      expect(renamed.readAsStringSync(), 'unchanged-content');
      expect(find.text('已重命名 1 个文件'), findsWidgets);
    } finally {
      temporary.deleteSync(recursive: true);
    }
  });
}
