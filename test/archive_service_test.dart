import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/archive_service.dart';

void main() {
  Uint8List zipWith(List<(String, String)> files) {
    final Archive archive = Archive();
    for (final (String name, String content) in files) {
      archive.addFile(ArchiveFile.string(name, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('格式路由', () {
    expect(archiveFormatForPath('a.zip'), ArchiveFormat.zip);
    expect(archiveFormatForPath('a.tar'), ArchiveFormat.tar);
    expect(archiveFormatForPath('a.tar.gz'), ArchiveFormat.tar);
    expect(archiveFormatForPath('a.7z'), ArchiveFormat.sevenZip);
    expect(archiveFormatForPath('a.rar'), ArchiveFormat.rar);
    expect(archiveFormatForPath('a.iso'), ArchiveFormat.iso);
    expect(archiveFormatForPath('a.zst'), ArchiveFormat.external);
    expect(archiveFormatForPath('a.wim'), ArchiveFormat.external);
    expect(archiveFormatForPath('a.xyz'), ArchiveFormat.unsupported);
  });

  test('列出 zip 条目', () {
    final Uint8List bytes = zipWith(<(String, String)>[
      ('dir/a.txt', 'hello'),
      ('b.txt', 'world'),
    ]);
    final ArchiveListing listing = ArchiveService.list(bytes, 'a.zip');
    expect(listing.format, ArchiveFormat.zip);
    expect(listing.entries.length, 2);
    expect(listing.totalUncompressedSize, 10);
  });

  test('不支持的格式抛错', () {
    expect(
      () => ArchiveService.list(Uint8List(0), 'a.7z'),
      throwsUnsupportedError,
    );
  });

  test('路径穿越被拒绝', () {
    expect(ArchiveService.safeRelativePath('../x'), isNull);
    expect(ArchiveService.safeRelativePath('a/../../x'), isNull);
    expect(ArchiveService.safeRelativePath('C:/x'), isNull);
    expect(ArchiveService.safeRelativePath('/abs'), isNull);
    expect(ArchiveService.safeRelativePath('a/b.txt'), 'a/b.txt');
  });

  test('自定义条目上限生效', () {
    final Archive archive = Archive()
      ..addFile(ArchiveFile('a.txt', 1, <int>[1]))
      ..addFile(ArchiveFile('b.txt', 1, <int>[2]));
    final Uint8List bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(
      () => ArchiveService.list(bytes, 'a.zip', maxEntries: 1),
      throwsFormatException,
    );
  });

  test('解压 zip 到临时目录', () {
    final Uint8List bytes = zipWith(<(String, String)>[
      ('dir/a.txt', 'hello'),
      ('b.txt', 'world'),
    ]);
    final ArchiveListing listing = ArchiveService.list(bytes, 'a.zip');
    final Directory tmp = Directory.systemTemp.createTempSync('vk_arc_test');
    try {
      final ExtractResult result = ArchiveService.extract(
        listing: listing,
        targetDir: tmp.path,
        selectedNames: <String>{},
        policy: ConflictPolicy.rename,
      );
      expect(result.succeeded, 2);
      expect(File('${tmp.path}/dir/a.txt').readAsStringSync(), 'hello');
      expect(File('${tmp.path}/b.txt').readAsStringSync(), 'world');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('创建 zip 并重新列出', () {
    final Uint8List bytes = ArchiveService.createArchive(
      files: <(String, List<int>)>[('a.txt', utf8.encode('hello'))],
      format: ArchiveFormat.zip,
    );
    final ArchiveListing listing = ArchiveService.list(bytes, 'out.zip');
    expect(listing.entries.single.name, 'a.txt');
    expect(listing.entries.single.file.content, utf8.encode('hello'));
  });

  test('创建 TAR 与 TAR.GZ 并重新列出', () {
    for (final (ArchiveFormat format, String path) in <(ArchiveFormat, String)>[
      (ArchiveFormat.tar, 'a.tar'),
      (ArchiveFormat.gzip, 'a.tar.gz'),
    ]) {
      final Uint8List bytes = ArchiveService.createArchive(
        files: <(String, List<int>)>[('folder/a.txt', utf8.encode('content'))],
        format: format,
      );
      final ArchiveListing listing = ArchiveService.list(bytes, path);
      expect(listing.entries.single.name, 'folder/a.txt');
    }
  });

  test('异步解压分块写入并清理临时文件', () async {
    final Directory target = Directory.systemTemp.createTempSync(
      'vk_archive_async',
    );
    addTearDown(() => target.deleteSync(recursive: true));
    final Uint8List bytes = ArchiveService.createArchive(
      files: <(String, List<int>)>[
        ('large.bin', List<int>.filled(256 * 1024, 7)),
      ],
      format: ArchiveFormat.zip,
    );
    final ArchiveListing listing = ArchiveService.list(bytes, 'a.zip');

    final ExtractResult result = await ArchiveService.extractAsync(
      listing: listing,
      targetDir: target.path,
      selectedNames: <String>{'large.bin'},
    );

    expect(result.succeeded, 1);
    expect(result.writtenBytes, 256 * 1024);
    expect(File('${target.path}/large.bin').lengthSync(), 256 * 1024);
    expect(
      target
          .listSync(recursive: true)
          .where((FileSystemEntity entity) => entity.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('异步解压取消后不保留半成品', () async {
    final Directory target = Directory.systemTemp.createTempSync(
      'vk_archive_cancel',
    );
    addTearDown(() => target.deleteSync(recursive: true));
    final Uint8List bytes = ArchiveService.createArchive(
      files: <(String, List<int>)>[
        ('cancel.bin', List<int>.filled(512 * 1024, 9)),
      ],
      format: ArchiveFormat.zip,
    );
    final ArchiveListing listing = ArchiveService.list(bytes, 'a.zip');
    final ArchiveCancellationToken token = ArchiveCancellationToken();

    final ExtractResult result = await ArchiveService.extractAsync(
      listing: listing,
      targetDir: target.path,
      selectedNames: <String>{'cancel.bin'},
      cancellationToken: token,
      onProgress: (ArchiveExtractProgress progress) {
        if (progress.writtenBytes >= 64 * 1024) token.cancel();
      },
    );

    expect(result.cancelled, isTrue);
    expect(result.failed, 0);
    expect(result.writtenBytes, 0);
    expect(File('${target.path}/cancel.bin').existsSync(), isFalse);
    expect(target.listSync(recursive: true), isEmpty);
  });

  test('压缩 TAR 变体可重新列出', () {
    for (final String path in <String>['a.tar.gz', 'a.tgz']) {
      final Uint8List bytes = ArchiveService.createArchive(
        files: <(String, List<int>)>[
          ('inside.txt', <int>[1, 2, 3]),
        ],
        format: ArchiveFormat.gzip,
      );
      final ArchiveListing listing = ArchiveService.list(bytes, path);
      expect(listing.entries.single.name, 'inside.txt');
    }
  });

  test('文件头优先于错误扩展名识别格式', () {
    final Uint8List zip = ArchiveService.createArchive(
      files: <(String, List<int>)>[
        ('a.txt', <int>[1]),
      ],
      format: ArchiveFormat.zip,
    );

    expect(archiveFormatForBytes(zip, path: 'wrong.bin'), ArchiveFormat.zip);
    expect(ArchiveService.list(zip, 'wrong.bin').entries.single.name, 'a.txt');
  });

  test('总展开大小和压缩比限制生效', () {
    final Uint8List zip = ArchiveService.createArchive(
      files: <(String, List<int>)>[
        ('repeated.bin', List<int>.filled(10000, 0)),
      ],
      format: ArchiveFormat.zip,
    );

    expect(
      () => ArchiveService.list(zip, 'a.zip', maxTotalExpandedBytes: 9999),
      throwsFormatException,
    );
    expect(
      () => ArchiveService.list(zip, 'a.zip', maxCompressionRatio: 2),
      throwsFormatException,
    );
  });

  test('逐个询问冲突策略应用用户选择', () async {
    final Directory target = Directory.systemTemp.createTempSync(
      'vk_archive_ask',
    );
    addTearDown(() => target.deleteSync(recursive: true));
    File('${target.path}/same.txt').writeAsStringSync('old');
    final Uint8List zip = ArchiveService.createArchive(
      files: <(String, List<int>)>[('same.txt', utf8.encode('new'))],
      format: ArchiveFormat.zip,
    );

    final ExtractResult result = await ArchiveService.extractAsync(
      listing: ArchiveService.list(zip, 'a.zip'),
      targetDir: target.path,
      selectedNames: <String>{'same.txt'},
      policy: ConflictPolicy.ask,
      onConflict: (String path) async => ConflictPolicy.rename,
    );

    expect(result.succeeded, 1);
    expect(File('${target.path}/same.txt').readAsStringSync(), 'old');
    expect(File('${target.path}/same (1).txt').readAsStringSync(), 'new');
  });

  test('目录打包保留相对结构并执行输入限制', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_archive_folder',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory nested = Directory('${root.path}/nested')..createSync();
    File('${nested.path}/a.txt').writeAsStringSync('abc');
    File('${root.path}/b.txt').writeAsStringSync('de');

    final List<(String, List<int>)> files =
        await ArchiveService.collectDirectory(root.path);
    final Set<String> names = files
        .map(((String, List<int>) item) => item.$1)
        .toSet();

    expect(
      names,
      contains(
        '${root.uri.pathSegments.where((String value) => value.isNotEmpty).last}/nested/a.txt',
      ),
    );
    expect(names, hasLength(2));
    expect(
      () => ArchiveService.collectDirectory(root.path, maxEntries: 1),
      throwsFormatException,
    );
    expect(
      () => ArchiveService.collectDirectory(root.path, maxTotalBytes: 4),
      throwsFormatException,
    );
  });
}
