import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'harness_runtime_log_store.dart';

/// Public lifecycle phases safe to share with a read-only status client.
enum HarnessWorkPhase {
  idle,
  starting,
  ready,
  queued,
  planning,
  reasoning,
  waitingApproval,
  invokingTool,
  toolRunning,

  /// Kept for source compatibility with the original single-value hub.
  @Deprecated('Use toolRunning for new registry tasks.')
  runningTool,
  synthesizing,
  completed,
  failed,
  canceled,
  stopped,
  interrupted,
}

extension HarnessWorkPhaseProperties on HarnessWorkPhase {
  HarnessWorkPhase get canonical => this == HarnessWorkPhase.runningTool
      ? HarnessWorkPhase.toolRunning
      : this;

  String get wireName => canonical.name;

  bool get terminal => switch (canonical) {
    HarnessWorkPhase.completed ||
    HarnessWorkPhase.failed ||
    HarnessWorkPhase.canceled ||
    HarnessWorkPhase.stopped ||
    HarnessWorkPhase.interrupted => true,
    _ => false,
  };

  bool get busy => switch (canonical) {
    HarnessWorkPhase.starting ||
    HarnessWorkPhase.queued ||
    HarnessWorkPhase.planning ||
    HarnessWorkPhase.reasoning ||
    HarnessWorkPhase.waitingApproval ||
    HarnessWorkPhase.invokingTool ||
    HarnessWorkPhase.toolRunning ||
    HarnessWorkPhase.synthesizing => true,
    _ => false,
  };
}

class HarnessWorkSnapshot {
  const HarnessWorkSnapshot({
    required this.phase,
    required this.message,
    required this.updatedAt,
    this.toolId = '',
    this.toolName = '',
    this.target = '',
  });

  factory HarnessWorkSnapshot.idle() => HarnessWorkSnapshot(
    phase: HarnessWorkPhase.idle,
    message: '尚未启动 Harness',
    updatedAt: DateTime.now(),
  );

  final HarnessWorkPhase phase;
  final String message;
  final DateTime updatedAt;
  final String toolId;
  final String toolName;
  final String target;

  bool get busy => phase.busy;

  Map<String, Object?> toJson() => <String, Object?>{
    'phase': phase.wireName,
    'message': message,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (toolId.isNotEmpty) 'toolId': toolId,
    if (toolName.isNotEmpty) 'toolName': toolName,
    if (target.isNotEmpty) 'target': target,
  };
}

class HarnessTaskKey {
  const HarnessTaskKey({
    required this.workspaceRef,
    required this.sessionRef,
    required this.taskId,
  });

  final String workspaceRef;
  final String sessionRef;
  final String taskId;

  @override
  bool operator ==(Object other) =>
      other is HarnessTaskKey &&
      workspaceRef == other.workspaceRef &&
      sessionRef == other.sessionRef &&
      taskId == other.taskId;

  @override
  int get hashCode => Object.hash(workspaceRef, sessionRef, taskId);

  @override
  String toString() => '$workspaceRef/$sessionRef/$taskId';
}

class HarnessWorkProgress {
  const HarnessWorkProgress({
    required this.current,
    required this.total,
    required this.unit,
  });

  final int current;
  final int total;
  final String unit;

  Map<String, Object?> toJson() => <String, Object?>{
    'current': current,
    'total': total,
    'unit': unit,
  };
}

class HarnessTaskSnapshot {
  const HarnessTaskSnapshot({
    required this.deviceRef,
    required this.workspaceRef,
    required this.workspaceLabel,
    required this.sessionRef,
    required this.taskId,
    required this.streamSequence,
    required this.taskRevision,
    required this.phase,
    required this.message,
    required this.startedAt,
    required this.updatedAt,
    this.toolId = '',
    this.toolName = '',
    this.target = '',
    this.progress,
  });

