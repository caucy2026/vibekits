import 'dart:async';
import 'dart:isolate';

import 'file_search_service.dart';

/// 在独立 Isolate 中执行完整目录遍历和内容解码。
///
/// UI Isolate 只接收每 100ms 至多一次的进度快照，避免大量小文件产生的
/// 消息风暴占满 Windows 窗口消息泵。
abstract final class FileSearchBackgroundRunner {
  static Future<FileSearchResult> search(
    FileSearchRequest request, {
    required FileSearchCancellation cancellation,
    required FileSearchProgressCallback onProgress,
  }) async {
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<FileSearchResult> completer = Completer<FileSearchResult>();
    SendPort? cancellationPort;
    bool reportedResult = false;

    void forwardCancellation() => cancellationPort?.send(true);

    cancellation.addCancelListener(forwardCancellation);
    late final StreamSubscription<Object?> resultSubscription;
    late final StreamSubscription<Object?> errorSubscription;
    late final StreamSubscription<Object?> exitSubscription;
    resultSubscription = resultPort.listen((Object? message) {
      if (message is! _SearchWorkerMessage) return;
      switch (message.kind) {
        case _SearchWorkerMessageKind.ready:
          cancellationPort = message.value! as SendPort;
          if (cancellation.isCancelled) forwardCancellation();
        case _SearchWorkerMessageKind.progress:
          onProgress(message.value! as FileSearchProgress);
        case _SearchWorkerMessageKind.result:
          reportedResult = true;
          if (!completer.isCompleted) {
            completer.complete(message.value! as FileSearchResult);
          }
        case _SearchWorkerMessageKind.error:
          reportedResult = true;
          if (!completer.isCompleted) {
            completer.completeError(StateError(message.value! as String));
          }
      }
    });
    errorSubscription = errorPort.listen((Object? error) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('后台文件搜索线程异常：$error'));
      }
    });
    exitSubscription = exitPort.listen((Object? _) {
      scheduleMicrotask(() {
        if (!reportedResult && !completer.isCompleted) {
          completer.completeError(StateError('后台文件搜索线程意外退出'));
        }
      });
    });

    try {
      await Isolate.spawn<_SearchWorkerRequest>(
        _searchEntry,
        _SearchWorkerRequest(resultPort.sendPort, request),
        debugName: 'vibekits-file-search',
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

  static Future<void> _searchEntry(_SearchWorkerRequest worker) async {
    final ReceivePort cancellationPort = ReceivePort();
    final FileSearchCancellation cancellation = FileSearchCancellation();
    final StreamSubscription<Object?> cancellationSubscription =
        cancellationPort.listen((Object? _) => cancellation.cancel());
    worker.resultPort.send(
      _SearchWorkerMessage(
        _SearchWorkerMessageKind.ready,
        cancellationPort.sendPort,
      ),
    );
    final Stopwatch progressClock = Stopwatch()..start();
    FileSearchProgress? latestProgress;
    try {
      final FileSearchResult result = await FileSearchService.search(
        worker.request,
        cancellation: cancellation,
        onProgress: (FileSearchProgress progress) {
          latestProgress = progress;
          if (progressClock.elapsedMilliseconds < 100) return;
          progressClock.reset();
          worker.resultPort.send(
            _SearchWorkerMessage(_SearchWorkerMessageKind.progress, progress),
          );
        },
      );
      if (latestProgress != null) {
        worker.resultPort.send(
          _SearchWorkerMessage(
            _SearchWorkerMessageKind.progress,
            latestProgress,
          ),
        );
      }
      worker.resultPort.send(
        _SearchWorkerMessage(_SearchWorkerMessageKind.result, result),
      );
    } catch (error, stackTrace) {
      worker.resultPort.send(
        _SearchWorkerMessage(
          _SearchWorkerMessageKind.error,
          '$error\n$stackTrace',
        ),
      );
    } finally {
      await cancellationSubscription.cancel();
      cancellationPort.close();
    }
  }
}

enum _SearchWorkerMessageKind { ready, progress, result, error }

class _SearchWorkerMessage {
  const _SearchWorkerMessage(this.kind, this.value);

  final _SearchWorkerMessageKind kind;
  final Object? value;
}

class _SearchWorkerRequest {
  const _SearchWorkerRequest(this.resultPort, this.request);

  final SendPort resultPort;
  final FileSearchRequest request;
}
