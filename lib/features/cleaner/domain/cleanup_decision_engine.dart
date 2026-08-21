import 'dart:io';

import 'cleanup_scanner.dart';

/// The decision made after a cleanup candidate has been discovered.
///
/// Discovery answers "what looks transient". This engine separately answers
/// "what may be selected without surprising the user".
enum CleanupDecisionTier { automatic, recommended, review, protected }

class CleanupDecision {
  const CleanupDecision({
    required this.candidate,
    required this.tier,
    required this.score,
    required this.explanation,
  });

  final CleanupCandidate candidate;
  final CleanupDecisionTier tier;
  final int score;
  final String explanation;
}

class CleanupDecisionPlan {
  const CleanupDecisionPlan(this.decisions);

  final List<CleanupDecision> decisions;

  List<CleanupCandidate> candidatesFor(CleanupDecisionTier tier) => decisions
      .where((CleanupDecision decision) => decision.tier == tier)
      .map((CleanupDecision decision) => decision.candidate)
      .toList(growable: false);

  int bytesFor(CleanupDecisionTier tier) => decisions
      .where((CleanupDecision decision) => decision.tier == tier)
      .fold<int>(0, (int total, CleanupDecision decision) {
        return total + decision.candidate.size;
      });
}

/// Converts conservative cleanup experience into deterministic, testable
/// product rules. Protection gates always win over disk-pressure scoring.
abstract final class CleanupDecisionEngine {
  static CleanupDecisionPlan buildPlan(
    Iterable<CleanupCandidate> candidates, {
    DateTime? now,
    double freeSpaceRatio = 1,
    Iterable<String> protectedRoots = const <String>[],
  }) {
    final DateTime clock = now ?? DateTime.now();
    final List<String> roots = <String>[
      ...protectedRoots,
      if (Platform.resolvedExecutable.trim().isNotEmpty)
        _parentPath(Platform.resolvedExecutable),
      if ((Platform.environment['LOCALAPPDATA'] ?? '').trim().isNotEmpty)
        '${Platform.environment['LOCALAPPDATA']}${Platform.pathSeparator}Vibekits',
      if ((Platform.environment['LOCALAPPDATA'] ?? '').trim().isNotEmpty)
        '${Platform.environment['LOCALAPPDATA']}${Platform.pathSeparator}'
            'flutter_webview_windows${Platform.pathSeparator}vibekits',
    ].where((String path) => path.trim().isNotEmpty).toList(growable: false);
    final List<CleanupCandidate> unique = _removeNestedDuplicates(candidates);
    return CleanupDecisionPlan(
      unique
          .map(
            (CleanupCandidate candidate) => _evaluate(
              candidate,
              now: clock,
              freeSpaceRatio: freeSpaceRatio,
              protectedRoots: roots,
            ),
          )
          .toList(growable: false),
    );
  }

