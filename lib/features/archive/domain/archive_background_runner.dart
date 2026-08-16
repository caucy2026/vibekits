import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'archive_service.dart';

/// 将纯 Dart 压缩包读取和解码放到独立 Isolate。
abstract final class ArchiveBackgroundRunner {
  static Future<ArchiveListing> listFile(
    String path,
    String displayName, {
    required int maxEntries,
    required int maxSingleExpandedBytes,
  }) {
    return Isolate.run(() {
      final Uint8List bytes = File(path).readAsBytesSync();
      return ArchiveService.list(
        bytes,
        displayName,
        maxEntries: maxEntries,
        maxSingleExpandedBytes: maxSingleExpandedBytes,
      );
    }, debugName: 'vibekits-archive-list');
  }

  static Future<int> create({
    required ArchiveFormat format,
    required String outputPath,
    required int maxEntries,
    required int maxTotalBytes,
    String? directory,
    List<(String, String)> files = const <(String, String)>[],
  }) {
    return Isolate.run(() async {
      final List<(String, List<int>)> entries;
      if (directory != null) {
        entries = await ArchiveService.collectDirectory(
          directory,
          maxEntries: maxEntries,
          maxTotalBytes: maxTotalBytes,
        );
      } else {
        if (files.length > maxEntries) {
          throw const FormatException('文件数量超过安全上限');
        }
        entries = <(String, List<int>)>[];
        int totalBytes = 0;
        for (final (String path, String name) in files) {
          final File file = File(path);
          final int length = file.lengthSync();
          totalBytes += length;
          if (totalBytes > maxTotalBytes) {
            throw const FormatException('文件总大小超过安全上限');
          }
          entries.add((name, file.readAsBytesSync()));
        }
      }
      if (entries.isEmpty) {
        throw const FormatException('所选来源中没有可打包文件');
      }
      final Uint8List bytes = ArchiveService.createArchive(
        files: entries,
        format: format,
      );
      File(outputPath).writeAsBytesSync(bytes, flush: true);
      return bytes.length;
    }, debugName: 'vibekits-archive-create');
  }
}
