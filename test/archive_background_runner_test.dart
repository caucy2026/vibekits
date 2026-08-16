import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/archive_background_runner.dart';
import 'package:vibekits/features/archive/domain/archive_service.dart';

void main() {
  test('纯 Dart 压缩包读取和解码在独立 Isolate 中完成', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_archive_worker',
    );
    final File source = File('${sandbox.path}/sample.zip');
    final archive.Archive data = archive.Archive()
      ..addFile(archive.ArchiveFile.string('hello.txt', 'hello'));
    source.writeAsBytesSync(archive.ZipEncoder().encode(data));
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final ArchiveListing listing = await ArchiveBackgroundRunner.listFile(
      source.path,
      'sample.zip',
      maxEntries: 100,
      maxSingleExpandedBytes: 1024,
    );

    expect(listing.entries.single.name, 'hello.txt');
    expect(listing.entries.single.size, 5);
  });

  test('目录读取、编码和写盘在独立 Isolate 中完成', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_archive_create_worker',
    );
    final Directory input = Directory('${sandbox.path}/input')..createSync();
    File('${input.path}/hello.txt').writeAsStringSync('hello');
    final String output = '${sandbox.path}/created.zip';
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final int bytes = await ArchiveBackgroundRunner.create(
      format: ArchiveFormat.zip,
      outputPath: output,
      maxEntries: 100,
      maxTotalBytes: 1024,
      directory: input.path,
    );
    final ArchiveListing listing = await ArchiveBackgroundRunner.listFile(
      output,
      'created.zip',
      maxEntries: 100,
      maxSingleExpandedBytes: 1024,
    );

    expect(bytes, greaterThan(0));
    expect(listing.entries.single.name, 'input/hello.txt');
  });
}
