import 'dart:async';
import 'dart:math';

import 'harness_continuation_store.dart';
import 'harness_official_remote_adapter.dart';

typedef HarnessContinuationSummaryBuilder =
    Future<String> Function({
      required String workspaceId,
      required String sourceSessionId,
      required String sourceTitle,
      required String sourceMaterial,
    });

class HarnessContinuationCancelled implements Exception {
  const HarnessContinuationCancelled();
}

class HarnessContinuationCoordinator {
  HarnessContinuationCoordinator({
    required this.adapter,
    required this.store,
    this.summarizer,
    this.pollInterval = const Duration(milliseconds: 350),
    this.timeout = const Duration(seconds: 90),
  });

  final HarnessRemoteApiAdapter adapter;
  final HarnessContinuationStore store;
  final HarnessContinuationSummaryBuilder? summarizer;
  final Duration pollInterval;
  final Duration timeout;
  bool _cancelled = false;
  String? _activeSourceSessionId;

  Future<void> placeChild({
    required String workspaceId,
    required String childSessionId,
    String beforeSessionId = '',
  }) => _request('workspace.insertSessionBefore', <String, Object?>{
    'workspaceId': workspaceId,
    'sessionId': childSessionId,
    if (beforeSessionId.isNotEmpty) 'beforeSessionId': beforeSessionId,
  });

  Future<(String, String)> createEmptyChild({
    required String workspaceId,
    required String sourceTitle,
    String beforeSessionId = '',
    Future<void> Function(String sessionId, String title)? onCreated,
  }) async {
    final created = await _request('session.create', <String, Object?>{
      'workspaceId': workspaceId,
    });
    final childSessionId = _value(created)['sessionId']?.toString();
    if (childSessionId == null || childSessionId.isEmpty) {
      throw const FormatException('Harness 未返回派生会话 ID');
    }
    await placeChild(
      workspaceId: workspaceId,
      childSessionId: childSessionId,
      beforeSessionId: beforeSessionId,
    );
    final baseTitle = sourceTitle.trim().isEmpty ? '未命名会话' : sourceTitle.trim();
    final existing = await store.childrenFor(workspaceId, beforeSessionId);
    final childTitle = '$baseTitle ${existing.length + 2}';
    final renamed = _value(
      await _request('session.rename', <String, Object?>{
        'sessionId': childSessionId,
        'title': childTitle,
      }),
    );
    if (renamed['title']?.toString() != childTitle || renamed['seq'] is! int) {
      throw const FormatException('Harness 未永久保存派生会话名称');
    }
    await onCreated?.call(childSessionId, childTitle);
    await _verifyChildPersisted(
      workspaceId: workspaceId,
      childSessionId: childSessionId,
      childTitle: childTitle,
    );
    return (childSessionId, childTitle);
  }

  Future<(String, String)> prepareExistingChild({
    required String workspaceId,
    required String childSessionId,
    required String sourceTitle,
    required String sourceSessionId,
  }) async {
    await placeChild(
      workspaceId: workspaceId,
      childSessionId: childSessionId,
      beforeSessionId: sourceSessionId,
    );
    final baseTitle = sourceTitle.trim().isEmpty ? '未命名会话' : sourceTitle.trim();
    final existing = await store.childrenFor(workspaceId, sourceSessionId);
    final childTitle = '$baseTitle ${existing.length + 2}';
    final renamed = _value(
      await _request('session.rename', <String, Object?>{
        'sessionId': childSessionId,
        'title': childTitle,
      }),
    );
    if (renamed['title']?.toString() != childTitle || renamed['seq'] is! int) {
      throw const FormatException('Harness 未永久保存派生会话名称');
    }
    await _verifyChildPersisted(
      workspaceId: workspaceId,
      childSessionId: childSessionId,
      childTitle: childTitle,
    );
    return (childSessionId, childTitle);
  }

