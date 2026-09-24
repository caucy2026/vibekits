import 'harness_official_remote_adapter.dart';

/// Sends a remote command through the official DSH API, independently of the
/// currently rendered WebView composer and its DOM compatibility profile.
final class HarnessOfficialCommandDispatcher {
  const HarnessOfficialCommandDispatcher(this.adapter);

  final HarnessRemoteApiAdapter adapter;

  Future<void> prompt({
    required String sessionId,
    required String requestId,
    required String text,
  }) async {
    final response = await adapter.request(<String, dynamic>{
      'type': 'client-request',
      'rpcId': 'remote-prompt-$requestId',
      'method': 'session.prompt',
      'payload': <String, Object?>{
        'sessionId': sessionId,
        'requestId': requestId,
        'mode': 'queue',
        'text': text,
      },
    }, timeout: const Duration(milliseconds: 2500));
    final result = response['result'];
    if (result is! Map || result['ok'] != true) {
      throw StateError('HARNESS_PROMPT_REJECTED');
    }
  }
}

/// Tracks one remotely submitted prompt against official session-log events.
/// A completion from an earlier turn must never complete a newer queued prompt.
final class HarnessOfficialCommandProgress {
  HarnessOfficialCommandProgress(this.requestId);

  final String requestId;
  bool acceptedInHistory = false;
  int? turn;
  String state = 'accepted';

  void addRecords(List<dynamic> records) {
    for (final record in records) {
      if (record is! Map) continue;
      final envelope = record['event'];
      final event = envelope is Map ? envelope : record;
      final type = event['type'];
      final data = event['data'];
      if (data is! Map) continue;
      if (type == 'user/message' &&
          data['source'] is Map &&
          (data['source'] as Map)['rpcId'] == requestId) {
        acceptedInHistory = true;
        continue;
      }
      if (!acceptedInHistory) continue;
      final eventTurn = data['turn'];
      if (turn == null && eventTurn is int && type != 'turn/end') {
        turn = eventTurn;
      }
      if (turn == null || eventTurn != turn) continue;
      if (type == 'turn/end') {
        final reason = data['reason'];
        final kind = reason is Map ? reason['kind'] : null;
        state = kind == 'completed'
            ? 'completed'
            : kind == 'cancelled'
            ? 'stopped'
            : 'failed';
      } else if (type == 'tool/call') {
        state = 'tool_running';
      } else if (type == 'assistant/message' || type == 'step/start') {
        state = 'running';
      }
    }
  }
}
