import 'dart:async';
import 'dart:convert';

import 'harness_remote_commands.dart';
import 'harness_remote_connection.dart';
import 'harness_remote_execution.dart';

/// One authenticated controller. Work is not serialized behind a long prompt:
/// a cancel command can arrive while its prompt request is still outstanding.
class HarnessRemoteServerConnection {
  HarnessRemoteServerConnection({
    required this.channel,
    required this.execution,
    this.readState,
  }) {
    if (channel.authenticatedPeerId.isEmpty) {
      throw ArgumentError('Remote channel is not authenticated');
    }
    _subscription = channel.frames.listen(
      _receive,
      onError: (Object error) {
        unawaited(close());
      },
      onDone: () {
        unawaited(close());
      },
    );
  }
  final HarnessRemoteChannel channel;
  final HarnessRemoteExecution execution;
  final Future<Map<String, Object?>> Function(
    String peerId,
    Map<String, dynamic> request,
  )?
  readState;
  late final StreamSubscription<String> _subscription;
  final Set<String> _pending = {};
  Future<void> _outbound = Future<void>.value();
  bool _closed = false;
  final Completer<void> _done = Completer<void>();
  Future<void> get done => _done.future;

  void _receive(String raw) {
    if (_closed) return;
    try {
      if (utf8.encode(raw).length > 8 * 1024 * 1024) {
        throw const FormatException('Frame too large');
      }
      final frame = jsonDecode(raw);
      if (frame is! Map<String, dynamic> ||
          frame['protocol'] != 'vibekits.harness.remote' ||
          frame['version'] != 1 ||
          frame['type'] != 'request' ||
          frame['requestId'] is! String ||
          (frame['requestId'] as String).isEmpty ||
          frame['payload'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid remote request');
      }
      final id = frame['requestId'] as String;
      if (_pending.contains(id) || _pending.length >= 128) {
        // Duplicate wire IDs cannot be correlated safely. A retry must use a
        // new requestId while retaining the original execution commandId.
        throw const FormatException('Duplicate or excessive wire requests');
      }
      _pending.add(id);
      unawaited(_dispatch(id, frame['payload'] as Map<String, dynamic>));
    } catch (_) {
      unawaited(close());
    }
  }

  Future<void> _dispatch(String id, Map<String, dynamic> payload) async {
    Map<String, Object?> response;
    try {
      if (payload['kind'] == 'read-state' && readState != null) {
        response = await readState!(channel.authenticatedPeerId, payload);
      } else {
        for (final key in [
          'commandId',
          'workspaceId',
          'sessionId',
          'operation',
        ]) {
          if (payload[key] is! String) {
            throw const FormatException('Missing identity');
          }
        }
        if (payload['arguments'] is! Map<String, dynamic>) {
          throw const FormatException('Missing arguments');
        }
        final command = HarnessRemoteCommand(
          id: payload['commandId'] as String,
          workspaceId: payload['workspaceId'] as String,
          sessionId: payload['sessionId'] as String,
          operation: payload['operation'] as String,
          arguments: payload['arguments'] as Map<String, dynamic>,
        );
        final result = await execution.dispatch(
          channel.authenticatedPeerId,
          command,
        );
        response = {
          'ok': true,
          'commandId': command.id,
          'officialResponse': result,
        };
      }
    } on FormatException {
      response = {'ok': false, 'code': 'REMOTE_BAD_REQUEST'};
    } on StateError catch (error) {
      const safeCodes = {
        'REMOTE_PERMISSION_DENIED',
        'REMOTE_COMMAND_ID_CONFLICT',
        'REMOTE_COMMAND_LEDGER_FULL',
      };
      response = {
        'ok': false,
        'code': safeCodes.contains(error.message)
            ? error.message
            : 'REMOTE_OUTCOME_UNKNOWN',
      };
    } catch (_) {
      // Do not leak loopback URLs, file paths or provider credentials through
      // raw exceptions, and never invite blind replay of an ambiguous command.
      response = {'ok': false, 'code': 'REMOTE_OUTCOME_UNKNOWN'};
    }
    try {
      if (!_closed) {
        final frame = jsonEncode({
          'protocol': 'vibekits.harness.remote',
          'version': 1,
          'type': 'response',
          'requestId': id,
          'payload': response,
        });
        _outbound = _outbound.then((_) async {
          if (!_closed) await channel.send(frame);
        });
        await _outbound;
      }
    } catch (_) {
      await close();
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _subscription.cancel();
      await channel.close();
    } finally {
      if (!_done.isCompleted) _done.complete();
    }
    // A viewer disconnect is not a request to cancel tasks or destroy the
    // host execution ledger. The owner controls those lifetimes separately.
  }
}
