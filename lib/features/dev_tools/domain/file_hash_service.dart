import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;

enum FileHashAlgorithm {
  md5('MD5'),
  sha1('SHA-1'),
  sha256('SHA-256'),
  sha512('SHA-512');

  const FileHashAlgorithm(this.label);

  final String label;
}

class FileHashCancellation {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final void Function() listener in List<void Function()>.of(
      _listeners,
    )) {
      listener();
    }
  }

  void addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeCancelListener(void Function() listener) =>
      _listeners.remove(listener);
}

class FileHashResult {
  const FileHashResult({
    required this.path,
    required this.algorithm,
    required this.totalBytes,
    this.digest,
    this.error,
    this.cancelled = false,
  });

  final String path;
  final FileHashAlgorithm algorithm;
  final int totalBytes;
  final String? digest;
  final String? error;
  final bool cancelled;

  bool get succeeded => digest != null && error == null && !cancelled;
}

typedef FileHashProgress = void Function(int processedBytes, int totalBytes);

/// 分块计算文件摘要，避免把大文件一次性读进内存。
Future<FileHashResult> calculateFileHash(
  String path,
  FileHashAlgorithm algorithm, {
  FileHashCancellation? cancellation,
  FileHashProgress? onProgress,
}) async {
  final File file = File(path);
  try {
    if (!await file.exists()) {
      return FileHashResult(
        path: path,
        algorithm: algorithm,
        totalBytes: 0,
        error: '文件不存在',
      );
    }
    final int total = await file.length();
    int processed = 0;
    onProgress?.call(0, total);
    final AccumulatorSink<crypto.Digest> output =
        AccumulatorSink<crypto.Digest>();
    final ByteConversionSink input = _hashFor(algorithm)
        .startChunkedConversion(output);
    try {
      await for (final List<int> chunk in file.openRead()) {
        if (cancellation?.isCancelled ?? false) {
          return FileHashResult(
            path: path,
            algorithm: algorithm,
            totalBytes: total,
            cancelled: true,
          );
        }
        input.add(chunk);
        processed += chunk.length;
        onProgress?.call(processed, total);
      }
      input.close();
      if (cancellation?.isCancelled ?? false) {
        return FileHashResult(
          path: path,
          algorithm: algorithm,
          totalBytes: total,
          cancelled: true,
        );
      }
      return FileHashResult(
        path: path,
        algorithm: algorithm,
        totalBytes: total,
        digest: output.events.single.toString(),
      );
    } finally {
      if (output.events.isEmpty) {
        input.close();
      }
    }
  } on FileSystemException catch (error) {
    return FileHashResult(
      path: path,
      algorithm: algorithm,
      totalBytes: 0,
      error: error.message,
    );
  } catch (error) {
    return FileHashResult(
      path: path,
      algorithm: algorithm,
      totalBytes: 0,
      error: '$error',
    );
  }
}

crypto.Hash _hashFor(FileHashAlgorithm algorithm) => switch (algorithm) {
  FileHashAlgorithm.md5 => crypto.md5,
  FileHashAlgorithm.sha1 => crypto.sha1,
  FileHashAlgorithm.sha256 => crypto.sha256,
  FileHashAlgorithm.sha512 => crypto.sha512,
};
