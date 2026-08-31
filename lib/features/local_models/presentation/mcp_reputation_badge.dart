import 'package:flutter/material.dart';

import '../../dev_tools/domain/mcp_capability_models.dart';
import '../../dev_tools/domain/mcp_tool_reputation_store.dart';

McpToolReputation? reputationForTool(
  Map<String, McpToolReputation> reputations,
  McpDeviceCapability device,
  McpToolInterface tool,
) => reputations[McpToolReputationStore.key(device.tier, device.id, tool.name)];

class McpReputationBadge extends StatelessWidget {
  const McpReputationBadge({super.key, required this.reputation});

  final McpToolReputation? reputation;

  @override
  Widget build(BuildContext context) {
    final McpToolReputation? value = reputation;
    if (value == null ||
        (value.totalCalls == 0 && value.manualRating == null)) {
      return const SizedBox.shrink();
    }
    final bool garbage = value.score < 30 || value.manualRating == 0;
    final Color color = garbage
        ? const Color(0xFFB42318)
        : value.score >= 70
        ? const Color(0xFF287A52)
        : const Color(0xFF8A5A00);
    final String label = garbage
        ? '垃圾 · ${value.score}'
        : '${value.score} · ${_gradeLabel(value.grade)}';
    return Tooltip(
      message: <String>[
        '全局工具类型评分（同名工具跨设备共享）',
        '调用 ${value.totalCalls} · 成功 ${value.successfulCalls} · 失败 ${value.failedCalls}',
        if (value.manualRating != null) '人工 ${value.manualRating}/5',
        '平均 ${value.averageLatencyMs} ms',
      ].join('\n'),
      child: Container(
        key: ValueKey<String>('mcp-reputation-${value.toolName}'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          value.manualRating == null
              ? label
              : '$label · 人工 ${value.manualRating}/5',
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static String _gradeLabel(String grade) => switch (grade) {
    'excellent' => '优秀',
    'good' => '好用',
    'poor' => '较差',
    'garbage' => '垃圾',
    _ => '一般',
  };
}
