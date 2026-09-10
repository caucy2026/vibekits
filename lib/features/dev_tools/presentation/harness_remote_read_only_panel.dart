import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/harness_remote_view_model.dart';
import '../domain/harness_remote_workspace_client.dart';

/// Read-only projection used while the native direct/relay carrier is being
/// established. It deliberately renders authoritative remote rows instead of
/// cloning a second conversation model or pretending stale data is live.
class HarnessRemoteReadOnlyPanel extends StatelessWidget {
  const HarnessRemoteReadOnlyPanel({
    super.key,
    required this.peerRoutingId,
    required this.model,
    required this.onDisconnect,
    this.onReconnect,
  });

  final String peerRoutingId;
  final HarnessRemoteViewModel model;
  final VoidCallback onDisconnect;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (BuildContext context, _) {
      final bool stale = model.stale;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: stale
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    stale ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '远程 Harness · $peerRoutingId',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          stale
                              ? model.error ?? '连接中断，以下为最后一次同步记录'
                              : '只读项目状态已同步${_latency(model.roundTrip)}',
                        ),
                      ],
                    ),
                  ),
                  if (stale && onReconnect != null)
                    IconButton(
                      key: const Key('harness-remote-reconnect'),
                      tooltip: '重新连接并重新同步',
                      onPressed: onReconnect,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  IconButton(
                    key: const Key('harness-remote-disconnect'),
                    tooltip: '断开远程连接（不停止远端任务）',
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.link_off_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (model.workspaces.isEmpty)
            const Expanded(child: Center(child: Text('正在同步远端项目与会话…')))
          else
            Expanded(
              child: ListView.separated(
                key: const Key('harness-remote-project-list'),
                itemCount: model.workspaces.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final Map<String, dynamic> workspace =
                      model.workspaces[index];
                  final String id = workspace['workspaceId']?.toString() ?? '';
                  final String title =
                      workspace['title']?.toString().trim().isNotEmpty == true
                      ? workspace['title'].toString()
                      : id;
                  final List<dynamic> sessions = workspace['sessionIds'] is List
                      ? workspace['sessionIds'] as List<dynamic>
                      : const <dynamic>[];
                  final String phase =
                      workspace['phase']?.toString().toLowerCase() ?? 'ready';
                  final bool busy = const <String>{
                    'busy',
                    'reasoning',
                    'toolrunning',
                    'waitingapproval',
                  }.contains(phase);
                  return ListTile(
                    key: Key('harness-remote-project-$id'),
                    leading: Icon(
                      busy ? Icons.sync_rounded : Icons.circle,
                      size: busy ? 22 : 12,
                      color: busy
                          ? const Color(0xFF16845B)
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(title),
                    subtitle: Text('$id · ${sessions.length} 个会话'),
                    trailing: Text(phase.toUpperCase()),
                  );
                },
              ),
            ),
        ],
      );
    },
  );

  static String _latency(Duration? value) =>
      value == null ? '' : ' · ${value.inMilliseconds} ms';
}

/// Minimal but complete remote action surface. It never mirrors drafts to the
/// execution host; only an explicit Send creates a durable commandId. Stop is
/// sent independently so it remains available while a prompt call is pending.
class HarnessRemoteCommandPanel extends StatefulWidget {
  const HarnessRemoteCommandPanel({
    super.key,
    required this.model,
    required this.client,
    required this.allowedOperations,
  });

  final HarnessRemoteViewModel model;
  final HarnessRemoteWorkspaceClient client;
  final Set<String> allowedOperations;

  @override
  State<HarnessRemoteCommandPanel> createState() =>
      _HarnessRemoteCommandPanelState();
}

