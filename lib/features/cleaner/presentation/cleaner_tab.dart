import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../archive/domain/disk_space.dart';
import '../domain/cleanup_background_runner.dart';
import '../domain/cleanup_deleter.dart';
import '../domain/cleanup_report.dart';
import '../domain/cleanup_scanner.dart';
import '../domain/cleanup_task.dart';
import '../domain/cleanup_targets.dart';
import '../domain/cleanup_whitelist.dart';
import '../domain/system_drive_analysis_runner.dart';
import '../domain/system_drive_analysis_report.dart';
import '../domain/system_drive_analyzer.dart';

typedef CleanupScanRunner = Future<CleanupScanResult> Function({
  required CleanupCancellationToken cancellationToken,
  required void Function(CleanupScanProgress progress) onProgress,
});
typedef CleanupDeleteRunner = Future<CleanupDeleteResult> Function({
  required List<CleanupCandidate> candidates,
  required CleanupCancellationToken cancellationToken,
  required bool permanentFallback,
  required void Function(CleanupDeleteProgress progress) onProgress,
});
typedef CleanupDiskSnapshotReader = DiskSpaceSnapshot? Function(String path);
typedef CleanupDriveAnalysisRunner = Future<SystemDriveAnalysis> Function({
  required CleanupCancellationToken cancellationToken,
  required void Function(SystemDriveAnalysisProgress progress) onProgress,
});

/// T2 Windows 清理 Tab（对标 360/CCleaner，docs/08 §4）。
class CleanerTab extends StatefulWidget {
  const CleanerTab({
    super.key,
    this.scanRunner,
    this.deleteRunner,
    this.diskSnapshotReader,
    this.initialWhitelist = const <String>[],
    this.initialTargetIds = const <String>[],
    this.initialTargetCatalogVersion = 0,
    this.onWhitelistChanged,
    this.onTargetIdsChanged,
    this.initialTotalReleasedBytes = 0,
    this.initialCompletedRuns = 0,
    this.onCleanupStatsChanged,
    this.availableTargets,
    this.driveAnalysisRunner,
    this.analyzeAfterCleanup = true,
    this.persistDriveAnalysisReport = true,
  });

  final CleanupScanRunner? scanRunner;
  final CleanupDeleteRunner? deleteRunner;
  final CleanupDiskSnapshotReader? diskSnapshotReader;
  final List<String> initialWhitelist;
  final List<String> initialTargetIds;
  final int initialTargetCatalogVersion;
  final Future<void> Function(List<String> whitelist)? onWhitelistChanged;
  final Future<void> Function(List<String> targetIds, int catalogVersion)?
  onTargetIdsChanged;
  final int initialTotalReleasedBytes;
  final int initialCompletedRuns;
  final Future<void> Function(int totalReleasedBytes, int completedRuns)?
  onCleanupStatsChanged;
  final List<CleanupScanTarget>? availableTargets;
  final CleanupDriveAnalysisRunner? driveAnalysisRunner;
  final bool analyzeAfterCleanup;
  final bool persistDriveAnalysisReport;

  @override
  State<CleanerTab> createState() => _CleanerTabState();
}

class _CleanerTabState extends State<CleanerTab> {
  List<CleanupCandidate> _candidates = const <CleanupCandidate>[];
  final Set<String> _selected = <String>{};
  late Set<String> _whitelist = CleanupWhitelist.sanitize(
    widget.initialWhitelist,
  ).toSet();
  List<CleanupScanTarget> _availableTargets = const <CleanupScanTarget>[];
  Set<String> _enabledTargetIds = <String>{};
  bool _discoveringTargets = true;
  bool _scanning = false;
  bool _cleaning = false;
  CleanupCancellationToken? _taskToken;
  CleanupScanProgress? _scanProgress;
  CleanupDeleteProgress? _deleteProgress;
  CleanupDeleteResult? _lastResult;
  File? _lastReport;
  File? _lastDriveAnalysisReport;
  DiskSpaceSnapshot? _diskBefore;
  DiskSpaceSnapshot? _diskAfter;
  SystemDriveAnalysis? _driveAnalysis;
  SystemDriveAnalysisProgress? _driveAnalysisProgress;
  bool _analyzingDrive = false;
  late int _totalReleasedBytes = widget.initialTotalReleasedBytes;
  late int _completedRuns = widget.initialCompletedRuns;
  String _message = '';
  final Map<CleanupCategory, int> _visibleItemLimits = <CleanupCategory, int>{};

