import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/tool_registry.dart';
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
import 'harness_tool_activity_dialog.dart';
import 'programmer_calculator_workspace.dart';
import 'remote_workspace.dart';
import 'windows_test_node_workspace.dart';
import 'serial_port_workspace.dart';
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
    this.initialSerialPortSettings,
    this.onSerialPortSettingsChanged,
    this.serialPortLister,
    this.serialPortOpener,
    this.apiExecute,
    this.gitInspect,
    this.gitPickDirectory,
    this.gitBackupPreview,
    this.gitBackupCommit,
    this.gitBackupPush,
    this.githubDiagnostics,
    this.remoteWorkspaceIntent,
    this.remoteWorkspaceIntentSerial = 0,
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
  final String? initialSerialPortSettings;
  final Future<void> Function(String settings)? onSerialPortSettingsChanged;
  final SerialPortLister? serialPortLister;
  final SerialPortOpener? serialPortOpener;
  final ApiExecutor? apiExecute;
  final GitInspector? gitInspect;
  final GitDirectoryPicker? gitPickDirectory;
  final GitBackupPreviewer? gitBackupPreview;
  final GitBackupCommitter? gitBackupCommit;
  final GitBackupPusher? gitBackupPush;
  final GithubDiagnosticsRunner? githubDiagnostics;
  final RemoteWorkspaceIntent? remoteWorkspaceIntent;
  final int remoteWorkspaceIntentSerial;

  @override
  State<DevToolsTab> createState() => _DevToolsTabState();
}

class _DevToolsTabState extends State<DevToolsTab> {
  String _query = '';
  ToolSpec _selected = devToolRegistry.first;
  late final PageController _toolPageController;
  String? _utilityInitialToolId;
  List<String> _hashInitialPaths = const <String>[];
  int _hashRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialAudioPath != null) {
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
    return Row(
      children: <Widget>[
        _buildSidebar(),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _buildWorkArea()),
      ],
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      key: const Key('dev-tools-sidebar'),
      width: 220,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
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
                      dense: true,
                      selected: tool.id == _selected.id,
                      title: Text(
                        tool.name,
                        style: const TextStyle(fontSize: 13),
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
    if (tool.id == 'programmer_calculator') {
      return const ProgrammerCalculatorWorkspace();
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
                Tab(text: 'SSH / SFTP'),
                Tab(text: '测试节点'),
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
        onSettingsChanged: widget.onSerialPortSettingsChanged,
        listPorts: widget.serialPortLister,
        openSession: widget.serialPortOpener,
      );
    }
    if (tool.id == 'adb_workspace') {
      return AdbWorkspace(loadSnapshot: widget.adbLoadSnapshot);
    }
    if (tool.id == 'api_workspace') {
      return ApiWorkspace(execute: widget.apiExecute);
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
