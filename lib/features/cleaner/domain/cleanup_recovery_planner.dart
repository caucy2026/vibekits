import 'cleanup_decision_engine.dart';
import 'cleanup_scanner.dart';

/// Turns the decision engine into an explainable space-recovery plan.
///
/// The goal never weakens protection gates. If verified and recommended
/// candidates cannot reach it, the remainder is reported instead of silently
/// promoting unknown files to deletable content.
class CleanupRecoveryPlan {
  const CleanupRecoveryPlan({
    required this.releaseGoalBytes,
    required this.automatic,
    required this.recommendedToGoal,
    required this.remainingRecommended,
    required this.reviewOpportunities,
    required this.protected,
  });

  final int releaseGoalBytes;
  final List<CleanupDecision> automatic;
  final List<CleanupDecision> recommendedToGoal;
  final List<CleanupDecision> remainingRecommended;
  final List<CleanupDecision> reviewOpportunities;
  final List<CleanupDecision> protected;

  Iterable<CleanupDecision> get selectedDecisions sync* {
    yield* automatic;
    yield* recommendedToGoal;
  }

  List<CleanupCandidate> get selectedCandidates => selectedDecisions
      .map((CleanupDecision decision) => decision.candidate)
      .toList(growable: false);

  int get automaticBytes => _bytes(automatic);
  int get recommendedToGoalBytes => _bytes(recommendedToGoal);
  int get selectedBytes => automaticBytes + recommendedToGoalBytes;
  int get reviewBytes => _bytes(reviewOpportunities);
  int get goalGapBytes =>
      (releaseGoalBytes - selectedBytes).clamp(0, releaseGoalBytes);
  bool get reachesGoal => selectedBytes >= releaseGoalBytes;

  static int _bytes(Iterable<CleanupDecision> decisions) => decisions.fold<int>(
    0,
    (int total, CleanupDecision decision) => total + decision.candidate.size,
  );
}

abstract final class CleanupRecoveryPlanner {
  static CleanupRecoveryPlan build(
    CleanupDecisionPlan decisionPlan, {
    required int releaseGoalBytes,
  }) {
    final List<CleanupDecision> automatic = _ordered(
      decisionPlan.decisions.where(
        (CleanupDecision item) => item.tier == CleanupDecisionTier.automatic,
      ),
    );
    final List<CleanupDecision> recommended = _ordered(
      decisionPlan.decisions.where(
        (CleanupDecision item) => item.tier == CleanupDecisionTier.recommended,
      ),
    );
    final List<CleanupDecision> review = _ordered(
      decisionPlan.decisions.where(
        (CleanupDecision item) =>
            item.tier == CleanupDecisionTier.review &&
            item.candidate.category != CleanupCategory.recycleBin,
      ),
    );
    final List<CleanupDecision> protected = _ordered(
      decisionPlan.decisions.where(
        (CleanupDecision item) => item.tier == CleanupDecisionTier.protected,
      ),
    );
    int accumulated = CleanupRecoveryPlan._bytes(automatic);
    final List<CleanupDecision> toGoal = <CleanupDecision>[];
    final List<CleanupDecision> remainder = <CleanupDecision>[];
    for (final CleanupDecision decision in recommended) {
      if (accumulated < releaseGoalBytes) {
        toGoal.add(decision);
        accumulated += decision.candidate.size;
      } else {
        remainder.add(decision);
      }
    }
    return CleanupRecoveryPlan(
      releaseGoalBytes: releaseGoalBytes,
      automatic: List<CleanupDecision>.unmodifiable(automatic),
      recommendedToGoal: List<CleanupDecision>.unmodifiable(toGoal),
      remainingRecommended: List<CleanupDecision>.unmodifiable(remainder),
      reviewOpportunities: List<CleanupDecision>.unmodifiable(review),
      protected: List<CleanupDecision>.unmodifiable(protected),
    );
  }

  static List<CleanupDecision> _ordered(Iterable<CleanupDecision> input) =>
      input.toList(growable: false)
        ..sort((CleanupDecision left, CleanupDecision right) {
          final int size = right.candidate.size.compareTo(left.candidate.size);
          if (size != 0) return size;
          return right.score.compareTo(left.score);
        });
}
