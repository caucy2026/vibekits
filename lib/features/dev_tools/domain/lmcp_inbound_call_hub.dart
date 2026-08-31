import 'dart:async';
import 'dart:convert';

enum LmcpInboundCallPhase { running, cancelling, succeeded, failed, cancelled }

class LmcpUserTerminatedException implements Exception {
  const LmcpUserTerminatedException();

  static const String code = 'USER_TERMINATED';

  @override
  String toString() => code;
}

typedef LmcpCancellationHook = FutureOr<void> Function();

/// Cooperative cancellation boundary for an inbound LMCP tool invocation.
///
/// Resource-owning adapters should register cleanup as soon as the resource is
/// acquired, and call [throwIfCancelled] between safe/atomic steps. A forced
/// close completes [whenCancelled] synchronously, so the HTTP request can
/// return without waiting for a slow cleanup hook.
class LmcpInboundCallCancellation {
  LmcpInboundCallCancellation({
    this.cleanupTimeout = const Duration(seconds: 5),
  });

  final Duration cleanupTimeout;
  final Completer<void> _cancelled = Completer<void>();
  final Completer<void> _cleanupFinished = Completer<void>();
  final List<LmcpCancellationHook> _hooks = <LmcpCancellationHook>[];

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  Future<void> get cleanupFinished => _cleanupFinished.future;

  void throwIfCancelled() {
    if (isCancelled) throw const LmcpUserTerminatedException();
  }

  void addCleanupHook(LmcpCancellationHook hook) {
    if (isCancelled) {
      unawaited(_runHook(hook));
      return;
    }
    _hooks.add(hook);
  }

  Future<void> _request() async {
    if (isCancelled) return cleanupFinished;
    _cancelled.complete();
    final List<LmcpCancellationHook> hooks = List<LmcpCancellationHook>.of(
      _hooks.reversed,
    );
    _hooks.clear();
    for (final LmcpCancellationHook hook in hooks) {
      await _runHook(hook);
    }
    if (!_cleanupFinished.isCompleted) _cleanupFinished.complete();
  }

  Future<void> _runHook(LmcpCancellationHook hook) async {
    try {
      await Future<void>.sync(hook).timeout(cleanupTimeout);
    } on Object {
      // Cleanup is best-effort and bounded. One failed resource must not keep
      // later resources open or delay the USER_TERMINATED response.
    }
  }
}

class LmcpInboundCallSnapshot {
  const LmcpInboundCallSnapshot({
    required this.traceId,
    required this.callerAppId,
    required this.callerInstanceId,
    required this.callerAddress,
    required this.toolId,
    required this.toolName,
    required this.argumentSummary,
    required this.scopeSummary,
    required this.startedAt,
    required this.updatedAt,
    required this.phase,
    this.taskId,
    this.progress,
    this.statusMessage,
  });

  final String traceId;
  final String callerAppId;
  final String callerInstanceId;
  final String callerAddress;
  final String toolId;
  final String toolName;
  final String argumentSummary;
  final String scopeSummary;
  final DateTime startedAt;
  final DateTime updatedAt;
  final LmcpInboundCallPhase phase;
  final String? taskId;
  final double? progress;
  final String? statusMessage;

  bool get terminal => switch (phase) {
    LmcpInboundCallPhase.succeeded ||
    LmcpInboundCallPhase.failed ||
    LmcpInboundCallPhase.cancelled => true,
    _ => false,
  };

  String get callerLabel {
    final String app = callerAppId.trim();
    final String device = callerInstanceId.trim();
    if (app.isNotEmpty && device.isNotEmpty) return '$app · $device';
    if (device.isNotEmpty) return device;
    if (app.isNotEmpty) return app;
    return callerAddress.isEmpty ? '未知 LMCP 调用方' : callerAddress;
  }

  LmcpInboundCallSnapshot copyWith({
    DateTime? updatedAt,
    LmcpInboundCallPhase? phase,
    String? taskId,
    double? progress,
    String? statusMessage,
  }) => LmcpInboundCallSnapshot(
    traceId: traceId,
    callerAppId: callerAppId,
    callerInstanceId: callerInstanceId,
    callerAddress: callerAddress,
    toolId: toolId,
    toolName: toolName,
    argumentSummary: argumentSummary,
    scopeSummary: scopeSummary,
    startedAt: startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    phase: phase ?? this.phase,
    taskId: taskId ?? this.taskId,
    progress: progress ?? this.progress,
    statusMessage: statusMessage ?? this.statusMessage,
  );
}

class LmcpInboundCallHandle {
  LmcpInboundCallHandle._(this._hub, this.traceId, this.cancellation);

  final LmcpInboundCallHub _hub;
  final String traceId;
  final LmcpInboundCallCancellation cancellation;

  void update({String? taskId, double? progress, String? statusMessage}) {
    _hub._update(
      traceId,
      taskId: taskId,
      progress: progress,
      statusMessage: statusMessage,
    );
  }

  void succeed([String? message]) =>
      _hub._finish(traceId, LmcpInboundCallPhase.succeeded, message ?? '调用完成');

  void fail([String? message]) =>
      _hub._finish(traceId, LmcpInboundCallPhase.failed, message ?? '调用失败');
}

