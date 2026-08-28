import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_decision_engine.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 21, 12);

  CleanupCandidate candidate({
    required String path,
    required CleanupCategory category,
    DateTime? modified,
    CleanupRiskLevel risk = CleanupRiskLevel.safe,
    int size = 100 * 1024 * 1024,
    String source = '已验证规则',
  }) => CleanupCandidate(
    path: path,
    size: size,
    category: category,
    reason: source,
    sourceLabel: source,
    modified: modified,
    riskLevel: risk,
  );

  test('only old known regenerable cache is automatically selected', () {
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      <CleanupCandidate>[
        candidate(
          path: r'C:\App\Cache\old.bin',
          category: CleanupCategory.applicationCache,
          modified: now.subtract(const Duration(days: 10)),
        ),
        candidate(
          path: r'C:\App\Cache\active.bin',
          category: CleanupCategory.applicationCache,
          modified: now.subtract(const Duration(hours: 2)),
        ),
      ],
      now: now,
    );

    expect(
      plan.candidatesFor(CleanupDecisionTier.automatic).single.path,
      r'C:\App\Cache\old.bin',
    );
    expect(
      plan.candidatesFor(CleanupDecisionTier.recommended).single.path,
      r'C:\App\Cache\active.bin',
    );
  });

  test(
    'system managed and current app files stay protected under pressure',
    () {
      final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
        <CleanupCandidate>[
          candidate(
            path: r'C:\Windows\WinSxS\payload.dll',
            category: CleanupCategory.systemCache,
            modified: now.subtract(const Duration(days: 300)),
            risk: CleanupRiskLevel.systemManaged,
            size: 8 * 1024 * 1024 * 1024,
          ),
          candidate(
            path: r'C:\Vibekits\cache.bin',
            category: CleanupCategory.applicationCache,
            modified: now.subtract(const Duration(days: 30)),
          ),
        ],
        now: now,
        freeSpaceRatio: 0.01,
        protectedRoots: const <String>[r'C:\Vibekits'],
      );

      expect(plan.candidatesFor(CleanupDecisionTier.protected), hasLength(2));
      expect(plan.candidatesFor(CleanupDecisionTier.automatic), isEmpty);
    },
  );

  test('recycle bin and user downloads always require explicit review', () {
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      <CleanupCandidate>[
        candidate(
          path: r'C:\$Recycle.Bin',
          category: CleanupCategory.recycleBin,
          risk: CleanupRiskLevel.systemManaged,
          size: 6 * 1024 * 1024 * 1024,
        ),
        candidate(
          path: r'C:\Users\me\Downloads\archive.zip',
          category: CleanupCategory.downloads,
          modified: now.subtract(const Duration(days: 200)),
          size: 4 * 1024 * 1024 * 1024,
        ),
      ],
      now: now,
    );

    expect(plan.candidatesFor(CleanupDecisionTier.review), hasLength(2));
    expect(plan.candidatesFor(CleanupDecisionTier.automatic), isEmpty);
  });

  test('directory rollup prevents nested size double counting', () {
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      <CleanupCandidate>[
        candidate(
          path: r'C:\Cache\old-version',
          category: CleanupCategory.pluginCache,
          modified: now.subtract(const Duration(days: 30)),
          size: 1000,
        ),
        candidate(
          path: r'C:\Cache\old-version\payload.bin',
          category: CleanupCategory.pluginCache,
          modified: now.subtract(const Duration(days: 30)),
          size: 900,
        ),
      ],
      now: now,
    );

    expect(plan.decisions, hasLength(1));
    expect(plan.decisions.single.candidate.size, 1000);
  });

  test('known one-day-old developer cache is recommended, never automatic', () {
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      <CleanupCandidate>[
        candidate(
          path: r'C:\Users\me\.gradle\caches\payload.bin',
          category: CleanupCategory.devCache,
          modified: now.subtract(const Duration(hours: 30)),
          size: 2 * 1024 * 1024 * 1024,
          source: 'Gradle 构建缓存',
        ),
      ],
      now: now,
      freeSpaceRatio: 0.08,
    );

    expect(plan.candidatesFor(CleanupDecisionTier.recommended), hasLength(1));
    expect(plan.candidatesFor(CleanupDecisionTier.automatic), isEmpty);
  });

  test('large candidate inventory deduplicates without quadratic stall', () {
    final List<CleanupCandidate> candidates = List<CleanupCandidate>.generate(
      50000,
      (int index) => candidate(
        path: 'C:\\Cache\\package_${index ~/ 10}\\file_$index.bin',
        category: CleanupCategory.applicationCache,
        modified: now.subtract(const Duration(days: 10)),
        size: 1024,
      ),
    );
    final Stopwatch clock = Stopwatch()..start();
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      candidates,
      now: now,
    );
    clock.stop();

    expect(plan.decisions, hasLength(50000));
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('Windows 用户配置容量始终受保护且不进入恢复计划', () {
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      <CleanupCandidate>[
        candidate(
          path: r'C:\Users\kemi-test',
          category: CleanupCategory.userProfileResidual,
          modified: now.subtract(const Duration(days: 500)),
          risk: CleanupRiskLevel.systemManaged,
          size: 12 * 1024 * 1024 * 1024,
          source: '其他 Windows 用户配置容量盘点',
        ),
      ],
      now: now,
      freeSpaceRatio: 0.001,
    );

    expect(plan.candidatesFor(CleanupDecisionTier.protected), hasLength(1));
    expect(plan.candidatesFor(CleanupDecisionTier.automatic), isEmpty);
    expect(plan.candidatesFor(CleanupDecisionTier.recommended), isEmpty);
    expect(plan.decisions.single.explanation, contains('Windows'));
  });

  test('Harness 调试证据只推荐展示且永不自动勾选', () {
    final String root = '${Directory.systemTemp.path}\\vibekits-harness-debug';
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      <CleanupCandidate>[
        candidate(
          path: '$root\\logs\\harness-old.log',
          category: CleanupCategory.logs,
          modified: now.subtract(const Duration(days: 60)),
          source: 'Harness 大模型调试日志',
          size: 5 * 1024 * 1024 * 1024,
        ),
      ],
      now: now,
      freeSpaceRatio: 0.001,
      harnessDebugDirectory: root,
    );

    expect(plan.candidatesFor(CleanupDecisionTier.review), hasLength(1));
    expect(plan.candidatesFor(CleanupDecisionTier.automatic), isEmpty);
    expect(plan.decisions.single.explanation, contains('用户选择'));
  });
}
