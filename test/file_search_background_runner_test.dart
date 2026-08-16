import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_search_background_runner.dart';
import 'package:vibekits/features/dev_tools/domain/file_search_service.dart';

void main() {
  test('独立 Isolate 返回搜索结果和限频进度', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_worker',
    );
    File('${sandbox.path}/target.dart').writeAsStringSync('void main() {}');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final List<FileSearchProgress> progress = <FileSearchProgress>[];

    final FileSearchResult result = await FileSearchBackgroundRunner.search(
      FileSearchRequest(root: sandbox.path, query: 'target'),
      cancellation: FileSearchCancellation(),
      onProgress: progress.add,
    );

    expect(result.matches.single.name, 'target.dart');
    expect(progress, isNotEmpty);
    expect(progress.last.visitedFiles, 1);
  });

  test('主线程提前取消会转发给搜索 Isolate', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_file_search_worker_cancel',
    );
    for (int index = 0; index < 50; index++) {
      File('${sandbox.path}/item_$index.txt').writeAsStringSync('$index');
    }
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final FileSearchCancellation cancellation = FileSearchCancellation()
      ..cancel();

    final FileSearchResult result = await FileSearchBackgroundRunner.search(
      FileSearchRequest(root: sandbox.path, query: 'item'),
      cancellation: cancellation,
      onProgress: (_) {},
    );

    expect(result.cancelled, isTrue);
  });
}
