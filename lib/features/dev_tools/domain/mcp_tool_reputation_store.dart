import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_capability_models.dart';

class McpToolReputation {
  const McpToolReputation({
    required this.tier,
    required this.instanceId,
    required this.toolName,
    required this.automaticQuality,
    required this.totalCalls,
    required this.successfulCalls,
    required this.failedCalls,
    required this.consecutiveFailures,
    required this.averageLatencyMs,
    required this.updatedAt,
    this.manualRating,
  });

  factory McpToolReputation.initial({
    required McpCapabilityTier tier,
    required String instanceId,
    required String toolName,
  }) => McpToolReputation(
    tier: tier,
    instanceId: instanceId,
    toolName: toolName,
    automaticQuality: 0.6,
    totalCalls: 0,
    successfulCalls: 0,
    failedCalls: 0,
    consecutiveFailures: 0,
    averageLatencyMs: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final McpCapabilityTier tier;
  final String instanceId;
  final String toolName;
  final double automaticQuality;
  final int totalCalls;
  final int successfulCalls;
  final int failedCalls;
  final int consecutiveFailures;
  final int averageLatencyMs;
  final int? manualRating;
  final DateTime updatedAt;

  int get score {
    final double automatic = automaticQuality * 100;
    final double combined = manualRating == null
        ? automatic
        : automatic * 0.35 + (manualRating! / 5) * 100 * 0.65;
    return (combined - consecutiveFailures * 7).round().clamp(0, 100);
  }

  String get grade => switch (score) {
    >= 85 => 'excellent',
    >= 70 => 'good',
    >= 50 => 'neutral',
    >= 30 => 'poor',
    _ => 'garbage',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'tier': tier.name,
    'instanceId': instanceId,
    'toolName': toolName,
    'automaticQuality': automaticQuality,
    'totalCalls': totalCalls,
    'successfulCalls': successfulCalls,
    'failedCalls': failedCalls,
    'consecutiveFailures': consecutiveFailures,
    'averageLatencyMs': averageLatencyMs,
    if (manualRating != null) 'manualRating': manualRating,
    'score': score,
    'grade': grade,
    'scope': 'global-tool-type',
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static McpToolReputation? fromJson(Object? value) {
    if (value is! Map) return null;
    final String tierName = '${value['tier'] ?? ''}';
    final McpCapabilityTier? tier = McpCapabilityTier.values
        .where((McpCapabilityTier item) => item.name == tierName)
        .firstOrNull;
    final String instanceId = '${value['instanceId'] ?? ''}'.trim();
    final String toolName = '${value['toolName'] ?? ''}'.trim();
    final DateTime? updatedAt = DateTime.tryParse(
      '${value['updatedAt'] ?? ''}',
    );
    if (tier == null ||
        instanceId.isEmpty ||
        toolName.isEmpty ||
        updatedAt == null) {
      return null;
    }
    double quality = value['automaticQuality'] is num
        ? (value['automaticQuality']! as num).toDouble()
        : 0.6;
    quality = quality.clamp(0, 1);
    int boundedInt(String key, int maximum) =>
        value[key] is int ? (value[key]! as int).clamp(0, maximum) : 0;
    final int? manualRating = value['manualRating'] is int
        ? (value['manualRating']! as int).clamp(0, 5)
        : null;
    return McpToolReputation(
      tier: tier,
      instanceId: instanceId,
      toolName: toolName,
      automaticQuality: quality,
      totalCalls: boundedInt('totalCalls', 1000000),
      successfulCalls: boundedInt('successfulCalls', 1000000),
      failedCalls: boundedInt('failedCalls', 1000000),
      consecutiveFailures: boundedInt('consecutiveFailures', 1000),
      averageLatencyMs: boundedInt('averageLatencyMs', 86400000),
      manualRating: manualRating,
      updatedAt: updatedAt.toLocal(),
    );
  }
}

class McpToolReputationStore {
  McpToolReputationStore({File? file}) : file = file ?? _defaultFile();

  static final McpToolReputationStore instance = McpToolReputationStore();
  static const int maxEntries = 4000;
  static const int maxFileBytes = 4 * 1024 * 1024;

  final File file;
  Future<void> _writeTail = Future<void>.value();

  static String key(
    McpCapabilityTier tier,
    String instanceId,
    String toolName,
  ) => toolName.trim().toLowerCase();

  Future<Map<String, McpToolReputation>> load() async {
    if (!await file.exists()) return <String, McpToolReputation>{};
    try {
      if (await file.length() > maxFileBytes) {
        return <String, McpToolReputation>{};
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) {
        return <String, McpToolReputation>{};
      }
      final Map<String, McpToolReputation> result =
          <String, McpToolReputation>{};
      for (final Object? raw in (decoded['entries']! as List).take(
        maxEntries,
      )) {
        final McpToolReputation? entry = McpToolReputation.fromJson(raw);
        if (entry == null) continue;
        result[key(entry.tier, entry.instanceId, entry.toolName)] = entry;
      }
      return result;
    } on Object {
      return <String, McpToolReputation>{};
    }
  }

  Future<void> record({
    required McpCapabilityTier tier,
    required String instanceId,
    required String toolName,
    required bool succeeded,
    required double completionQuality,
    required int latencyMs,
  }) => _enqueue(() async {
    final Map<String, McpToolReputation> entries = await load();
    final String id = key(tier, instanceId, toolName);
    final McpToolReputation current =
        entries[id] ??
        McpToolReputation.initial(
          tier: tier,
          instanceId: instanceId,
          toolName: toolName,
        );
    final double quality = completionQuality.clamp(0, 1);
    final double weight = current.totalCalls == 0 ? 1 : 0.25;
    final int nextCalls = current.totalCalls + 1;
    entries[id] = McpToolReputation(
      tier: tier,
      instanceId: '*',
      toolName: toolName,
      automaticQuality:
          current.automaticQuality * (1 - weight) + quality * weight,
      totalCalls: nextCalls,
      successfulCalls: current.successfulCalls + (succeeded ? 1 : 0),
      failedCalls: current.failedCalls + (succeeded ? 0 : 1),
      consecutiveFailures: succeeded ? 0 : current.consecutiveFailures + 1,
      averageLatencyMs: current.totalCalls == 0
          ? latencyMs.clamp(0, 86400000)
          : ((current.averageLatencyMs * current.totalCalls + latencyMs) /
                    nextCalls)
                .round()
                .clamp(0, 86400000),
      manualRating: current.manualRating,
      updatedAt: DateTime.now(),
    );
    await _save(entries);
  });

  Future<McpToolReputation> rate({
    required McpCapabilityTier tier,
    required String instanceId,
    required String toolName,
    required int rating,
  }) async {
    McpToolReputation? saved;
    await _enqueue(() async {
      final Map<String, McpToolReputation> entries = await load();
      final String id = key(tier, instanceId, toolName);
      final McpToolReputation current =
          entries[id] ??
          McpToolReputation.initial(
            tier: tier,
            instanceId: instanceId,
            toolName: toolName,
          );
      saved = McpToolReputation(
        tier: tier,
        instanceId: '*',
        toolName: toolName,
        automaticQuality: current.automaticQuality,
        totalCalls: current.totalCalls,
        successfulCalls: current.successfulCalls,
        failedCalls: current.failedCalls,
        consecutiveFailures: current.consecutiveFailures,
        averageLatencyMs: current.averageLatencyMs,
        manualRating: rating.clamp(0, 5),
        updatedAt: DateTime.now(),
      );
      entries[id] = saved!;
      await _save(entries);
    });
    return saved!;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final Completer<void> completer = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        await operation();
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _save(Map<String, McpToolReputation> entries) async {
    final List<McpToolReputation> ordered = entries.values.toList()
      ..sort(
        (McpToolReputation a, McpToolReputation b) =>
            b.updatedAt.compareTo(a.updatedAt),
      );
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': ordered
            .take(maxEntries)
            .map((McpToolReputation item) => item.toJson())
            .toList(growable: false),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static File _defaultFile() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return File(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
      '${Platform.pathSeparator}mcp-tool-reputation-v1.json',
    );
  }
}

double inferMcpCompletionQuality(Map<String, Object?> result) {
  if (result['isError'] == true ||
      result['ok'] == false ||
      result['success'] == false ||
      result['error'] != null) {
    return 0;
  }
  final Object? structured = result['structuredContent'];
  if (structured is Map &&
      (structured['isError'] == true || structured['error'] != null)) {
    return 0;
  }
  if (result['final'] == false ||
      result['completed'] == false ||
      result['verified'] == false) {
    return 0.45;
  }
  return 1;
}
