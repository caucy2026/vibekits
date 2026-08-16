import 'dart:async';
import 'dart:isolate';

import '../../cleaner/domain/cleanup_task.dart';
import 'duplicate_file_scanner.dart';

/// 在独立 Isolate 中枚举和哈希重复文件候选。
abstract final class DuplicateFileBackgroundRunner {
  static Future<DuplicateScanResult> scan(
    String root, {
    required bool recursive,
    required int minimumSize,
    required CleanupCancellationToken cancellationToken,
    required void Function(DuplicateScanProgress progress) onProgress,
  }) async {
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<DuplicateScanResult> completer =
        Completer<DuplicateScanResult>();
    SendPort? cancellationPort;
    bool reportedResult = false;

    void forwardCancellation() => cancellationPort?.send(true);

    cancellationToken.addCancelListener(forwardCancellation);
    late final StreamSubscription<Object?> resultSubscription;
    late final StreamSubscription<Object?> errorSubscription;
    late final StreamSubscription<Object?> exitSubscription;
    resultSubscription = resultPort.listen((Object? message) {
      if (message is! _DuplicateWorkerMessage) return;
      switch (message.kind) {
        case _DuplicateWorkerMessageKind.ready:
          cancellationPort = message.value! as SendPort;
          if (cancellationToken.isCancelled) forwardCancellation();
        case _DuplicateWorkerMessageKind.progress:
          onProgress(message.value! as DuplicateScanProgress);
        case _DuplicateWorkerMessageKind.result:
          reportedResult = true;
          if (!completer.isCompleted) {
            completer.complete(message.value! as DuplicateScanResult);
          }
        case _DuplicateWorkerMessageKind.error:
          reportedResult = true;
          if (!completer.isCompleted) {
            completer.completeError(StateError(message.value! as String));
          }
      }
    });
    errorSubscription = errorPort.listen((Object? error) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('后台重复文件线程异常：$error'));
      }
    });
    exitSubscription = exitPort.listen((Object? _) {
      scheduleMicrotask(() {
        if (!reportedResult && !completer.isCompleted) {
          completer.completeError(StateError('后台重复文件线程意外退出'));
        }
      });
    });
    try {
      await Isolate.spawn<_DuplicateWorkerRequest>(
        _scanEntry,
        _DuplicateWorkerRequest(
          resultPort: resultPort.sendPort,
          root: root,
          recursive: recursive,
          minimumSize: minimumSize,
        ),
        debugName: 'vibekits-duplicate-scan',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      return await completer.future;
    } finally {
      cancellationToken.removeCancelListener(forwardCancellation);
      await resultSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      resultPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  static Future<void> _scanEntry(_DuplicateWorkerRequest worker) async {
    final ReceivePort cancellationPort = ReceivePort();
    final CleanupCancellationToken cancellation = CleanupCancellationToken();
    final StreamSubscription<Object?> cancellationSubscription =
        cancellationPort.listen((Object? _) => cancellation.cancel());
    worker.resultPort.send(
      _DuplicateWorkerMessage(
        _DuplicateWorkerMessageKind.ready,
        cancellationPort.sendPort,
      ),
    );
    final Stopwatch progressClock = Stopwatch()..start();
    DuplicateScanProgress? latest;
    try {
      final DuplicateScanResult result = await DuplicateFileScanner.scan(
        worker.root,
        recursive: worker.recursive,
        minimumSize: worker.minimumSize,
        cancellationToken: cancellation,
        onProgress: (DuplicateScanProgress progress) {
          latest = progress;
          if (progressClock.elapsedMilliseconds < 100) return;
          progressClock.reset();
          worker.resultPort.send(
            _DuplicateWorkerMessage(
              _DuplicateWorkerMessageKind.progress,
              progress,
            ),
          );
        },
      );
      if (latest != null) {
        worker.resultPort.send(
          _DuplicateWorkerMessage(_DuplicateWorkerMessageKind.progress, latest),
        );
      }
      worker.resultPort.send(
        _DuplicateWorkerMessage(_DuplicateWorkerMessageKind.result, result),
      );
    } catch (error, stackTrace) {
      worker.resultPort.send(
        _DuplicateWorkerMessage(
          _DuplicateWorkerMessageKind.error,
          '$error\n$stackTrace',
        ),
      );
    } finally {
      await cancellationSubscription.cancel();
      cancellationPort.close();
    }
  }
}

enum _DuplicateWorkerMessageKind { ready, progress, result, error }

class _DuplicateWorkerMessage {
  const _DuplicateWorkerMessage(this.kind, this.value);

  final _DuplicateWorkerMessageKind kind;
  final Object? value;
}

class _DuplicateWorkerRequest {
  const _DuplicateWorkerRequest({
    required this.resultPort,
    required this.root,
    required this.recursive,
    required this.minimumSize,
  });

  final SendPort resultPort;
  final String root;
  final bool recursive;
  final int minimumSize;
}
