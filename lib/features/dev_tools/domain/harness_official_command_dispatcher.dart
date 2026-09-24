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
