import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_search_service.dart';

void main() {
  test('文件名搜索递归匹配且默认忽略隐藏项', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_name',
    );
    final Directory nested = Directory('${sandbox.path}/nested')..createSync();
    final Directory hidden = Directory('${sandbox.path}/.hidden')..createSync();
    File('${sandbox.path}/config.json').writeAsStringSync('{}');
    File('${nested.path}/app_config.yaml').writeAsStringSync('name: app');
    File('${hidden.path}/secret_config.txt').writeAsStringSync('hidden');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final FileSearchResult result = await FileSearchService.search(
      FileSearchRequest(root: sandbox.path, query: 'config'),
    );

    expect(result.cancelled, isFalse);
    expect(result.matches.map((FileSearchMatch item) => item.name), <String>[
      'config.json',
      'app_config.yaml',
    ]);
    expect(result.visitedFiles, 2);
  });

  test('内容搜索返回行号和片段并跳过超限及二进制文件', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_content',
    );
    File('${sandbox.path}/main.dart')
        .writeAsStringSync('void main() {}\n// TODO: close the loop\n');
    File('${sandbox.path}/large.txt').writeAsStringSync('TODO'.padRight(64));
    File('${sandbox.path}/binary.bin')
        .writeAsBytesSync(<int>[0, 84, 79, 68, 79]);
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final FileSearchResult result = await FileSearchService.search(
      FileSearchRequest(
        root: sandbox.path,
        query: 'todo',
        mode: FileSearchMode.content,
        maxContentFileBytes: 48,
      ),
    );

    expect(result.matches, hasLength(1));
    expect(result.matches.single.name, 'main.dart');
    expect(result.matches.single.lineNumber, 2);
    expect(result.matches.single.snippet, contains('close the loop'));
    expect(result.skippedFiles, 1);
  });

  test('搜索可协作取消并保留已找到结果', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_cancel',
    );
    for (int index = 0; index < 30; index++) {
      File('${sandbox.path}/match_$index.txt').writeAsStringSync('$index');
    }
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final FileSearchCancellation cancellation = FileSearchCancellation();

    final FileSearchResult result = await FileSearchService.search(
      FileSearchRequest(root: sandbox.path, query: 'match'),
      cancellation: cancellation,
      onProgress: (FileSearchProgress progress) {
        if (progress.visitedFiles >= 3) cancellation.cancel();
      },
    );

    expect(result.cancelled, isTrue);
    expect(result.visitedFiles, 3);
    expect(result.matches, hasLength(3));
    expect(sandbox.listSync().whereType<File>(), hasLength(30));
  });

  test('结果达到上限时明确标记截断', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_limit',
    );
    for (int index = 0; index < 5; index++) {
      File('${sandbox.path}/item_$index.txt').writeAsStringSync('$index');
    }
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final FileSearchResult result = await FileSearchService.search(
      FileSearchRequest(root: sandbox.path, query: 'item', maxResults: 2),
    );

    expect(result.matches, hasLength(2));
    expect(result.truncated, isTrue);
  });

  test('类型、大小和修改时间筛选在匹配前生效', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_filters',
    );
    final File recent = File('${sandbox.path}/recent.dart')
      ..writeAsStringSync(''.padRight(2048, 'x'));
    final File small = File('${sandbox.path}/small.dart')
      ..writeAsStringSync('x');
    final File wrongType = File('${sandbox.path}/recent.txt')
      ..writeAsStringSync(''.padRight(2048, 'x'));
    recent.setLastModifiedSync(DateTime.now());
    small.setLastModifiedSync(DateTime.now());
    wrongType.setLastModifiedSync(DateTime.now());
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final FileSearchResult result = await FileSearchService.search(
      FileSearchRequest(
        root: sandbox.path,
        query: 'recent',
        extensions: const <String>{'dart'},
        minimumBytes: 1024,
        modifiedAfter: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    expect(result.matches.map((FileSearchMatch item) => item.name), <String>[
      'recent.dart',
    ]);
  });

  test('默认遵循根 gitignore 并采用 smart case', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_ignore',
    );
    Directory('${sandbox.path}/build').createSync();
    File('${sandbox.path}/.gitignore').writeAsStringSync('build/\n*.tmp\n');
    File('${sandbox.path}/UserService.dart')
        .writeAsStringSync('class UserService {}');
    File('${sandbox.path}/userservice.tmp').writeAsStringSync('ignored');
    File('${sandbox.path}/build/UserService.dart')
        .writeAsStringSync('generated');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final FileSearchResult exact = await FileSearchService.search(
      FileSearchRequest(root: sandbox.path, query: 'UserService'),
    );
    expect(exact.matches.map((FileSearchMatch item) => item.name), <String>[
      'UserService.dart',
    ]);

    final FileSearchResult wrongCase = await FileSearchService.search(
      FileSearchRequest(root: sandbox.path, query: 'Userservice'),
    );
    expect(wrongCase.matches, isEmpty);

    final FileSearchResult insensitive = await FileSearchService.search(
      FileSearchRequest(root: sandbox.path, query: 'userservice'),
    );
    expect(insensitive.matches, hasLength(1));
  });
}
