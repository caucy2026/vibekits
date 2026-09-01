import 'dart:io';

import 'cleanup_scanner.dart';
import 'cleanup_platform_policy.dart';

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
    CleanupPlatform? platform,
    Map<String, String>? environment,
    String harnessDebugDirectory = '',
  }) {
    final CleanupPlatform targetPlatform = platform ?? CleanupPlatform.current;
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
    final List<CleanupCandidate> unique = _removeNestedDuplicates(
      candidates,
      targetPlatform,
    );
    return CleanupDecisionPlan(
      unique
          .map(
            (CleanupCandidate candidate) => _evaluate(
              candidate,
              now: clock,
              freeSpaceRatio: freeSpaceRatio,
              protectedRoots: roots,
              platform: targetPlatform,
              environment: environment,
              harnessDebugDirectory: harnessDebugDirectory,
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
    required CleanupPlatform platform,
    required Map<String, String>? environment,
    required String harnessDebugDirectory,
  }) {
    if (candidate.category != CleanupCategory.recycleBin &&
        !CleanupPlatformPolicy.allowsDeletion(
          platform,
          candidate.path,
          environment: environment,
          harnessDebugDirectory: harnessDebugDirectory,
        )) {
      return CleanupDecision(
        candidate: candidate,
        tier: CleanupDecisionTier.protected,
        score: 0,
        explanation: '${platform.label} 平台安全边界之外，只展示信息，不允许清理',
      );
    }
    final String source = candidate.sourceLabel?.toLowerCase() ?? '';
    final bool harnessArtifact =
        source.contains('harness') ||
        (harnessDebugDirectory.trim().isNotEmpty &&
            _containsPath(harnessDebugDirectory, candidate.path, platform));
    if (harnessArtifact) {
      return CleanupDecision(
        candidate: candidate,
        tier: CleanupDecisionTier.review,
        score: 60,
        explanation: 'Harness 调试证据可能用于定位故障；已统计容量，但必须由用户选择后才清理',
      );
    }
    if (protectedRoots.any(
      (String root) => _containsPath(root, candidate.path, platform),
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
            : candidate.category == CleanupCategory.userProfileResidual
            ? '用户配置可能包含文档、密钥和已加载注册表；只盘点容量，必须通过 Windows 账户/用户配置流程删除'
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
      final bool verifiedRegenerableDeveloperCache =
          candidate.riskLevel == CleanupRiskLevel.safe &&
          candidate.category == CleanupCategory.devCache &&
          knownOwner &&
          ageHours >= 24 &&
          score >= 65;
      return CleanupDecision(
        candidate: candidate,
        tier:
            verifiedRegenerableDeveloperCache ||
                (ageHours >= minimumAutomaticAge && score >= 70)
            ? CleanupDecisionTier.recommended
            : CleanupDecisionTier.review,
        score: score,
        explanation: verifiedRegenerableDeveloperCache
            ? '归属明确、可重新下载或重建，且已超过一天未修改；保持人工确认，不自动删除'
            : ageHours < 0
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
    CleanupPlatform platform,
  ) {
    final List<CleanupCandidate> ordered = candidates.toList(growable: false)
      ..sort((CleanupCandidate left, CleanupCandidate right) {
        return left.path.length.compareTo(right.path.length);
      });
    final List<CleanupCandidate> result = <CleanupCandidate>[];
    final Map<String, Set<String>> acceptedByGroup = <String, Set<String>>{};
    for (final CleanupCandidate candidate in ordered) {
      final String group =
          '${candidate.category.index}\u0000'
          '${candidate.sourceLabel ?? ''}';
      final Set<String> accepted = acceptedByGroup.putIfAbsent(
        group,
        () => <String>{},
      );
      final String normalized = _normalize(candidate.path, platform);
      if (_hasAcceptedAncestor(accepted, normalized, platform)) continue;
      result.add(candidate);
      if (candidate.category != CleanupCategory.recycleBin &&
          candidate.size > 0) {
        accepted.add(normalized);
      }
    }
    return result;
  }

  static bool _hasAcceptedAncestor(
    Set<String> accepted,
    String path,
    CleanupPlatform platform,
  ) {
    final String pathSeparator = platform == CleanupPlatform.windows
        ? r'\'
        : '/';
    String cursor = path;
    while (cursor.isNotEmpty) {
      if (accepted.contains(cursor)) return true;
      final int separator = cursor.lastIndexOf(pathSeparator);
      if (separator < 0) return false;
      // Preserve a Windows drive root (C:\) as the last possible ancestor.
      final int nextLength = separator == 2 && cursor.length >= 3
          ? 3
          : separator;
      if (nextLength >= cursor.length || nextLength <= 0) return false;
      cursor = cursor.substring(0, nextLength);
    }
    return false;
  }

  static bool _containsPath(
    String root,
    String candidate,
    CleanupPlatform platform,
  ) {
    final String separator = platform == CleanupPlatform.windows ? r'\' : '/';
    final String normalizedRoot = _normalize(root, platform);
    final String normalizedCandidate = _normalize(candidate, platform);
    return normalizedCandidate == normalizedRoot ||
        normalizedCandidate.startsWith('$normalizedRoot$separator');
  }

  static String _normalize(String path, CleanupPlatform platform) {
    final String separator = platform == CleanupPlatform.windows ? r'\' : '/';
    String value = path.replaceAll(RegExp(r'[\\/]'), separator);
    while (value.endsWith(separator) && value.length > 3) {
      value = value.substring(0, value.length - 1);
    }
    return platform == CleanupPlatform.windows ? value.toLowerCase() : value;
  }

  static String _parentPath(String path) {
    final int separator = path.lastIndexOf(Platform.pathSeparator);
    return separator <= 0 ? '' : path.substring(0, separator);
  }
}
