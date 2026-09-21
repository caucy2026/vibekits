import 'harness_official_remote_adapter.dart';

class HarnessContinuationSource {
  const HarnessContinuationSource({
    required this.workspaceId,
    required this.sessionId,
    required this.title,
  });

  final String workspaceId;
  final String sessionId;
  final String title;
}

/// Resolves the selected official Harness row without relying on private DOM
/// attributes. Some DSH builds expose only a title in the session tree.
class HarnessContinuationSourceResolver {
  HarnessContinuationSourceResolver(this.adapter);

  final HarnessRemoteApiAdapter adapter;

  Future<HarnessContinuationSource> resolve({
    String requestedSessionId = '',
    String requestedTitle = '',
  }) async {
    final workspaces = await adapter.workspaceSnapshot();
    final requestedId = requestedSessionId.trim();
    final title = _normaliseTitle(requestedTitle);
    final candidates = <(String, String)>[];
    for (final workspace in workspaces) {
      final workspaceId = workspace['workspaceId']?.toString().trim() ?? '';
      final sessionIds = workspace['sessionIds'];
      if (workspaceId.isEmpty || sessionIds is! List) continue;
      for (final rawId in sessionIds) {
        final sessionId = rawId.toString().trim();
        if (sessionId.isEmpty) continue;
        if (requestedId == sessionId) {
          return HarnessContinuationSource(
            workspaceId: workspaceId,
            sessionId: sessionId,
            title: title.isEmpty ? '未命名会话' : title,
          );
        }
        candidates.add((workspaceId, sessionId));
      }
    }
    if (title.isEmpty) throw const FormatException('无法识别当前 Harness 会话');
    final resolved = await Future.wait(
      candidates.reversed.map((candidate) async {
        try {
          final response = await adapter.request(<String, dynamic>{
            'type': 'client-request',
            'rpcId': 'resolve-${candidate.$2}',
            'method': 'session.history',
            'payload': <String, Object?>{
              'sessionId': candidate.$2,
              'cursor': 0,
            },
          }, timeout: const Duration(seconds: 5));
          final result = response['result'];
          final value = result is Map ? result['value'] : null;
          final projections = value is Map ? value['projections'] : null;
          final projectionValues = projections is Map
              ? projections['values']
              : null;
          final candidateTitle = projectionValues is Map
              ? _normaliseTitle(projectionValues['title']?.toString() ?? '')
              : '';
          return candidateTitle == title
              ? HarnessContinuationSource(
                  workspaceId: candidate.$1,
                  sessionId: candidate.$2,
                  title: candidateTitle,
                )
              : null;
        } on Object {
          return null;
        }
      }),
    );
    for (final source in resolved) {
      if (source != null) return source;
    }
    throw FormatException('未找到会话：《$title》');
  }

  static String _normaliseTitle(String value) => value
      .replaceFirst(RegExp(r'\s*(刚刚|\d+\s*(秒|分钟|小时|天|周|个月|月|年)(前)?)$'), '')
      .trim();
}
