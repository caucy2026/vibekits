import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_hash_background_runner.dart';
import 'package:vibekits/features/dev_tools/domain/file_hash_service.dart';

void main() {
  test('文件哈希在独立 Isolate 中返回 SHA-256 和进度', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_hash_worker',
    );
    final File source = File('${sandbox.path}/abc.txt')
      ..writeAsStringSync('abc');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final List<(int, int)> progress = <(int, int)>[];

    final FileHashResult result = await FileHashBackgroundRunner.calculate(
      source.path,
      FileHashAlgorithm.sha256,
      cancellation: FileHashCancellation(),
      onProgress: (int processed, int total) =>
          progress.add((processed, total)),
    );

    expect(
      result.digest,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(progress.last, (3, 3));
  });

  test('文件哈希取消会转发给工作 Isolate', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_hash_worker_cancel',
    );
    final File source = File('${sandbox.path}/large.bin')
      ..writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 7));
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final FileHashCancellation cancellation = FileHashCancellation()..cancel();

    final FileHashResult result = await FileHashBackgroundRunner.calculate(
      source.path,
      FileHashAlgorithm.sha256,
      cancellation: cancellation,
      onProgress: (_, _) {},
    );

    expect(result.cancelled, isTrue);
  });
}