  Future<void> _verifyChildPersisted({
    required String workspaceId,
    required String childSessionId,
    required String childTitle,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      _throwIfCancelled();
      final workspaces = await adapter.workspaceSnapshot();
      final attached = workspaces.any(
        (workspace) =>
            workspace['workspaceId'] == workspaceId &&
            workspace['sessionIds'] is List &&
            (workspace['sessionIds'] as List).contains(childSessionId),
      );
      final snapshot = _value(await _history(childSessionId, 0));
      if (attached && snapshot['sessionId'] == childSessionId) return;
      await Future<void>.delayed(pollInterval);
    }
    throw TimeoutException('派生会话没有永久保存到官方 Harness', timeout);
  }

  Future<HarnessContinuationRecord> completeChild({
    required String childSessionId,
    required String workspace,
    required String sourceSessionId,
    required String sourceTitle,
    String continuationTitle = '',
    void Function(String status)? onProgress,
  }) async {
    _cancelled = false;
    _activeSourceSessionId = sourceSessionId;
    try {
      _throwIfCancelled();
      onProgress?.call('正在读取来源会话');
      final before = await _history(sourceSessionId, 0);
      final int cursor = _cursor(before);
      _throwIfCancelled();

      onProgress?.call('正在生成交接摘要');
      final sourceMaterial = _buildSummary(before);
      final String summary = summarizer == null
          ? sourceMaterial
          : await summarizer!(
              workspaceId: workspace,
              sourceSessionId: sourceSessionId,
              sourceTitle: sourceTitle,
              sourceMaterial: sourceMaterial,
            );
      _validateSummary(summary);
      _throwIfCancelled();

      final now = DateTime.now().toUtc();
      final record = HarnessContinuationRecord(
        id: _id(),
        workspace: workspace,
        sourceSessionId: sourceSessionId,
        continuationSessionId: childSessionId,
        sourceTitleSnapshot: sourceTitle.trim().isEmpty
            ? '未命名会话'
            : sourceTitle.trim(),
        continuationTitleSnapshot: continuationTitle.trim(),
        summary: summary,
        sourceMessageCursor: '$cursor',
        createdAt: now,
        updatedAt: now,
      );
      onProgress?.call('正在保存来源关系');
      await store.upsert(record);
      onProgress?.call('整理完成');
      return record;
    } finally {
      _activeSourceSessionId = null;
    }
  }

  static const List<String> requiredSections = <String>[
    '目标',
    '约束',
    '已完成',
    '关键决定',
    '文件与版本',
    '验证结果',
    '未完成项',
    '已知问题',
    '下一步',
  ];