  @override
  void initState() {
    super.initState();
    final List<CleanupScanTarget>? supplied = widget.availableTargets;
    if (supplied != null) {
      _applyDiscoveredTargets(supplied);
    } else {
      unawaited(_discoverTargets());
    }
  }

  Future<void> _discoverTargets() async {
    try {
      final List<CleanupScanTarget> targets =
          await CleanupBackgroundRunner.discoverTargets();
      if (mounted) _applyDiscoveredTargets(targets);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _discoveringTargets = false;
        _message = '扫描范围加载失败：$error';
      });
    }
  }

  void _applyDiscoveredTargets(List<CleanupScanTarget> targets) {
    _availableTargets = List<CleanupScanTarget>.unmodifiable(targets);
    _enabledTargetIds = _initialTargetIds();
    _discoveringTargets = false;
    if (mounted) setState(() {});
    if (widget.initialTargetCatalogVersion <
        CleanupTargetDiscovery.catalogVersion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onTargetIdsChanged?.call(
          _enabledTargetIds.toList()..sort(),
          CleanupTargetDiscovery.catalogVersion,
        );
      });
    }
  }

  @override
  void dispose() {
    _taskToken?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CleanerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_cleaning) {
      _totalReleasedBytes = widget.initialTotalReleasedBytes;
      _completedRuns = widget.initialCompletedRuns;
    }
    final Set<String> incoming = CleanupWhitelist.sanitize(
      widget.initialWhitelist,
    ).toSet();
    if (!_samePaths(_whitelist, incoming)) {
      _whitelist = incoming;
      _candidates = _candidates
          .where(
            (CleanupCandidate candidate) => !incoming.any(
              (String root) => CleanupWhitelist.contains(root, candidate.path),
            ),
          )
          .toList();
      _selected.removeWhere(
        (String path) => incoming.any(
          (String root) => CleanupWhitelist.contains(root, path),
        ),
      );
    }
    if (widget.initialTargetIds.isNotEmpty) {
      final Set<String> available = _availableTargets
          .map((CleanupScanTarget target) => target.id)
          .toSet();
      final Set<String> incomingTargets = widget.initialTargetIds
          .where(available.contains)
          .toSet();
      if (incomingTargets.isNotEmpty &&
          !_samePaths(_enabledTargetIds, incomingTargets)) {
        _enabledTargetIds = incomingTargets;
      }
    }
  }

  Future<void> _scan() async {
    if (_discoveringTargets || _enabledTargetIds.isEmpty) return;
    setState(() {
      _scanning = true;
      _message = '';
      _candidates = const <CleanupCandidate>[];
      _selected.clear();
      _scanProgress = null;
      _lastResult = null;
    });
    final CleanupCancellationToken token = CleanupCancellationToken();
    _taskToken = token;
    try {
      void onProgress(CleanupScanProgress progress) {
        if (mounted) setState(() => _scanProgress = progress);
      }

      final CleanupScanResult result = widget.scanRunner == null
          ? await CleanupBackgroundRunner.scanTargets(
              _availableTargets
                  .where(
                    (CleanupScanTarget target) =>
                        _enabledTargetIds.contains(target.id),
                  )
                  .toList(growable: false),
              cancellationToken: token,
              onProgress: onProgress,
            )
          : await widget.scanRunner!(
              cancellationToken: token,
              onProgress: onProgress,
            );
      final List<CleanupCandidate> filtered = result.candidates
          .where(
            (CleanupCandidate candidate) => !_whitelist.any(
              (String root) => CleanupWhitelist.contains(root, candidate.path),
            ),
          )
          .toList();
      filtered.sort((CleanupCandidate left, CleanupCandidate right) {
        final int category = left.category.index.compareTo(
          right.category.index,
        );
        return category != 0 ? category : right.size.compareTo(left.size);
      });
      if (mounted) {
        setState(() {
          _candidates = filtered;
          _visibleItemLimits.clear();
          _selected.addAll(
            filtered
                .where(
                  (CleanupCandidate candidate) => candidate.defaultSelected,
                )
                .map((CleanupCandidate candidate) => candidate.path),
          );
          _scanning = false;
          _message = result.cancelled
              ? '扫描已取消；保留取消前发现的 ${filtered.length} 项，扫描未删除任何内容'
              : '扫描完成：${filtered.length} 项；无法读取 ${result.unreadablePaths} 个位置';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _message = '扫描失败：$e';
        });
      }
    } finally {
      if (identical(_taskToken, token)) _taskToken = null;
    }
  }

  Map<CleanupCategory, List<CleanupCandidate>> get _grouped {
    final Map<CleanupCategory, List<CleanupCandidate>> grouped =
        <CleanupCategory, List<CleanupCandidate>>{};
    for (final CleanupCandidate candidate in _candidates) {
      grouped
          .putIfAbsent(candidate.category, () => <CleanupCandidate>[])
          .add(candidate);
    }
    return grouped;
  }

  int get _selectedSize => _candidates
      .where((CleanupCandidate c) => _selected.contains(c.path))
      .fold<int>(0, (int sum, CleanupCandidate c) => sum + c.size);

  Future<void> _clean() async {
    final List<CleanupCandidate> plan = _candidates
        .where(
          (CleanupCandidate candidate) =>
              _selected.contains(candidate.path) &&
              !_whitelist.any(
                (String root) =>
                    CleanupWhitelist.contains(root, candidate.path),
              ),
        )
        .toList(growable: false);
    if (plan.isEmpty) return;
    final int planSize = plan.fold<int>(
      0,
      (int total, CleanupCandidate candidate) => total + candidate.size,
    );
    bool permanentFallback = true;
    final bool hasRegenerableCache = plan.any(
      (CleanupCandidate candidate) => candidate.allowsPermanentFallback,
    );
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              title: const Text('确认清理'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '将 ${plan.length} 个项目（${_formatSize(planSize)}）优先移入回收站。',
                    ),
                    if (hasRegenerableCache) ...<Widget>[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: permanentFallback,
                        title: const Text('强力清理可再生成缓存'),
                        subtitle: const Text(
                          '回收站拒绝时永久删除浏览器、应用、开发、插件下载及调试缓存；不用于下载目录和旧插件。',
                        ),
                        onChanged: (bool? value) => setDialogState(
                          () => permanentFallback = value ?? false,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      '正在被浏览器、编辑器或包管理器占用的文件仍需关闭对应程序后重试。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('清理'),
                ),
              ],
            ),
      ),
    );
    if (confirm != true) return;

    final CleanupCancellationToken token = CleanupCancellationToken();
    final DateTime startedAt = DateTime.now();
    final CleanupDiskSnapshotReader diskReader =
        widget.diskSnapshotReader ?? DiskSpace.snapshot;
    final String systemDiskPath = _systemDiskPath();
    final DiskSpaceSnapshot? diskBefore = diskReader(systemDiskPath);
    setState(() {
      _cleaning = true;
      _taskToken = token;
      _deleteProgress = CleanupDeleteProgress(completed: 0, total: plan.length);
      _message = '';
      _diskBefore = diskBefore;
      _diskAfter = null;
    });
    bool shouldAnalyze = false;
    try {
      final CleanupDeleteResult result = widget.deleteRunner == null
          ? await CleanupBackgroundRunner.deleteCandidates(
              plan,
              cancellationToken: token,
              permanentFallback: permanentFallback,
              onProgress: (CleanupDeleteProgress progress) {
                if (mounted) setState(() => _deleteProgress = progress);
              },
            )
          : await widget.deleteRunner!(
              candidates: plan,
              cancellationToken: token,
              permanentFallback: permanentFallback,
              onProgress: (CleanupDeleteProgress progress) {
                if (mounted) setState(() => _deleteProgress = progress);
              },
            );
      final DiskSpaceSnapshot? diskAfter = diskReader(systemDiskPath);
      if (!mounted) return;
      final int nextTotal = _totalReleasedBytes + result.releasedBytes;
      final int nextRuns = _completedRuns + (result.items.isEmpty ? 0 : 1);
      final Set<String> succeededPaths = result.items
          .where(
            (CleanupItemResult item) =>
                item.status == CleanupItemStatus.succeeded,
          )
          .map((CleanupItemResult item) => item.candidate.path)
          .toSet();
      setState(() {
        _cleaning = false;
        _lastResult = result;
        _lastReport = null;
        _diskAfter = diskAfter;
        _totalReleasedBytes = nextTotal;
        _completedRuns = nextRuns;
        _candidates = _candidates
            .where(
              (CleanupCandidate candidate) =>
                  !succeededPaths.contains(candidate.path),
            )
            .toList();
        _selected.removeAll(succeededPaths);
        _message = result.cancelled ? '清理已取消，已完成部分见报告' : '清理完成';
      });
      shouldAnalyze = !result.cancelled && result.items.isNotEmpty;
      try {
        await widget.onCleanupStatsChanged?.call(nextTotal, nextRuns);
      } catch (error) {
        if (mounted) {
          setState(() => _message = '$_message；累计数据保存失败：${error.runtimeType}');
        }
      }
      try {
        final File report = await CleanupReportWriter.write(
          result,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
        );
        if (mounted) setState(() => _lastReport = report);
      } catch (error) {
        if (mounted) {
          setState(() => _message = '$_message，但报告保存失败：${error.runtimeType}');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _cleaning = false;
          _message = '清理失败：$error';
        });
      }
    } finally {
      if (identical(_taskToken, token)) _taskToken = null;
    }
    if (shouldAnalyze && widget.analyzeAfterCleanup && mounted) {
      await _analyzeSystemDrive();
    }
  }

  Future<void> _analyzeSystemDrive() async {
    if (_scanning || _cleaning || _analyzingDrive) return;
    final CleanupCancellationToken token = CleanupCancellationToken();
    _taskToken = token;
    setState(() {
      _analyzingDrive = true;
      _driveAnalysisProgress = null;
      _lastDriveAnalysisReport = null;
      _message = '正在分析系统盘根目录与空间占用…';
    });
    try {
      final SystemDriveAnalysis analysis = widget.driveAnalysisRunner == null
          ? await SystemDriveAnalysisRunner.analyze(
              _systemDiskPath(),
              cancellationToken: token,
              onProgress: (SystemDriveAnalysisProgress progress) {
                if (mounted) {
                  setState(() => _driveAnalysisProgress = progress);
                }
              },
            )
          : await widget.driveAnalysisRunner!(
              cancellationToken: token,
              onProgress: (SystemDriveAnalysisProgress progress) {
                if (mounted) {
                  setState(() => _driveAnalysisProgress = progress);
                }
              },
            );
      if (!mounted) return;
      setState(() {
        _driveAnalysis = analysis;
        _analyzingDrive = false;
        _message = analysis.cancelled
            ? '空间分析已取消，以下为已完成部分'
            : '空间分析完成：${analysis.entries.length} 个系统盘根项目';
      });
      if (widget.persistDriveAnalysisReport) {
        try {
          final File report = await SystemDriveAnalysisReportWriter.write(
            analysis,
          );
          if (mounted) setState(() => _lastDriveAnalysisReport = report);
        } catch (error) {
          if (mounted) {
            setState(
              () => _message = '$_message；详细报告保存失败：${error.runtimeType}',
            );
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _analyzingDrive = false;
          _message = '系统盘空间分析失败：$error';
        });
      }
    } finally {
      if (identical(_taskToken, token)) _taskToken = null;
    }
  }

  String _systemDiskPath() {
    final String? systemDrive = Platform.environment['SystemDrive'];
    if (systemDrive != null && systemDrive.trim().isNotEmpty) {
      return systemDrive.endsWith(Platform.pathSeparator)
          ? systemDrive
          : '$systemDrive${Platform.pathSeparator}';
    }
    final String? windowsDirectory = Platform.environment['WINDIR'];
    if (windowsDirectory != null && windowsDirectory.length >= 3) {
      return windowsDirectory.substring(0, 3);
    }
    return Directory.current.path;
  }

  Future<void> _manageWhitelist() async {
    final Set<String>? updated = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext dialogContext) {
        final Set<String> draft = <String>{..._whitelist};
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) =>
              AlertDialog(
                title: const Text('白名单目录'),
                content: SizedBox(
                  width: 560,
                  height: 320,
                  child: Column(
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final String? selected = await getDirectoryPath();
                            final String? normalized = selected == null
                                ? null
                                : CleanupWhitelist.normalize(selected);
                            if (normalized != null) {
                              setDialogState(() => draft.add(normalized));
                            }
                          },
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('选择目录'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: draft.isEmpty
                            ? const Center(child: Text('尚未添加白名单目录'))
                            : ListView(
                                children: <Widget>[
                                  for (final String path in draft)
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        path,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: IconButton(
                                        tooltip: '移除',
                                        onPressed: () => setDialogState(
                                          () => draft.remove(path),
                                        ),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: draft.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(draft),
                    child: const Text('保存'),
                  ),
                ],
              ),
        );
      },
    );
    if (updated == null) return;
    final Set<String> sanitized = CleanupWhitelist.sanitize(updated).toSet();
    setState(() {
      _whitelist = sanitized;
      _candidates = _candidates
          .where(
            (CleanupCandidate candidate) => !sanitized.any(
              (String root) => CleanupWhitelist.contains(root, candidate.path),
            ),
          )
          .toList();
      _selected.removeWhere(
        (String path) => sanitized.any(
          (String root) => CleanupWhitelist.contains(root, path),
        ),
      );
    });
    await widget.onWhitelistChanged?.call(sanitized.toList()..sort());
  }

  Future<void> _manageScanTargets() async {
    final Set<String>? updated = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext dialogContext) {
        final Set<String> draft = <String>{..._enabledTargetIds};
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
            title: const Text('扫描范围'),
            content: SizedBox(
              width: 620,
              height: 420,
              child: _availableTargets.isEmpty
                  ? const Center(child: Text('当前环境没有可用扫描范围'))
                  : Column(
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            TextButton.icon(
                              onPressed: () => setDialogState(() {
                                draft
                                  ..clear()
                                  ..addAll(
                                    _availableTargets
                                        .where(
                                          (CleanupScanTarget target) =>
                                              target.defaultEnabled,
                                        )
                                        .map(
                                          (CleanupScanTarget target) =>
                                              target.id,
                                        ),
                                  );
                              }),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('推荐范围'),
                            ),
                            TextButton(
                              onPressed: () => setDialogState(() {
                                draft
                                  ..clear()
                                  ..addAll(
                                    _availableTargets.map(
                                      (CleanupScanTarget target) => target.id,
                                    ),
                                  );
                              }),
                              child: const Text('全部'),
                            ),
                            TextButton(
                              onPressed: () => setDialogState(draft.clear),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            children: <Widget>[
                              for (final CleanupCategory category
                                  in CleanupCategory.values)
                                if (_availableTargets.any(
                                  (CleanupScanTarget target) =>
                                      target.category == category,
                                )) ...<Widget>[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      4,
                                    ),
                                    child: Text(
                                      '${category.label}${category.highRisk ? ' · 默认不选择清理项' : ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: category.highRisk
                                            ? VibekitsColors.warning
                                            : context.vibe.muted,
                                      ),
                                    ),
                                  ),
                                  for (final CleanupScanTarget target
                                      in _availableTargets.where(
                                        (CleanupScanTarget target) =>
                                            target.category == category,
                                      ))
                                    CheckboxListTile(
                                      dense: true,
                                      value: draft.contains(target.id),
                                      title: Text(target.label),
                                      subtitle: Text(
                                        target.safetyNote.isEmpty
                                            ? target.path
                                            : '${target.safetyNote}\n${target.path}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onChanged: (bool? enabled) =>
                                          setDialogState(() {
                                            if (enabled == true) {
                                              draft.add(target.id);
                                            } else {
                                              draft.remove(target.id);
                                            }
                                          }),
                                    ),
                                ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(draft),
                child: const Text('应用'),
              ),
            ],
          ),
        );
      },
    );
    if (updated != null) {
      setState(() => _enabledTargetIds = updated);
      await widget.onTargetIdsChanged?.call(
        updated.toList()..sort(),
        CleanupTargetDiscovery.catalogVersion,
      );
    }
  }

  bool _samePaths(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  Set<String> _initialTargetIds() {
    final Set<String> available = _availableTargets
        .map((CleanupScanTarget target) => target.id)
        .toSet();
    final Set<String> configured = widget.initialTargetIds
        .where(available.contains)
        .toSet();
    final Set<String> defaults = _availableTargets
        .where((CleanupScanTarget target) => target.defaultEnabled)
        .map((CleanupScanTarget target) => target.id)
        .toSet();
    if (configured.isEmpty) return defaults;
    if (widget.initialTargetCatalogVersion <
        CleanupTargetDiscovery.catalogVersion) {
      configured.addAll(defaults);
    }
    return configured;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildToolbar(),
        if (_message.isNotEmpty)
          Container(
            width: double.infinity,
            color: VibekitsColors.info.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(8),
            child: Text(
              _message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ),
        if (_lastResult != null) _buildResultSummary(_lastResult!),
        if (_analyzingDrive && _driveAnalysisProgress != null)
          _buildDriveAnalysisProgress(_driveAnalysisProgress!),
        if (_driveAnalysis != null) _buildDriveAnalysis(_driveAnalysis!),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool veryCompact = constraints.maxWidth < 820;
          return Row(
            children: <Widget>[
              ElevatedButton.icon(
                onPressed:
                    _scanning ||
                        _cleaning ||
                        _discoveringTargets ||
                        _enabledTargetIds.isEmpty
                    ? null
                    : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(_scanning ? '扫描中…' : '开始扫描'),
              ),
              if (_scanning || _cleaning) ...<Widget>[
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () => _taskToken?.cancel(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('取消'),
                ),
              ],
              const SizedBox(width: 6),
              if (veryCompact)
                IconButton(
                  tooltip: '系统盘空间分析',
                  onPressed: _scanning || _cleaning || _analyzingDrive
                      ? null
                      : _analyzeSystemDrive,
                  icon: const Icon(Icons.donut_large, size: 18),
                )
              else
                OutlinedButton.icon(
                  onPressed: _scanning || _cleaning || _analyzingDrive
                      ? null
                      : _analyzeSystemDrive,
                  icon: const Icon(Icons.donut_large, size: 18),
                  label: Text(_analyzingDrive ? '分析中…' : '空间分析'),
                ),
              const SizedBox(width: 6),
              if (veryCompact)
                IconButton(
                  tooltip: '白名单（${_whitelist.length}）',
                  onPressed: _manageWhitelist,
                  icon: const Icon(Icons.block, size: 18),
                )
              else
                OutlinedButton.icon(
                  onPressed: _manageWhitelist,
                  icon: const Icon(Icons.block, size: 18),
                  label: Text('白名单（${_whitelist.length}）'),
                ),
              const SizedBox(width: 6),
              if (veryCompact)
                IconButton(
                  tooltip: '范围（${_enabledTargetIds.length}）',
                  onPressed: _scanning || _cleaning || _discoveringTargets
                      ? null
                      : _manageScanTargets,
                  icon: const Icon(Icons.tune, size: 18),
                )
              else
                OutlinedButton.icon(
                  onPressed: _scanning || _cleaning || _discoveringTargets
                      ? null
                      : _manageScanTargets,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text('范围（${_enabledTargetIds.length}）'),
                ),
              const Spacer(),
              if (!veryCompact) ...<Widget>[
                Text(
                  '已选择 ${_formatSize(_selectedSize)}',
                  style: TextStyle(fontSize: 12, color: context.vibe.muted),
                ),
                const SizedBox(width: 6),
              ],
              ElevatedButton(
                onPressed: _selected.isEmpty || _scanning || _cleaning
                    ? null
                    : _clean,
                child: Text(_cleaning ? '清理中…' : '清理 ${_selected.length} 项'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDriveAnalysisProgress(SystemDriveAnalysisProgress progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '空间分析 ${progress.completedRootEntries}/${progress.totalRootEntries} · '
              '已检查 ${progress.visitedEntries} 项 · ${_formatSize(progress.measuredBytes)} · '
              '${progress.currentPath}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => _taskToken?.cancel(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriveAnalysis(SystemDriveAnalysis analysis) {
    final List<SystemDriveUsageEntry> visible = analysis.entries
        .take(10)
        .toList(growable: false);
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      decoration: BoxDecoration(
        color: context.vibe.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.vibe.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.storage_outlined, size: 18),
                const SizedBox(width: 8),
                const Text(
                  '系统盘空间分析',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '总量 ${_formatSize(analysis.totalBytes)} · '
                    '已用 ${_formatSize(analysis.usedBytes)} · '
                    '剩余 ${_formatSize(analysis.freeBytes)} · '
                    '已归类 ${_formatSize(analysis.measuredBytes)} · '
                    '未归类/不可读 ${_formatSize(analysis.unaccountedBytes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.vibe.muted),
                  ),
                ),
                IconButton(
                  tooltip: '重新分析',
                  onPressed: _analyzingDrive ? null : _analyzeSystemDrive,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                if (_lastDriveAnalysisReport != null)
                  IconButton(
                    tooltip: '查看完整空间报告',
                    onPressed: () => _showDriveAnalysisReport(analysis),
                    icon: const Icon(Icons.description_outlined, size: 18),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: visible.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final SystemDriveUsageEntry entry = visible[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    entry.needsReview
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    size: 18,
                    color: entry.needsReview
                        ? VibekitsColors.warning
                        : context.vibe.success,
                  ),
                  title: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          entry.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${entry.complete ? '' : '≥ '}${_formatSize(entry.sizeBytes)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${entry.kind.label} · ${entry.needsReview ? '需复核' : '正常'} · ${entry.reason}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDriveAnalysisReport(SystemDriveAnalysis analysis) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('系统盘详细分析报告'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '总量 ${_formatSize(analysis.totalBytes)} · '
                  '已用 ${_formatSize(analysis.usedBytes)} · '
                  '剩余 ${_formatSize(analysis.freeBytes)}',
                ),
                const SizedBox(height: 8),
                for (final SystemDriveUsageEntry entry in analysis.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${entry.needsReview ? '需复核' : '正常'} · '
                      '${entry.name} · ${entry.complete ? '' : '≥ '}'
                      '${_formatSize(entry.sizeBytes)}\n'
                      '${entry.kind.label}：${entry.reason}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (_lastDriveAnalysisReport != null) ...<Widget>[
                  const Divider(),
                  SelectableText(
                    '完整 JSON：${_lastDriveAnalysisReport!.path}',
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_discoveringTargets) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.hourglass_top_outlined, size: 34),
            SizedBox(height: 10),
            Text('正在后台识别可清理范围…'),
          ],
        ),
      );
    }
    if (_scanning) {
      final CleanupScanProgress? progress = _scanProgress;
      return Center(
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                progress == null
                    ? '正在准备扫描…'
                    : '已检查 ${progress.visitedEntries} 项，发现 ${progress.candidateCount} 项（${_formatSize(progress.candidateBytes)}）',
              ),
              if (progress != null)
                Text(
                  progress.currentPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
            ],
          ),
        ),
      );
    }
    if (_cleaning) {
      final CleanupDeleteProgress progress =
          _deleteProgress ??
          const CleanupDeleteProgress(completed: 0, total: 0);
      final double? value = progress.total == 0
          ? null
          : progress.completed / progress.total;
      return Center(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text('正在清理 ${progress.completed}/${progress.total}'),
              const Text('已完成项目不会因取消而回滚', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
    }
    if (_candidates.isEmpty) {
      return Center(
        child: Text(
          '点击“开始扫描”查找可清理的临时文件\n扫描不会删除任何内容',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.vibe.muted),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        for (final MapEntry<CleanupCategory, List<CleanupCandidate>> entry
            in _grouped.entries)
          _buildCategory(entry.key, entry.value),
      ],
    );
  }

  Widget _buildResultSummary(CleanupDeleteResult result) {
    final DiskSpaceSnapshot? disk = _diskAfter ?? _diskBefore;
    final int? availableChange = _diskBefore == null || _diskAfter == null
        ? null
        : _diskAfter!.availableBytes - _diskBefore!.availableBytes;
    return Container(
      width: double.infinity,
      color: context.vibe.panelRaised,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                result.cancelled
                    ? Icons.pause_circle_outline
                    : Icons.check_circle_outline,
                size: 18,
                color: result.cancelled
                    ? VibekitsColors.warning
                    : context.vibe.success,
              ),
              const SizedBox(width: 6),
              Text(
                result.cancelled ? '清理已取消，已完成部分已计入' : '清理完成',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(onPressed: _showReport, child: const Text('查看报告')),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _SummaryMetric(
                label: '本次清理',
                value: _formatSize(result.releasedBytes),
              ),
              _SummaryMetric(
                label: '累计清理',
                value: _formatSize(_totalReleasedBytes),
                detail: '$_completedRuns 次',
              ),
              if (disk != null) ...<Widget>[
                _SummaryMetric(
                  label: '系统盘总容量',
                  value: _formatSize(disk.totalBytes),
                ),
                _SummaryMetric(
                  label: '当前可用',
                  value: _formatSize(disk.availableBytes),
                  detail: availableChange == null || availableChange == 0
                      ? null
                      : '${availableChange > 0 ? '+' : ''}${_formatSize(availableChange.abs())}',
                ),
                _SummaryMetric(
                  label: '当前已用',
                  value: _formatSize(disk.usedBytes),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '成功 ${result.succeeded} · 跳过 ${result.skipped} · 失败 ${result.failed} · 后台低占用执行',
            style: TextStyle(fontSize: 11, color: context.vibe.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _showReport() async {
    final CleanupDeleteResult? result = _lastResult;
    if (result == null) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清理报告'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '成功 ${result.succeeded}，跳过 ${result.skipped}，失败 ${result.failed}',
              ),
              Text('本次清理 ${_formatSize(result.releasedBytes)}'),
              Text(
                '历史累计 ${_formatSize(_totalReleasedBytes)}（$_completedRuns 次）',
              ),
              if (_diskAfter != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('系统盘总容量 ${_formatSize(_diskAfter!.totalBytes)}'),
                Text('当前可用 ${_formatSize(_diskAfter!.availableBytes)}'),
                Text('当前已用 ${_formatSize(_diskAfter!.usedBytes)}'),
              ],
              if (_lastReport != null)
                SelectableText(
                  '报告文件：${_lastReport!.path}',
                  style: const TextStyle(fontSize: 11),
                ),
              const SizedBox(height: 8),
              ...result.items
                  .where(
                    (CleanupItemResult item) =>
                        item.status != CleanupItemStatus.succeeded,
                  )
                  .map(
                    (CleanupItemResult item) => Text(
                      '${item.status.name}: ${item.reason}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(
    CleanupCategory category,
    List<CleanupCandidate> items,
  ) {
    final int selectedCount = items
        .where((CleanupCandidate c) => _selected.contains(c.path))
        .length;
    final bool all = selectedCount == items.length;
    final bool partial = selectedCount > 0 && !all;
    final int totalSize = items.fold<int>(
      0,
      (int sum, CleanupCandidate c) => sum + c.size,
    );
    final int visibleLimit = _visibleItemLimits[category] ?? 100;
    final List<CleanupCandidate> visibleItems = items
        .take(visibleLimit)
        .toList(growable: false);
    return ExpansionTile(
      initiallyExpanded: items.length <= 100,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.only(left: 12, bottom: 6),
      leading: Checkbox(
        tristate: true,
        value: all ? true : (partial ? null : false),
        onChanged: (bool? v) => setState(() {
          for (final CleanupCandidate candidate in items) {
            if (v == true) {
              _selected.add(candidate.path);
            } else {
              _selected.remove(candidate.path);
            }
          }
        }),
      ),
      title: Text(
        '${category.label}${category.highRisk ? '（需确认）' : ''}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: category.highRisk
              ? VibekitsColors.warning
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        '${items.length} 项 · ${_formatSize(totalSize)} · 已选 $selectedCount 项',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: <Widget>[
        for (final CleanupCandidate candidate in visibleItems)
          Tooltip(
            message: candidate.path,
            child: CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(candidate.path),
              title: Text(
                _fileName(candidate.path),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${candidate.reason} · ${_formatSize(candidate.size)}'
                    '${candidate.modified == null ? '' : ' · ${_formatDate(candidate.modified!)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    candidate.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              onChanged: (bool? v) => setState(() {
                if (v == true) {
                  _selected.add(candidate.path);
                } else {
                  _selected.remove(candidate.path);
                }
              }),
            ),
          ),
        if (visibleItems.length < items.length)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton.icon(
              onPressed: () => setState(() {
                _visibleItemLimits[category] = visibleLimit + 200;
              }),
              icon: const Icon(Icons.expand_more),
              label: Text(
                '再显示 ${items.length - visibleItems.length > 200 ? 200 : items.length - visibleItems.length} 项'
                '（剩余 ${items.length - visibleItems.length} 项）',
              ),
            ),
          ),
      ],
    );
  }

  String _fileName(String path) => path
      .replaceAll('/', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .where((String part) => part.isNotEmpty)
      .last;

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.vibe.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 10, color: context.vibe.muted),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail != null) ...<Widget>[
                const SizedBox(width: 5),
                Text(
                  detail!,
                  style: TextStyle(fontSize: 10, color: context.vibe.muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
