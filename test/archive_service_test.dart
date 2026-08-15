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
}
