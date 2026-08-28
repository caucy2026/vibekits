import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/archive/presentation/archive_tab.dart';
import '../features/cleaner/presentation/cleaner_tab.dart';
import '../features/documents/presentation/documents_tab.dart';
import '../features/documents/domain/format_router.dart';
import '../features/dev_tools/presentation/dev_tools_tab.dart';
import '../features/dev_tools/domain/remote_session.dart';
import '../features/local_models/presentation/local_models_tab.dart';
import 'app_shortcuts.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'platform_storage_layout.dart';
import 'app_version.dart';
import 'android_display_context.dart';
import 'dropped_file_router.dart';
import 'supported_file_types.dart';
import 'windows_file_drop.dart';

/// 应用主窗口：侧边导航 + 模块标题栏 + 内容区 + 状态栏。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.settingsController,
    this.preapprovedHarnessToolIds = const <String>{},
    this.initialFilePath,
    this.initialFilePaths = const <String>[],
    this.initialWorkspaceId,
    this.droppedFiles,
    this.dropClassifier,
  });

  final AppSettingsController settingsController;
  final Set<String> preapprovedHarnessToolIds;
  final String? initialFilePath;
  final List<String> initialFilePaths;
  final String? initialWorkspaceId;
  final Stream<List<String>>? droppedFiles;
  final Future<DroppedFileRoute> Function(String path)? dropClassifier;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const List<String> _tabTitles = <String>[
    '智能体（Harness）',
    '解压缩',
    '系统清理',
    '文档阅读',
    '开发工具',
  ];

  static const List<String> _workspaceIds = <String>[
    'large-model',
    'archive',
    'cleaner',
    'documents',
    'dev-tools',
  ];

  static const List<IconData> _tabIcons = <IconData>[
    Icons.auto_awesome_outlined,
    Icons.folder_zip_outlined,
    Icons.cleaning_services_outlined,
    Icons.article_outlined,
    Icons.construction_outlined,
  ];

  static const List<String> _tabDescriptions = <String>[
    '开发智能体（Harness）、任务会话与截图识别（OCR）',
    '安全查看、创建与提取压缩文件',
    '扫描可清理空间并生成可核对报告',
    '快速查看文本、结构化数据与二进制文件',
    '独立开发工作区与转换检查工具',
  ];

  int _selectedIndex = 0;
  AndroidDisplayContext? _androidDisplayContext;
  final List<int> _mobileNavigationHistory = <int>[];
  bool _hasUserSelectedTab = false;
  late final Set<int> _loadedTabs;
  final ValueNotifier<int> _openRequest = ValueNotifier<int>(0);
  final ValueNotifier<int> _findRequest = ValueNotifier<int>(0);
  final ValueNotifier<int> _saveRequest = ValueNotifier<int>(0);
  String? _archiveDropPath;
  String? _documentDropPath;
  DocViewMode? _documentDropMode;
  String? _modelDropPath;
  String? _imageDropPath;
  String? _databaseDropPath;
  String? _audioDropPath;
  int _archiveDropSerial = 0;
  int _documentDropSerial = 0;
  int _modelDropSerial = 0;
  int _imageDropSerial = 0;
  int _databaseDropSerial = 0;
  int _audioDropSerial = 0;
  RemoteWorkspaceIntent? _remoteWorkspaceIntent;
  int _remoteWorkspaceIntentSerial = 0;
  String _harnessExternalPrompt = '';
  int _harnessExternalPromptSerial = 0;
  int _dropGeneration = 0;
  List<DroppedFileRoute> _dropBatch = const <DroppedFileRoute>[];
  StreamSubscription<List<String>>? _dropSubscription;

  @override
  void initState() {
    super.initState();
    final AppSettings settings = widget.settingsController.value;
    final VibekitsFileKind startupKind = widget.initialFilePath == null
        ? VibekitsFileKind.unsupported
        : SupportedFileTypes.kindForPath(widget.initialFilePath!);
    _selectedIndex = switch (startupKind) {
      VibekitsFileKind.archive => 1,
      VibekitsFileKind.document => 3,
      VibekitsFileKind.database => 4,
      VibekitsFileKind.image => 0,
      VibekitsFileKind.model => 0,
      VibekitsFileKind.audio => 4,
      VibekitsFileKind.unsupported =>
        settings.restoreLastTab ? _indexForWorkspace(settings) : 0,
    };
    final int requestedWorkspace = _workspaceIds.indexOf(
      widget.initialWorkspaceId ?? '',
    );
    if (startupKind == VibekitsFileKind.unsupported &&
        requestedWorkspace >= 0) {
      _selectedIndex = requestedWorkspace;
    }
    // Android starts with Harness. In dual-display mode this exact same widget
    // tree spans the full 1920x2560 canvas; no second route is created.
    if (Platform.isAndroid && startupKind == VibekitsFileKind.unsupported) {
      _selectedIndex = 0;
    }
    // First frame contains only the navigation shell. Heavy workspaces are
    // mounted on the next frame so a click always produces visible UI before
    // disk discovery, WebView/DSH startup or model inspection begins.
    _loadedTabs = <int>{};
    if (Platform.isAndroid && startupKind == VibekitsFileKind.unsupported) {
      unawaited(_resolveAndroidDisplayContext());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _loadedTabs.add(_selectedIndex));
    });
    widget.settingsController.addListener(_applySettings);
    final bool supportsNativeDrop = Platform.isWindows || Platform.isMacOS;
    if (widget.droppedFiles != null) {
      _dropSubscription = widget.droppedFiles!.listen(_handleDroppedFiles);
    } else if (supportsNativeDrop) {
      WindowsFileDrop.instance.start();
      _dropSubscription = WindowsFileDrop.instance.files.listen(
        _handleDroppedFiles,
      );
    }
    if (widget.initialFilePath != null &&
        startupKind == VibekitsFileKind.unsupported) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleDroppedFiles(<String>[widget.initialFilePath!]),
      );
    }
    if (widget.initialFilePaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleDroppedFiles(widget.initialFilePaths),
      );
    }
  }

  Future<void> _resolveAndroidDisplayContext() async {
    try {
      final AndroidDisplayContext display = await AndroidDisplayContext.read();
      if (!mounted) return;
      setState(() {
        _androidDisplayContext = display;
      });
    } on MissingPluginException {
      // Widget tests and non-embedded Android runners keep the primary role.
    } on PlatformException {
      // A display-context failure must not block the usable Harness workspace.
    }
  }

  void _applySettings() {
    if (widget.initialFilePath != null || widget.initialFilePaths.isNotEmpty) {
      return;
    }
    final AppSettings settings = widget.settingsController.value;
    int restoredIndex = _indexForWorkspace(settings);
    if (Platform.isAndroid && !_hasUserSelectedTab) {
      restoredIndex = 0;
    }
    if (settings.restoreLastTab && restoredIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = restoredIndex;
        if (Platform.isAndroid || Platform.isIOS) {
          _loadedTabs
            ..clear()
            ..add(restoredIndex);
        } else {
          _loadedTabs.add(restoredIndex);
        }
      });
    }
  }

  static int _indexForWorkspace(AppSettings settings) {
    final int stableIndex = _workspaceIds.indexOf(settings.lastWorkspaceId);
    return stableIndex >= 0
        ? stableIndex
        : settings.lastTab.clamp(0, 4).toInt();
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_applySettings);
    _openRequest.dispose();
    _findRequest.dispose();
    _saveRequest.dispose();
    _dropSubscription?.cancel();
    super.dispose();
  }

  void _selectTab(int index, {bool recordMobileHistory = true}) {
    if (index < 0 || index >= _tabTitles.length) {
      return;
    }
    if (index == _selectedIndex) return;
    _hasUserSelectedTab = true;
    final bool mobile = Platform.isAndroid || Platform.isIOS;
    if (mobile && recordMobileHistory) {
      _mobileNavigationHistory.remove(index);
      _mobileNavigationHistory.add(_selectedIndex);
    }
    final bool needsLoad = !_loadedTabs.contains(index);
    setState(() {
      _selectedIndex = index;
      // Desktop keeps workspaces alive for instant switching. Mobile keeps
      // only the visible workspace mounted so OCR, archive and database state
      // cannot accumulate into an ever-growing background memory footprint.
      if (mobile && !needsLoad) {
        _loadedTabs
          ..clear()
          ..add(index);
      }
    });
    if (needsLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedIndex != index) return;
        setState(() {
          if (mobile) _loadedTabs.clear();
          _loadedTabs.add(index);
        });
      });
    }
    if (widget.settingsController.value.restoreLastTab) {
      unawaited(
        widget.settingsController.updateInBackground(
          widget.settingsController.value.copyWith(
            lastTab: index,
            lastWorkspaceId: _workspaceIds[index],
          ),
        ),
      );
    }
  }

  Future<void> _openHarnessWithPrompt(String prompt) async {
    _selectTab(0);
    if (!mounted) return;
    setState(() {
      _harnessExternalPrompt = prompt;
      _harnessExternalPromptSerial++;
    });
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => _SettingsDialog(
        initial: widget.settingsController.value,
        onSave: widget.settingsController.update,
      ),
    );
  }

  Future<void> _handleDroppedFiles(List<String> paths) async {
    if (!mounted) return;
    final int generation = ++_dropGeneration;
    final Future<DroppedFileRoute> Function(String path) classifier =
        widget.dropClassifier ?? DroppedFileRouter.classify;
    final List<DroppedFileRoute> routes = await Future.wait(
      paths.map(classifier),
    );
    if (!mounted || generation != _dropGeneration) return;
    final DroppedFileRoute? first = routes
        .where((DroppedFileRoute route) => route.canOpen)
        .firstOrNull;
    setState(() {
      _dropBatch = routes;
    });
    if (first != null) _openDroppedRoute(first);
    final int rejected = routes
        .where((DroppedFileRoute route) => !route.canOpen)
        .length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            routes.isEmpty
                ? '没有收到可处理的路径'
                : routes.length == 1
                ? first == null
                      ? routes.single.detail
                      : '${routes.single.detail}：${_fileName(routes.single.path)}'
                : '已逐项识别 ${routes.length} 个项目，可打开 ${routes.length - rejected} 个${rejected == 0 ? '' : '，$rejected 个需注意'}；当前显示 ${first == null ? '处理清单' : _fileName(first.path)}',
          ),
          action: routes.length > 1 || rejected > 0
              ? SnackBarAction(label: '查看清单', onPressed: _showDropBatch)
              : null,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  void _openDroppedRoute(DroppedFileRoute route) {
    if (!route.canOpen) return;
    final bool archive = route.kind == DroppedFileRouteKind.archive;
    final bool model = route.kind == DroppedFileRouteKind.model;
    final bool image = route.kind == DroppedFileRouteKind.image;
    final bool database = route.kind == DroppedFileRouteKind.database;
    final bool audio = route.kind == DroppedFileRouteKind.audio;
    _selectTab(
      archive
          ? 1
          : model || image
          ? 0
          : database || audio
          ? 4
          : 3,
    );
    setState(() {
      if (archive) {
        _archiveDropPath = route.path;
        _archiveDropSerial++;
      } else if (model) {
        _modelDropPath = route.path;
        _modelDropSerial++;
      } else if (image) {
        _imageDropPath = route.path;
        _imageDropSerial++;
      } else if (database) {
        _databaseDropPath = route.path;
        _databaseDropSerial++;
      } else if (audio) {
        _audioDropPath = route.path;
        _audioDropSerial++;
      } else {
        _documentDropPath = route.path;
        _documentDropMode = route.documentMode;
        _documentDropSerial++;
      }
    });
  }

  Future<void> _openRemoteWorkspace(RemoteWorkspaceIntent intent) async {
    intent.validate();
    _selectTab(4);
    if (!mounted) return;
    setState(() {
      _remoteWorkspaceIntent = intent;
      _remoteWorkspaceIntentSerial++;
    });
  }

  Future<void> _showDropBatch() async {
    if (!mounted || _dropBatch.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('本次拖入 · ${_dropBatch.length} 项'),
        content: SizedBox(
          width: 620,
          height: (MediaQuery.sizeOf(dialogContext).height * 0.58).clamp(
            260,
            520,
          ),
          child: ListView.separated(
            itemCount: _dropBatch.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final DroppedFileRoute route = _dropBatch[index];
              final bool archive = route.kind == DroppedFileRouteKind.archive;
              final bool model = route.kind == DroppedFileRouteKind.model;
              final bool image = route.kind == DroppedFileRouteKind.image;
              final bool database = route.kind == DroppedFileRouteKind.database;
              return ListTile(
                key: ValueKey<String>('drop-route-${route.path}'),
                enabled: route.canOpen,
                leading: Icon(
                  route.canOpen
                      ? archive
                            ? Icons.folder_zip_outlined
                            : model
                            ? Icons.memory_outlined
                            : image
                            ? Icons.image_outlined
                            : database
                            ? Icons.storage_outlined
                            : Icons.description_outlined
                      : Icons.warning_amber_outlined,
                ),
                title: Text(
                  route.path.isEmpty ? '空路径' : _fileName(route.path),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  route.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: route.canOpen
                    ? const Icon(Icons.open_in_new, size: 17)
                    : null,
                onTap: route.canOpen
                    ? () {
                        Navigator.of(dialogContext).pop();
                        _openDroppedRoute(route);
                      }
                    : null,
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
    );
  }

  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = widget.settingsController.value;
    final List<Widget> allTabPages = <Widget>[
      LocalModelsTab(
        key: ValueKey<String>(
          '${settings.modelDirectory}|${settings.toolDownloadDirectory}|'
          '${settings.deepSeekHarnessDebugDirectory}|$_modelDropSerial|'
          '$_imageDropSerial',
        ),
        directory: settings.modelDirectory,
        toolDownloadDirectory: settings.toolDownloadDirectory,
        rustDeskExecutable: settings.rustDeskExecutable,
        rustDeskWebClientUrl: settings.rustDeskWebClientUrl,
        preapprovedHarnessToolIds: widget.preapprovedHarnessToolIds,
        initialImportPath:
            _modelDropPath ??
            (SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                    VibekitsFileKind.model
                ? widget.initialFilePath
                : null),
        initialImagePath:
            _imageDropPath ??
            (SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                    VibekitsFileKind.image
                ? widget.initialFilePath
                : null),
        initialLargeModelView: Platform.isAndroid
            ? 'agent'
            : settings.lastLargeModelView,
        onLargeModelViewChanged: (String view) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                lastLargeModelView: view,
              ),
            ),
        initialHarnessWorkspace: settings.deepSeekHarnessWorkspace,
        onHarnessWorkspaceChanged: (String workspace) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                deepSeekHarnessWorkspace: workspace,
              ),
            ),
        initialHarnessDebugDirectory: settings.deepSeekHarnessDebugDirectory,
        onHarnessDebugDirectoryChanged: (String directory) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                deepSeekHarnessDebugDirectory: directory,
              ),
            ),
        remoteWorkspaceLauncher: _openRemoteWorkspace,
        externalHarnessPrompt: _harnessExternalPrompt,
        externalHarnessPromptSerial: _harnessExternalPromptSerial,
      ),
      ArchiveTab(
        key: ValueKey<String>('archive-drop-$_archiveDropSerial'),
        openRequest: _openRequest,
        initialPath:
            _archiveDropPath ??
            (SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                    VibekitsFileKind.archive
                ? widget.initialFilePath
                : null),
        maxEntries: settings.archiveMaxEntries,
        maxSingleExpandedBytes: settings.archiveMaxFileMb * 1024 * 1024,
      ),
      CleanerTab(
        harnessDebugDirectory: settings.deepSeekHarnessDebugDirectory,
        onAskHarness: _openHarnessWithPrompt,
        initialWhitelist: settings.cleanupWhitelist,
        initialTargetIds: settings.cleanupScanTargets,
        initialTargetCatalogVersion: settings.cleanupTargetCatalogVersion,
        initialTotalReleasedBytes: settings.cleanupTotalReleasedBytes,
        initialCompletedRuns: settings.cleanupCompletedRuns,
        onWhitelistChanged: (List<String> whitelist) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                cleanupWhitelist: whitelist,
              ),
            ),
        onTargetIdsChanged: (List<String> targetIds, int catalogVersion) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                cleanupScanTargets: targetIds,
                cleanupTargetCatalogVersion: catalogVersion,
              ),
            ),
        onCleanupStatsChanged: (int totalReleasedBytes, int completedRuns) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                cleanupTotalReleasedBytes: totalReleasedBytes,
                cleanupCompletedRuns: completedRuns,
              ),
            ),
      ),
      DocumentsTab(
        key: ValueKey<String>('document-drop-$_documentDropSerial'),
        openRequest: _openRequest,
        findRequest: _findRequest,
        saveRequest: _saveRequest,
        initialPath:
            _documentDropPath ??
            (SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                    VibekitsFileKind.document
                ? widget.initialFilePath
                : null),
        initialMode: _documentDropPath == null ? null : _documentDropMode,
        initialRecentPaths: settings.recentDocumentPaths,
        onRecentPathsChanged: (List<String> paths) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                recentDocumentPaths: paths,
              ),
            ),
      ),
      DevToolsTab(
        key: ValueKey<String>(
          'dev-drop-$_databaseDropSerial-$_audioDropSerial',
        ),
        initialAudioPath:
            _audioDropPath ??
            (SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                    VibekitsFileKind.audio
                ? widget.initialFilePath
                : null),
        initialDatabasePath:
            _databaseDropPath ??
            (SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                    VibekitsFileKind.database
                ? widget.initialFilePath
                : null),
        initialRemoteDatabaseProfiles: settings.remoteDatabaseProfiles,
        onRemoteDatabaseProfilesChanged: (List<String> profiles) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                remoteDatabaseProfiles: profiles,
              ),
            ),
        initialRemoteSessionProfiles: settings.remoteSessionProfiles,
        onRemoteSessionProfilesChanged: (List<String> profiles) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                remoteSessionProfiles: profiles,
              ),
            ),
        initialSerialPortSettings: settings.serialPortSettings,
        initialSerialSendHistory: settings.serialSendHistory,
        onSerialPortSettingsChanged: (String serialSettings) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                serialPortSettings: serialSettings,
              ),
            ),
        onSerialSendHistoryChanged: (List<String> history) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                serialSendHistory: history,
              ),
            ),
        initialAdbRecentAddresses: settings.adbRecentAddresses,
        initialAdbCommandHistory: settings.adbCommandHistory,
        onAdbRecentAddressesChanged: (List<String> history) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                adbRecentAddresses: history,
              ),
            ),
        onAdbCommandHistoryChanged: (List<String> history) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                adbCommandHistory: history,
              ),
            ),
        initialApiRequestHistory: settings.apiRequestHistory,
        onApiRequestHistoryChanged: (List<String> history) =>
            widget.settingsController.updateInBackground(
              widget.settingsController.value.copyWith(
                apiRequestHistory: history,
              ),
            ),
        remoteWorkspaceIntent: _remoteWorkspaceIntent,
        remoteWorkspaceIntentSerial: _remoteWorkspaceIntentSerial,
        onAskHarness: _openHarnessWithPrompt,
        initialToolId: null,
      ),
    ];
    final List<Widget> tabPages = List<Widget>.generate(
      allTabPages.length,
      (int index) => _loadedTabs.contains(index)
          ? allTabPages[index]
          : const _DeferredWorkspace(),
      growable: false,
    );
    final Map<ShortcutActivator, VoidCallback> shortcuts =
        AppShortcuts.forShell(
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
          onOpen: () {
            if (_selectedIndex == 1 || _selectedIndex == 3) {
              _openRequest.value++;
            }
          },
          onFind: () {
            if (_selectedIndex == 3) _findRequest.value++;
          },
          onSave: () {
            if (_selectedIndex == 3) _saveRequest.value++;
          },
        );

    final bool mobile = Platform.isAndroid || Platform.isIOS;
    return PopScope<Object?>(
      canPop: !mobile || _mobileNavigationHistory.isEmpty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || !mobile || _mobileNavigationHistory.isEmpty) return;
        final int previous = _mobileNavigationHistory.removeLast();
        _selectTab(previous, recordMobileHistory: false);
      },
      child: CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: !mobile,
          child: Scaffold(
            body: SafeArea(
              bottom: !mobile,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool useSidebar =
                      !mobile && constraints.maxWidth >= 1180;
                  if (!useSidebar) {
                    return Column(
                      children: <Widget>[
                        _buildTopBar(context, compact: true),
                        if (!mobile) _buildCompactNavigation(context),
                        Expanded(child: _buildWorkspace(context, tabPages)),
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      _buildNavigation(context),
                      Expanded(child: _buildWorkspace(context, tabPages)),
                    ],
                  );
                },
              ),
            ),
            bottomNavigationBar: mobile
                ? NavigationBar(
                    key: const Key('primary-navigation-mobile'),
                    height: 76,
                    selectedIndex: _selectedIndex,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    onDestinationSelected: _selectTab,
                    destinations: List<NavigationDestination>.generate(
                      _tabTitles.length,
                      (int index) => NavigationDestination(
                        icon: Icon(_tabIcons[index]),
                        selectedIcon: Icon(_tabIcons[index], fill: 1),
                        label: _tabTitles[index]
                            .replaceAll('（智能体）', '')
                            .replaceAll('系统', ''),
                        tooltip: _tabTitles[index],
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, List<Widget> tabPages) {
    final bool mobile = Platform.isAndroid || Platform.isIOS;
    return Column(
      children: <Widget>[
        if (MediaQuery.sizeOf(context).width >= 1180) _buildTopBar(context),
        Expanded(
          child: Padding(
            padding: mobile
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Material(
              color: context.vibe.panelRaised,
              elevation: mobile ? 0 : 2,
              shadowColor: context.vibe.glow,
              clipBehavior: Clip.antiAlias,
              shape: mobile
                  ? const RoundedRectangleBorder()
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: context.vibe.border),
                    ),
              child: IndexedStack(index: _selectedIndex, children: tabPages),
            ),
          ),
        ),
        if (!mobile) _buildStatusBar(context),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, {bool compact = false}) {
    return Container(
      height: compact ? 60 : 76,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      child: Row(
        children: <Widget>[
          if (compact) ...<Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'V',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _tabTitles[_selectedIndex],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    _tabDescriptions[_selectedIndex],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (!compact) ...<Widget>[
            _StatusPill(
              icon: Icons.shield_outlined,
              label: '隐私优先',
              color: context.vibe.success,
            ),
            const SizedBox(width: 8),
          ],
          if (_dropBatch.length > 1) ...<Widget>[
            IconButton(
              key: const Key('drop-batch-button'),
              tooltip: '查看本次拖入的 ${_dropBatch.length} 个项目',
              onPressed: _showDropBatch,
              icon: Badge(
                label: Text('${_dropBatch.length}'),
                child: const Icon(Icons.file_copy_outlined),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (compact &&
              _androidDisplayContext?.isContinuousCanvas == true) ...<Widget>[
            _StatusPill(
              icon: Icons.vertical_align_center,
              label: '连续画布 · 1920×2560',
              color: context.vibe.success,
            ),
            const SizedBox(width: 4),
          ],
          if (Platform.isAndroid)
            IconButton(
              key: const Key('android-exit-app'),
              tooltip: '退出应用（关闭两屏）',
              onPressed: _exitAndroidApp,
              icon: const Icon(Icons.logout_rounded),
            ),
          IconButton(
            key: const Key('app-settings-button'),
            tooltip: '设置 (Ctrl+,)',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _exitAndroidApp() async {
    try {
      await AndroidDisplayContext.exitApp();
    } on PlatformException {
      await SystemNavigator.pop();
    } on MissingPluginException {
      await SystemNavigator.pop();
    }
  }

  Widget _buildCompactNavigation(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool iconsOnly = constraints.maxWidth < 760;
        return Container(
          key: const Key('primary-navigation-compact'),
          height: 58,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: context.vibe.panel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.vibe.border),
          ),
          child: Row(
            children: List<Widget>.generate(_tabTitles.length, (int index) {
              final bool selected = index == _selectedIndex;
              final Color color = selected
                  ? Theme.of(context).colorScheme.primary
                  : context.vibe.muted;
              return Expanded(
                child: Tooltip(
                  message: _tabTitles[index],
                  child: Semantics(
                    selected: selected,
                    button: true,
                    child: Material(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                                .withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: ValueKey<String>(
                          'compact-nav-${_tabTitles[index]}',
                        ),
                        onTap: () => _selectTab(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(_tabIcons[index], size: 18, color: color),
                            if (!iconsOnly) ...<Widget>[
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  _tabTitles[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildNavigation(BuildContext context) {
    return Container(
      key: const Key('primary-navigation'),
      width: 216,
      decoration: BoxDecoration(
        color: context.vibe.panel,
        border: Border(right: BorderSide(color: context.vibe.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: context.vibe.glow, blurRadius: 14),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'V',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Vibekits',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'LOCAL TOOLKIT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.vibe.muted,
                          letterSpacing: 1.1,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '工作台',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: context.vibe.muted, letterSpacing: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          ...List<Widget>.generate(_tabTitles.length, (int index) {
            final bool selected = index == _selectedIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _NavigationItem(
                key: ValueKey<String>('nav-${_tabTitles[index]}'),
                icon: _tabIcons[index],
                label: _tabTitles[index],
                shortcut: '${index + 1}',
                selected: selected,
                onTap: () => _selectTab(index),
              ),
            );
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.vibe.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.lock_outline, size: 16, color: context.vibe.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '数据默认留在本机',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'VIBEKITS  ·  ${AppVersion.display}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: context.vibe.muted, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: 7, color: context.vibe.success),
          const SizedBox(width: 7),
          Text('系统就绪', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            '${AppVersion.display} · 文件默认本机处理',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? Theme.of(context).colorScheme.primary
        : context.vibe.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.26),
                    )
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 19, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).textTheme.bodyMedium?.color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  shortcut,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontFamily: 'Cascadia Mono',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeferredWorkspace extends StatelessWidget {
  const _DeferredWorkspace();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(height: 12),
        Text('界面已就绪，正在加载工作区…'),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial, required this.onSave});

  final AppSettings initial;
  final Future<void> Function(AppSettings) onSave;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late AppSettings _value = widget.initial;
  late final TextEditingController _modelDirectory = TextEditingController(
    text: _value.modelDirectory,
  );
  late final TextEditingController _harnessDebugDirectory =
      TextEditingController(text: _value.deepSeekHarnessDebugDirectory);
  late final TextEditingController _toolDownloadDirectory =
      TextEditingController(text: _value.toolDownloadDirectory);
  late final TextEditingController _rustDeskExecutable = TextEditingController(
    text: _value.rustDeskExecutable,
  );
  late final TextEditingController _rustDeskWebClientUrl =
      TextEditingController(text: _value.rustDeskWebClientUrl);

  PlatformStorageLayout get _storage => PlatformStorageLayout.current();

  String _storageAccessText() {
    final PlatformStorageAccessReport? report =
        PlatformStorageLayout.lastAccessReport;
    if (report == null) return '可写状态：尚未探测';
    final String status = report.allRequiredWritable ? '全部已验证可写' : '存在不可写目录';
    final String temporary = report.persistentDataUsesTemporaryStorage
        ? ' · 警告：持久数据正在使用临时应急目录'
        : '';
    final String fallbacks = report.fallbacks.isEmpty
        ? ''
        : '\n自动切换：${report.fallbacks.join('；')}';
    return '可写状态：$status$temporary$fallbacks';
  }

  String get _defaultDebugDirectory => _storage.harnessDebugDirectory;

  String get _defaultToolDownloadDirectory {
    return _storage.downloadsDirectory;
  }

  Future<void> _pickDirectory(TextEditingController controller) async {
    final String? selected = await getDirectoryPath(
      initialDirectory: controller.text.trim().isEmpty
          ? null
          : controller.text.trim(),
      confirmButtonText: '使用此目录',
    );
    if (selected != null && mounted) {
      setState(() => controller.text = selected);
    }
  }

  Future<void> _pickRustDeskExecutable() async {
    final XFile? selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'RustDesk 客户端', extensions: <String>['exe']),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _rustDeskExecutable.text = selected.path);
    }
  }

  @override
  void dispose() {
    _modelDirectory.dispose();
    _harnessDebugDirectory.dispose();
    _toolDownloadDirectory.dispose();
    _rustDeskExecutable.dispose();
    _rustDeskWebClientUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<ThemeMode>(
                key: const Key('theme-mode'),
                initialValue: _value.themeMode,
                decoration: const InputDecoration(labelText: '主题'),
                items: const <DropdownMenuItem<ThemeMode>>[
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
                onChanged: (ThemeMode? mode) {
                  if (mode != null) {
                    setState(() => _value = _value.copyWith(themeMode: mode));
                  }
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('恢复上次打开的标签页'),
                value: _value.restoreLastTab,
                onChanged: (bool enabled) => setState(
                  () => _value = _value.copyWith(restoreLastTab: enabled),
                ),
              ),
              DropdownButtonFormField<AppLogLevel>(
                initialValue: _value.logLevel,
                decoration: const InputDecoration(labelText: '日志级别'),
                items: AppLogLevel.values
                    .map(
                      (AppLogLevel level) => DropdownMenuItem<AppLogLevel>(
                        value: level,
                        child: Text(level.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (AppLogLevel? level) {
                  if (level != null) {
                    setState(() => _value = _value.copyWith(logLevel: level));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _value.cacheLimitMb.toString(),
                decoration: const InputDecoration(
                  labelText: '缓存上限（MB，64–8192）',
                ),
                keyboardType: TextInputType.number,
                onChanged: (String text) {
                  final int? number = int.tryParse(text);
                  if (number != null && number >= 64 && number <= 8192) {
                    _value = _value.copyWith(cacheLimitMb: number);
                  }
                },
              ),
              const SizedBox(height: 12),
              Container(
                key: const Key('platform-storage-locations'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.vibe.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.vibe.border),
                ),
                child: SelectableText(
                  '${_storage.platform.toUpperCase()} 存储位置\n'
                  '设置：${_storage.settingsFile}\n'
                  '缓存：${_storage.cacheDirectory}\n'
                  '凭据：${_storage.credentialStoreLabel}\n'
                  '${_storageAccessText()}',
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelDirectory,
                decoration: const InputDecoration(labelText: '模型目录（留空使用默认目录）'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('harness-debug-directory'),
                controller: _harnessDebugDirectory,
                decoration: InputDecoration(
                  labelText: '智能体调试临时目录（Harness）',
                  helperText: '默认：$_defaultDebugDirectory',
                  suffixIcon: IconButton(
                    tooltip: '选择目录',
                    onPressed: () => _pickDirectory(_harnessDebugDirectory),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('tool-download-directory'),
                controller: _toolDownloadDirectory,
                decoration: InputDecoration(
                  labelText: '工具与模型下载目录',
                  helperText: '默认：$_defaultToolDownloadDirectory',
                  suffixIcon: IconButton(
                    tooltip: '选择目录',
                    onPressed: () => _pickDirectory(_toolDownloadDirectory),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('rustdesk-executable'),
                controller: _rustDeskExecutable,
                decoration: InputDecoration(
                  labelText: 'RustDesk 客户端路径',
                  helperText: '留空时自动查找已安装的 RustDesk',
                  suffixIcon: IconButton(
                    tooltip: '选择 RustDesk.exe',
                    onPressed: _pickRustDeskExecutable,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('rustdesk-web-client-url'),
                controller: _rustDeskWebClientUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'RustDesk 网页端地址',
                  helperText: '留空自动从 RustDesk 推导 /web；不保存远程控制密码',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      initialValue: _value.archiveMaxEntries.toString(),
                      decoration: const InputDecoration(labelText: '解压最大条目数'),
                      keyboardType: TextInputType.number,
                      onChanged: (String text) {
                        final int? number = int.tryParse(text);
                        if (number != null &&
                            number >= 1000 &&
                            number <= 1000000) {
                          _value = _value.copyWith(archiveMaxEntries: number);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _value.archiveMaxFileMb.toString(),
                      decoration: const InputDecoration(labelText: '单文件上限（MB）'),
                      keyboardType: TextInputType.number,
                      onChanged: (String text) {
                        final int? number = int.tryParse(text);
                        if (number != null &&
                            number >= 64 &&
                            number <= 102400) {
                          _value = _value.copyWith(archiveMaxFileMb: number);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final NavigatorState navigator = Navigator.of(context);
            await widget.onSave(
              _value.copyWith(
                modelDirectory: _modelDirectory.text.trim(),
                deepSeekHarnessDebugDirectory: _harnessDebugDirectory.text
                    .trim(),
                toolDownloadDirectory: _toolDownloadDirectory.text.trim(),
                rustDeskExecutable: _rustDeskExecutable.text.trim(),
                rustDeskWebClientUrl: _rustDeskWebClientUrl.text.trim(),
              ),
            );
            if (mounted) navigator.pop();
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
