import 'dart:io';
import 'dart:typed_data';

import '../../../app/atomic_file.dart';

class SourceSaveResult {
  const SourceSaveResult({required this.size, required this.modified});

  final int size;
  final DateTime modified;
}

abstract final class SourceFileSaver {
  static Future<SourceSaveResult> save(
    String path,
    Uint8List bytes, {
    required int expectedSize,
    required DateTime? expectedModified,
  }) async {
    final File destination = File(path);
    final int currentSize = await destination.length();
    final DateTime currentModified = await destination.lastModified();
    if (currentSize != expectedSize ||
        (expectedModified != null && currentModified != expectedModified)) {
      throw const FileSystemException('文件已被其他程序修改，已停止覆盖；请重新打开后合并修改');
    }
    final File temporary = File(
      '$path.vibekits-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await AtomicFile.commit(temporary, destination);
      return SourceSaveResult(
        size: bytes.length,
        modified: await destination.lastModified(),
      );
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
