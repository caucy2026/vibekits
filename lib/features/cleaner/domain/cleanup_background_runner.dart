import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'cleanup_deleter.dart';
import 'cleanup_rule_database.dart';
import 'cleanup_scanner.dart';
import 'cleanup_task.dart';
import 'cleanup_targets.dart';

/// Runs disk-heavy cleanup work outside the UI isolate.
///
/// Cancellation is forwarded through a dedicated send port, so pressing stop
/// remains responsive even while the worker is enumerating many files.
abstract final class CleanupBackgroundRunner {
  /// Two workers keep directory enumeration responsive without saturating the
  /// system disk or competing aggressively with foreground applications.
  static const int maxScanWorkers = 2;

  static Future<List<CleanupScanTarget>> discoverTargets({
    String harnessDebugDirectory = '',
    String bundledRuleDatabase = '',
  }) => Isolate.run(() {
    final List<CleanupScanTarget> targets = List<CleanupScanTarget>.of(
      CleanupTargetDiscovery.discover(
        harnessDebugDirectory: harnessDebugDirectory,
      ),
    );
    if (bundledRuleDatabase.trim().isNotEmpty) {
      try {
        final CleanupRuleDatabaseResult database = CleanupRuleDatabase.parse(
          bundledRuleDatabase,
        );
        final Set<String> ids = targets
            .map((CleanupScanTarget target) => target.id)
            .toSet();
        targets.addAll(
          database.targets.where(
            (CleanupScanTarget target) => ids.add(target.id),
          ),
        );
      } on FormatException {
        // A bad optional database never disables the compiled safe catalog.
      }
    }
    return targets;
  }, debugName: 'vibekits-cleanup-target-discovery');

  static Future<CleanupScanResult> scanTargets(
    List<CleanupScanTarget> targets, {
    required CleanupCancellationToken cancellationToken,
    required void Function(CleanupScanProgress progress) onProgress,
  }) async {
    if (targets.isEmpty) {
      return const CleanupScanResult(
        candidates: <CleanupCandidate>[],
        cancelled: false,
        unreadablePaths: 0,
      );
    }
    final int workerCount = targets.length < maxScanWorkers
        ? targets.length
        : maxScanWorkers;
    final List<List<CleanupScanTarget>> chunks =
        List<List<CleanupScanTarget>>.generate(
          workerCount,
          (_) => <CleanupScanTarget>[],
        );
    for (int index = 0; index < targets.length; index++) {
      chunks[index % workerCount].add(targets[index]);
    }

    final List<CleanupScanProgress?> latest = List<CleanupScanProgress?>.filled(
      workerCount,
      null,
    );
    void report(int worker, CleanupScanProgress progress) {
      latest[worker] = progress;
      onProgress(
        CleanupScanProgress(
          currentPath: progress.currentPath,
          visitedEntries: latest.fold<int>(
            0,
            (int total, CleanupScanProgress? item) =>
                total + (item?.visitedEntries ?? 0),
          ),
          candidateCount: latest.fold<int>(
            0,
            (int total, CleanupScanProgress? item) =>
                total + (item?.candidateCount ?? 0),
          ),
          candidateBytes: latest.fold<int>(
            0,
            (int total, CleanupScanProgress? item) =>
                total + (item?.candidateBytes ?? 0),
          ),
        ),
      );
    }

    final List<CleanupScanResult> results = await Future.wait(
      List<Future<CleanupScanResult>>.generate(workerCount, (int worker) {
        return _runWorker<CleanupScanResult>(
          cancellationToken: cancellationToken,
          onProgress: (Object progress) =>
              report(worker, progress as CleanupScanProgress),
          spawn: (SendPort resultPort, SendPort errorPort, SendPort exitPort) =>
              Isolate.spawn<_ScanRequest>(
                _scanEntry,
                _ScanRequest(resultPort: resultPort, targets: chunks[worker]),
                debugName: 'vibekits-cleanup-scan-${worker + 1}',
                onError: errorPort,
                onExit: exitPort,
              ),
        );
      }),
    );
    final Map<String, CleanupCandidate> candidates =
        <String, CleanupCandidate>{};
    for (final CleanupScanResult result in results) {
      for (final CleanupCandidate candidate in result.candidates) {
        final String key = Platform.isWindows
            ? candidate.path.toLowerCase()
            : candidate.path;
        candidates[key] = candidate;
      }
    }
    return CleanupScanResult(
      candidates: candidates.values.toList(growable: false),
      cancelled:
          cancellationToken.isCancelled ||
          results.any((CleanupScanResult result) => result.cancelled),
      unreadablePaths: results.fold<int>(
        0,
        (int total, CleanupScanResult result) => total + result.unreadablePaths,
      ),
      visitedEntries: results.fold<int>(
        0,
        (int total, CleanupScanResult result) => total + result.visitedEntries,
      ),
      candidateBytes: candidates.values.fold<int>(
        0,
        (int total, CleanupCandidate candidate) => total + candidate.size,
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
