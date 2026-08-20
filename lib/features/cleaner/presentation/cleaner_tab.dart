import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../../archive/domain/disk_space.dart';
import '../domain/cleanup_background_runner.dart';
import '../domain/cleanup_deleter.dart';
import '../domain/cleanup_report.dart';
import '../domain/cleanup_scanner.dart';
import '../domain/cleanup_task.dart';
import '../domain/cleanup_targets.dart';
import '../domain/cleanup_whitelist.dart';
import '../domain/disk_volume_discovery.dart';
import '../domain/installed_application_service.dart';
import '../domain/software_storage_analyzer.dart';
import '../domain/system_drive_analysis_runner.dart';
import '../domain/system_drive_analysis_report.dart';
import '../domain/system_drive_analyzer.dart';
import '../domain/system_drive_insights.dart';

void _recycleSoftwareCacheEntry(List<Object> request) {
  final SendPort resultPort = request[0] as SendPort;
  final List<String> paths = (request[1] as List<Object>).cast<String>();
  resultPort.send(CleanupDeleter.sendToRecycleBin(paths));
}

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
typedef CleanupVolumeLoader = Future<List<DiskVolumeInfo>> Function();
typedef CleanupVolumeDriveAnalysisRunner = Future<SystemDriveAnalysis> Function(
  String rootPath, {
  required CleanupCancellationToken cancellationToken,
  required void Function(SystemDriveAnalysisProgress progress) onProgress,
});
typedef CleanupDriveEntryRecycler = Future<bool> Function(String path);
typedef CleanupHarnessLauncher = Future<void> Function(String prompt);
typedef InstalledApplicationLoader =
    Future<List<InstalledApplication>> Function();
typedef ApplicationUninstallLauncher = Future<bool> Function(
  InstalledApplication application,
);

enum _CleanupResultView {
  recommended('推荐清理', Icons.auto_awesome_outlined),
  softwareCache('软件缓存', Icons.apps_outlined),
  largeDownloads('大文件 / 下载', Icons.file_present_outlined),
  unusedSoftware('不常用软件', Icons.inventory_2_outlined),
  deepCleanup('深度清理', Icons.manage_search_outlined);

  const _CleanupResultView(this.label, this.icon);

