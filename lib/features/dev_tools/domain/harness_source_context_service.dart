import 'dart:async';

import 'harness_continuation_store.dart';

typedef HarnessSourceHistoryLoader =
    Future<Map<String, Object?>> Function(String sessionId, int afterCursor);

class HarnessSourceContextService {
  HarnessSourceContextService({
    required this.store,
    required this.historyLoader,
  });

  static const int maxLimit = 20;
  static const int maxCharacters = 24000;

  final HarnessContinuationStore store;
  final HarnessSourceHistoryLoader historyLoader;

  Future<Map<String, Object?>> query({
    required String workspace,
    required String continuationSessionId,
    String query = '',
    int afterCursor = 0,
    int? beforeCursor,
    int limit = 8,
  }) async {
    final relation = await store.sourceFor(workspace, continuationSessionId);
    if (relation == null) throw StateError('HARNESS_SOURCE_NOT_LINKED');
    final snapshot = await historyLoader(
      relation.sourceSessionId,
      afterCursor.clamp(0, 1 << 62).toInt(),
    );
    final rawRecords = snapshot['records'];
    if (rawRecords is! List) {
      throw const FormatException('Invalid source history');
    }
    final needle = query.trim().toLowerCase();
    final boundedLimit = limit.clamp(1, maxLimit).toInt();
    final matches = <Map<String, Object?>>[];
    var totalCharacters = 0;
    for (final raw in rawRecords.reversed) {
      if (raw is! Map) continue;
      final event = raw['event'] is Map ? raw['event'] as Map : raw;
      if (!const {'user/message', 'assistant/message'}.contains(event['type'])) continue;
      final seq = event['seq'];
      if (seq is int && seq <= afterCursor) continue;
      if (seq is int && beforeCursor != null && seq >= beforeCursor) continue;
      final text = _redact(_flatten(event['data']));
      if (text.isEmpty ||
          (needle.isNotEmpty && !text.toLowerCase().contains(needle))) {
        continue;
      }
      final remaining = maxCharacters - totalCharacters;
      if (remaining <= 0) break;
      final clipped = text.length <= remaining
          ? text
          : text.substring(0, remaining);
      matches.add(<String, Object?>{'cursor': seq ?? 0, 'text': clipped});
      totalCharacters += clipped.length;
      if (matches.length >= boundedLimit) break;
    }
    return <String, Object?>{
      'sourceSessionId': relation.sourceSessionId,
      'sourceTitle': relation.sourceTitleSnapshot,
      'summary': relation.summary,
      'records': matches.reversed.toList(growable: false),
      'cursor': snapshot['cursor'] ?? relation.sourceMessageCursor,
    };
  }

  static String _flatten(Object? value) {
    if (value is String) return value.trim();
    if (value is List) {
      return value.map(_flatten).where((e) => e.isNotEmpty).join('\n');
    }
    if (value is Map) {
      return value.entries
          .where(
            (entry) => !const {
              'token',
              'apiKey',
              'authorization',
              'cookie',
            }.contains('${entry.key}'),
          )
          .map((entry) => _flatten(entry.value))
          .where((entry) => entry.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  static String _redact(String value) => value
      .replaceAll(
        RegExp(r'bearer\s+[a-z0-9._~+/-]+=*', caseSensitive: false),
        '[REDACTED]',
      )
      .replaceAll(
        RegExp(
          r'(api[_-]?key|token|password)\s*[:=]\s*\S+',
          caseSensitive: false,
        ),
        r'$1=[REDACTED]',
      )
      .trim();
}

typedef HarnessSourceContextQuery =
    Future<Map<String, Object?>> Function(
      String continuationSessionId,
      String query,
      int afterCursor,
      int? beforeCursor,
      int limit,
    );

class HarnessSourceContextBroker {
  HarnessSourceContextBroker._();

  static final HarnessSourceContextBroker instance =
      HarnessSourceContextBroker._();
  HarnessSourceContextQuery? _query;

  void register(HarnessSourceContextQuery query) => _query = query;

  void unregister(HarnessSourceContextQuery query) {
    if (identical(_query, query)) _query = null;
  }

  Future<Map<String, Object?>> query(
    String continuationSessionId,
    String query,
    int afterCursor,
    int? beforeCursor,
    int limit,
  ) {
    final handler = _query;
    if (handler == null) throw StateError('HARNESS_SOURCE_UNAVAILABLE');
    return handler(
      continuationSessionId,
      query,
      afterCursor,
      beforeCursor,
      limit,
    );
  }
}
