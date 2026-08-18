import 'dart:async';
import 'dart:isolate';

import 'cleanup_task.dart';
import 'system_drive_analyzer.dart';

abstract final class SystemDriveAnalysisRunner {
  static Future<SystemDriveAnalysis> analyze(
    String rootPath, {
    required CleanupCancellationToken cancellationToken,
    required void Function(SystemDriveAnalysisProgress progress) onProgress,
  }) async {
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<SystemDriveAnalysis> completer =
        Completer<SystemDriveAnalysis>();
    SendPort? cancelPort;
    bool reported = false;

    void forwardCancel() => cancelPort?.send(true);

    cancellationToken.addCancelListener(forwardCancel);
    final StreamSubscription<Object?> resultSubscription = resultPort.listen((
      Object? message,
    ) {
      if (message is _DriveAnalysisReady) {
        cancelPort = message.cancelPort;
        if (cancellationToken.isCancelled) forwardCancel();
      } else if (message is SystemDriveAnalysisProgress) {
        onProgress(message);
      } else if (message is SystemDriveAnalysis) {
        reported = true;
        if (!completer.isCompleted) completer.complete(message);
      } else if (message is _DriveAnalysisFailure) {
        reported = true;
        if (!completer.isCompleted) {
          completer.completeError(StateError(message.message));
        }
      }
    });
    final StreamSubscription<Object?> errorSubscription = errorPort.listen((
      Object? error,
    ) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('系统盘分析线程异常：$error'));
      }
    });
    final StreamSubscription<Object?> exitSubscription = exitPort.listen((_) {
      scheduleMicrotask(() {
        if (!reported && !completer.isCompleted) {
          completer.completeError(StateError('系统盘分析线程意外退出'));
        }
      });
    });
    try {
      await Isolate.spawn<_DriveAnalysisRequest>(
        _entry,
        _DriveAnalysisRequest(resultPort.sendPort, rootPath),
        debugName: 'vibekits-system-drive-analysis',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      return await completer.future;
    } finally {
      cancellationToken.removeCancelListener(forwardCancel);
      await resultSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      resultPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  static Future<void> _entry(_DriveAnalysisRequest request) async {
    final ReceivePort cancellationPort = ReceivePort();
    final CleanupCancellationToken token = CleanupCancellationToken();
    final StreamSubscription<Object?> subscription = cancellationPort.listen((
      _,
    ) {
      token.cancel();
    });
    request.resultPort.send(_DriveAnalysisReady(cancellationPort.sendPort));
    try {
      final SystemDriveAnalysis analysis = await SystemDriveAnalyzer.analyze(
        request.rootPath,
        cancellationToken: token,
        onProgress: request.resultPort.send,
      );
      request.resultPort.send(analysis);
    } catch (error, stackTrace) {
      request.resultPort.send(_DriveAnalysisFailure('$error\n$stackTrace'));
    } finally {
      await subscription.cancel();
      cancellationPort.close();
    }
  }
}

class _DriveAnalysisRequest {
  const _DriveAnalysisRequest(this.resultPort, this.rootPath);

  final SendPort resultPort;
  final String rootPath;
}

class _DriveAnalysisReady {
  const _DriveAnalysisReady(this.cancelPort);

  final SendPort cancelPort;
}

class _DriveAnalysisFailure {
  const _DriveAnalysisFailure(this.message);

  final String message;
}
