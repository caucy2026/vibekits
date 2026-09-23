import 'dart:async';

import 'harness_official_remote_adapter.dart';

class HarnessContinuationSummarizer {
  HarnessContinuationSummarizer({
    required this.adapter,
    this.timeout = const Duration(seconds: 90),
    this.pollInterval = const Duration(milliseconds: 350),
  });

  final HarnessRemoteApiAdapter adapter;
  final Duration timeout;
  final Duration pollInterval;

  Future<String> summarize({
    required String workspaceId,
    required String sourceSessionId,
    required String sourceTitle,
    required String sourceMaterial,
  }) async {
    String helperSessionId = '';
    try {
      final created = await _request('session.create', <String, Object?>{
        'workspaceId': workspaceId,
      });
      helperSessionId = _value(created)['sessionId']?.toString() ?? '';
      if (helperSessionId.isEmpty) {
        throw const FormatException('Harness 未创建摘要任务');
      }
      // Official DSH has no session.delete RPC. Hide this internal helper
      // through the supported archive API before it receives any messages.
      _value(
        await _request('workspace.archiveSession', <String, Object?>{
          'sessionId': helperSessionId,
        }),
      );
      final requestId =
          'continuation-summary-${DateTime.now().microsecondsSinceEpoch}';
      await _request('session.prompt', <String, Object?>{
        'sessionId': helperSessionId,
        'requestId': requestId,
        'mode': 'queue',
        'text':
            '''你正在为一个长期开发任务生成一次性的交接摘要。不要调用工具，不要执行任务，只整理下面的来源资料。输出必须简洁、具体，并且完整保留以下九个中文标题：目标、约束、已完成、关键决定、文件与版本、验证结果、未完成项、已知问题、下一步。不得复制聊天时间线，不得编造资料中不存在的结论。来源会话标题：$sourceTitle
来源会话编号：$sourceSessionId

$sourceMaterial''',
      }, requestTimeout: const Duration(seconds: 10));
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final history = _value(
          await _request('session.history', <String, Object?>{
            'sessionId': helperSessionId,
            'cursor': 0,
          }),
        );
        final records = history['records'];
        if (records is List) {
          for (final raw in records.reversed) {
            if (raw is! Map) continue;
            final event = raw['event'] is Map ? raw['event'] as Map : raw;
            if (event['type'] != 'assistant/message') continue;
            final text = _assistantText(event['data']);
            if (text.isNotEmpty) return text;
          }
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException('Harness 生成交接摘要超时', timeout);
    } finally {
      if (helperSessionId.isNotEmpty) {
        try {
          await _request('workspace.archiveSession', <String, Object?>{
            'sessionId': helperSessionId,
          });
        } on Object {
          // Preserve the original outcome; the helper was archived before work.
        }
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, Object?> payload, {
    Duration requestTimeout = const Duration(seconds: 30),
  }) => adapter.request(<String, dynamic>{
    'type': 'client-request',
    'rpcId': 'continuation-summary-${DateTime.now().microsecondsSinceEpoch}',
    'method': method,
    'payload': payload,
  }, timeout: requestTimeout);

  static Map _value(Map<String, dynamic> response) {
    final result = response['result'];
    if (result is! Map || result['ok'] != true || result['value'] is! Map) {
      throw const FormatException('Harness 摘要任务返回结果无效');
    }
    return result['value'] as Map;
  }

  static String _flatten(Object? value) {
    if (value is String) return value;
    if (value is Iterable) {
      return value.map(_flatten).where((text) => text.isNotEmpty).join('\n');
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
          .where((text) => text.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  static String _assistantText(Object? value) {
    const headings = <String>[
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
    final leaves = <String>[];
    void collect(Object? node) {
      if (node is String && node.trim().isNotEmpty) {
        leaves.add(node.trim());
      } else if (node is Iterable) {
        for (final item in node) {
          collect(item);
        }
      } else if (node is Map) {
        for (final entry in node.entries) {
          if (!const {
            'token',
            'apiKey',
            'authorization',
            'cookie',
          }.contains('${entry.key}')) {
            collect(entry.value);
          }
        }
      }
    }

    collect(value);
    final structured =
        leaves.where((text) => headings.every(text.contains)).toList()
          ..sort((left, right) => left.length.compareTo(right.length));
    final selected = structured.isNotEmpty ? structured.first : _flatten(value);
    return selected.length <= 24000 ? selected : selected.substring(0, 24000);
  }
}
