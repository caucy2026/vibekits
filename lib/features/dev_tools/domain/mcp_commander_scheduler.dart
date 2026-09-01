import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'mcp_capability_models.dart';
import 'mcp_tool_reputation_store.dart';

class McpSchedulingCandidate {
  const McpSchedulingCandidate({
    required this.device,
    required this.tool,
    required this.reputation,
    required this.score,
    required this.reason,
    required this.tieBreaker,
  });

  final McpDeviceCapability device;
  final McpToolInterface tool;
  final McpToolReputation reputation;
  final double score;
  final String reason;
  final String tieBreaker;

  Map<String, Object?> toJson() => <String, Object?>{
    'instanceId': device.id,
    'name': device.name,
    'tier': device.tier.name,
    'toolName': tool.name,
    'score': double.parse(score.toStringAsFixed(4)),
    'reason': reason,
    'runtime': device.runtime.toJson(),
    'reputation': reputation.toJson(),
  };
}

/// Pure, deterministic LMCP commander ranking defined by standard section 6.9.
/// Reservation is deliberately performed by the caller after ranking; a UDP
/// idle state never grants the right to execute a side-effecting tool.
abstract final class McpCommanderScheduler {
  static List<McpSchedulingCandidate> rank({
    required Iterable<McpDeviceCapability> devices,
    required String toolName,
    required String taskId,
    required Map<String, McpToolReputation> reputations,
    DateTime? now,
  }) {
    final DateTime clock = now ?? DateTime.now();
    final List<(McpDeviceCapability, McpToolInterface)> eligible =
        <(McpDeviceCapability, McpToolInterface)>[];
    for (final McpDeviceCapability device in devices) {
      if (!device.online || !device.schedulable) continue;
      for (final McpToolInterface tool in device.tools) {
        if (tool.name == toolName) eligible.add((device, tool));
      }
    }
    if (eligible.isEmpty) return const <McpSchedulingCandidate>[];
    final int bestTier = eligible
        .map(
          ((McpDeviceCapability, McpToolInterface) item) => item.$1.tier.index,
        )
        .reduce((int left, int right) => left < right ? left : right);
    final List<McpSchedulingCandidate> ranked = <McpSchedulingCandidate>[];
    for (final (McpDeviceCapability device, McpToolInterface tool)
        in eligible.where(
          ((McpDeviceCapability, McpToolInterface) item) =>
              item.$1.tier.index == bestTier,
        )) {
      final McpToolReputation reputation =
          reputations[McpToolReputationStore.key(
            device.tier,
            device.id,
            tool.name,
          )] ??
          McpToolReputation.initial(
            tier: device.tier,
            instanceId: device.id,
            toolName: tool.name,
          );
      final double slots =
          device.runtime.availableSlots / device.runtime.capacity;
      final double quality = reputation.score / 100;
      final double reliability = reputation.totalCalls == 0
          ? 0.6
          : reputation.successfulCalls / reputation.totalCalls;
      final double latency = reputation.averageLatencyMs <= 0
          ? 0.6
          : (1 - reputation.averageLatencyMs / 30000).clamp(0, 1);
      final int ageMs = clock.difference(device.lastUpdated).inMilliseconds;
      final double freshness = (1 - ageMs / 12000).clamp(0, 1);
      final String tieBreaker = sha256
          .convert(utf8.encode('$taskId:${device.id}'))
          .toString();
      final double fairness =
          int.parse(tieBreaker.substring(0, 8), radix: 16) / 0xffffffff;
      final double score =
          slots * 0.35 +
          quality * 0.25 +
          reliability * 0.15 +
          latency * 0.15 +
          freshness * 0.05 +
          fairness * 0.05;
      ranked.add(
        McpSchedulingCandidate(
          device: device,
          tool: tool,
          reputation: reputation,
          score: score,
          tieBreaker: tieBreaker,
          reason:
              '层级=${device.tier.name}，空闲槽=${device.runtime.availableSlots}/${device.runtime.capacity}，'
              '工具质量=${reputation.score}，可靠性=${(reliability * 100).round()}%，'
              '预计延迟=${reputation.averageLatencyMs}ms，状态年龄=${ageMs.clamp(0, 999999)}ms',
        ),
      );
    }
    ranked.sort((McpSchedulingCandidate left, McpSchedulingCandidate right) {
      final int byScore = right.score.compareTo(left.score);
      return byScore != 0
          ? byScore
          : left.tieBreaker.compareTo(right.tieBreaker);
    });
    return List<McpSchedulingCandidate>.unmodifiable(ranked);
  }
}
