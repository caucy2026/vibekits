import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_decision_engine.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_recovery_planner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

void main() {
  CleanupDecision decision(
    String path,
    int gib,
    CleanupDecisionTier tier,
    int score,
  ) => CleanupDecision(
    candidate: CleanupCandidate(
      path: path,
      size: gib * 1024 * 1024 * 1024,
      category: CleanupCategory.applicationCache,
      reason: '测试缓存',
    ),
    tier: tier,
    score: score,
    explanation: '测试',
  );

  test('只从安全和建议层补足目标，不用未知项凑容量', () {
    final CleanupRecoveryPlan plan = CleanupRecoveryPlanner.build(
      CleanupDecisionPlan(<CleanupDecision>[
        decision('auto', 2, CleanupDecisionTier.automatic, 90),
        decision('recommended-large', 6, CleanupDecisionTier.recommended, 70),
        decision('recommended-small', 3, CleanupDecisionTier.recommended, 80),
        decision('unknown-huge', 20, CleanupDecisionTier.review, 25),
        decision('system', 30, CleanupDecisionTier.protected, 0),
      ]),
      releaseGoalBytes: 10 * 1024 * 1024 * 1024,
    );
    expect(plan.reachesGoal, isTrue);
    expect(plan.selectedBytes, 11 * 1024 * 1024 * 1024);
    expect(plan.recommendedToGoal.first.candidate.path, 'recommended-large');
    expect(
      plan.selectedCandidates.map((item) => item.path),
      isNot(contains('unknown-huge')),
    );
    expect(plan.reviewBytes, 20 * 1024 * 1024 * 1024);
  });

  test('安全候选不足时明确报告缺口', () {
    final CleanupRecoveryPlan plan = CleanupRecoveryPlanner.build(
      CleanupDecisionPlan(<CleanupDecision>[
        decision('safe', 1, CleanupDecisionTier.automatic, 90),
        decision('unknown', 50, CleanupDecisionTier.review, 25),
      ]),
      releaseGoalBytes: 10 * 1024 * 1024 * 1024,
    );
    expect(plan.reachesGoal, isFalse);
    expect(plan.goalGapBytes, 9 * 1024 * 1024 * 1024);
  });
}
