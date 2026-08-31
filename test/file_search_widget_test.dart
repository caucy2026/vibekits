import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_hash_service.dart';
import 'package:vibekits/features/dev_tools/domain/file_search_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';
import 'package:vibekits/features/dev_tools/presentation/file_search_workspace.dart';

void main() {
  testWidgets('后台搜索中销毁工作区不会阻塞界面关闭', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Completer<void> cancelled = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileSearchWorkspace(
            directoryPicker: () async => r'D:\workspace',
            searchRunner:
                (
                  FileSearchRequest request,
                  FileSearchCancellation cancellation,
                  FileSearchProgressCallback onProgress,
                ) async {
                  final Completer<FileSearchResult> result =
                      Completer<FileSearchResult>();
                  cancellation.addCancelListener(() {
                    cancelled.complete();
                    result.complete(
                      const FileSearchResult(
                        matches: <FileSearchMatch>[],
                        cancelled: true,
                        truncated: false,
                        visitedFiles: 0,
                        skippedFiles: 0,
                        elapsed: Duration(milliseconds: 1),
                      ),
                    );
                  });
                  return result.future;
                },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('file-search-pick-directory')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('file-search-query')), 'x');
    await tester.tap(find.byKey(const Key('file-search-run')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await cancelled.future.timeout(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件搜索在 1024×700 开发工具布局中无溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevToolsTab())),
    );
    final Finder toolSearch = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(toolSearch, '文件搜索');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dev-tool-nav-file_search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('file-search-query')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件搜索用默认选项一键搜索并提供结果动作', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const String root = r'D:\workspace';
    const String path = r'D:\workspace\lib\app.dart';
    String? revealed;
    String? hashed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileSearchWorkspace(
            directoryPicker: () async => root,
            searchRunner:
                (
                  FileSearchRequest request,
                  FileSearchCancellation cancellation,
                  FileSearchProgressCallback onProgress,
                ) async {
                  expect(request.root, root);
                  expect(request.query, 'app');
                  expect(request.recursive, isTrue);
                  expect(request.includeHidden, isFalse);
                  onProgress(
                    const FileSearchProgress(
                      currentPath: path,
                      visitedFiles: 8,
                      matchedFiles: 1,
                      skippedFiles: 0,
                    ),
                  );
                  return FileSearchResult(
                    matches: <FileSearchMatch>[
                      FileSearchMatch(
                        path: path,
                        name: 'app.dart',
                        size: 2048,
                        modified: DateTime(2026, 8, 17),
                      ),
                    ],
                    cancelled: false,
                    truncated: false,
                    visitedFiles: 8,
                    skippedFiles: 0,
                    elapsed: const Duration(milliseconds: 25),
                  );
                },
            reveal: (String value) async => revealed = value,
            onHashRequested: (String value) => hashed = value,
          ),
        ),
      ),
    );

    expect(find.text('包含子文件夹'), findsNothing);
    await tester.tap(find.byKey(const Key('file-search-pick-directory')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('file-search-query')), 'app');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('app.dart'), findsOneWidget);
    expect(find.textContaining('找到 1 个'), findsOneWidget);
    await tester.tap(find.byTooltip('在文件管理器中定位'));
    await tester.pump();
    expect(revealed, path);
    await tester.tap(find.byTooltip('计算 SHA-256'));
    expect(hashed, path);

    await tester.tap(find.byKey(const Key('file-search-options')));
    await tester.pumpAndSettle();
    expect(find.text('包含子文件夹'), findsOneWidget);
    expect(find.text('包含隐藏项'), findsOneWidget);
    expect(find.byKey(const Key('file-search-extensions')), findsOneWidget);
    expect(find.byKey(const Key('file-search-minimum-size')), findsOneWidget);
    expect(find.byKey(const Key('file-search-modified-days')), findsOneWidget);
  });

  testWidgets('文件搜索运行中可停止且保留部分结果', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Completer<void> started = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileSearchWorkspace(
            directoryPicker: () async => r'D:\workspace',
            searchRunner:
                (
                  FileSearchRequest request,
                  FileSearchCancellation cancellation,
                  FileSearchProgressCallback onProgress,
                ) async {
                  onProgress(
                    const FileSearchProgress(
                      currentPath: r'D:\workspace\partial.txt',
                      visitedFiles: 4,
                      matchedFiles: 1,
                      skippedFiles: 0,
                    ),
                  );
                  started.complete();
                  while (!cancellation.isCancelled) {
                    await Future<void>.delayed(const Duration(milliseconds: 5));
                  }
                  return FileSearchResult(
                    matches: <FileSearchMatch>[
                      FileSearchMatch(
                        path: r'D:\workspace\partial.txt',
                        name: 'partial.txt',
                        size: 10,
                        modified: DateTime(2026, 8, 17),
                      ),
                    ],
                    cancelled: true,
                    truncated: false,
                    visitedFiles: 4,
                    skippedFiles: 0,
                    elapsed: const Duration(milliseconds: 20),
                  );
                },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('file-search-pick-directory')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('file-search-query')), 'part');
    await tester.tap(find.byKey(const Key('file-search-run')));
    await tester.pump();
    await started.future;
    expect(find.byKey(const Key('file-search-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('file-search-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('partial.txt'), findsOneWidget);
    expect(find.textContaining('已取消'), findsOneWidget);
  });

  testWidgets('搜索结果一键进入文件哈希并自动计算', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_search_to_hash',
    );
    final File source = File('${sandbox.path}${Platform.pathSeparator}app.dart')
      ..writeAsStringSync('void main() {}');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            fileSearchDirectoryPicker: () async => sandbox.path,
            fileSearchRunner:
                (
                  FileSearchRequest request,
                  FileSearchCancellation cancellation,
                  FileSearchProgressCallback onProgress,
                ) async => FileSearchResult(
                  matches: <FileSearchMatch>[
                    FileSearchMatch(
                      path: source.path,
                      name: 'app.dart',
                      size: source.lengthSync(),
                      modified: source.lastModifiedSync(),
                    ),
                  ],
                  cancelled: false,
                  truncated: false,
                  visitedFiles: 1,
                  skippedFiles: 0,
                  elapsed: const Duration(milliseconds: 1),
                ),
            fileHashCalculator:
                (
                  String path,
                  FileHashAlgorithm algorithm,
                  FileHashCancellation cancellation,
                  FileHashProgress onProgress,
                ) async {
                  expect(path, source.path);
                  expect(algorithm, FileHashAlgorithm.sha256);
                  onProgress(source.lengthSync(), source.lengthSync());
                  return FileHashResult(
                    path: path,
                    algorithm: algorithm,
                    totalBytes: source.lengthSync(),
                    digest: 'search-to-hash-ok',
                  );
                },
          ),
        ),
      ),
    );

    final Finder toolSearch = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(toolSearch, '文件搜索');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dev-tool-nav-file_search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file-search-pick-directory')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('file-search-query')), 'app');
    await tester.tap(find.byKey(const Key('file-search-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('计算 SHA-256'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('文件哈希'), findsWidgets);
    expect(find.text('app.dart'), findsOneWidget);
    expect(find.text('search-to-hash-ok'), findsOneWidget);
  });
}
