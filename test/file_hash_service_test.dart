import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_hash_service.dart';

void main() {
  late Directory sandbox;

  setUp(() => sandbox = Directory.systemTemp.createTempSync('vk_hash'));
  tearDown(() => sandbox.deleteSync(recursive: true));

  test('分块计算四种标准文件哈希', () async {
    final File file = File('${sandbox.path}${Platform.pathSeparator}abc.txt')
      ..writeAsStringSync('abc');
    final Map<FileHashAlgorithm, String> expected = <FileHashAlgorithm, String>{
      FileHashAlgorithm.md5: '900150983cd24fb0d6963f7d28e17f72',
      FileHashAlgorithm.sha1: 'a9993e364706816aba3e25717850c26c9cd0d89d',
      FileHashAlgorithm.sha256:
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      FileHashAlgorithm.sha512:
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
          '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
    };

    for (final MapEntry<FileHashAlgorithm, String> item in expected.entries) {
      final FileHashResult result = await calculateFileHash(
        file.path,
        item.key,
      );
      expect(result.succeeded, isTrue);
      expect(result.digest, item.value);
      expect(result.totalBytes, 3);
    }
  });

  test('进度覆盖完整文件且预取消不读取内容', () async {
    final File file = File('${sandbox.path}${Platform.pathSeparator}large.bin')
      ..writeAsBytesSync(List<int>.filled(256 * 1024, 7));
    final List<int> progress = <int>[];
    final FileHashResult result = await calculateFileHash(
      file.path,
      FileHashAlgorithm.sha256,
      onProgress: (int processed, int total) => progress.add(processed),
    );
    expect(result.succeeded, isTrue);
    expect(progress.first, 0);
    expect(progress.last, 256 * 1024);

    final FileHashCancellation cancellation = FileHashCancellation()..cancel();
    final FileHashResult cancelled = await calculateFileHash(
      file.path,
      FileHashAlgorithm.sha256,
      cancellation: cancellation,
    );
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.digest, isNull);
  });

  test('不存在的文件返回可展示错误', () async {
    final FileHashResult result = await calculateFileHash(
      '${sandbox.path}${Platform.pathSeparator}missing.bin',
      FileHashAlgorithm.sha256,
    );
    expect(result.succeeded, isFalse);
    expect(result.error, '文件不存在');
  });
}
