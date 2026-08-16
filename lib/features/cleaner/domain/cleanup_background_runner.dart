import 'dart:async';
import 'dart:isolate';

import 'cleanup_deleter.dart';
import 'cleanup_scanner.dart';
import 'cleanup_task.dart';
import 'cleanup_targets.dart';

/// Runs disk-heavy cleanup work outside the UI isolate.
///
/// Cancellation is forwarded through a dedicated send port, so pressing stop
/// remains responsive even while the worker is enumerating many files.
abstract final class CleanupBackgroundRunner {
  static Future<List<CleanupScanTarget>> discoverTargets() => Isolate.run(
    CleanupTargetDiscovery.discover,
    debugName: 'vibekits-cleanup-target-discovery',
  );

  static Future<CleanupScanResult> scanTargets(
    List<CleanupScanTarget> targets, {
    required CleanupCancellationToken cancellationToken,
    required void Function(CleanupScanProgress progress) onProgress,
  }) {
    return _runWorker<CleanupScanResult>(
      cancellationToken: cancellationToken,
      onProgress: (Object progress) =>
          onProgress(progress as CleanupScanProgress),
      spawn: (SendPort resultPort, SendPort errorPort, SendPort exitPort) =>
          Isolate.spawn<_ScanRequest>(
            _scanEntry,
            _ScanRequest(resultPort: resultPort, targets: targets),
            debugName: 'vibekits-cleanup-scan',
            onError: errorPort,
            onExit: exitPort,
          ),
    );
  }

  static Future<CleanupDeleteResult> deleteCandidates(
    List<CleanupCandidate> candidates, {
    required CleanupCancellationToken cancellationToken,
    required bool permanentFallback,
    required void Function(CleanupDeleteProgress progress) onProgress,
  }) {
    return _runWorker<CleanupDeleteResult>(
      cancellationToken: cancellationToken,
      onProgress: (Object progress) =>
          onProgress(progress as CleanupDeleteProgress),
      spawn: (SendPort resultPort, SendPort errorPort, SendPort exitPort) =>
          Isolate.spawn<_DeleteRequest>(
            _deleteEntry,
            _DeleteRequest(
              resultPort: resultPort,
              candidates: candidates,
              permanentFallback: permanentFallback,
            ),
            debugName: 'vibekits-cleanup-delete',
            onError: errorPort,
            onExit: exitPort,
          ),
    );
  }

  static Future<T> _runWorker<T>({
    required CleanupCancellationToken cancellationToken,
    required void Function(Object progress) onProgress,
    required Future<Isolate> Function(
      SendPort resultPort,
      SendPort errorPort,
      SendPort exitPort,
    )
    spawn,
  }) async {
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<T> completer = Completer<T>();
    SendPort? workerCancellationPort;
    bool workerReportedResult = false;

    void forwardCancellation() => workerCancellationPort?.send(true);

    cancellationToken.addCancelListener(forwardCancellation);
    late final StreamSubscription<Object?> resultSubscription;
    late final StreamSubscription<Object?> errorSubscription;
    late final StreamSubscription<Object?> exitSubscription;
    resultSubscription = resultPort.listen((Object? message) {
      if (message is! _WorkerMessage) return;
      switch (message.kind) {
        case _WorkerMessageKind.ready:
          workerCancellationPort = message.value! as SendPort;
          if (cancellationToken.isCancelled) forwardCancellation();
        case _WorkerMessageKind.progress:
          onProgress(message.value!);
        case _WorkerMessageKind.result:
          workerReportedResult = true;
          if (!completer.isCompleted) completer.complete(message.value! as T);
        case _WorkerMessageKind.error:
          workerReportedResult = true;
          if (!completer.isCompleted) {
            completer.completeError(StateError(message.value! as String));
          }
      }
    });
    errorSubscription = errorPort.listen((Object? error) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('后台清理线程异常：$error'));
      }
    });
    exitSubscription = exitPort.listen((Object? _) {
      scheduleMicrotask(() {
        if (!workerReportedResult && !completer.isCompleted) {
          completer.completeError(StateError('后台清理线程意外退出'));
        }
      });
    });

    try {
      await spawn(resultPort.sendPort, errorPort.sendPort, exitPort.sendPort);
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

  static Future<void> _scanEntry(_ScanRequest request) async {
    final ReceivePort cancellationPort = ReceivePort();
    final CleanupCancellationToken token = CleanupCancellationToken();
    final StreamSubscription<Object?> cancellationSubscription =
        cancellationPort.listen((Object? _) => token.cancel());
    request.resultPort.send(
      _WorkerMessage(_WorkerMessageKind.ready, cancellationPort.sendPort),
    );
    try {
      final CleanupScanResult result = await CleanupScanner.scanTargets(
        request.targets,
        cancellationToken: token,
        onProgress: (CleanupScanProgress progress) => request.resultPort.send(
          _WorkerMessage(_WorkerMessageKind.progress, progress),
        ),
      );
      request.resultPort.send(
        _WorkerMessage(_WorkerMessageKind.result, result),
      );
    } catch (error, stackTrace) {
      request.resultPort.send(
        _WorkerMessage(_WorkerMessageKind.error, '$error\n$stackTrace'),
      );
    } finally {
      await cancellationSubscription.cancel();
      cancellationPort.close();
    }
  }

  static Future<void> _deleteEntry(_DeleteRequest request) async {
    final ReceivePort cancellationPort = ReceivePort();
    final CleanupCancellationToken token = CleanupCancellationToken();
    final StreamSubscription<Object?> cancellationSubscription =
        cancellationPort.listen((Object? _) => token.cancel());
    request.resultPort.send(
      _WorkerMessage(_WorkerMessageKind.ready, cancellationPort.sendPort),
    );
    try {
      final CleanupDeleteResult result = await CleanupDeleter.deleteCandidates(
        request.candidates,
        cancellationToken: token,
        permanentFallback: request.permanentFallback,
        onProgress: (CleanupDeleteProgress progress) => request.resultPort.send(
          _WorkerMessage(_WorkerMessageKind.progress, progress),
        ),
      );
      request.resultPort.send(
        _WorkerMessage(_WorkerMessageKind.result, result),
      );
    } catch (error, stackTrace) {
      request.resultPort.send(
        _WorkerMessage(_WorkerMessageKind.error, '$error\n$stackTrace'),
      );
    } finally {
      await cancellationSubscription.cancel();
      cancellationPort.close();
    }
  }
}

enum _WorkerMessageKind { ready, progress, result, error }

class _WorkerMessage {
  const _WorkerMessage(this.kind, this.value);

  final _WorkerMessageKind kind;
  final Object? value;
}

class _ScanRequest {
  const _ScanRequest({required this.resultPort, required this.targets});

  final SendPort resultPort;
  final List<CleanupScanTarget> targets;
}

class _DeleteRequest {
  const _DeleteRequest({
    required this.resultPort,
    required this.candidates,
    required this.permanentFallback,
  });

  final SendPort resultPort;
  final List<CleanupCandidate> candidates;
  final bool permanentFallback;
}
