import 'dart:math';

import 'harness_remote_connection.dart';

/// Remote UI action adapter. Caller-owned draft stays local; submitted content
/// and all task state remain authoritative on the execution host.
class HarnessRemoteWorkspaceClient {
  HarnessRemoteWorkspaceClient(this.connection);
  final HarnessRemoteConnection connection;
  final Random _random = Random.secure();

  String newCommandId() => List.generate(
    24,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<Map<String, dynamic>> readState({String? epoch, int? sequence}) =>
      connection.request(newCommandId(), {
        'kind': 'read-state',
        if (epoch != null && sequence != null) ...{
          'epoch': epoch,
          'sequence': sequence,
        },
      });

  Future<Map<String, dynamic>> call({
    required String commandId,
    required String workspaceId,
    required String sessionId,
    required String method,
    required Map<String, Object?> payload,
  }) async {
    if (payload.containsKey('sessionId') && payload['sessionId'] != sessionId) {
      throw ArgumentError('Remote session scope mismatch');
    }
    final receipt = await connection.request(newCommandId(), {
      'commandId': commandId,
      'workspaceId': workspaceId,
      'sessionId': sessionId,
      'operation': method,
      'arguments': {...payload, 'sessionId': sessionId},
    });
    if (receipt['ok'] != true) {
      throw HarnessRemoteActionException(
        receipt['code'] is String
            ? receipt['code'] as String
            : 'REMOTE_BAD_RESPONSE',
        commandId,
      );
    }
    if (receipt['commandId'] != commandId ||
        receipt['officialResponse'] is! Map<String, dynamic>) {
      throw const FormatException('Remote command receipt mismatch');
    }
    return receipt['officialResponse'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancel({
    required String commandId,
    required String workspaceId,
    required String sessionId,
  }) => call(
    commandId: commandId,
    workspaceId: workspaceId,
    sessionId: sessionId,
    method: 'session.cancel',
    payload: const {},
  );
}

class HarnessRemoteActionException implements Exception {
  const HarnessRemoteActionException(this.code, this.commandId);
  final String code;
  final String commandId;
  @override
  String toString() => 'HarnessRemoteActionException($code, $commandId)';
}
