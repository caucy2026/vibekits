import 'dart:async';
import 'dart:convert';

/// Identity comes from the authenticated transport, never the command payload.
class HarnessRemoteCommand {
  HarnessRemoteCommand({
    required this.id,
    required this.workspaceId,
    required this.sessionId,
    required this.operation,
    required Map<String, Object?> arguments,
  }) : argumentsJson = jsonEncode(_canonical(arguments)) {
    if ([id, workspaceId, sessionId, operation].any((v) => v.isEmpty)) {
      throw const FormatException('Missing remote command identity');
    }
    if (utf8.encode(argumentsJson).length > 65536) {
      throw const FormatException('Remote command exceeds 64 KiB');
    }
  }

  final String id;
  final String workspaceId;
  final String sessionId;
  final String operation;
  final String argumentsJson;
  Map<String, dynamic> get arguments =>
      jsonDecode(argumentsJson) as Map<String, dynamic>;
  String get fingerprint =>
      jsonEncode([workspaceId, sessionId, operation, argumentsJson]);

  static Object? _canonical(Object? value) {
    if (value is Map<String, Object?>) {
      return {
        for (final key in value.keys.toList()..sort())
          key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}

typedef HarnessRemoteAuthorizer =
    Future<bool> Function(String peerId, HarnessRemoteCommand command);
typedef HarnessRemoteExecutor =
    Future<Map<String, Object?>> Function(HarnessRemoteCommand command);

/// Per-authority-epoch dispatch gate. Production reconnect/restart guarantees
/// additionally require a durable command ledger before binding a transport.
/// Entries are never evicted silently: full capacity rejects new work.
class HarnessRemoteCommandGate {
  HarnessRemoteCommandGate({
    required this.authorize,
    required this.execute,
    this.executeClaimed,
    this.capacity = 4096,
  }) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
  }

  final HarnessRemoteAuthorizer authorize;
  final HarnessRemoteExecutor execute;
  final Future<Map<String, dynamic>> Function(
    String peerId,
    HarnessRemoteCommand command,
    Future<Map<String, Object?>> Function() action,
  )?
  executeClaimed;
  final int capacity;
  final Map<(String, String), (String, Future<String>)> _commands = {};

  Future<Map<String, dynamic>> dispatch(
    String authenticatedPeerId,
    HarnessRemoteCommand command,
  ) async {
    if (authenticatedPeerId.isEmpty ||
        !await authorize(authenticatedPeerId, command)) {
      throw StateError('REMOTE_PERMISSION_DENIED');
    }
    final key = (authenticatedPeerId, command.id);
    final existing = _commands[key];
    if (existing != null) {
      if (existing.$1 != command.fingerprint) {
        throw StateError('REMOTE_COMMAND_ID_CONFLICT');
      }
      return jsonDecode(await existing.$2) as Map<String, dynamic>;
    }
    if (_commands.length >= capacity) {
      throw StateError('REMOTE_COMMAND_LEDGER_FULL');
    }
    final completion = Completer<String>();
    // Claim synchronously before invoking any user code, including reentrancy.
    _commands[key] = (command.fingerprint, completion.future);
    unawaited(_run(authenticatedPeerId, command, completion));
    return jsonDecode(await completion.future) as Map<String, dynamic>;
  }

  Future<void> _run(
    String peerId,
    HarnessRemoteCommand command,
    Completer<String> completion,
  ) async {
    try {
      final claim = executeClaimed;
      completion.complete(
        jsonEncode(
          claim == null
              ? await execute(command)
              : await claim(peerId, command, () => execute(command)),
        ),
      );
    } catch (error, stack) {
      completion.completeError(error, stack);
    }
  }
}