  factory HarnessTaskSnapshot.fromJson(Map<String, Object?> json) {
    final HarnessWorkPhase phase = HarnessWorkPhase.values.firstWhere(
      (HarnessWorkPhase value) => value.wireName == json['phase'],
      orElse: () => HarnessWorkPhase.interrupted,
    );
    final Object? rawProgress = json['progress'];
    final Map<Object?, Object?>? progressJson =
        rawProgress is Map<Object?, Object?> ? rawProgress : null;
    return HarnessTaskSnapshot(
      deviceRef: json['deviceRef'] as String? ?? '',
      workspaceRef: json['workspaceRef'] as String? ?? '',
      workspaceLabel: json['workspaceLabel'] as String? ?? '',
      sessionRef: json['sessionRef'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      streamSequence: json['streamSequence'] as int? ?? 0,
      taskRevision: json['taskRevision'] as int? ?? 0,
      phase: phase,
      message: json['message'] as String? ?? '',
      toolId: json['toolId'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      target: json['target'] as String? ?? '',
      progress: progressJson == null
          ? null
          : HarnessWorkProgress(
              current: progressJson['current'] as int? ?? 0,
              total: progressJson['total'] as int? ?? 0,
              unit: progressJson['unit'] as String? ?? '',
            ),
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  final String deviceRef;
  final String workspaceRef;
  final String workspaceLabel;
  final String sessionRef;
  final String taskId;
  final int streamSequence;
  final int taskRevision;
  final HarnessWorkPhase phase;
  final String message;
  final String toolId;
  final String toolName;
  final String target;
  final HarnessWorkProgress? progress;
  final DateTime startedAt;
  final DateTime updatedAt;

  HarnessTaskKey get key => HarnessTaskKey(
    workspaceRef: workspaceRef,
    sessionRef: sessionRef,
    taskId: taskId,
  );

  bool get busy => phase.busy;
  bool get terminal => phase.terminal;

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceRef': deviceRef,
    'workspaceRef': workspaceRef,
    'workspaceLabel': workspaceLabel,
    'sessionRef': sessionRef,
    'taskId': taskId,
    'streamSequence': streamSequence,
    'taskRevision': taskRevision,
    'phase': phase.wireName,
    'message': message,
    if (toolId.isNotEmpty) 'toolId': toolId,
    if (toolName.isNotEmpty) 'toolName': toolName,
    if (target.isNotEmpty) 'target': target,
    if (progress case final HarnessWorkProgress value)
      'progress': value.toJson(),
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class HarnessWorkAggregate {
  const HarnessWorkAggregate({
    required this.taskCount,
    required this.busyCount,
    required this.waitingApprovalCount,
    required this.failedCount,
  });

  final int taskCount;
  final int busyCount;
  final int waitingApprovalCount;
  final int failedCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'taskCount': taskCount,
    'busyCount': busyCount,
    'waitingApprovalCount': waitingApprovalCount,
    'failedCount': failedCount,
  };
}

class HarnessWorkRegistrySnapshot {
  const HarnessWorkRegistrySnapshot({
    required this.streamSequence,
    required this.generatedAt,
    required this.aggregate,
    required this.tasks,
  });

  static const String schema = 'vibekits.harness.status/v1';

  final int streamSequence;
  final DateTime generatedAt;
  final HarnessWorkAggregate aggregate;
  final List<HarnessTaskSnapshot> tasks;

  bool get busy => aggregate.busyCount > 0;
  int get encodedByteLength => utf8.encode(jsonEncode(toJson())).length;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'streamSequence': streamSequence,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'aggregate': aggregate.toJson(),
    'tasks': <Map<String, Object?>>[
      for (final HarnessTaskSnapshot task in tasks) task.toJson(),
    ],
  };
}

typedef HarnessWorkClock = DateTime Function();

/// Multi-workspace, multi-session, multi-task public status registry.
///
/// It stores only latest task state, publishes synchronously with no back
/// pressure, and bounds both retained task count and encoded public snapshots.
class HarnessTaskStateRegistry {
  HarnessTaskStateRegistry({
    HarnessWorkClock? clock,
    this.maxTasks = 128,
    this.maxSnapshotBytes = 32 * 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxTasks < 10) {
      throw ArgumentError.value(maxTasks, 'maxTasks', 'must be at least 10');
    }
    if (maxSnapshotBytes < maxTaskSnapshotBytes) {
      throw ArgumentError.value(
        maxSnapshotBytes,
        'maxSnapshotBytes',
        'must fit at least one task snapshot',
      );
    }
    _latest = _makeSnapshot(_clock().toUtc());
  }

  static const int maxTaskSnapshotBytes = 4 * 1024;

  final HarnessWorkClock _clock;
  final int maxTasks;
  final int maxSnapshotBytes;
  final Map<HarnessTaskKey, HarnessTaskSnapshot> _tasks =
      <HarnessTaskKey, HarnessTaskSnapshot>{};
  final StreamController<HarnessWorkRegistrySnapshot> _changes =
      StreamController<HarnessWorkRegistrySnapshot>.broadcast();
  int _streamSequence = 0;
  int _generatedTaskId = 0;
  bool _changeScheduled = false;
  late HarnessWorkRegistrySnapshot _latest;

  HarnessWorkRegistrySnapshot get latest => _latest;
  Stream<HarnessWorkRegistrySnapshot> get changes => _changes.stream;
  int get streamSequence => _streamSequence;

  HarnessTaskSnapshot beginTask({
    String deviceRef = 'opaque-device',
    required String workspaceRef,
    String workspaceLabel = '工作区',
    required String sessionRef,
    String taskId = '',
    HarnessWorkPhase phase = HarnessWorkPhase.queued,
    String message = '任务已排队',
    String toolId = '',
    String toolName = '',
    String target = '',
    HarnessWorkProgress? progress,
  }) {
    final HarnessWorkPhase canonicalPhase = phase.canonical;
    if (canonicalPhase == HarnessWorkPhase.idle || canonicalPhase.terminal) {
      throw ArgumentError.value(
        phase,
        'phase',
        'a task must begin in a non-terminal work phase',
      );
    }
    final DateTime now = _clock().toUtc();
    final HarnessTaskKey key = HarnessTaskKey(
      workspaceRef: _publicRef(workspaceRef, 'workspace'),
      sessionRef: _publicRef(sessionRef, 'session'),
      taskId: _publicRef(
        taskId.isEmpty ? 'task-${++_generatedTaskId}' : taskId,
        'task',
      ),
    );
    if (_tasks.containsKey(key)) {
      throw StateError('Harness task already exists: $key');
    }
    final HarnessTaskSnapshot task = HarnessTaskSnapshot(
      deviceRef: _publicRef(deviceRef, 'device'),
      workspaceRef: key.workspaceRef,
      workspaceLabel: _publicText(workspaceLabel, 120),
      sessionRef: key.sessionRef,
      taskId: key.taskId,
      streamSequence: ++_streamSequence,
      taskRevision: 1,
      phase: canonicalPhase,
      message: _publicText(message, 240),
      toolId: _publicText(toolId, 200, redactPaths: false),
      toolName: _publicText(toolName, 120),
      target: _publicText(target, 300),
      progress: _sanitizeProgress(progress),
      startedAt: now,
      updatedAt: now,
    );
    _tasks[key] = task;
    _pruneRetainedTasks();
    _emit(now);
    return task;
  }

  HarnessTaskSnapshot updateTask({
    required HarnessTaskKey key,
    required HarnessWorkPhase phase,
    String? message,
    String? toolId,
    String? toolName,
    String? target,
    HarnessWorkProgress? progress,
    bool clearProgress = false,
  }) {
    final HarnessTaskKey normalizedKey = _normalizeKey(key);
    final HarnessTaskSnapshot current = _requireTask(normalizedKey);
    final HarnessWorkPhase next = phase.canonical;
    if (!_canTransition(current.phase.canonical, next)) {
      throw StateError(
        'Illegal Harness task transition: '
        '${current.phase.wireName} -> ${next.wireName}',
      );
    }
    return _replaceTask(
      current,
      phase: next,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
      progress: progress,
      clearProgress: clearProgress,
    );
  }

  HarnessTaskSnapshot finishTask({
    required HarnessTaskKey key,
    required HarnessWorkPhase phase,
    String? message,
    String? toolId,
    String? toolName,
    String? target,
    HarnessWorkProgress? progress,
  }) {
    if (!phase.terminal) {
      throw ArgumentError.value(phase, 'phase', 'must be a terminal phase');
    }
    return updateTask(
      key: key,
      phase: phase,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
      progress: progress,
    );
  }

  /// Restores persisted latest states after process restart.
  ///
  /// Previously running tasks become terminal `interrupted` tasks. Global
  /// sequence continues above the previous stream for gap/resync detection.
  void restoreAfterRestart(
    Iterable<HarnessTaskSnapshot> previousTasks, {
    int afterStreamSequence = 0,
  }) {
    if (_tasks.isNotEmpty) {
      throw StateError('Restart restoration requires an empty registry');
    }
    final List<HarnessTaskSnapshot> restored = previousTasks.toList();
    int previousMaximum = afterStreamSequence;
    for (final HarnessTaskSnapshot task in restored) {
      if (task.streamSequence > previousMaximum) {
        previousMaximum = task.streamSequence;
      }
    }
    _streamSequence = previousMaximum;
    for (final HarnessTaskSnapshot previous in restored) {
      final DateTime now = _clock().toUtc();
      final HarnessTaskKey key = _normalizeKey(previous.key);
      if (_tasks.containsKey(key)) continue;
      final bool wasTerminal = previous.phase.terminal;
      _tasks[key] = HarnessTaskSnapshot(
        deviceRef: _publicRef(previous.deviceRef, 'device'),
        workspaceRef: key.workspaceRef,
        workspaceLabel: _publicText(previous.workspaceLabel, 120),
        sessionRef: key.sessionRef,
        taskId: key.taskId,
        streamSequence: ++_streamSequence,
        taskRevision: previous.taskRevision + (wasTerminal ? 0 : 1),
        phase: wasTerminal
            ? previous.phase.canonical
            : HarnessWorkPhase.interrupted,
        message: wasTerminal
            ? _publicText(previous.message, 240)
            : '应用重启，任务已中断',
        toolId: _publicText(previous.toolId, 200, redactPaths: false),
        toolName: _publicText(previous.toolName, 120),
        target: _publicText(previous.target, 300),
        progress: _sanitizeProgress(previous.progress),
        startedAt: previous.startedAt.toUtc(),
        updatedAt: now,
      );
    }
    _pruneRetainedTasks();
    _emit(_clock().toUtc());
  }

  /// Feeds pre-registry callers into a reserved task without breaking their
  /// historical phase-skipping behavior.
  HarnessTaskSnapshot publishCompatibility({
    required HarnessWorkPhase phase,
    required String message,
    String toolId = '',
    String toolName = '',
    String target = '',
  }) {
    const String workspaceRef = 'legacy-workspace';
    const String sessionRef = 'legacy-session';
    HarnessTaskSnapshot? current;
    for (final HarnessTaskSnapshot task in _tasks.values) {
      if (task.workspaceRef == workspaceRef &&
          task.sessionRef == sessionRef &&
          (current == null || task.streamSequence > current.streamSequence)) {
        current = task;
      }
    }
    final HarnessWorkPhase next = phase.canonical;
    if (current == null ||
        current.terminal ||
        next == HarnessWorkPhase.starting &&
            current.phase.canonical != HarnessWorkPhase.starting) {
      return beginTask(
        workspaceRef: workspaceRef,
        sessionRef: sessionRef,
        taskId: 'legacy-task-${++_generatedTaskId}',
        phase: next == HarnessWorkPhase.idle ? HarnessWorkPhase.ready : next,
        message: message,
        toolId: toolId,
        toolName: toolName,
        target: target,
      );
    }
    // Compatibility calls may skip lifecycle phases, but a terminal task is
    // never reopened: the branch above creates a new task instead.
    return _replaceTask(
      current,
      phase: next,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
    );
  }

  HarnessTaskSnapshot _replaceTask(
    HarnessTaskSnapshot current, {
    required HarnessWorkPhase phase,
    String? message,
    String? toolId,
    String? toolName,
    String? target,
    HarnessWorkProgress? progress,
    bool clearProgress = false,
  }) {
    final DateTime now = _clock().toUtc();
    final HarnessTaskSnapshot task = HarnessTaskSnapshot(
      deviceRef: current.deviceRef,
      workspaceRef: current.workspaceRef,
      workspaceLabel: current.workspaceLabel,
      sessionRef: current.sessionRef,
      taskId: current.taskId,
      streamSequence: ++_streamSequence,
      taskRevision: current.taskRevision + 1,
      phase: phase.canonical,
      message: message == null ? current.message : _publicText(message, 240),
      toolId: toolId == null
          ? current.toolId
          : _publicText(toolId, 200, redactPaths: false),
      toolName: toolName == null
          ? current.toolName
          : _publicText(toolName, 120),
      target: target == null ? current.target : _publicText(target, 300),
      progress: clearProgress
          ? null
          : _sanitizeProgress(progress) ?? current.progress,
      startedAt: current.startedAt,
      updatedAt: now,
    );
    _tasks[current.key] = task;
    _emit(now);
    return task;
  }

  HarnessTaskSnapshot _requireTask(HarnessTaskKey key) {
    final HarnessTaskSnapshot? task = _tasks[key];
    if (task == null) throw StateError('Unknown Harness task: $key');
    return task;
  }

  HarnessTaskKey _normalizeKey(HarnessTaskKey key) => HarnessTaskKey(
    workspaceRef: _publicRef(key.workspaceRef, 'workspace'),
    sessionRef: _publicRef(key.sessionRef, 'session'),
    taskId: _publicRef(key.taskId, 'task'),
  );

  void _emit(DateTime generatedAt) {
    _latest = _makeSnapshot(generatedAt);
    if (_changeScheduled) return;
    _changeScheduled = true;
    scheduleMicrotask(() {
      _changeScheduled = false;
      _changes.add(_latest);
    });
  }

  HarnessWorkRegistrySnapshot _makeSnapshot(DateTime generatedAt) {
    final List<HarnessTaskSnapshot> allTasks = _tasks.values.toList()
      ..sort(
        (HarnessTaskSnapshot a, HarnessTaskSnapshot b) =>
            b.streamSequence.compareTo(a.streamSequence),
      );
    final HarnessWorkAggregate aggregate = HarnessWorkAggregate(
      taskCount: allTasks.length,
      busyCount: allTasks.where((HarnessTaskSnapshot task) => task.busy).length,
      waitingApprovalCount: allTasks
          .where(
            (HarnessTaskSnapshot task) =>
                task.phase.canonical == HarnessWorkPhase.waitingApproval,
          )
          .length,
      failedCount: allTasks
          .where(
            (HarnessTaskSnapshot task) =>
                task.phase.canonical == HarnessWorkPhase.failed,
          )
          .length,
    );
    final List<HarnessTaskSnapshot> included = <HarnessTaskSnapshot>[];
    for (final HarnessTaskSnapshot task in allTasks) {
      final HarnessWorkRegistrySnapshot candidate = HarnessWorkRegistrySnapshot(
        streamSequence: _streamSequence,
        generatedAt: generatedAt,
        aggregate: aggregate,
        tasks: List<HarnessTaskSnapshot>.unmodifiable(<HarnessTaskSnapshot>[
          ...included,
          task,
        ]),
      );
      if (candidate.encodedByteLength > maxSnapshotBytes) break;
      included.add(task);
    }
    return HarnessWorkRegistrySnapshot(
      streamSequence: _streamSequence,
      generatedAt: generatedAt,
      aggregate: aggregate,
      tasks: List<HarnessTaskSnapshot>.unmodifiable(included),
    );
  }

  void _pruneRetainedTasks() {
    if (_tasks.length <= maxTasks) return;
    final List<HarnessTaskSnapshot> oldestFirst = _tasks.values.toList()
      ..sort(
        (HarnessTaskSnapshot a, HarnessTaskSnapshot b) =>
            a.streamSequence.compareTo(b.streamSequence),
      );
    for (final HarnessTaskSnapshot task in oldestFirst) {
      if (_tasks.length <= maxTasks) break;
      _tasks.remove(task.key);
    }
  }

  static bool _canTransition(HarnessWorkPhase current, HarnessWorkPhase next) {
    if (current.terminal) return false;
    if (next == HarnessWorkPhase.idle || next == HarnessWorkPhase.starting) {
      return current == next;
    }
    if (next.terminal || current == next) return true;
    return switch (current) {
      HarnessWorkPhase.starting => next == HarnessWorkPhase.ready,
      HarnessWorkPhase.ready =>
        next == HarnessWorkPhase.queued ||
            next == HarnessWorkPhase.planning ||
            next == HarnessWorkPhase.reasoning ||
            next == HarnessWorkPhase.waitingApproval ||
            next == HarnessWorkPhase.invokingTool ||
            next == HarnessWorkPhase.toolRunning ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.queued =>
        next == HarnessWorkPhase.planning ||
            next == HarnessWorkPhase.reasoning ||
            next == HarnessWorkPhase.waitingApproval ||
            next == HarnessWorkPhase.invokingTool ||
            next == HarnessWorkPhase.toolRunning ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.planning =>
        next == HarnessWorkPhase.reasoning ||
            next == HarnessWorkPhase.waitingApproval ||
            next == HarnessWorkPhase.invokingTool ||
            next == HarnessWorkPhase.toolRunning ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.reasoning =>
        next == HarnessWorkPhase.waitingApproval ||
            next == HarnessWorkPhase.invokingTool ||
            next == HarnessWorkPhase.toolRunning ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.waitingApproval =>
        next == HarnessWorkPhase.reasoning ||
            next == HarnessWorkPhase.invokingTool ||
            next == HarnessWorkPhase.toolRunning ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.invokingTool =>
        next == HarnessWorkPhase.toolRunning ||
            next == HarnessWorkPhase.reasoning ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.toolRunning || HarnessWorkPhase.runningTool =>
        next == HarnessWorkPhase.queued ||
            next == HarnessWorkPhase.planning ||
            next == HarnessWorkPhase.reasoning ||
            next == HarnessWorkPhase.waitingApproval ||
            next == HarnessWorkPhase.invokingTool ||
            next == HarnessWorkPhase.synthesizing,
      HarnessWorkPhase.synthesizing => false,
      HarnessWorkPhase.idle ||
      HarnessWorkPhase.completed ||
      HarnessWorkPhase.failed ||
      HarnessWorkPhase.canceled ||
      HarnessWorkPhase.stopped ||
      HarnessWorkPhase.interrupted => false,
    };
  }
}

/// Backward-compatible process-wide projection plus the full task registry.
abstract final class HarnessWorkStatusHub {
  static final StreamController<HarnessWorkSnapshot> _changes =
      StreamController<HarnessWorkSnapshot>.broadcast();
  static final HarnessTaskStateRegistry _registry = HarnessTaskStateRegistry();
  static HarnessWorkSnapshot _latest = HarnessWorkSnapshot.idle();

  static HarnessWorkSnapshot get latest => _latest;
  static Stream<HarnessWorkSnapshot> get changes => _changes.stream;
  static HarnessWorkRegistrySnapshot get registryLatest => _registry.latest;
  static Stream<HarnessWorkRegistrySnapshot> get registryChanges =>
      _registry.changes;

  static HarnessTaskSnapshot beginTask({
    String deviceRef = 'opaque-device',
    required String workspaceRef,
    String workspaceLabel = '工作区',
    required String sessionRef,
    String taskId = '',
    HarnessWorkPhase phase = HarnessWorkPhase.queued,
    String message = '任务已排队',
    String toolId = '',
    String toolName = '',
    String target = '',
    HarnessWorkProgress? progress,
  }) {
    final HarnessTaskSnapshot task = _registry.beginTask(
      deviceRef: deviceRef,
      workspaceRef: workspaceRef,
      workspaceLabel: workspaceLabel,
      sessionRef: sessionRef,
      taskId: taskId,
      phase: phase,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
      progress: progress,
    );
    _project(task);
    return task;
  }

  static HarnessTaskSnapshot updateTask({
    required HarnessTaskKey key,
    required HarnessWorkPhase phase,
    String? message,
    String? toolId,
    String? toolName,
    String? target,
    HarnessWorkProgress? progress,
    bool clearProgress = false,
  }) {
    final HarnessTaskSnapshot task = _registry.updateTask(
      key: key,
      phase: phase,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
      progress: progress,
      clearProgress: clearProgress,
    );
    _project(task);
    return task;
  }

  static HarnessTaskSnapshot finishTask({
    required HarnessTaskKey key,
    required HarnessWorkPhase phase,
    String? message,
    String? toolId,
    String? toolName,
    String? target,
    HarnessWorkProgress? progress,
  }) {
    final HarnessTaskSnapshot task = _registry.finishTask(
      key: key,
      phase: phase,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
      progress: progress,
    );
    _project(task);
    return task;
  }

  static void restoreAfterRestart(
    Iterable<HarnessTaskSnapshot> previousTasks, {
    int afterStreamSequence = 0,
  }) {
    _registry.restoreAfterRestart(
      previousTasks,
      afterStreamSequence: afterStreamSequence,
    );
    if (_registry.latest.tasks case <HarnessTaskSnapshot>[final task, ...]) {
      _project(task);
    }
  }

  static void publish({
    required HarnessWorkPhase phase,
    required String message,
    String toolId = '',
    String toolName = '',
    String target = '',
  }) {
    final HarnessTaskSnapshot task = _registry.publishCompatibility(
      phase: phase,
      message: message,
      toolId: toolId,
      toolName: toolName,
      target: target,
    );
    _project(task, legacyPhase: phase);
  }

  static void _project(
    HarnessTaskSnapshot task, {
    HarnessWorkPhase? legacyPhase,
  }) {
    _latest = HarnessWorkSnapshot(
      phase: legacyPhase ?? task.phase,
      message: task.message,
      updatedAt: task.updatedAt,
      toolId: task.toolId,
      toolName: task.toolName,
      target: task.target,
    );
    _changes.add(_latest);
    unawaited(HarnessRuntimeLogStore.appendWorkEvent(_latest.toJson()));
  }
}

HarnessWorkProgress? _sanitizeProgress(HarnessWorkProgress? progress) {
  if (progress == null) return null;
  final int total = progress.total < 0 ? 0 : progress.total;
  final int current = progress.current < 0 ? 0 : progress.current;
  return HarnessWorkProgress(
    current: total == 0 || current <= total ? current : total,
    total: total,
    unit: _publicText(progress.unit, 40, redactPaths: false),
  );
}

String _publicRef(String value, String prefix) {
  final String trimmed = value.trim();
  if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(trimmed) &&
      !RegExp(
        r'(password|secret|token|api[_-]?key|authorization)',
        caseSensitive: false,
      ).hasMatch(trimmed)) {
    return trimmed;
  }
  final String digest = sha256.convert(utf8.encode(trimmed)).toString();
  return '$prefix-${digest.substring(0, 24)}';
}

String _publicText(String value, int max, {bool redactPaths = true}) {
  String result = value
      .replaceAll(
        RegExp(
          r'(password|passwd|secret|token|api[_ -]?key|cookie)\s*[:=]\s*\S+',
          caseSensitive: false,
        ),
        r'$1=<hidden>',
      )
      .replaceAll(
        RegExp(r'authorization\s*:\s*(?:bearer\s+)?\S+', caseSensitive: false),
        'authorization: <hidden>',
      )
      .replaceAll(
        RegExp(
          r'--(?:password|token|api-key)(?:=|\s+)\S+',
          caseSensitive: false,
        ),
        '--credential=<hidden>',
      )
      .replaceAll(
        RegExp(r'https?://[^\s"\x27<>]+', caseSensitive: false),
        '<url>',
      );
  if (redactPaths) {
    result = result
        .replaceAll(
          RegExp(r'(?:[A-Za-z]:[\\/]|/)(?:[^\s"<>|]+[\\/]?)+'),
          '<path>',
        )
        .replaceAll(RegExp(r'(?:\.\.?[\\/])+(?:[^\s"<>|]+[\\/]?)+'), '<path>');
  }
  final String normalized = result.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  return normalized.length <= max
      ? normalized
      : '${normalized.substring(0, max)}…';
}
