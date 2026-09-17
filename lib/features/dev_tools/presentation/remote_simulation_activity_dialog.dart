import 'package:flutter/material.dart';

import '../domain/remote_simulation_activity.dart';

class RemoteSimulationStatusChip extends StatelessWidget {
  const RemoteSimulationStatusChip({
    required this.color,
    required this.label,
    this.semanticKey,
    super.key,
  });

  final Color color;
  final String label;
  final Key? semanticKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Tooltip(
      message: '查看远程仿真活动记录',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: semanticKey,
          borderRadius: BorderRadius.circular(16),
          onTap: () => showRemoteSimulationActivityDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> showRemoteSimulationActivityDialog(BuildContext context) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭远程仿真记录',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (BuildContext dialogContext, _, _) =>
          const _RemoteSimulationActivityDialog(),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
              child: child,
            ),
          ),
    );

class _RemoteSimulationActivityDialog extends StatelessWidget {
  const _RemoteSimulationActivityDialog();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: Dialog(
          key: const Key('remote-simulation-activity-dialog'),
          elevation: 18,
          backgroundColor: colors.surface.withValues(alpha: 0.92),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 420,
              maxWidth: 720,
              maxHeight: 560,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.monitor_heart_outlined, size: 21),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          '远程仿真调试记录',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('remote-simulation-clear-activity'),
                        onPressed: RemoteSimulationActivityHub.instance.clear,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('清空记录'),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '仅记录远程仿真通道内的连接、诊断、文件和应用操作；敏感参数已脱敏。',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: StreamBuilder<List<RemoteSimulationActivityEntry>>(
                      stream: RemoteSimulationActivityHub.instance.changes,
                      initialData: RemoteSimulationActivityHub.instance.entries,
                      builder: (context, snapshot) {
                        final entries =
                            snapshot.data ??
                            RemoteSimulationActivityHub.instance.entries;
                        if (entries.isEmpty) {
                          return const SizedBox(
                            height: 220,
                            child: Center(child: Text('暂无远程仿真操作记录')),
                          );
                        }
                        return ListView.separated(
                          key: const Key('remote-simulation-activity-list'),
                          shrinkWrap: true,
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) =>
                              _ActivityTile(entry: entries[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry});

  final RemoteSimulationActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (IconData, Color, String) state = switch (entry.phase) {
      RemoteSimulationActivityPhase.running => (
        Icons.sync_rounded,
        colors.primary,
        '进行中',
      ),
      RemoteSimulationActivityPhase.succeeded => (
        Icons.check_circle_outline_rounded,
        const Color(0xFF16845B),
        '已完成',
      ),
      RemoteSimulationActivityPhase.failed => (
        Icons.error_outline_rounded,
        colors.error,
        '失败',
      ),
    };
    final String direction =
        entry.direction == RemoteSimulationActivityDirection.outgoing
        ? '本机发起'
        : '远端发起';
    final DateTime time = entry.startedAt.toLocal();
    final String timestamp =
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: Icon(state.$1, color: state.$2, size: 21),
      title: Text(
        entry.action,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$direction · ${entry.peerId.isEmpty ? '未知设备' : entry.peerId} · $timestamp\n${entry.detail}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Text(state.$3, style: TextStyle(fontSize: 12, color: state.$2)),
    );
  }
}
