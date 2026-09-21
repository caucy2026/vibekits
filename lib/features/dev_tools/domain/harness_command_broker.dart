import 'dart:async';

typedef HarnessPromptHandler =
    Future<Map<String, Object?>> Function(String text, String requestId);
typedef HarnessSessionHandler =
    Future<Map<String, Object?>> Function(String sessionId);
typedef HarnessHistoryHandler =
    Future<Map<String, Object?>> Function(String sessionId, int cursor);

final class HarnessCommandRegistration {
  HarnessCommandRegistration._(this._broker, this._generation);

  final HarnessCommandBroker _broker;
  final int _generation;

  void unregister() => _broker._unregister(_generation);
}

final class HarnessCommandBroker {
  HarnessCommandBroker._();

  static final HarnessCommandBroker instance = HarnessCommandBroker._();

  int _generation = 0;
  HarnessPromptHandler? _prompt;
  HarnessSessionHandler? _status;
  HarnessHistoryHandler? _history;
  HarnessSessionHandler? _cancel;
  Stream<Map<String, Object?>>? _changes;

  HarnessCommandRegistration register({
    required HarnessPromptHandler prompt,
    required HarnessSessionHandler status,
    required HarnessHistoryHandler history,
    required HarnessSessionHandler cancel,
    required Stream<Map<String, Object?>> changes,
  }) {
    final generation = ++_generation;
    _prompt = prompt;
    _status = status;
    _history = history;
    _cancel = cancel;
    _changes = changes;
    return HarnessCommandRegistration._(this, generation);
  }

  void _unregister(int generation) {
    if (generation != _generation) return;
    _generation++;
    _prompt = null;
    _status = null;
    _history = null;
    _cancel = null;
    _changes = null;
  }

  Future<Map<String, Object?>> prompt(String text, {String? requestId}) async {
    final value = text.trim();
    if (value.isEmpty) throw const FormatException('text must not be empty');
    final handler = _prompt;
    if (handler == null) throw StateError('HARNESS_WORKSPACE_UNAVAILABLE');
    final id = requestId?.trim().isNotEmpty == true
        ? requestId!.trim()
        : '${DateTime.now().microsecondsSinceEpoch}-$_generation';
    return handler(value, id).timeout(const Duration(seconds: 3));
  }

  Future<Map<String, Object?>> status(String sessionId) =>
      _requireSession(_status, sessionId).timeout(const Duration(seconds: 3));

  Future<Map<String, Object?>> history(String sessionId, int cursor) {
    final handler = _history;
    if (handler == null) throw StateError('HARNESS_WORKSPACE_UNAVAILABLE');
    return handler(
      _sessionId(sessionId),
      cursor,
    ).timeout(const Duration(seconds: 3));
  }

  Future<Map<String, Object?>> cancel(String sessionId) =>
      _requireSession(_cancel, sessionId).timeout(const Duration(seconds: 3));

  Future<Map<String, Object?>> waitForChange(
    String sessionId,
    int afterCursor,
    Duration timeout,
  ) async {
    final changes = _changes;
    if (changes == null) throw StateError('HARNESS_WORKSPACE_UNAVAILABLE');
    final id = _sessionId(sessionId);
    try {
      final event = await changes
          .firstWhere(
            (item) =>
                item['sessionId'] == id &&
                (item['cursor'] is int) &&
                (item['cursor'] as int) > afterCursor,
          )
          .timeout(timeout);
      return <String, Object?>{'changed': true, ...event};
    } on TimeoutException {
      return <String, Object?>{
        'changed': false,
        'sessionId': id,
        'cursor': afterCursor,
      };
    }
  }

  Future<Map<String, Object?>> _requireSession(
    HarnessSessionHandler? handler,
    String sessionId,
  ) {
    if (handler == null) throw StateError('HARNESS_WORKSPACE_UNAVAILABLE');
    return handler(_sessionId(sessionId));
  }

  String _sessionId(String value) {
    final id = value.trim();
    if (id.isEmpty) throw const FormatException('sessionId must not be empty');
    return id;
  }
}
