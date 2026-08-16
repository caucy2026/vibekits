import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/source_file_saver.dart';
import 'package:vibekits/features/documents/presentation/documents_tab.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    required File source,
    required String initialText,
    required ValueNotifier<int> saveRequest,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  saveRequest.value++,
            },
            child: Focus(
              autofocus: true,
              child: DocumentsTab(
                initialPath: source.path,
                bytesReader: (_) async =>
                    Uint8List.fromList(utf8.encode(initialText)),
                saveRequest: saveRequest,
                saveFile:
                    (
                      String path,
                      Uint8List bytes,
                      int expectedSize,
                      DateTime? expectedModified,
                    ) async {
                      source.writeAsBytesSync(bytes, flush: true);
                      return SourceSaveResult(
                        size: bytes.length,
                        modified: source.lastModifiedSync(),
                      );
                    },
              ),
            ),
          ),
        ),
      ),
    );
    for (
      int attempt = 0;
      attempt < 100 &&
          find.byKey(const Key('document-edit')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('源码识别语言，编辑并用 Ctrl+S 保存', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_source_editor_',
    );
    final File source = File(
      '${sandbox.path}${Platform.pathSeparator}main.dart',
    )..writeAsStringSync('void main() {}\n');
    final ValueNotifier<int> saveRequest = ValueNotifier<int>(0);
    addTearDown(saveRequest.dispose);
    addTearDown(() => sandbox.deleteSync(recursive: true));

    await pumpEditor(
      tester,
      source: source,
      initialText: 'void main() {}\n',
      saveRequest: saveRequest,
    );

    expect(find.text('Dart'), findsWidgets);
    await tester.tap(find.byKey(const Key('document-edit')));
    await tester.pump();
    final Finder editor = find.byKey(const Key('source-editor'));
    await tester.enterText(editor, 'void main() => print("ok");\n');
    await tester.pump();
    expect(find.textContaining('● main.dart'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(source.readAsStringSync(), 'void main() => print("ok");\n');
    expect(find.textContaining('● main.dart'), findsNothing);
  });

  testWidgets('取消编辑恢复最后保存内容', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_source_cancel_',
    );
    final File source = File(
      '${sandbox.path}${Platform.pathSeparator}script.sh',
    )..writeAsStringSync('#!/bin/sh\necho safe\n');
    final ValueNotifier<int> saveRequest = ValueNotifier<int>(0);
    addTearDown(saveRequest.dispose);
    addTearDown(() => sandbox.deleteSync(recursive: true));

    await pumpEditor(
      tester,
      source: source,
      initialText: '#!/bin/sh\necho safe\n',
      saveRequest: saveRequest,
    );
    expect(find.text('Shell'), findsWidgets);
    await tester.tap(find.byKey(const Key('document-edit')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('source-editor')),
      '#!/bin/sh\necho changed\n',
    );
    await tester.tap(find.byKey(const Key('document-cancel-edit')));
    await tester.pump();

    expect(source.readAsStringSync(), '#!/bin/sh\necho safe\n');
    await tester.tap(find.byKey(const Key('document-edit')));
    await tester.pump();
    final TextField editor = tester.widget<TextField>(
      find.byKey(const Key('source-editor')),
    );
    expect(editor.controller?.text, '#!/bin/sh\necho safe\n');
  });
}
