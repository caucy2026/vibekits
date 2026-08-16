import 'dart:async';
import 'dart:isolate';

import 'file_hash_service.dart';

/// 在独立 Isolate 中分块计算哈希，避免大文件占用 UI Isolate。
abstract final class FileHashBackgroundRunner {
  static Future<FileHashResult> calculate(
    String path,
    FileHashAlgorithm algorithm, {
    required FileHashCancellation cancellation,
    required FileHashProgress onProgress,
  }) async {
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<FileHashResult> completer = Completer<FileHashResult>();
    SendPort? cancellationPort;
    bool reportedResult = false;

    void forwardCancellation() => cancellationPort?.send(true);

    cancellation.addCancelListener(forwardCancellation);
    late final StreamSubscription<Object?> resultSubscription;
    late final StreamSubscription<Object?> errorSubscription;
    late final StreamSubscription<Object?> exitSubscription;
    resultSubscription = resultPort.listen((Object? message) {
      if (message is! _HashWorkerMessage) return;
      switch (message.kind) {
        case _HashWorkerMessageKind.ready:
          cancellationPort = message.value! as SendPort;
          if (cancellation.isCancelled) forwardCancellation();
        case _HashWorkerMessageKind.progress:
          final List<int> values = message.value! as List<int>;
          onProgress(values[0], values[1]);
        case _HashWorkerMessageKind.result:
          reportedResult = true;
          if (!completer.isCompleted) {
            completer.complete(message.value! as FileHashResult);
          }
        case _HashWorkerMessageKind.error:
          reportedResult = true;
          if (!completer.isCompleted) {
            completer.completeError(StateError(message.value! as String));
          }
      }
    });
    errorSubscription = errorPort.listen((Object? error) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('后台文件哈希线程异常：$error'));
      }
    });
    exitSubscription = exitPort.listen((Object? _) {
      scheduleMicrotask(() {
        if (!reportedResult && !completer.isCompleted) {
          completer.completeError(StateError('后台文件哈希线程意外退出'));
        }
      });
    });
    try {
      await Isolate.spawn<_HashWorkerRequest>(
        _hashEntry,
        _HashWorkerRequest(resultPort.sendPort, path, algorithm),
        debugName: 'vibekits-file-hash',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      return await completer.future;
    } finally {
      cancellation.removeCancelListener(forwardCancellation);
      await resultSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      resultPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  static Future<void> _hashEntry(_HashWorkerRequest worker) async {
    final ReceivePort cancellationPort = ReceivePort();
    final FileHashCancellation cancellation = FileHashCancellation();
    final StreamSubscription<Object?> cancellationSubscription =
        cancellationPort.listen((Object? _) => cancellation.cancel());
    worker.resultPort.send(
      _HashWorkerMessage(
        _HashWorkerMessageKind.ready,
        cancellationPort.sendPort,
      ),
    );
    final Stopwatch progressClock = Stopwatch()..start();
    List<int>? latest;
    try {
      final FileHashResult result = await calculateFileHash(
        worker.path,
        worker.algorithm,
        cancellation: cancellation,
        onProgress: (int processed, int total) {
          latest = <int>[processed, total];
          if (progressClock.elapsedMilliseconds < 100 && processed != total) {
            return;
          }
          progressClock.reset();
          worker.resultPort.send(
            _HashWorkerMessage(_HashWorkerMessageKind.progress, <int>[
              processed,
              total,
            ]),
          );
        },
      );
      if (latest != null && result.cancelled) {
        worker.resultPort.send(
          _HashWorkerMessage(_HashWorkerMessageKind.progress, latest),
        );
      }
      worker.resultPort.send(
        _HashWorkerMessage(_HashWorkerMessageKind.result, result),
      );
    } catch (error, stackTrace) {
      worker.resultPort.send(
        _HashWorkerMessage(_HashWorkerMessageKind.error, '$error\n$stackTrace'),
      );
    } finally {
      await cancellationSubscription.cancel();
      cancellationPort.close();
    }
  }
}

enum _HashWorkerMessageKind { ready, progress, result, error }

class _HashWorkerMessage {
  const _HashWorkerMessage(this.kind, this.value);

  final _HashWorkerMessageKind kind;
  final Object? value;
}

class _HashWorkerRequest {
  const _HashWorkerRequest(this.resultPort, this.path, this.algorithm);

  final SendPort resultPort;
  final String path;
  final FileHashAlgorithm algorithm;
}
