import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_tool_reputation_store.dart';
import 'package:vibekits/features/local_models/presentation/mcp_reputation_badge.dart';

void main() {
  test('同名 MCP 工具跨设备共享加权分并持久化', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-reputation-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final File file = File('${root.path}/reputation.json');
    final McpToolReputationStore store = McpToolReputationStore(file: file);

    await store.record(
      tier: McpCapabilityTier.lan,
      instanceId: 'kemi-device-a',
      toolName: 'kemi.files.send',
      succeeded: true,
      completionQuality: 1,
      latencyMs: 120,
    );
    await store.record(
      tier: McpCapabilityTier.lan,
      instanceId: 'kemi-device-b',
      toolName: 'kemi.files.send',
      succeeded: false,
      completionQuality: 0,
      latencyMs: 5000,
    );

    final Map<String, McpToolReputation> entries = await store.load();
    expect(entries, hasLength(1));
    final McpToolReputation shared = entries.values.single;
    expect(shared.toolName, 'kemi.files.send');
    expect(shared.totalCalls, 2);
    expect(shared.successfulCalls, 1);
    expect(shared.failedCalls, 1);
    expect(
      entries[McpToolReputationStore.key(
            McpCapabilityTier.lan,
            'kemi-device-c',
            'kemi.files.send',
          )]!
          .score,
      shared.score,
    );

    final McpToolReputation garbage = await store.rate(
      tier: McpCapabilityTier.lan,
      instanceId: 'kemi-device-c',
      toolName: 'kemi.files.send',
      rating: 0,
    );
    expect(garbage.manualRating, 0);
    expect(garbage.grade, 'garbage');

    final McpToolReputationStore restarted = McpToolReputationStore(file: file);
    final McpToolReputation persisted = (await restarted.load()).values.single;
    expect(persisted.manualRating, 0);
    expect(persisted.totalCalls, 2);
    final String raw = await file.readAsString();
    expect(raw, isNot(contains('sourcePath')));
    expect(raw, isNot(contains('password')));
    expect(raw, isNot(contains('token')));
  });

  test('MCP 结构化错误和未完成结果会自动降权', () {
    expect(inferMcpCompletionQuality(<String, Object?>{'isError': true}), 0);
    expect(
      inferMcpCompletionQuality(<String, Object?>{
        'structuredContent': <String, Object?>{
          'error': <String, Object?>{'code': 'FAILED'},
        },
      }),
      0,
    );
    expect(inferMcpCompletionQuality(<String, Object?>{'final': false}), 0.45);
    expect(inferMcpCompletionQuality(<String, Object?>{'ok': true}), 1);
  });

  testWidgets('未评分保持原样，评分后显示全局徽标和垃圾标识', (WidgetTester tester) async {
    final McpToolReputation unscored = McpToolReputation.initial(
      tier: McpCapabilityTier.lan,
      instanceId: '*',
      toolName: 'kemi.files.send',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            const Text('kemi.files.send'),
            McpReputationBadge(reputation: unscored),
          ],
        ),
      ),
    );
    expect(find.text('垃圾 · 0'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('mcp-reputation-kemi.files.send')),
      findsNothing,
    );

    final McpToolReputation garbage = McpToolReputation(
      tier: McpCapabilityTier.lan,
      instanceId: '*',
      toolName: 'kemi.files.send',
      automaticQuality: 0.2,
      totalCalls: 3,
      successfulCalls: 0,
      failedCalls: 3,
      consecutiveFailures: 3,
      averageLatencyMs: 5000,
      manualRating: 0,
      updatedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(home: McpReputationBadge(reputation: garbage)),
    );
    expect(find.textContaining('垃圾'), findsOneWidget);
    expect(find.textContaining('人工 0/5'), findsOneWidget);
  });
}
