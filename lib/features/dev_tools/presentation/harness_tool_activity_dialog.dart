import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/harness_tool_activity_store.dart';

Future<void> showHarnessToolActivityDialog(
  BuildContext context, {
  required String toolName,
  required Set<String> toolIds,
}) async {
  List<HarnessToolActivity> entries = await HarnessToolActivityStore.load(
    toolIds,
  );
  bool loggingEnabled = await HarnessToolActivityStore.loadLoggingEnabled(
    toolIds,
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, void Function(void Function()) setDialogState) {
        Future<void> reload() async {
          final List<HarnessToolActivity> loaded =
              await HarnessToolActivityStore.load(toolIds);
          if (dialogContext.mounted) {
            setDialogState(() => entries = loaded);
          }
        }

        return AlertDialog(
          title: Text(
            '$toolName · Harness 记录',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          content: SizedBox(
            width: 720,
            height: 430,
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  key: const Key('harness-activity-enabled'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    '记录当前工具的 Harness 调用',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    '默认开启；只关闭当前模块，不影响其他工具，已有记录保留',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: loggingEnabled,
                  onChanged: (bool value) async {
                    await HarnessToolActivityStore.setLoggingEnabled(
                      value,
                      toolIds: toolIds,
                    );
                    if (dialogContext.mounted) {
                      setDialogState(() => loggingEnabled = value);
                    }
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(child: Text('暂无 Harness 调用记录'))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (BuildContext context, int index) {
                            final HarnessToolActivity entry = entries[index];
                            return ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(
                                horizontal: -3,
                                vertical: -3,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              leading: Icon(
                                _icon(entry.status),
                                color: _color(context, entry.status),
                                size: 19,
                              ),
                              title: Text(
                                '${entry.toolName} · ${_label(entry.status)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${_time(entry.startedAt)} · ${entry.elapsedMs} ms'
                                '${entry.target.isEmpty ? '' : '\n目标：${entry.target}'}'
                                '\n命令：${entry.argumentsSummary}'
                                '${entry.resultSummary.isEmpty ? '' : '\n结果：${entry.resultSummary}'}',
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.25,
                                  color: context.vibe.muted,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: '删除这条记录',
                                onPressed: () async {
                                  await HarnessToolActivityStore.delete(
                                    entry.id,
                                  );
                                  await reload();
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 19,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: reload,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('刷新'),
            ),
            TextButton.icon(
              onPressed: entries.isEmpty
                  ? null
                  : () async {
                      await HarnessToolActivityStore.clear(toolIds);
                      await reload();
                    },
              icon: const Icon(Icons.delete_sweep_outlined, size: 17),
              label: const Text('清空当前工具'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        );
      },
    ),
  );
}

IconData _icon(HarnessToolActivityStatus status) => switch (status) {
  HarnessToolActivityStatus.succeeded => Icons.check_circle_outline,
  HarnessToolActivityStatus.failed => Icons.error_outline,
  HarnessToolActivityStatus.denied => Icons.block,
};

Color _color(BuildContext context, HarnessToolActivityStatus status) =>
    switch (status) {
      HarnessToolActivityStatus.succeeded => context.vibe.success,
      HarnessToolActivityStatus.failed => VibekitsColors.danger,
      HarnessToolActivityStatus.denied => VibekitsColors.warning,
    };

String _label(HarnessToolActivityStatus status) => switch (status) {
  HarnessToolActivityStatus.succeeded => '成功',
  HarnessToolActivityStatus.failed => '失败',
  HarnessToolActivityStatus.denied => '未执行',
};

String _time(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';
