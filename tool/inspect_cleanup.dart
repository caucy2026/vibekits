// ignore_for_file: avoid_print

import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';

Future<void> main() async {
  final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover();
  final List<CleanupScanTarget> enabled = targets
      .where((CleanupScanTarget target) => target.defaultEnabled)
      .toList(growable: false);
  final CleanupScanResult result = await CleanupScanner.scanTargets(enabled);
  final Map<CleanupCategory, (int, int)> totals =
      <CleanupCategory, (int, int)>{};
  for (final CleanupCandidate candidate in result.candidates) {
    final (int, int) current = totals[candidate.category] ?? (0, 0);
    totals[candidate.category] = (current.$1 + 1, current.$2 + candidate.size);
  }

  print('可用范围: ${targets.length}，默认扫描: ${enabled.length}');
  for (final MapEntry<CleanupCategory, (int, int)> entry in totals.entries) {
    print(
      '${entry.key.label}: ${entry.value.$1} 项，${_formatBytes(entry.value.$2)}',
    );
  }
  print(
    '合计: ${result.candidates.length} 项，${_formatBytes(result.candidateBytes)}，'
    '无法读取 ${result.unreadablePaths} 个位置',
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
