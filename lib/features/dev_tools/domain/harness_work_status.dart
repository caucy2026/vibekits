import 'dart:async';

enum HarnessWorkPhase {
  idle,
  starting,
  ready,
  runningTool,
  waitingApproval,
  failed,
  stopped,
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

  bool get busy =>
      phase == HarnessWorkPhase.starting ||
      phase == HarnessWorkPhase.runningTool ||
      phase == HarnessWorkPhase.waitingApproval;

  Map<String, Object?> toJson() => <String, Object?>{
    'phase': phase.name,
    'message': message,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (toolId.isNotEmpty) 'toolId': toolId,
    if (toolName.isNotEmpty) 'toolName': toolName,
    if (target.isNotEmpty) 'target': target,
  };
}

/// Single process-wide projection of work that is safe to show remotely.
///
/// It intentionally excludes prompts, model responses, file contents,
/// credentials and full command arguments. Consumers only receive the current
/// phase and a bounded, user-readable target summary.
abstract final class HarnessWorkStatusHub {
  static final StreamController<HarnessWorkSnapshot> _changes =
      StreamController<HarnessWorkSnapshot>.broadcast(sync: true);
  static HarnessWorkSnapshot _latest = HarnessWorkSnapshot.idle();

  static HarnessWorkSnapshot get latest => _latest;
  static Stream<HarnessWorkSnapshot> get changes => _changes.stream;

  static void publish({
    required HarnessWorkPhase phase,
    required String message,
    String toolId = '',
    String toolName = '',
    String target = '',
  }) {
    _latest = HarnessWorkSnapshot(
      phase: phase,
      message: _bounded(message, 240),
      updatedAt: DateTime.now(),
      toolId: _bounded(toolId, 200),
      toolName: _bounded(toolName, 120),
      target: _redactTarget(_bounded(target, 300)),
    );
    _changes.add(_latest);
  }

  static String _redactTarget(String value) => value
      .replaceAll(
        RegExp(
          r'(password|secret|token|api[_ -]?key)\s*[:=]\s*\S+',
          caseSensitive: false,
        ),
        r'$1=<hidden>',
      )
      .replaceAll(
        RegExp(r'authorization:\s*\S+', caseSensitive: false),
        'authorization: <hidden>',
      );

  static String _bounded(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
