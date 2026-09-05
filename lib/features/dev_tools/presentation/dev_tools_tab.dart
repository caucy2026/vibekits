import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/tool_registry.dart';
import '../domain/system_resource_service.dart';
import '../domain/remote_session.dart';
import '../domain/file_diff_service.dart';
import 'batch_rename_workspace.dart';
import 'adb_workspace.dart';
import 'api_workspace.dart';
import 'audio_debug_workspace.dart';
import 'database_workspace.dart';
import 'duplicate_files_workspace.dart';
import 'file_hash_workspace.dart';
import 'file_diff_workspace.dart';
import 'file_search_workspace.dart';
import 'git_workspace.dart';
import 'github_diagnostics_workspace.dart';
import 'network_virtualization_workspace.dart';
import 'packet_capture_workspace.dart';
import 'harness_tool_activity_dialog.dart';
import 'programmer_calculator_workspace.dart';
import 'remote_workspace.dart';
import 'windows_test_node_workspace.dart';
import 'serial_port_workspace.dart';
import 'system_resource_workspace.dart';
import 'stopwatch_workspace.dart';
import 'utility_collection_workspace.dart';

/// T4 开发工具 Tab。
///
/// 左侧为工具分组与搜索，右侧为通用输入/输出工作区。
/// M1 提供离线工具（DEV-001～DEV-003），网络与文件工具在 M6 补齐。
class DevToolsTab extends StatefulWidget {
  const DevToolsTab({
    super.key,
    this.fileHashPickFiles,
    this.fileHashCalculator,
    this.fileDiffPicker,
    this.fileDiffComparer,
    this.fileSearchDirectoryPicker,
    this.fileSearchRunner,
    this.fileSearchReveal,
    this.initialDatabasePath,
    this.initialAudioPath,
    this.databasePickFile,
    this.databaseInspect,
    this.databaseLoadPage,
    this.databaseRunQuery,
    this.initialRemoteDatabaseProfiles = const <String>[],
    this.onRemoteDatabaseProfilesChanged,
    this.remoteStartSession,
    this.initialRemoteSessionProfiles = const <String>[],
    this.onRemoteSessionProfilesChanged,
    this.remoteCredentialRead,
    this.remoteCredentialWrite,
    this.remoteCredentialDelete,
    this.remoteProfileIdGenerator,
    this.adbLoadSnapshot,
    this.rustDeskExecutable = '',
    this.initialAdbRecentAddresses = const <String>[],
    this.initialAdbCommandHistory = const <String>[],
    this.onAdbRecentAddressesChanged,
    this.onAdbCommandHistoryChanged,
    this.initialSerialPortSettings,
    this.initialSerialSendHistory = const <String>[],
    this.onSerialPortSettingsChanged,
    this.onSerialSendHistoryChanged,
    this.serialPortLister,
    this.serialPortOpener,
    this.apiExecute,
    this.initialApiRequestHistory = const <String>[],
    this.onApiRequestHistoryChanged,
    this.gitInspect,
    this.gitPickDirectory,
    this.gitBackupPreview,
    this.gitBackupCommit,
    this.gitBackupPush,
    this.githubDiagnostics,
    this.systemResourceInspector,
    this.initialToolId,
    this.remoteWorkspaceIntent,
    this.remoteWorkspaceIntentSerial = 0,
    this.onAskHarness,
  });

  final FileHashPicker? fileHashPickFiles;
  final FileHashCalculator? fileHashCalculator;
  final FileDiffPicker? fileDiffPicker;
  final FileDiffComparer? fileDiffComparer;
  final FileSearchDirectoryPicker? fileSearchDirectoryPicker;
  final FileSearchRunner? fileSearchRunner;
  final FileSearchReveal? fileSearchReveal;
  final String? initialDatabasePath;
  final String? initialAudioPath;
  final SqliteFilePicker? databasePickFile;
  final SqliteInspector? databaseInspect;
  final SqlitePageLoader? databaseLoadPage;
  final SqliteQueryRunner? databaseRunQuery;
  final List<String> initialRemoteDatabaseProfiles;
  final Future<void> Function(List<String> profiles)?
  onRemoteDatabaseProfilesChanged;
  final RemoteSessionStarter? remoteStartSession;
  final List<String> initialRemoteSessionProfiles;
  final Future<void> Function(List<String> profiles)?
  onRemoteSessionProfilesChanged;
  final RemoteCredentialReader? remoteCredentialRead;
  final RemoteCredentialWriter? remoteCredentialWrite;
  final RemoteCredentialDeleter? remoteCredentialDelete;
  final String Function()? remoteProfileIdGenerator;
  final AdbWorkspaceLoader? adbLoadSnapshot;
  final String rustDeskExecutable;
  final List<String> initialAdbRecentAddresses;
  final List<String> initialAdbCommandHistory;
  final Future<void> Function(List<String> history)?
  onAdbRecentAddressesChanged;
  final Future<void> Function(List<String> history)? onAdbCommandHistoryChanged;
  final String? initialSerialPortSettings;
  final List<String> initialSerialSendHistory;
  final Future<void> Function(String settings)? onSerialPortSettingsChanged;
  final Future<void> Function(List<String> history)? onSerialSendHistoryChanged;
  final SerialPortLister? serialPortLister;
  final SerialPortOpener? serialPortOpener;
  final ApiExecutor? apiExecute;
  final List<String> initialApiRequestHistory;
  final Future<void> Function(List<String> history)? onApiRequestHistoryChanged;
  final GitInspector? gitInspect;
  final GitDirectoryPicker? gitPickDirectory;
  final GitBackupPreviewer? gitBackupPreview;
  final GitBackupCommitter? gitBackupCommit;
  final GitBackupPusher? gitBackupPush;
  final GithubDiagnosticsRunner? githubDiagnostics;
  final Future<SystemResourceSnapshot> Function(String? adbSerial)?
  systemResourceInspector;
  final String? initialToolId;
  final RemoteWorkspaceIntent? remoteWorkspaceIntent;
  final int remoteWorkspaceIntentSerial;
  final Future<void> Function(String prompt)? onAskHarness;