  final String label;
  final IconData icon;
}

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
    this.volumeLoader,
    this.volumeDriveAnalysisRunner,
    this.driveEntryRecycler,
    this.analyzeAfterCleanup = true,
    this.persistDriveAnalysisReport = true,
    this.harnessDebugDirectory = '',
    this.onAskHarness,
    this.installedApplicationLoader,
    this.applicationUninstallLauncher,
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
  final CleanupVolumeLoader? volumeLoader;
  final CleanupVolumeDriveAnalysisRunner? volumeDriveAnalysisRunner;
  final CleanupDriveEntryRecycler? driveEntryRecycler;
  final bool analyzeAfterCleanup;
  final bool persistDriveAnalysisReport;
  final String harnessDebugDirectory;
  final CleanupHarnessLauncher? onAskHarness;
  final InstalledApplicationLoader? installedApplicationLoader;
  final ApplicationUninstallLauncher? applicationUninstallLauncher;

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
  final Map<String, SystemDriveAnalysis> _driveAnalyses =
      <String, SystemDriveAnalysis>{};
  List<DiskVolumeInfo> _volumes = const <DiskVolumeInfo>[];
  late Set<String> _selectedVolumeRoots;
  String? _activeVolumeRoot;
  bool _discoveringVolumes = true;
  SystemDriveAnalysisProgress? _driveAnalysisProgress;
  final Map<String, SystemDriveUsageEntry> _partialDriveEntries =
      <String, SystemDriveUsageEntry>{};
  bool _analyzingDrive = false;
  String? _deletingDrivePath;
  List<InstalledApplication> _installedApplications =
      const <InstalledApplication>[];
  String? _cleaningSoftwareId;
  Isolate? _softwareCleanupIsolate;
  ReceivePort? _softwareCleanupPort;
  String? _uninstallingSoftwareId;
  String _softwareQuery = '';
  _CleanupResultView _cleanupResultView = _CleanupResultView.recommended;
  bool _loadingInstalledApplications = false;
  late int _totalReleasedBytes = widget.initialTotalReleasedBytes;
  late int _completedRuns = widget.initialCompletedRuns;
  String _message = '';
  final Map<CleanupCategory, int> _visibleItemLimits = <CleanupCategory, int>{};

  @override
  void initState() {
    super.initState();
    _selectedVolumeRoots = <String>{_systemDiskPath()};
    _activeVolumeRoot = _systemDiskPath();
    unawaited(_discoverVolumes());
    final List<CleanupScanTarget>? supplied = widget.availableTargets;
    if (supplied != null) {
      _applyDiscoveredTargets(supplied);
    } else {
      unawaited(_discoverTargets());
    }
  }

  Future<void> _discoverVolumes() async {
    try {
      List<DiskVolumeInfo> volumes =
          await (widget.volumeLoader?.call() ?? DiskVolumeDiscovery.discover());
      if (volumes.isEmpty) {
        final String root = _systemDiskPath();
        final DiskSpaceSnapshot? disk =
            widget.diskSnapshotReader?.call(root) ?? DiskSpace.snapshot(root);
        volumes = <DiskVolumeInfo>[
          DiskVolumeInfo(
            rootPath: root,
            name: '${_shortVolumeName(root)}（系统盘）',
            type: DiskVolumeType.fixed,
            totalBytes: disk?.totalBytes ?? 0,
            freeBytes: disk?.freeBytes ?? 0,
            availableBytes: disk?.availableBytes ?? 0,
            isSystemVolume: true,
          ),
        ];
      }
      if (!mounted) return;
      final Set<String> available = volumes
          .map((DiskVolumeInfo item) => _volumeKey(item.rootPath))
          .toSet();
      final Set<String> retained = _selectedVolumeRoots
          .where((String root) => available.contains(_volumeKey(root)))
          .toSet();
      if (retained.isEmpty) {
        retained.add(
          volumes
              .firstWhere(
                (DiskVolumeInfo item) => item.isSystemVolume,
                orElse: () => volumes.first,
              )
              .rootPath,
        );
      }
      setState(() {
        _volumes = List<DiskVolumeInfo>.unmodifiable(volumes);
        _selectedVolumeRoots = retained;
        _activeVolumeRoot = _matchingVolumeRoot(
          _activeVolumeRoot ?? retained.first,
          volumes,
        );
        _discoveringVolumes = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _discoveringVolumes = false;
        _message = '磁盘列表加载失败：$error';
      });
    }
  }

  Future<void> _discoverTargets() async {
    try {
      final String bundledRuleDatabase = await rootBundle.loadString(
        'assets/cleaner/windows_rules_v6.json',
      );
      final List<CleanupScanTarget>
      targets = await CleanupBackgroundRunner.discoverTargets(
        harnessDebugDirectory: widget.harnessDebugDirectory.trim().isEmpty
            ? '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tmp'
            : widget.harnessDebugDirectory.trim(),
        bundledRuleDatabase: bundledRuleDatabase,
      );
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
    _softwareCleanupIsolate?.kill(priority: Isolate.immediate);
    _softwareCleanupPort?.close();
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

  _CleanupResultView _viewForCandidate(CleanupCandidate candidate) {
    if (candidate.category == CleanupCategory.downloads ||
        candidate.category == CleanupCategory.duplicateFiles) {
      return _CleanupResultView.largeDownloads;
    }
    if (<CleanupCategory>{
      CleanupCategory.browserCache,
      CleanupCategory.applicationCache,
      CleanupCategory.devCache,
      CleanupCategory.pluginCache,
    }.contains(candidate.category)) {
      return _CleanupResultView.softwareCache;
    }
    return candidate.highRisk
        ? _CleanupResultView.deepCleanup
        : _CleanupResultView.recommended;
  }

  List<CleanupCandidate> _candidatesForView(_CleanupResultView view) =>
      _candidates
          .where((CleanupCandidate item) => _viewForCandidate(item) == view)
          .toList(growable: false);

  Map<CleanupCategory, List<CleanupCandidate>> _groupCandidates(
    List<CleanupCandidate> candidates,
  ) {
    final Map<CleanupCategory, List<CleanupCandidate>> grouped =
        <CleanupCategory, List<CleanupCandidate>>{};
    for (final CleanupCandidate candidate in candidates) {
      grouped
          .putIfAbsent(candidate.category, () => <CleanupCandidate>[])
          .add(candidate);
    }
    return grouped;
  }

  Future<void> _selectCleanupView(_CleanupResultView view) async {
    setState(() => _cleanupResultView = view);
    if (view != _CleanupResultView.unusedSoftware ||
        _installedApplications.isNotEmpty ||
        _loadingInstalledApplications) {
      return;
    }
    setState(() => _loadingInstalledApplications = true);
    try {
      final List<InstalledApplication> applications =
          await (widget.installedApplicationLoader?.call() ??
              InstalledApplicationService.load());
      if (mounted) setState(() => _installedApplications = applications);
    } finally {
      if (mounted) setState(() => _loadingInstalledApplications = false);
    }
  }

  int get _selectedSize => _candidates
      .where((CleanupCandidate c) => _selected.contains(c.path))
      .fold<int>(0, (int sum, CleanupCandidate c) => sum + c.size);

  Future<void> _smartSelect() async {
    final List<CleanupCandidate> plan = _candidates
        .where((candidate) {
          if (candidate.category == CleanupCategory.downloads ||
              candidate.category == CleanupCategory.duplicateFiles ||
              candidate.category == CleanupCategory.pluginResidual) {
            return false;
          }
          // Smart mode must never turn a review item into an automatic delete.
          // App runtimes, downloaded models, recycle-bin contents and unknown
          // discoveries remain visible, but require an explicit user choice.
          const Set<CleanupCategory> automaticCategories = <CleanupCategory>{
            CleanupCategory.userTemp,
            CleanupCategory.browserCache,
            CleanupCategory.applicationCache,
            CleanupCategory.systemCache,
            CleanupCategory.pluginCache,
            CleanupCategory.debugArtifacts,
            CleanupCategory.logs,
          };
          return !candidate.highRisk &&
              candidate.defaultSelected &&
              automaticCategories.contains(candidate.category);
        })
        .toList(growable: false);
    if (plan.isEmpty) return;
    final int bytes = plan.fold<int>(
      0,
      (int total, CleanupCandidate candidate) => total + candidate.size,
    );
    final int reviewCount = _candidates
        .where((CleanupCandidate candidate) => candidate.highRisk)
        .length;
    final bool emptiesRecycleBin = plan.any(
      (CleanupCandidate candidate) =>
          candidate.category == CleanupCategory.recycleBin,
    );
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('智能选择清理计划'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('将选择 ${plan.length} 项，预计 ${_formatSize(bytes)}。'),
              const SizedBox(height: 10),
              const Text(
                '包含旧临时文件、日志、可重建开发缓存、应用更新包和可重新下载的运行缓存；不选项目、下载文件、重复文件或旧插件。',
              ),
              if (reviewCount > 0) ...<Widget>[
                const SizedBox(height: 10),
                Text('$reviewCount 项需复核，已保留在列表中且不会被智能选择。'),
              ],
              if (emptiesRecycleBin) ...<Widget>[
                const SizedBox(height: 10),
                const Text(
                  '⚠ 包含清空系统回收站：本次移入及回收站原有内容将无法恢复。',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
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
            child: const Text('确认选择'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(plan.map((CleanupCandidate candidate) => candidate.path));
    });
  }

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
    // Regenerable cache/log candidates use the fast permanent path by default.
    // Review/high-risk items still go through the recycle-bin path.
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
    final List<String> roots =
        _selectedVolumeRoots.isEmpty
              ? <String>[_systemDiskPath()]
              : _selectedVolumeRoots.toList(growable: false)
          ..sort((String left, String right) => left.compareTo(right));
    final CleanupCancellationToken token = CleanupCancellationToken();
    _taskToken = token;
    setState(() {
      _analyzingDrive = true;
      _driveAnalysis = null;
      _driveAnalyses.clear();
      _driveAnalysisProgress = null;
      _partialDriveEntries.clear();
      _lastDriveAnalysisReport = null;
      _message = '正在分析 ${roots.length} 个已选磁盘的空间占用…';
    });
    try {
      final Future<List<InstalledApplication>> applicationsFuture =
          widget.installedApplicationLoader?.call() ??
          InstalledApplicationService.load();
      int completed = 0;
      for (final String root in roots) {
        if (token.isCancelled) break;
        if (mounted) {
          setState(() {
            _activeVolumeRoot = root;
            _driveAnalysisProgress = null;
            _partialDriveEntries.clear();
            _message =
                '正在分析 ${_shortVolumeName(root)} '
                '(${completed + 1}/${roots.length})…';
          });
        }
        final SystemDriveAnalysis analysis = await _runDriveAnalysis(
          root,
          token,
        );
        completed++;
        if (!mounted) return;
        setState(() {
          _driveAnalyses[_volumeKey(root)] = analysis;
          _driveAnalysis = analysis;
          _partialDriveEntries.clear();
        });
        if (widget.persistDriveAnalysisReport) {
          try {
            final File report = await SystemDriveAnalysisReportWriter.write(
              analysis,
            );
            if (mounted) setState(() => _lastDriveAnalysisReport = report);
          } on Object {
            // 单个磁盘报告失败不影响其他磁盘继续分析。
          }
        }
      }
      List<InstalledApplication> applications;
      try {
        applications = await applicationsFuture;
      } on Object {
        applications = const <InstalledApplication>[];
      }
      if (!mounted) return;
      setState(() {
        _installedApplications = applications;
        _analyzingDrive = false;
        _partialDriveEntries.clear();
        final int rootEntries = _driveAnalyses.values.fold<int>(
          0,
          (int total, SystemDriveAnalysis item) => total + item.entries.length,
        );
        _message = token.isCancelled
            ? '空间分析已取消，已保留 ${_driveAnalyses.length} 个磁盘的完成结果'
            : '空间分析完成：${_driveAnalyses.length} 个磁盘，'
                  '识别 ${applications.length} 个已安装软件、$rootEntries 个根项目';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _analyzingDrive = false;
          _message = '磁盘空间分析失败：$error';
        });
      }
    } finally {
      if (identical(_taskToken, token)) _taskToken = null;
    }
  }

  Future<SystemDriveAnalysis> _runDriveAnalysis(
    String root,
    CleanupCancellationToken token,
  ) {
    void onProgress(SystemDriveAnalysisProgress progress) {
      if (mounted) _recordDriveProgress(progress);
    }

    if (widget.volumeDriveAnalysisRunner != null) {
      return widget.volumeDriveAnalysisRunner!(
        root,
        cancellationToken: token,
        onProgress: onProgress,
      );
    }
    if (widget.driveAnalysisRunner != null &&
        _volumeKey(root) == _volumeKey(_systemDiskPath())) {
      return widget.driveAnalysisRunner!(
        cancellationToken: token,
        onProgress: onProgress,
      );
    }
    return SystemDriveAnalysisRunner.analyze(
      root,
      cancellationToken: token,
      onProgress: onProgress,
    );
  }

  void _recordDriveProgress(SystemDriveAnalysisProgress progress) {
    setState(() {
      _driveAnalysisProgress = progress;
      final SystemDriveUsageEntry? completed = progress.completedEntry;
      if (completed != null) _partialDriveEntries[completed.path] = completed;
      for (final SystemDriveUsageEntry entry
          in progress.completedBreakdownEntries) {
        _partialDriveEntries[entry.path] = entry;
      }
    });
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

  String _volumeKey(String path) =>
      Platform.isWindows ? path.replaceAll('/', '\\').toLowerCase() : path;

  String _shortVolumeName(String path) {
    if (Platform.isWindows && path.length >= 2 && path[1] == ':') {
      return path.substring(0, 2).toUpperCase();
    }
    return path == '/' ? '/' : path.split('/').where((e) => e.isNotEmpty).last;
  }

  String _matchingVolumeRoot(String root, List<DiskVolumeInfo> volumes) {
    final String key = _volumeKey(root);
    for (final DiskVolumeInfo volume in volumes) {
      if (_volumeKey(volume.rootPath) == key) return volume.rootPath;
    }
    return volumes.first.rootPath;
  }

  DiskVolumeInfo? _volumeForRoot(String root) {
    final String key = _volumeKey(root);
    for (final DiskVolumeInfo volume in _volumes) {
      if (_volumeKey(volume.rootPath) == key) return volume;
    }
    return null;
  }

  int _cleanableBytes(SystemDriveAnalysis analysis) {
    final Map<String, SystemDriveUsageEntry> safe =
        <String, SystemDriveUsageEntry>{};
    for (final SystemDriveUsageEntry entry in <SystemDriveUsageEntry>[
      ...analysis.entries,
      ...analysis.breakdownEntries,
    ]) {
      if (entry.canDelete) safe[entry.path.toLowerCase()] = entry;
    }
    return safe.values.fold<int>(
      0,
      (int total, SystemDriveUsageEntry entry) => total + entry.sizeBytes,
    );
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
      // v10 removes the whole-drive log inventory from the fast default scan.
      // It remains available as an explicit deep-clean option.
      if (widget.initialTargetCatalogVersion < 10) {
        configured.remove('system-drive-log-inventory');
      }
      configured.addAll(defaults);
    }
    return configured;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildToolbar(),
        _buildVolumeSelector(),
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
        if (_analyzingDrive && _partialDriveEntries.isNotEmpty)
          _buildPartialDriveAnalysis(),
        if (_driveAnalyses.isNotEmpty) _buildDriveResultsSelector(),
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
                  tooltip: '清理日志',
                  onPressed: _showCleanupHistory,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                )
              else
                OutlinedButton.icon(
                  onPressed: _showCleanupHistory,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('清理日志'),
                ),
              const SizedBox(width: 6),
              if (veryCompact)
                IconButton(
                  tooltip: '磁盘空间分析',
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
                  label: Text(_analyzingDrive ? '分析中…' : '分析所选磁盘'),
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
              if (_candidates.isNotEmpty) ...<Widget>[
                const SizedBox(width: 6),
                if (veryCompact)
                  IconButton(
                    tooltip: '智能选择可清理内容',
                    onPressed: _scanning || _cleaning ? null : _smartSelect,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _scanning || _cleaning ? null : _smartSelect,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('智能选择'),
                  ),
              ],
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

  Widget _buildVolumeSelector() {
    if (_discoveringVolumes && _volumes.isEmpty) {
      return const SizedBox(
        height: 46,
        child: Center(child: Text('正在读取本机磁盘…')),
      );
    }
    if (_volumes.isEmpty) {
      return SizedBox(
        height: 46,
        child: Center(
          child: TextButton.icon(
            onPressed: _discoverVolumes,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('未读取到磁盘，点击重试'),
          ),
        ),
      );
    }
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: context.vibe.canvas,
        border: Border.symmetric(
          horizontal: BorderSide(color: context.vibe.border),
        ),
      ),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Text(
              '扫描磁盘',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.vibe.muted,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 5),
              itemCount: _volumes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (BuildContext context, int index) {
                final DiskVolumeInfo volume = _volumes[index];
                final bool selected = _selectedVolumeRoots.any(
                  (String root) =>
                      _volumeKey(root) == _volumeKey(volume.rootPath),
                );
                return InkWell(
                  key: ValueKey<String>('cleaner-volume-${volume.rootPath}'),
                  borderRadius: BorderRadius.circular(9),
                  onTap: _analyzingDrive
                      ? null
                      : () => setState(() {
                          if (selected && _selectedVolumeRoots.length > 1) {
                            _selectedVolumeRoots.removeWhere(
                              (String root) =>
                                  _volumeKey(root) ==
                                  _volumeKey(volume.rootPath),
                            );
                          } else {
                            _selectedVolumeRoots.add(volume.rootPath);
                          }
                        }),
                  child: Container(
                    width: 184,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : context.vibe.panel,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : context.vibe.border,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Checkbox(
                          value: selected,
                          visualDensity: VisualDensity.compact,
                          onChanged: _analyzingDrive
                              ? null
                              : (_) => setState(() {
                                  if (selected &&
                                      _selectedVolumeRoots.length > 1) {
                                    _selectedVolumeRoots.removeWhere(
                                      (String root) =>
                                          _volumeKey(root) ==
                                          _volumeKey(volume.rootPath),
                                    );
                                  } else {
                                    _selectedVolumeRoots.add(volume.rootPath);
                                  }
                                }),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${volume.name} · ${volume.type.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '已用 ${_formatSize(volume.usedBytes)} / '
                                '${_formatSize(volume.totalBytes)} · '
                                '剩余 ${_formatSize(volume.freeBytes)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.vibe.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          TextButton(
            onPressed: _analyzingDrive
                ? null
                : () => setState(() {
                    if (_selectedVolumeRoots.length == _volumes.length) {
                      final DiskVolumeInfo system = _volumes.firstWhere(
                        (DiskVolumeInfo item) => item.isSystemVolume,
                        orElse: () => _volumes.first,
                      );
                      _selectedVolumeRoots = <String>{system.rootPath};
                    } else {
                      _selectedVolumeRoots = _volumes
                          .map((DiskVolumeInfo item) => item.rootPath)
                          .toSet();
                    }
                  }),
            child: Text(
              _selectedVolumeRoots.length == _volumes.length ? '仅系统盘' : '全选',
            ),
          ),
          IconButton(
            tooltip: '刷新磁盘列表',
            onPressed: _analyzingDrive ? null : _discoverVolumes,
            icon: const Icon(Icons.refresh, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _buildDriveResultsSelector() {
    if (_driveAnalyses.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: <Widget>[
          for (final SystemDriveAnalysis analysis in _driveAnalyses.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey<String>(
                  'cleaner-volume-result-${analysis.rootPath}',
                ),
                selected:
                    _activeVolumeRoot != null &&
                    _volumeKey(_activeVolumeRoot!) ==
                        _volumeKey(analysis.rootPath),
                onSelected: (_) => setState(() {
                  _activeVolumeRoot = analysis.rootPath;
                  _driveAnalysis = analysis;
                }),
                label: Text(
                  '${_shortVolumeName(analysis.rootPath)} · '
                  '已用 ${_formatSize(analysis.usedBytes)} · '
                  '剩余 ${_formatSize(analysis.freeBytes)} · '
                  '可清 ${_formatSize(_cleanableBytes(analysis))}',
                ),
              ),
            ),
        ],
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
    final SystemDriveInsights insights = SystemDriveInsights.from(analysis);
    final bool isSystemVolume =
        _volumeForRoot(analysis.rootPath)?.isSystemVolume ??
        _volumeKey(analysis.rootPath) == _volumeKey(_systemDiskPath());
    final Map<String, SystemDriveEntryAssessment> assessmentsByPath =
        <String, SystemDriveEntryAssessment>{
          for (final SystemDriveEntryAssessment item in insights.assessments)
            item.entry.path: item,
        };
    final Map<SystemDriveEntryKind, int> totals = <SystemDriveEntryKind, int>{};
    for (final SystemDriveUsageEntry entry in analysis.entries) {
      totals.update(
        entry.kind,
        (int value) => value + entry.sizeBytes,
        ifAbsent: () => entry.sizeBytes,
      );
    }
    final List<SystemDriveUsageEntry> details =
        <SystemDriveUsageEntry>[
          ...analysis.entries,
          ...analysis.breakdownEntries,
        ]..sort(
          (SystemDriveUsageEntry left, SystemDriveUsageEntry right) =>
              right.sizeBytes.compareTo(left.sizeBytes),
        );
    final List<SystemDriveUsageEntry> visible = details
        .take(40)
        .toList(growable: false);
    final List<SoftwareStorageSummary> software =
        SoftwareStorageAnalyzer.summarize(analysis, _installedApplications);
    return DefaultTabController(
      length: 2,
      initialIndex: software.isEmpty ? 1 : 0,
      child: Container(
        height: 370,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        decoration: BoxDecoration(
          color: context.vibe.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.vibe.border),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.storage_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${_shortVolumeName(analysis.rootPath)} 磁盘空间分析'
                          '${_volumeForRoot(analysis.rootPath)?.isSystemVolume == true ? '（系统盘）' : ''}',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '总量 ${_formatSize(analysis.totalBytes)} · '
                          '已用 ${_formatSize(analysis.usedBytes)} · '
                          '剩余 ${_formatSize(analysis.freeBytes)} · '
                          '识别软件 ${software.length} 个',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${insights.storagePressure.label} · '
                          '${insights.storagePressureSummary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                insights.storagePressure ==
                                    SystemDriveAssessmentLevel.normal
                                ? context.vibe.success
                                : VibekitsColors.warning,
                          ),
                        ),
                      ],
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
                  if (widget.onAskHarness != null)
                    TextButton.icon(
                      onPressed: () => _askHarnessAboutDrive(analysis),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                      label: const Text('让 Harness 解释'),
                    ),
                ],
              ),
            ),
            const TabBar(
              tabs: <Widget>[
                Tab(key: Key('cleaner-software-storage-tab'), text: '软件占用与操作'),
                Tab(key: Key('cleaner-system-storage-tab'), text: '磁盘占用与可清理'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _buildSoftwareStorageList(software),
                  _buildSystemStorageList(
                    visible,
                    assessmentsByPath,
                    totals,
                    insights,
                    isSystemVolume: isSystemVolume,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoftwareStorageList(List<SoftwareStorageSummary> software) {
    final String query = _softwareQuery.trim().toLowerCase();
    final List<SoftwareStorageSummary> visible = query.isEmpty
        ? software
        : software
              .where(
                (SoftwareStorageSummary item) =>
                    item.name.toLowerCase().contains(query) ||
                    (item.application?.publisher.toLowerCase().contains(
                          query,
                        ) ??
                        false),
              )
              .toList(growable: false);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          child: TextField(
            key: const Key('cleaner-software-search'),
            onChanged: (String value) => setState(() => _softwareQuery = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索软件、发布者',
              prefixIcon: const Icon(Icons.search, size: 17),
              suffixText: '${visible.length}/${software.length}',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('没有匹配的软件'))
              : ListView.separated(
                  key: const Key('cleaner-software-storage-list'),
                  itemCount: visible.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final SoftwareStorageSummary item = visible[index];
                    final bool busy =
                        _cleaningSoftwareId == item.id ||
                        _uninstallingSoftwareId == item.id;
                    final Color statusColor =
                        item.level == SystemDriveAssessmentLevel.normal
                        ? context.vibe.success
                        : VibekitsColors.warning;
                    return ListTile(
                      key: ValueKey<String>('software-storage-${item.id}'),
                      dense: true,
                      leading: Icon(
                        Icons.apps_outlined,
                        color: statusColor,
                        size: 20,
                      ),
                      title: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${item.level.label} · '
                            '${item.sizeKnown ? _formatSize(item.totalBytes) : '体积未知'}',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '安装 ${_formatSize(item.installBytes)} · '
                        '数据 ${_formatSize(item.dataBytes)} · '
                        '可清缓存 ${_formatSize(item.cacheBytes)}\n'
                        '${item.assessment}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: busy
                          ? _cleaningSoftwareId == item.id
                                ? TextButton.icon(
                                    onPressed: _cancelSoftwareCacheCleanup,
                                    icon: const Icon(Icons.stop, size: 16),
                                    label: const Text('停止'),
                                  )
                                : const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                OutlinedButton(
                                  key: ValueKey<String>(
                                    'software-clean-cache-${item.id}',
                                  ),
                                  onPressed: item.canCleanCache
                                      ? () => _cleanSoftwareCache(item)
                                      : null,
                                  child: Text(
                                    item.cacheBytes > 0 ? '清理缓存' : '未发现缓存',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  key: ValueKey<String>(
                                    'software-uninstall-${item.id}',
                                  ),
                                  onPressed: item.canUninstall
                                      ? () => _uninstallSoftware(item)
                                      : null,
                                  child: const Text('卸载'),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSystemStorageList(
    List<SystemDriveUsageEntry> visible,
    Map<String, SystemDriveEntryAssessment> assessmentsByPath,
    Map<SystemDriveEntryKind, int> totals,
    SystemDriveInsights insights, {
    required bool isSystemVolume,
  }) => Column(
    children: <Widget>[
      Container(
        width: double.infinity,
        color: context.vibe.canvas,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          '异常判断：${insights.priorities.length} 项需要关注 · '
          '${insights.storagePressure.label}\n'
          '${isSystemVolume ? insights.systemBaseline : '数据盘普通目录仅统计占用；只允许清理明确识别的缓存、临时文件和日志'}\n'
          '${totals.entries.where((item) => item.value > 0).map((item) => '${item.key.label} ${_formatSize(item.value)}').join(' · ')}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: context.vibe.muted),
        ),
      ),
      Expanded(
        child: ListView.separated(
          key: const Key('cleaner-system-storage-list'),
          itemCount: visible.length,
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final SystemDriveUsageEntry entry = visible[index];
            return _buildDriveEntryTile(
              entry,
              assessment: assessmentsByPath[entry.path],
            );
          },
        ),
      ),
    ],
  );

  Future<void> _cleanSoftwareCache(SoftwareStorageSummary software) async {
    if (_cleaningSoftwareId != null || _uninstallingSoftwareId != null) return;
    final List<SystemDriveUsageEntry> entries = software.cacheEntries
        .where((SystemDriveUsageEntry entry) => entry.canDelete)
        .toList(growable: false);
    if (entries.isEmpty) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('清理 ${software.name} 的缓存？'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${entries.length} 个缓存/日志目录 · '
                '${_formatSize(software.cacheBytes)}',
              ),
              const SizedBox(height: 8),
              const Text('只处理扫描确认的可再生缓存和日志，不删除软件配置、数据库或用户文件。'),
              const SizedBox(height: 8),
              for (final SystemDriveUsageEntry entry in entries.take(6))
                Text(
                  '• ${entry.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-software-cache-clean'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移到回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cleaningSoftwareId = software.id);
    bool removed = true;
    if (widget.driveEntryRecycler != null) {
      for (final SystemDriveUsageEntry entry in entries) {
        if (!await widget.driveEntryRecycler!(entry.path)) removed = false;
      }
    } else {
      removed = await _runSoftwareCacheCleanup(
        entries.map((SystemDriveUsageEntry entry) => entry.path).toList(),
      );
    }
    if (!mounted) return;
    setState(() {
      _cleaningSoftwareId = null;
      _message = removed
          ? '已清理 ${software.name} 缓存 ${_formatSize(software.cacheBytes)}'
          : '${software.name} 部分缓存未能清理；请关闭软件后重试';
    });
    if (removed) await _analyzeSystemDrive();
  }

  Future<bool> _runSoftwareCacheCleanup(List<String> paths) async {
    final ReceivePort port = ReceivePort();
    _softwareCleanupPort = port;
    try {
      final Isolate isolate = await Isolate.spawn<List<Object>>(
        _recycleSoftwareCacheEntry,
        <Object>[port.sendPort, paths],
        debugName: 'vibekits-software-cache-delete',
      );
      _softwareCleanupIsolate = isolate;
      final Object? result = await port.first.timeout(
        const Duration(seconds: 30),
      );
      return result == true;
    } on TimeoutException {
      if (mounted) _message = '缓存清理超过 30 秒，已自动停止；请查看明细后分项处理';
      return false;
    } on StateError {
      return false;
    } finally {
      _softwareCleanupIsolate?.kill(priority: Isolate.immediate);
      _softwareCleanupIsolate = null;
      _softwareCleanupPort?.close();
      _softwareCleanupPort = null;
    }
  }

  void _cancelSoftwareCacheCleanup() {
    _softwareCleanupIsolate?.kill(priority: Isolate.immediate);
    _softwareCleanupPort?.close();
    _softwareCleanupIsolate = null;
    _softwareCleanupPort = null;
    if (!mounted) return;
    setState(() {
      _cleaningSoftwareId = null;
      _message = '已停止缓存清理';
    });
  }

  Future<void> _uninstallSoftware(SoftwareStorageSummary software) async {
    final InstalledApplication? application = software.application;
    if (application == null ||
        !application.canUninstall ||
        _cleaningSoftwareId != null ||
        _uninstallingSoftwareId != null) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('卸载 ${software.name}？'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '当前占用约 ${_formatSize(software.totalBytes)}'
                '${application.publisher.isEmpty ? '' : ' · ${application.publisher}'}',
              ),
              const SizedBox(height: 8),
              const Text('将启动软件自己的 Windows 卸载器；Vibekits 不直接删除安装目录。'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-software-uninstall'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('打开卸载器'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _uninstallingSoftwareId = software.id);
    final bool launched = widget.applicationUninstallLauncher != null
        ? await widget.applicationUninstallLauncher!(application)
        : await InstalledApplicationService.launchUninstaller(application);
    if (!mounted) return;
    setState(() {
      _uninstallingSoftwareId = null;
      _message = launched
          ? '已打开 ${software.name} 的 Windows 卸载器'
          : '无法启动 ${software.name} 的卸载器';
    });
  }

  Widget _buildPartialDriveAnalysis() {
    final List<SystemDriveUsageEntry> visible =
        _partialDriveEntries.values.toList()..sort(
          (SystemDriveUsageEntry left, SystemDriveUsageEntry right) =>
              right.sizeBytes.compareTo(left.sizeBytes),
        );
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
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
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.storage_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  '占用结果实时加载 · 已显示 ${visible.length} 项',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '扫描可继续在后台运行',
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: visible.length > 30 ? 30 : visible.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) =>
                  _buildDriveEntryTile(visible[index]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askHarnessAboutDrive(SystemDriveAnalysis analysis) async {
    final String prompt =
        '请调用 vibekits.cleaner.analyze_drive 分析 ${analysis.rootPath}。'
        '请按系统、已安装软件、软件数据、普通数据、日志缓存和未知目录说明各占多少，'
        '解释哪些属于常见范围、哪些异常、判断依据和最安全的处理顺序。'
        '不要直接删除任何内容；需要清理时先列出具体路径、影响和恢复方式，等待我确认。';
    await widget.onAskHarness?.call(prompt);
  }

  Widget _buildDriveEntryTile(
    SystemDriveUsageEntry entry, {
    SystemDriveEntryAssessment? assessment,
  }) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: Icon(
      entry.canDelete
          ? Icons.delete_sweep_outlined
          : entry.needsReview
          ? Icons.warning_amber_rounded
          : Icons.check_circle_outline,
      size: 18,
      color: entry.canDelete
          ? VibekitsColors.warning
          : entry.needsReview
          ? VibekitsColors.warning
          : context.vibe.success,
    ),
    title: Text(entry.name, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      assessment == null
          ? '${entry.kind.label} · '
                '${entry.canDelete
                    ? '可清理'
                    : entry.needsReview
                    ? '需复核'
                    : '正常'} · '
                '${entry.ownerLabel.isEmpty ? entry.reason : '${entry.ownerLabel} · ${entry.reason}'}'
          : '${entry.kind.label} · ${assessment.level.label} · '
                '${assessment.summary}\n${assessment.suggestedAction}',
      maxLines: assessment == null ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${entry.complete ? '' : '≥ '}${_formatSize(entry.sizeBytes)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (entry.canDelete) ...<Widget>[
          const SizedBox(width: 6),
          if (_deletingDrivePath == entry.path)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: '移到回收站',
              onPressed: _analyzingDrive || _deletingDrivePath != null
                  ? null
                  : () => _deleteDriveEntry(entry),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
        ],
      ],
    ),
  );

  Future<void> _deleteDriveEntry(SystemDriveUsageEntry entry) async {
    if (!entry.canDelete || _deletingDrivePath != null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('从空间列表清理？'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${entry.name} · ${_formatSize(entry.sizeBytes)}'),
              const SizedBox(height: 8),
              SelectableText(entry.path),
              const SizedBox(height: 8),
              Text(entry.reason),
              const SizedBox(height: 8),
              const Text('该项目将优先移入系统回收站；系统目录和程序安装目录不会在这里直接删除。'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移到回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingDrivePath = entry.path);
    final bool removed = widget.driveEntryRecycler != null
        ? await widget.driveEntryRecycler!(entry.path)
        : await Isolate.run<bool>(
            () => CleanupDeleter.sendToRecycleBin(<String>[entry.path]),
            debugName: 'vibekits-space-entry-delete',
          );
    if (!mounted) return;
    setState(() {
      _deletingDrivePath = null;
      _message = removed
          ? '已移到回收站：${entry.name}（${_formatSize(entry.sizeBytes)}）'
          : '无法清理 ${entry.name}；可能正在使用或权限不足';
    });
    if (removed) await _analyzeSystemDrive();
  }

  Future<void> _showDriveAnalysisReport(SystemDriveAnalysis analysis) async {
    final SystemDriveInsights insights = SystemDriveInsights.from(analysis);
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('${_shortVolumeName(analysis.rootPath)} 磁盘详细分析报告'),
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
                const SizedBox(height: 6),
                Text(
                  analysis.hasLogicalOvercount
                      ? '目录逻辑量 ${_formatSize(analysis.logicalMeasuredBytes)}，其中至少 '
                            '${_formatSize(analysis.logicalOvercountBytes)} 是 NTFS 硬链接重复计数；'
                            '各目录数字用于定位来源，不能相加当作物理占用。'
                      : '目录逻辑量 ${_formatSize(analysis.logicalMeasuredBytes)} · '
                            '未归类/系统保留 ${_formatSize(analysis.unaccountedBytes)}',
                  style: TextStyle(fontSize: 12, color: context.vibe.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  '${insights.storagePressure.label}：${insights.storagePressureSummary}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  insights.systemBaseline,
                  style: TextStyle(fontSize: 12, color: context.vibe.muted),
                ),
                const SizedBox(height: 10),
                for (final SystemDriveEntryAssessment item
                    in insights.assessments.where(
                      (SystemDriveEntryAssessment item) =>
                          !item.entry.isBreakdown,
                    ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${item.level.label} · ${item.entry.name} · '
                      '${item.entry.complete ? '' : '≥ '}'
                      '${_formatSize(item.entry.sizeBytes)}\n'
                      '${item.summary}；${item.suggestedAction}',
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
    final List<CleanupCandidate> visible = _candidatesForView(
      _cleanupResultView,
    );
    final Map<CleanupCategory, List<CleanupCandidate>> grouped =
        _groupCandidates(visible);
    return Column(
      children: <Widget>[
        _buildCleanupTaskNavigation(),
        Expanded(
          child: _cleanupResultView == _CleanupResultView.unusedSoftware
              ? _buildUnusedSoftwareTask()
              : visible.isEmpty
              ? Center(
                  child: Text(
                    '${_cleanupResultView.label}没有发现项目',
                    style: TextStyle(color: context.vibe.muted),
                  ),
                )
              : ListView(
                  children: <Widget>[
                    for (final MapEntry<CleanupCategory, List<CleanupCandidate>>
                        entry
                        in grouped.entries)
                      _buildCategory(entry.key, entry.value),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCleanupTaskNavigation() {
    return Container(
      height: 49,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.vibe.canvas,
        border: Border(bottom: BorderSide(color: context.vibe.border)),
      ),
      child: ListView.separated(
        key: const ValueKey<String>('cleanup-task-navigation'),
        scrollDirection: Axis.horizontal,
        itemCount: _CleanupResultView.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          final _CleanupResultView view = _CleanupResultView.values[index];
          final List<CleanupCandidate> items =
              view == _CleanupResultView.unusedSoftware
              ? const <CleanupCandidate>[]
              : _candidatesForView(view);
          final int bytes = items.fold<int>(
            0,
            (int total, CleanupCandidate item) => total + item.size,
          );
          return ChoiceChip(
            key: ValueKey<String>('cleanup-view-${view.name}'),
            selected: _cleanupResultView == view,
            onSelected: (_) => _selectCleanupView(view),
            avatar: Icon(view.icon, size: 16),
            label: Text(
              view == _CleanupResultView.unusedSoftware
                  ? '${view.label} · ${_installedApplications.length}'
                  : '${view.label} · ${items.length} · ${_formatSize(bytes)}',
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnusedSoftwareTask() {
    if (_loadingInstalledApplications) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<InstalledApplication> applications =
        List<InstalledApplication>.of(_installedApplications)..sort(
          (InstalledApplication left, InstalledApplication right) =>
              right.estimatedSizeBytes.compareTo(left.estimatedSizeBytes),
        );
    if (applications.isEmpty) {
      return const Center(child: Text('没有读取到可管理的已安装软件'));
    }
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          color: VibekitsColors.warning.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Text(
            '当前先按安装体积列出软件。没有可靠最近使用证据前，不会擅自标记为“不常用”；后续接入本地使用频率数据库。',
            style: TextStyle(fontSize: 11),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: applications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final InstalledApplication application = applications[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.apps_outlined, size: 19),
                title: Text(application.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${application.publisher.isEmpty ? '未知发布者' : application.publisher}'
                  '${application.version.isEmpty ? '' : ' · ${application.version}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      application.estimatedSizeBytes > 0
                          ? _formatSize(application.estimatedSizeBytes)
                          : '体积未知',
                      style: TextStyle(fontSize: 11, color: context.vibe.muted),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: application.canUninstall
                          ? () => _confirmInstalledApplicationUninstall(
                              application,
                            )
                          : null,
                      child: const Text('卸载'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmInstalledApplicationUninstall(
    InstalledApplication application,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('卸载 ${application.name}？'),
        content: const Text('将启动软件自己的 Windows 卸载器；Vibekits 不直接删除安装目录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('打开卸载器'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final bool launched = widget.applicationUninstallLauncher != null
        ? await widget.applicationUninstallLauncher!(application)
        : await InstalledApplicationService.launchUninstaller(application);
    if (mounted) {
      setState(() {
        _message = launched
            ? '已打开 ${application.name} 的卸载器'
            : '无法启动 ${application.name} 的卸载器';
      });
    }
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

  Future<void> _showCleanupHistory() async {
    List<CleanupReportEntry> reports = await CleanupReportWriter.list();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: const Text('清理日志'),
          content: SizedBox(
            width: 720,
            height: 480,
            child: reports.isEmpty
                ? const Center(child: Text('还没有清理记录'))
                : ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final CleanupReportEntry report = reports[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          report.failed > 0 || report.unreadable
                              ? Icons.error_outline
                              : report.cancelled
                              ? Icons.pause_circle_outline
                              : Icons.check_circle_outline,
                          size: 20,
                        ),
                        title: Text(
                          '${_formatLocalTime(report.finishedAt)} · '
                          '${_formatSize(report.releasedBytes)}',
                        ),
                        subtitle: Text(
                          report.unreadable
                              ? '日志损坏或无法读取'
                              : '成功 ${report.succeeded} · 跳过 ${report.skipped} · 失败 ${report.failed}'
                                    '${report.cancelled ? ' · 已取消' : ''}',
                        ),
                        onTap: report.unreadable
                            ? null
                            : () => _showStoredReport(report),
                        trailing: IconButton(
                          tooltip: '删除这条记录',
                          icon: const Icon(Icons.delete_outline, size: 19),
                          onPressed: () async {
                            final bool deleted =
                                await CleanupReportWriter.delete(report.file);
                            if (deleted) {
                              reports = List<CleanupReportEntry>.of(reports)
                                ..removeAt(index);
                              setDialogState(() {});
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStoredReport(CleanupReportEntry report) => showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('清理明细 · ${_formatLocalTime(report.finishedAt)}'),
      content: SizedBox(
        width: 760,
        height: 460,
        child: ListView.separated(
          itemCount: report.items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final Map<String, Object?> item = report.items[index];
            return ListTile(
              dense: true,
              title: SelectableText(
                item['path'] as String? ?? '旧版日志未记录路径',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                '${item['status'] ?? 'unknown'} · '
                '${_formatSize(item['size'] is int ? item['size']! as int : 0)} · '
                '${item['reason'] ?? ''}',
                style: const TextStyle(fontSize: 11),
              ),
            );
          },
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

  String _formatLocalTime(DateTime value) {
    final DateTime local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
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
    final bool requiresConfirmation = items.any(
      (CleanupCandidate item) => item.highRisk,
    );
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
            if (v == true && !candidate.highRisk) {
              _selected.add(candidate.path);
            } else {
              _selected.remove(candidate.path);
            }
          }
        }),
      ),
      title: Text(
        '${category.label}${requiresConfirmation ? '（高风险项需逐项选择）' : ''}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: requiresConfirmation
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
                    '${candidate.highRisk && candidate.riskLevel == CleanupRiskLevel.safe ? '需确认' : candidate.riskLevel.label} · ${candidate.reason} · ${_formatSize(candidate.size)}'
                    '${candidate.modified == null ? '' : ' · ${_formatDate(candidate.modified!)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    candidate.impactNote.isEmpty
                        ? candidate.path
                        : '${candidate.impactNote} · ${candidate.path}',
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