  static CleanupDecision _evaluate(
    CleanupCandidate candidate, {
    required DateTime now,
    required double freeSpaceRatio,
    required List<String> protectedRoots,
  }) {
    if (protectedRoots.any(
      (String root) => _containsPath(root, candidate.path),
    )) {
      return CleanupDecision(
        candidate: candidate,
        tier: CleanupDecisionTier.protected,
        score: 0,
        explanation: '属于当前程序运行目录，退出程序后才能复核',
      );
    }
    if (candidate.riskLevel == CleanupRiskLevel.systemManaged) {
      return CleanupDecision(
        candidate: candidate,
        tier: candidate.category == CleanupCategory.recycleBin
            ? CleanupDecisionTier.review
            : CleanupDecisionTier.protected,
        score: 0,
        explanation: candidate.category == CleanupCategory.recycleBin
            ? '回收站可释放空间，但清空后无法恢复，必须单独确认'
            : '由系统或安装器管理，不执行文件级删除',
      );
    }
    if (candidate.category == CleanupCategory.downloads ||
        candidate.category == CleanupCategory.duplicateFiles ||
        candidate.category == CleanupCategory.discoveredTransient) {
      return CleanupDecision(
        candidate: candidate,
        tier: CleanupDecisionTier.review,
        score: 25,
        explanation: '内容可能属于用户数据或仅由名称推断，需要查看路径后决定',
      );
    }

    final int ageHours = candidate.modified == null
        ? -1
        : now.difference(candidate.modified!).inHours;
    final bool knownOwner = candidate.sourceLabel?.trim().isNotEmpty ?? false;
    final bool cacheLike = <CleanupCategory>{
      CleanupCategory.userTemp,
      CleanupCategory.browserCache,
      CleanupCategory.applicationCache,
      CleanupCategory.systemCache,
      CleanupCategory.pluginCache,
      CleanupCategory.pluginResidual,
      CleanupCategory.devCache,
      CleanupCategory.logs,
      CleanupCategory.debugArtifacts,
    }.contains(candidate.category);
    final int minimumAutomaticAge = switch (candidate.category) {
      CleanupCategory.userTemp => 24,
      CleanupCategory.debugArtifacts => 24 * 14,
      CleanupCategory.logs => 24 * 7,
      _ => 24 * 7,
    };

    int score = cacheLike ? 50 : 20;
    if (knownOwner) score += 15;
    if (ageHours >= minimumAutomaticAge) {
      score += 25;
    } else if (ageHours >= 24) {
      score += 10;
    }
    if (candidate.size >= 512 * 1024 * 1024) {
      score += 10;
    } else if (candidate.size >= 64 * 1024 * 1024) {
      score += 5;
    }
    // Low free space changes ranking, never protection gates or age evidence.
    if (freeSpaceRatio < 0.05) score += 5;
    if (score > 100) score = 100;

    if (candidate.riskLevel == CleanupRiskLevel.cautious ||
        candidate.category.highRisk) {
      return CleanupDecision(
        candidate: candidate,
        tier: ageHours >= minimumAutomaticAge && score >= 70
            ? CleanupDecisionTier.recommended
            : CleanupDecisionTier.review,
        score: score,
        explanation: ageHours < 0
            ? '可重建性或最近使用时间证据不足，需要确认'
            : '属于开发缓存或谨慎规则，已保留人工确认',
      );
    }
    if (cacheLike && ageHours >= minimumAutomaticAge && score >= 85) {
      return CleanupDecision(
        candidate: candidate,
        tier: CleanupDecisionTier.automatic,
        score: score,
        explanation: '归属明确、可重建且已超过保留期',
      );
    }
    if (cacheLike && score >= 65) {
      return CleanupDecision(
        candidate: candidate,
        tier: CleanupDecisionTier.recommended,
        score: score,
        explanation: ageHours < 0
            ? '缓存归属明确，但缺少最近使用时间，清理前确认'
            : '可重建缓存，未达到自动清理的保留期',
      );
    }
    return CleanupDecision(
      candidate: candidate,
      tier: CleanupDecisionTier.review,
      score: score,
      explanation: '证据不足，不自动选择',
    );
  }

  static List<CleanupCandidate> _removeNestedDuplicates(
    Iterable<CleanupCandidate> candidates,
  ) {
    final List<CleanupCandidate> ordered = candidates.toList(growable: false)
      ..sort((CleanupCandidate left, CleanupCandidate right) {
        return left.path.length.compareTo(right.path.length);
      });
    final List<CleanupCandidate> result = <CleanupCandidate>[];
    for (final CleanupCandidate candidate in ordered) {
      final bool covered = result.any(
        (CleanupCandidate parent) =>
            parent.category != CleanupCategory.recycleBin &&
            parent.category == candidate.category &&
            parent.sourceLabel == candidate.sourceLabel &&
            parent.size > 0 &&
            _containsPath(parent.path, candidate.path),
      );
      if (!covered) result.add(candidate);
    }
    return result;
  }

  static bool _containsPath(String root, String candidate) {
    final String normalizedRoot = _normalize(root);
    final String normalizedCandidate = _normalize(candidate);
    return normalizedCandidate == normalizedRoot ||
        normalizedCandidate.startsWith(
          '$normalizedRoot${Platform.pathSeparator}',
        );
  }

  static String _normalize(String path) {
    String value = path.replaceAll('/', Platform.pathSeparator);
    while (value.endsWith(Platform.pathSeparator) && value.length > 3) {
      value = value.substring(0, value.length - 1);
    }
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  static String _parentPath(String path) {
    final int separator = path.lastIndexOf(Platform.pathSeparator);
    return separator <= 0 ? '' : path.substring(0, separator);
  }
}