  @override
  State<DevToolsTab> createState() => _DevToolsTabState();
}

class _DevToolsTabState extends State<DevToolsTab> {
  static const Set<String> _desktopRuntimeToolIds = <String>{
    'network_virtualization',
    'virtual_machine',
    'remote_workspace',
    'serial_port',
    'adb_workspace',
    'git_workspace',
    'github_diagnostics',
    'packet_capture',
  };

  String _query = '';
  ToolSpec _selected = devToolRegistry.first;
  late final PageController _toolPageController;
  String? _utilityInitialToolId;
  List<String> _hashInitialPaths = const <String>[];
  int _hashRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    final String initialToolId = widget.initialToolId?.trim() ?? '';
    if (initialToolId.isNotEmpty &&
        devToolRegistry.any((ToolSpec tool) => tool.id == initialToolId)) {
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == initialToolId,
      );
    } else if (widget.initialAudioPath != null) {
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'audio_analyzer',
      );
    } else if (widget.initialDatabasePath != null) {
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'database_manager',
      );
    } else if (widget.remoteWorkspaceIntent != null) {
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'remote_workspace',
      );
    }
    _toolPageController = PageController(
      initialPage: devToolRegistry.indexOf(_selected),
    );
  }

  @override
  void dispose() {
    _toolPageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DevToolsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.remoteWorkspaceIntent != null &&
        widget.remoteWorkspaceIntentSerial !=
            oldWidget.remoteWorkspaceIntentSerial) {
      setState(() {
        _selected = devToolRegistry.firstWhere(
          (ToolSpec tool) => tool.id == 'remote_workspace',
        );
      });
      _showSelectedToolPage();
    }
  }

  List<ToolSpec> get _filteredTools {
    if (_query.trim().isEmpty) {
      return devToolRegistry;
    }
    final String lower = _query.trim().toLowerCase();
    final List<ToolSpec> matches = devToolRegistry
        .where(
          (ToolSpec tool) =>
              tool.name.toLowerCase().contains(lower) ||
              tool.description.toLowerCase().contains(lower),
        )
        .toList();
    final bool utilityMatches = utilityToolRegistry.any(
      (ToolSpec tool) =>
          tool.name.toLowerCase().contains(lower) ||
          tool.description.toLowerCase().contains(lower) ||
          tool.group.toLowerCase().contains(lower),
    );
    if (utilityMatches &&
        !matches.any((ToolSpec tool) => tool.id == utilityCollectionTool.id)) {
      matches.add(utilityCollectionTool);
    }
    return matches;
  }

  Map<String, List<ToolSpec>> get _groupedTools {
    final Map<String, List<ToolSpec>> grouped = <String, List<ToolSpec>>{};
    for (final ToolSpec tool in _filteredTools) {
      grouped.putIfAbsent(tool.group, () => <ToolSpec>[]).add(tool);
    }
    return grouped;
  }

  void _selectTool(ToolSpec tool) {
    setState(() {
      _selected = tool;
      if (tool.id == 'file_hash') {
        _hashInitialPaths = const <String>[];
        _hashRequestSerial++;
      }
      if (tool.id == utilityCollectionTool.id && _query.trim().isNotEmpty) {
        final String lower = _query.trim().toLowerCase();
        _utilityInitialToolId = utilityToolRegistry
            .where(
              (ToolSpec item) =>
                  item.name.toLowerCase().contains(lower) ||
                  item.description.toLowerCase().contains(lower) ||
                  item.group.toLowerCase().contains(lower),
            )
            .firstOrNull
            ?.id;
      }
    });
    _showSelectedToolPage();
  }

  void _showSelectedToolPage() {
    final int index = devToolRegistry.indexWhere(
      (ToolSpec tool) => tool.id == _selected.id,
    );
    if (index < 0) return;
    if (_toolPageController.hasClients) {
      _toolPageController.jumpToPage(index);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _toolPageController.hasClients) {
        _toolPageController.jumpToPage(index);
      }
    });
  }

  void _openHashFor(String path) {
    setState(() {
      _hashInitialPaths = <String>[path];
      _hashRequestSerial++;
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'file_hash',
      );
    });
    _showSelectedToolPage();
  }

  @override
  Widget build(BuildContext context) {
    final bool mobile = Platform.isAndroid || Platform.isIOS;
    return Row(
      children: <Widget>[
        _buildSidebar(mobile: mobile),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _buildWorkArea()),
      ],
    );
  }

  Widget _buildSidebar({required bool mobile}) {
    return SizedBox(
      key: const Key('dev-tools-sidebar'),
      width: mobile ? 280 : 220,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const Key('dev-tool-search'),
              onChanged: (String value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '搜索工具',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (final MapEntry<String, List<ToolSpec>> entry
                    in _groupedTools.entries) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.vibe.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final ToolSpec tool in entry.value)
                    ListTile(
                      key: ValueKey<String>('dev-tool-nav-${tool.id}'),
                      dense: !mobile,
                      minTileHeight: mobile ? 56 : null,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: mobile ? 16 : 12,
                      ),
                      selected: tool.id == _selected.id,
                      title: Text(
                        tool.name,
                        style: TextStyle(fontSize: mobile ? 15 : 13),
                      ),
                      onTap: () => _selectTool(tool),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkArea() {
    return Column(
      children: <Widget>[
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.vibe.border)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _selected.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('current-tool-harness-activity'),
                onPressed: () => showHarnessToolActivityDialog(
                  context,
                  toolName: _selected.name,
                  toolIds: harnessToolIdsFor(_selected),
                ),
                icon: const Icon(Icons.history_rounded, size: 17),
                label: const Text('Harness 记录'),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            key: const Key('dev-tool-pages'),
            controller: _toolPageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devToolRegistry.length,
            itemBuilder: (BuildContext context, int index) =>
                _KeepAliveToolWorkspace(
                  child: KeyedSubtree(
                    key: PageStorageKey<String>(
                      'dev-tool-${devToolRegistry[index].id}',
                    ),
                    child: _buildToolArea(devToolRegistry[index]),
                  ),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolArea(ToolSpec tool) {
    if ((Platform.isAndroid || Platform.isIOS) &&
        _desktopRuntimeToolIds.contains(tool.id)) {
      return _buildMobileDesktopToolNotice(tool);
    }
    if (tool.id == 'programmer_calculator') {
      return const ProgrammerCalculatorWorkspace();
    }
    if (tool.id == 'stopwatch') {
      return const StopwatchWorkspace();
    }
    if (tool.id == 'system_resources') {
      return SystemResourceWorkspace(inspector: widget.systemResourceInspector);
    }
    if (tool.id == utilityCollectionTool.id) {
      return UtilityCollectionWorkspace(initialToolId: _utilityInitialToolId);
    }
    if (tool.id == 'database_manager') {
      return DatabaseWorkspace(
        initialPath: widget.initialDatabasePath,
        pickFile: widget.databasePickFile,
        inspect: widget.databaseInspect,
        loadPage: widget.databaseLoadPage,
        runQuery: widget.databaseRunQuery,
        initialRemoteProfiles: widget.initialRemoteDatabaseProfiles,
        onRemoteProfilesChanged: widget.onRemoteDatabaseProfilesChanged,
      );
    }
    if (tool.id == 'remote_workspace') {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: <Widget>[
            const TabBar(
              tabs: <Widget>[
                Tab(text: '远程终端（SSH/SFTP）'),
                Tab(text: '测试节点（Node）'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  RemoteWorkspace(
                    startSession: widget.remoteStartSession,
                    initialProfiles: widget.initialRemoteSessionProfiles,
                    onProfilesChanged: widget.onRemoteSessionProfilesChanged,
                    readCredential: widget.remoteCredentialRead,
                    writeCredential: widget.remoteCredentialWrite,
                    deleteCredential: widget.remoteCredentialDelete,
                    profileIdGenerator: widget.remoteProfileIdGenerator,
                    launchIntent: widget.remoteWorkspaceIntent,
                    launchIntentSerial: widget.remoteWorkspaceIntentSerial,
                  ),
                  const WindowsTestNodeWorkspace(),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (tool.id == 'serial_port') {
      return SerialPortWorkspace(
        initialSettings: widget.initialSerialPortSettings,
        initialSendHistory: widget.initialSerialSendHistory,
        onSettingsChanged: widget.onSerialPortSettingsChanged,
        onSendHistoryChanged: widget.onSerialSendHistoryChanged,
        listPorts: widget.serialPortLister,
        openSession: widget.serialPortOpener,
      );
    }
    if (tool.id == 'adb_workspace') {
      return AdbWorkspace(
        key: ValueKey<String>('adb-${widget.rustDeskExecutable}'),
        loadSnapshot: widget.adbLoadSnapshot,
        rustDeskExecutable: widget.rustDeskExecutable,
        initialRecentAddresses: widget.initialAdbRecentAddresses,
        initialCommandHistory: widget.initialAdbCommandHistory,
        onRecentAddressesChanged: widget.onAdbRecentAddressesChanged,
        onCommandHistoryChanged: widget.onAdbCommandHistoryChanged,
      );
    }
    if (tool.id == 'api_workspace') {
      return ApiWorkspace(
        execute: widget.apiExecute,
        initialHistory: widget.initialApiRequestHistory,
        onHistoryChanged: widget.onApiRequestHistoryChanged,
      );
    }
    if (tool.id == 'packet_capture') {
      return const PacketCaptureWorkspace();
    }
    if (tool.id == 'git_workspace') {
      return GitWorkspace(
        inspect: widget.gitInspect,
        pickDirectory: widget.gitPickDirectory,
        previewBackup: widget.gitBackupPreview,
        commitBackup: widget.gitBackupCommit,
        pushBackup: widget.gitBackupPush,
      );
    }
    if (tool.id == 'github_diagnostics') {
      return GithubDiagnosticsWorkspace(
        runDiagnostics: widget.githubDiagnostics,
      );
    }
    if (tool.id == 'network_virtualization') {
      return const NetworkVirtualizationWorkspace();
    }
    if (tool.id == 'virtual_machine') {
      return const NetworkVirtualizationWorkspace(virtualMachineOnly: true);
    }
    if (tool.id == 'audio_analyzer') {
      return AudioDebugWorkspace(initialPath: widget.initialAudioPath);
    }
    if (tool.id == 'batch_rename') {
      return const BatchRenameWorkspace();
    }
    if (tool.id == 'duplicate_files') {
      return const DuplicateFilesWorkspace();
    }
    if (tool.id == 'file_search') {
      return FileSearchWorkspace(
        directoryPicker: widget.fileSearchDirectoryPicker,
        searchRunner: widget.fileSearchRunner,
        reveal: widget.fileSearchReveal,
        onHashRequested: _openHashFor,
      );
    }
    if (tool.id == 'file_hash') {
      return FileHashWorkspace(
        key: ValueKey<int>(_hashRequestSerial),
        pickFiles: widget.fileHashPickFiles,
        calculate: widget.fileHashCalculator,
        initialPaths: _hashInitialPaths,
      );
    }
    if (tool.id == 'file_diff') {
      return FileDiffWorkspace(
        pickFile: widget.fileDiffPicker,
        compare: widget.fileDiffComparer ?? FileDiffService.compare,
      );
    }
    return const Center(child: Text('该工具暂不可用'));
  }

  Widget _buildMobileDesktopToolNotice(ToolSpec tool) {
    final String prompt =
        '请通过已登记的 Vibekits 桌面节点调用“${tool.name}”。'
        '先检查节点在线和权限，再执行，并把真实调用日志给我。';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.desktop_windows_outlined,
                size: 42,
                color: context.vibe.muted,
              ),
              const SizedBox(height: 14),
              Text(
                '${tool.name}需要桌面节点',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前是移动端，不会在手机上启动 Windows/macOS 二进制运行时，'
                '因此不会造成闪退。\n连接 Vibekits 桌面节点后，Harness 可调用该能力。',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.vibe.muted, height: 1.5),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  key: ValueKey<String>('mobile-ask-harness-${tool.id}'),
                  onPressed: widget.onAskHarness == null
                      ? null
                      : () => widget.onAskHarness!(prompt),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('让 Harness 连接桌面节点'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制 Harness 任务')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制任务'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveToolWorkspace extends StatefulWidget {
  const _KeepAliveToolWorkspace({required this.child});

  final Widget child;

  @override
  State<_KeepAliveToolWorkspace> createState() =>
      _KeepAliveToolWorkspaceState();
}

class _KeepAliveToolWorkspaceState extends State<_KeepAliveToolWorkspace>
    with AutomaticKeepAliveClientMixin<_KeepAliveToolWorkspace> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
