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

  @override
  void dispose() {
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
    });
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
      if (mounted) setState(() => _feedback = '执行端已返回：$result');
    } on Object catch (error) {
      if (mounted) setState(() => _feedback = '远程命令失败或结果未知：$error');
    } finally {
      if (mounted) setState(() => _activeCommandId = null);
    }
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
      if (mounted) setState(() => _feedback = '停止请求已返回：$result');
    } on Object catch (error) {
      if (mounted) setState(() => _feedback = '停止请求失败或结果未知：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final selected = _selected();
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