  Future<HarnessContinuationRecord> create({
    required String workspace,
    required String workspaceId,
    required String sourceSessionId,
    required String sourceTitle,
    void Function(String status)? onProgress,
    void Function(String sessionId, String title)? onChildCreated,
  }) async {
    _cancelled = false;
    _activeSourceSessionId = sourceSessionId;
    String? childSessionId;
    try {
      onProgress?.call('正在创建派生会话');
      final child = await createEmptyChild(
        workspaceId: workspaceId,
        sourceTitle: sourceTitle,
        beforeSessionId: sourceSessionId,
      );
      childSessionId = child.$1;
      final childTitle = child.$2;
      onChildCreated?.call(childSessionId, childTitle);
      try {
        return await completeChild(
          childSessionId: childSessionId,
          workspace: workspace,
          sourceSessionId: sourceSessionId,
          sourceTitle: sourceTitle,
          continuationTitle: childTitle,
          onProgress: onProgress,
        );
      } on Object {
        await _deleteEmptyChild(childSessionId);
        rethrow;
      }
    } on HarnessContinuationCancelled {
      if (childSessionId != null) await _deleteEmptyChild(childSessionId);
      rethrow;
    } finally {
      _activeSourceSessionId = null;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    final source = _activeSourceSessionId;
    if (source == null) return;
    try {
      await _request('session.cancel', <String, Object?>{'sessionId': source});
    } on Object {
      // Local cancellation remains authoritative if Harness has already ended.
    }
  }

  static String _buildSummary(Map<String, dynamic> response) {
    final value = _value(response);
    final records = value['records'];
    final excerpts = <String>[];
    if (records is List) {
      for (final record in records.reversed) {
        if (record is! Map) continue;
        final event = record['event'] is Map ? record['event'] as Map : record;
        final type = '${event['type'] ?? ''}';
        if (type != 'user/message' && type != 'assistant/message') continue;
        final text = _redact(_strings(event['data']).join('\n')).trim();
        if (text.isEmpty) continue;
        excerpts.add(text.length > 1800 ? '${text.substring(0, 1800)}…' : text);
        if (excerpts.length >= 8) break;
      }
    }
    final recent = excerpts.reversed.join('\n\n');
    final bounded = recent.length > 16000
        ? recent.substring(recent.length - 16000)
        : recent;
    final context = bounded.isEmpty ? '来源会话暂无可提取的对话正文。' : bounded;
    return '''目标：继续完成来源会话中的当前任务。
约束：沿用来源会话已确认的用户要求与项目约定；需要细节时查询来源会话。
已完成：已读取并压缩来源会话最近的用户与助手消息。
关键决定：派生会话不复制聊天记录，通过持久化来源关系继续工作。
文件与版本：从来源会话按需查询，以当前工作区实际文件为准。
验证结果：已建立可追溯的来源游标 ${value['cursor'] ?? 0}。
未完成项：根据下方压缩上下文继续处理尚未完成的要求。
已知问题：压缩摘要可能省略细节，可使用“查阅来源会话”补充。
下一步：先读取压缩上下文，再从最后一项未完成工作继续。

压缩上下文：
$context''';
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
      );

  Future<Map<String, dynamic>> _history(String sessionId, int cursor) =>
      _request('session.history', <String, Object?>{
        'sessionId': sessionId,
        'cursor': cursor,
      });

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, Object?> payload,
  ) {
    final requestTimeout = timeout > const Duration(seconds: 15)
        ? const Duration(seconds: 15)
        : timeout;
    return adapter.request(<String, dynamic>{
      'type': 'client-request',
      'rpcId': _id(),
      'method': method,
      'payload': payload,
    }, timeout: requestTimeout);
  }

  Future<void> _deleteEmptyChild(String sessionId) async {
    try {
      await _request('session.delete', <String, Object?>{
        'sessionId': sessionId,
      });
    } on Object {
      // The caller reports the original atomic-save failure. An orphan remains
      // visible in official Harness if its own delete endpoint also fails.
    }
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const HarnessContinuationCancelled();
  }

  static Map _value(Map<String, dynamic> response) {
    final result = response['result'];
    if (result is! Map || result['ok'] != true || result['value'] is! Map) {
      throw const FormatException('Harness 返回结果无效');
    }
    return result['value'] as Map;
  }

  static int _cursor(Map<String, dynamic> response) {
    final value = _value(response);
    final cursor = value['cursor'];
    return cursor is int ? cursor : int.tryParse('$cursor') ?? 0;
  }

  static Iterable<String> _strings(Object? value) sync* {
    if (value is String) {
      if (value.trim().isNotEmpty) {
        yield value;
      }
    } else if (value is Iterable) {
      for (final item in value) {
        yield* _strings(item);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        final key = '${entry.key}'.toLowerCase();
        if (<String>{
          'token',
          'apikey',
          'authorization',
          'cookie',
        }.contains(key)) {
          continue;
        }
        yield* _strings(entry.value);
      }
    }
  }

  static void _validateSummary(String summary) {
    final missing = requiredSections.where(
      (section) => !summary.contains(section),
    );
    if (summary.isEmpty ||
        summary.length > HarnessContinuationStore.maxSummaryCharacters ||
        missing.isNotEmpty) {
      throw FormatException('Harness 交接摘要结构无效：缺少 ${missing.join('、')}');
    }
  }

  static String _id() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${random.nextInt(1 << 32).toRadixString(36)}';
  }
}
