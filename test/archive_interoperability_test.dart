import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/archive_service.dart';
import 'package:vibekits/features/archive/domain/seven_zip.dart';

void main() {
  final List<(String, List<int>)> corpus = <(String, List<int>)>[
    ('plain.txt', utf8.encode('Vibekits archive interoperability\n')),
    ('中文目录/中文 文件.txt', utf8.encode('中文 UTF-8 内容')),
    (
      'binary/all-bytes.bin',
      <int>[for (int value = 0; value < 256; value++) value],
    ),
    ('empty.dat', const <int>[]),
  ];

  for (final (ArchiveFormat format, String suffix) in <(ArchiveFormat, String)>[
    (ArchiveFormat.zip, 'zip'),
    (ArchiveFormat.tar, 'tar'),
    (ArchiveFormat.gzip, 'tar.gz'),
  ]) {
    test('$suffix 标准语料压缩、列出、解压后逐字节一致', () async {
      final Directory target = Directory.systemTemp.createTempSync(
        'vk_archive_${suffix}_',
      );
      addTearDown(() => target.deleteSync(recursive: true));
      final Uint8List bytes = ArchiveService.createArchive(
        files: corpus,
        format: format,
      );
      final ArchiveListing listing = ArchiveService.list(bytes, 'case.$suffix');
      expect(
        listing.entries.map((ArchiveEntry item) => item.name),
        containsAll(corpus.map(((String, List<int>) item) => item.$1)),
      );

      final ExtractResult result = await ArchiveService.extractAsync(
        listing: listing,
        targetDir: target.path,
        selectedNames: const <String>{},
      );
      expect(result.failed, 0);
      for (final (String name, List<int> expected) in corpus) {
        final String path = name.replaceAll('/', Platform.pathSeparator);
        expect(
          File('${target.path}${Platform.pathSeparator}$path')
              .readAsBytesSync(),
          expected,
        );
      }
    });
  }

  test('内置 7-Zip 与真实 7z/ZIP/RAR5 文件互操作', () async {
    if (!Platform.isWindows || !SevenZip.isAvailable) return;
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_7z_interop_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory source = Directory(
      '${root.path}${Platform.pathSeparator}source',
    )..createSync();
    for (final (String name, List<int> data) in corpus) {
      final File file = File(
        '${source.path}${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data);
    }
    final String executable = SevenZip.findExecutable()!;
    for (final String suffix in <String>['7z', 'zip']) {
      final String archive =
          '${root.path}${Platform.pathSeparator}external.$suffix';
      final ProcessResult created = await Process.run(executable, <String>[
        'a',
        '-t$suffix',
        archive,
        '.',
      ], workingDirectory: source.path);
      expect(created.exitCode, 0, reason: '${created.stderr}');
      final List<SevenZipEntry> listing = await SevenZip.list(archive);
      expect(
        listing.map((SevenZipEntry item) => item.name.replaceAll('\\', '/')),
        containsAll(corpus.map(((String, List<int>) item) => item.$1)),
      );
      final Directory output = Directory(
        '${root.path}${Platform.pathSeparator}out-$suffix',
      );
      await SevenZip.extract(archive, output.path, policy: 'overwrite');
      for (final (String name, List<int> expected) in corpus) {
        final String path = name.replaceAll('/', Platform.pathSeparator);
        expect(
          File('${output.path}${Platform.pathSeparator}$path')
              .readAsBytesSync(),
          expected,
        );
      }
    }

    final File rar = File(
      'test_data${Platform.pathSeparator}archives${Platform.pathSeparator}rarlng.rar',
    );
    expect(rar.existsSync(), isTrue);
    expect(await SevenZip.list(rar.absolute.path), isNotEmpty);
  });
}