class _HarnessRemoteCommandPanelState extends State<HarnessRemoteCommandPanel> {
  final TextEditingController _draft = TextEditingController();
  final Map<String, String> _sessionDrafts = <String, String>{};
  String? _workspaceId;
  String? _sessionId;
  String? _activeCommandId;
  String _feedback = '';
  Timer? _historyTimer;
  bool _historyLoading = false;
  List<Map<String, dynamic>> _history = const <Map<String, dynamic>>[];
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _historyTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshHistory());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshHistory());
    });
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _draft.dispose();
    super.dispose();
  }

  List<(String, String, String)> get _targets {
    final rows = <(String, String, String)>[];
    for (final workspace in widget.model.workspaces) {
      final workspaceId = workspace['workspaceId']?.toString() ?? '';
      final title = workspace['title']?.toString() ?? workspaceId;
      final sessions = workspace['sessionIds'];
      if (workspaceId.isEmpty || sessions is! List) continue;
      for (final value in sessions) {
        final sessionId = value.toString();
        if (sessionId.isNotEmpty) rows.add((workspaceId, sessionId, title));
      }
    }
    return rows;
  }

  (String, String, String)? _selected() {
    final targets = _targets;
    if (targets.isEmpty) return null;
    return targets.cast<(String, String, String)?>().firstWhere(
      (target) => target!.$1 == _workspaceId && target.$2 == _sessionId,
      orElse: () => targets.first,
    );
  }

  String _targetKey((String, String, String) target) =>
      '${target.$1}\n${target.$2}';

  void _selectTarget((String, String, String) target) {
    final previous = _selected();
    if (previous != null) {
      _sessionDrafts[_targetKey(previous)] = _draft.text;
    }
    final nextKey = _targetKey(target);
    setState(() {
      _workspaceId = target.$1;
      _sessionId = target.$2;
      _draft.value = TextEditingValue(
        text: _sessionDrafts[nextKey] ?? '',
        selection: TextSelection.collapsed(
          offset: (_sessionDrafts[nextKey] ?? '').length,
        ),
      );
      _history = const <Map<String, dynamic>>[];
      _historyError = null;
    });
    unawaited(_refreshHistory());
  }

  Future<void> _refreshHistory() async {
    final target = _selected();
    if (!mounted ||
        _historyLoading ||
        widget.model.stale ||
        target == null ||
        !widget.allowedOperations.contains('session.history')) {
      return;
    }
    _historyLoading = true;
    try {
      final response = await widget.client.call(
        commandId: widget.client.newCommandId(),
        workspaceId: target.$1,
        sessionId: target.$2,
        method: 'session.history',
        payload: const <String, Object?>{},
      );
      final result = response['result'];
      final value = result is Map ? result['value'] : null;
      final source = value is Map
          ? (value['records'] is List ? value['records'] : value['messages'])
          : null;
      if (result is! Map || result['ok'] != true || source is! List) {
        throw const FormatException('REMOTE_HISTORY_INVALID');
      }
      final rows = <Map<String, dynamic>>[
        for (final row in source)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      if (!mounted || _selected()?.$2 != target.$2) return;
      setState(() {
        _history = rows;
        _historyError = null;
      });
    } on Object catch (error) {
      if (mounted && _selected()?.$2 == target.$2) {
        setState(() => _historyError = '会话反馈同步失败：$error');
      }
    } finally {
      _historyLoading = false;
    }
  }

  Future<void> _send() async {
    final target = _selected();
    final text = _draft.text.trim();
    if (target == null || text.isEmpty || _activeCommandId != null) return;
    final commandId = widget.client.newCommandId();
    setState(() {
      _workspaceId = target.$1;
      _sessionId = target.$2;
      _activeCommandId = commandId;
      _feedback = '命令已提交，等待执行端确认与反馈…';
    });
    try {
      final result = await widget.client.call(
        commandId: commandId,
        workspaceId: target.$1,
        sessionId: target.$2,
        method: 'session.prompt',
        payload: <String, Object?>{'text': text},
      );
      if (mounted) {
        setState(() {
          _feedback = _isAccepted(result)
              ? '执行端已接收命令；运行状态与会话反馈将持续同步，请勿把接收回执当作完成。'
              : '执行端返回：${_compactResult(result)}';
        });
        unawaited(_refreshHistory());
      }
    } on Object catch (error) {
      if (mounted) setState(() => _feedback = '远程命令失败或结果未知：$error');
    } finally {
      if (mounted) setState(() => _activeCommandId = null);
    }
  }

  bool _isAccepted(Map<String, dynamic> response) {
    final result = response['result'];
    final value = result is Map ? result['value'] : null;
    return result is Map &&
        result['ok'] == true &&
        value is Map &&
        value['accepted'] == true;
  }

  String _compactResult(Map<String, dynamic> response) {
    final text = jsonEncode(response);
    return text.length <= 320 ? text : '${text.substring(0, 320)}…';
  }

  String _historyTitle(Map<String, dynamic> row) {
    final user = row['user'];
    if (user is bool) return user ? '用户' : 'Harness';
    final type = row['type']?.toString() ?? '记录';
    if (row['event'] is Map) {
      return (row['event'] as Map)['type']?.toString() ?? '流式反馈';
    }
    return type;
  }

  String _historySummary(Map<String, dynamic> row) {
    final direct = row['text'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    final event = row['event'];
    final data = event is Map ? event['data'] : row['data'];
    return _readableValue(data) ?? '结构化事件；展开可查看完整详情';
  }

  String? _readableValue(Object? value, [int depth = 0]) {
    if (depth > 4 || value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return text.length <= 600 ? text : '${text.substring(0, 600)}…';
    }
    if (value is List) {
      final parts = value
          .map((item) => _readableValue(item, depth + 1))
          .whereType<String>()
          .where((text) => text.isNotEmpty)
          .take(4)
          .toList();
      return parts.isEmpty ? null : parts.join('\n');
    }
    if (value is Map) {
      for (final key in const <String>[
        'texts',
        'text',
        'content',
        'message',
        'reason',
        'detail',
        'name',
        'toolName',
        'status',
        'result',
        'arguments',
      ]) {
        final readable = _readableValue(value[key], depth + 1);
        if (readable != null) return readable;
      }
    }
    return null;
  }

  List<_RemoteHistoryEntry> _historyEntries() {
    final entries = <_RemoteHistoryEntry>[];
    final assistantText = StringBuffer();
    final assistantDetails = <Map<String, dynamic>>[];

    void flushAssistant() {
      final text = assistantText.toString().trim();
      if (text.isNotEmpty) {
        entries.add(
          _RemoteHistoryEntry(
            title: 'Harness',
            summary: text,
            records: List<Map<String, dynamic>>.from(assistantDetails),
          ),
        );
      }
      assistantText.clear();
      assistantDetails.clear();
    }

    for (final row in _history) {
      final type = _historyTitle(row).toLowerCase();
      if (type == 'user/message') {
        flushAssistant();
        final summary = _historySummary(row);
        if (_isInternalUserMessage(summary)) continue;
        entries.add(
          _RemoteHistoryEntry(
            title: '用户',
            summary: summary,
            records: <Map<String, dynamic>>[row],
          ),
        );
        continue;
      }
      if (type == 'chunkrow/text-chunks') {
        final chunk = _textChunks(row);
        if (chunk.isNotEmpty) {
          assistantText.write(chunk);
          assistantDetails.add(row);
        }
        continue;
      }
      if (type.contains('tool') || type.contains('command')) {
        flushAssistant();
        entries.add(
          _RemoteHistoryEntry(
            title: '工具调用',
            summary: _historySummary(row),
            records: <Map<String, dynamic>>[row],
          ),
        );
        continue;
      }
      if (type == 'turn/end' || type == 'turn/complete') {
        flushAssistant();
        entries.add(
          _RemoteHistoryEntry(
            title: '本轮完成',
            summary: '远端 Harness 已结束本轮执行',
            records: <Map<String, dynamic>>[row],
          ),
        );
      }
    }
    flushAssistant();
    return entries;
  }

  bool _isInternalUserMessage(String text) {
    final normalized = text.trimLeft().toLowerCase();
    return normalized.startsWith('<system-reminder>') ||
        normalized.startsWith('current runtime context.') ||
        normalized.startsWith('<available_skills>') ||
        normalized.startsWith('instructions from:');
  }

  String _textChunks(Map<String, dynamic> row) {
    final event = row['event'];
    final data = event is Map ? event['data'] : row['data'];
    if (data is Map && data['texts'] is List) {
      return (data['texts'] as List)
          .whereType<String>()
          .map((text) => text)
          .join();
    }
    return _readableValue(data) ?? '';
  }

  String _entryDetails(_RemoteHistoryEntry entry) {
    final encoded = const JsonEncoder.withIndent('  ').convert(entry.records);
    return encoded.length <= 6000
        ? encoded
        : '${encoded.substring(0, 6000)}\n…';
  }

  Future<void> _stop() async {
    final target = _selected();
    if (target == null) return;
    setState(() => _feedback = '正在请求停止远端会话…');
    try {
      final result = await widget.client.cancel(
        commandId: widget.client.newCommandId(),
        workspaceId: target.$1,
        sessionId: target.$2,
      );
      if (mounted) {
        setState(() {
          _feedback = _isAccepted(result)
              ? '停止请求已被执行端接受；正在同步最终状态。'
              : '停止请求已返回：${_compactResult(result)}';
        });
        unawaited(_refreshHistory());
      }
    } on Object catch (error) {
      if (mounted) setState(() => _feedback = '停止请求失败或结果未知：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final selected = _selected();
    final historyEntries = _historyEntries();
    final canPrompt = widget.allowedOperations.contains('session.prompt');
    final canCancel = widget.allowedOperations.contains('session.cancel');
    return AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<String>(
            key: const Key('harness-remote-session-picker'),
            initialValue: selected == null
                ? null
                : '${selected.$1}\n${selected.$2}',
            decoration: const InputDecoration(
              labelText: '远端项目 / 会话',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final target in targets)
                DropdownMenuItem(
                  value: '${target.$1}\n${target.$2}',
                  child: Text('${target.$3} · ${target.$2}'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              final target = targets.firstWhere(
                (candidate) => _targetKey(candidate) == value,
              );
              _selectTarget(target);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('harness-remote-command-input'),
            controller: _draft,
            enabled: canPrompt && targets.isNotEmpty,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '向选中的远端会话发送命令',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              FilledButton.icon(
                key: const Key('harness-remote-command-send'),
                onPressed: canPrompt && _activeCommandId == null ? _send : null,
                icon: const Icon(Icons.send_rounded),
                label: const Text('发送'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('harness-remote-command-stop'),
                onPressed: canCancel && targets.isNotEmpty ? _stop : null,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('停止远端任务'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('harness-remote-history'),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            leading: _historyLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.forum_outlined),
            title: Text('远端会话反馈（${historyEntries.length} 条）'),
            subtitle: Text(
              _historyError ??
                  (historyEntries.isEmpty ? '正在读取正式会话记录…' : '每 2 秒同步，执行端为唯一权威'),
            ),
            children: <Widget>[
              for (final entry
                  in historyEntries.reversed.take(12).toList().reversed)
                ExpansionTile(
                  dense: true,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(entry.title),
                  subtitle: Text(
                    entry.summary,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        _entryDetails(entry),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_feedback.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText(
              _feedback,
              key: const Key('harness-remote-command-feedback'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteHistoryEntry {
  const _RemoteHistoryEntry({
    required this.title,
    required this.summary,
    required this.records,
  });

  final String title;
  final String summary;
  final List<Map<String, dynamic>> records;
}
