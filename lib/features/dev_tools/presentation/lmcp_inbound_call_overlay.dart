import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/lmcp_inbound_call_hub.dart';

/// Non-modal, process-wide disclosure for inbound LMCP tool invocations.
class LmcpInboundCallOverlay extends StatefulWidget {
  const LmcpInboundCallOverlay({required this.child, this.hub, super.key});

  final Widget child;
  final LmcpInboundCallHub? hub;

  @override
  State<LmcpInboundCallOverlay> createState() => _LmcpInboundCallOverlayState();
}

class _LmcpInboundCallOverlayState extends State<LmcpInboundCallOverlay> {
  final Set<String> _expanded = <String>{};

  LmcpInboundCallHub get _hub => widget.hub ?? LmcpInboundCallHub.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LmcpInboundCallSnapshot>>(
      stream: _hub.changes,
      initialData: _hub.snapshots,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<LmcpInboundCallSnapshot>> asyncSnapshot,
          ) {
            final List<LmcpInboundCallSnapshot> calls =
                asyncSnapshot.data ?? const <LmcpInboundCallSnapshot>[];
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                widget.child,
                if (calls.isNotEmpty)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: SafeArea(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 320,
                          maxWidth: 430,
                          maxHeight: 640,
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: calls.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              final LmcpInboundCallSnapshot call = calls[index];
                              return _CallCard(
                                key: ValueKey<String>(
                                  'lmcp-call-${call.traceId}',
                                ),
                                call: call,
                                expanded: _expanded.contains(call.traceId),
                                onToggleDetails: () => setState(() {
                                  if (!_expanded.add(call.traceId)) {
                                    _expanded.remove(call.traceId);
                                  }
                                }),
                                onForceClose:
                                    call.terminal ||
                                        call.phase ==
                                            LmcpInboundCallPhase.cancelling
                                    ? null
                                    : () => unawaited(
                                        _hub.forceClose(call.traceId),
                                      ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({
    required this.call,
    required this.expanded,
    required this.onToggleDetails,
    required this.onForceClose,
    super.key,
  });

  final LmcpInboundCallSnapshot call;
  final bool expanded;
  final VoidCallback onToggleDetails;
  final VoidCallback? onForceClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'LMCP 调用：${call.callerLabel} 调用 ${call.toolName}，${_status(call)}',
      child: Card(
        elevation: 8,
        color: colors.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _icon(call.phase),
                    color: _statusColor(colors, call.phase),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          call.callerLabel,
                          key: ValueKey<String>('lmcp-caller-${call.traceId}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          call.toolName,
                          key: ValueKey<String>('lmcp-tool-${call.traceId}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _status(call),
                    key: ValueKey<String>('lmcp-status-${call.traceId}'),
                    style: TextStyle(
                      color: _statusColor(colors, call.phase),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '开始时间 ${_clockText(call.startedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (call.progress != null) ...<Widget>[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: call.progress),
              ],
              if (expanded) ...<Widget>[
                const Divider(height: 20),
                SelectableText('参数摘要：${call.argumentSummary}'),
                const SizedBox(height: 4),
                SelectableText('授权范围：${call.scopeSummary}'),
                const SizedBox(height: 4),
                SelectableText('traceId：${call.traceId}'),
                if (call.taskId?.isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: 4),
                  SelectableText('taskId：${call.taskId}'),
                ],
                const SizedBox(height: 4),
                const Text('审计：已写入 Harness 工具活动记录'),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    key: ValueKey<String>('lmcp-info-${call.traceId}'),
                    onPressed: onToggleDetails,
                    child: Text(expanded ? '收起信息' : '调用信息'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    key: ValueKey<String>('lmcp-stop-${call.traceId}'),
                    onPressed: onForceClose,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('强制关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _status(LmcpInboundCallSnapshot call) =>
      call.statusMessage ??
      switch (call.phase) {
        LmcpInboundCallPhase.running => '正在调用',
        LmcpInboundCallPhase.cancelling => '正在强制关闭',
        LmcpInboundCallPhase.succeeded => '调用完成',
        LmcpInboundCallPhase.failed => '调用失败',
        LmcpInboundCallPhase.cancelled => '已强制关闭',
      };

  static IconData _icon(LmcpInboundCallPhase phase) => switch (phase) {
    LmcpInboundCallPhase.running => Icons.sync_rounded,
    LmcpInboundCallPhase.cancelling => Icons.stop_circle_outlined,
    LmcpInboundCallPhase.succeeded => Icons.check_circle_outline,
    LmcpInboundCallPhase.failed => Icons.error_outline,
    LmcpInboundCallPhase.cancelled => Icons.cancel_outlined,
  };

  static Color _statusColor(ColorScheme colors, LmcpInboundCallPhase phase) =>
      switch (phase) {
        LmcpInboundCallPhase.running => colors.primary,
        LmcpInboundCallPhase.succeeded => colors.tertiary,
        _ => colors.error,
      };

  static String _clockText(DateTime value) {
    final DateTime local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