/// Process-wide observable state for every inbound LMCP tools/call.
class LmcpInboundCallHub {
  LmcpInboundCallHub({
    this.minimumVisibleDuration = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final LmcpInboundCallHub instance = LmcpInboundCallHub();

  final Duration minimumVisibleDuration;
  final DateTime Function() _clock;
  final StreamController<List<LmcpInboundCallSnapshot>> _changes =
      StreamController<List<LmcpInboundCallSnapshot>>.broadcast(sync: true);
  final Map<String, LmcpInboundCallSnapshot> _calls =
      <String, LmcpInboundCallSnapshot>{};
  final Map<String, LmcpInboundCallCancellation> _cancellations =
      <String, LmcpInboundCallCancellation>{};
  final Map<String, Timer> _removalTimers = <String, Timer>{};

  Stream<List<LmcpInboundCallSnapshot>> get changes => _changes.stream;

  List<LmcpInboundCallSnapshot> get snapshots {
    final List<LmcpInboundCallSnapshot> result = _calls.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List<LmcpInboundCallSnapshot>.unmodifiable(result);
  }

  LmcpInboundCallHandle begin({
    required String traceId,
    required String callerAppId,
    required String callerInstanceId,
    required String callerAddress,
    required String toolId,
    required String toolName,
    required Map<String, Object?> arguments,
    required String scopeSummary,
  }) {
    final DateTime now = _clock();
    final LmcpInboundCallCancellation cancellation =
        LmcpInboundCallCancellation();
    _removalTimers.remove(traceId)?.cancel();
    _calls[traceId] = LmcpInboundCallSnapshot(
      traceId: traceId,
      callerAppId: _bounded(callerAppId, 160),
      callerInstanceId: _bounded(callerInstanceId, 200),
      callerAddress: _bounded(callerAddress, 80),
      toolId: _bounded(toolId, 240),
      toolName: _bounded(toolName, 240),
      argumentSummary: redactLmcpArguments(arguments),
      scopeSummary: _bounded(scopeSummary, 240),
      startedAt: now,
      updatedAt: now,
      phase: LmcpInboundCallPhase.running,
      statusMessage: '正在调用',
    );
    _cancellations[traceId] = cancellation;
    _emit();
    return LmcpInboundCallHandle._(this, traceId, cancellation);
  }

  Future<void> forceClose(String traceId) async {
    final LmcpInboundCallSnapshot? current = _calls[traceId];
    final LmcpInboundCallCancellation? cancellation = _cancellations[traceId];
    if (current == null || cancellation == null || current.terminal) return;
    _calls[traceId] = current.copyWith(
      updatedAt: _clock(),
      phase: LmcpInboundCallPhase.cancelling,
      statusMessage: '正在强制关闭',
    );
    _emit();
    await cancellation._request();
    _finish(traceId, LmcpInboundCallPhase.cancelled, '已由用户强制关闭');
  }

  void _update(
    String traceId, {
    String? taskId,
    double? progress,
    String? statusMessage,
  }) {
    final LmcpInboundCallSnapshot? current = _calls[traceId];
    if (current == null || current.terminal) return;
    _calls[traceId] = current.copyWith(
      updatedAt: _clock(),
      taskId: taskId,
      progress: progress?.clamp(0, 1),
      statusMessage: statusMessage == null
          ? null
          : _bounded(statusMessage, 240),
    );
    _emit();
  }

  void _finish(
    String traceId,
    LmcpInboundCallPhase phase,
    String statusMessage,
  ) {
    final LmcpInboundCallSnapshot? current = _calls[traceId];
    if (current == null || current.terminal) return;
    if (current.phase == LmcpInboundCallPhase.cancelling &&
        phase != LmcpInboundCallPhase.cancelled) {
      return;
    }
    final DateTime now = _clock();
    _calls[traceId] = current.copyWith(
      updatedAt: now,
      phase: phase,
      statusMessage: _bounded(statusMessage, 240),
    );
    _cancellations.remove(traceId);
    _emit();
    final Duration elapsed = now.difference(current.startedAt);
    final Duration remaining = elapsed >= minimumVisibleDuration
        ? Duration.zero
        : minimumVisibleDuration - elapsed;
    _removalTimers.remove(traceId)?.cancel();
    _removalTimers[traceId] = Timer(remaining, () {
      _removalTimers.remove(traceId);
      _calls.remove(traceId);
      _emit();
    });
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(snapshots);
  }

  Future<void> dispose() async {
    for (final Timer timer in _removalTimers.values) {
      timer.cancel();
    }
    _removalTimers.clear();
    await _changes.close();
  }
}

String redactLmcpArguments(Map<String, Object?> arguments) {
  final Object? redacted = _redactValue(arguments, 0);
  final String encoded = jsonEncode(redacted);
  return _bounded(encoded, 600);
}

Object? _redactValue(Object? value, int depth) {
  if (depth >= 8) return '<省略>';
  if (value is Map) {
    final Map<String, Object?> result = <String, Object?>{};
    int count = 0;
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (count++ >= 24) {
        result['…'] = '<其余字段省略>';
        break;
      }
      final String key = '${entry.key}';
      result[_bounded(key, 80)] = _sensitiveKey.hasMatch(key)
          ? '<已脱敏>'
          : _redactValue(entry.value, depth + 1);
    }
    return result;
  }
  if (value is List) {
    return value
        .take(20)
        .map((Object? item) => _redactValue(item, depth + 1))
        .toList(growable: false);
  }
  if (value is String) return _bounded(value, 160);
  return value;
}

final RegExp _sensitiveKey = RegExp(
  r'(password|passwd|secret|token|authorization|cookie|credential|private.?key|api.?key)',
  caseSensitive: false,
);

String _bounded(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit - 1)}…';
