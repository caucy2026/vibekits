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
}
