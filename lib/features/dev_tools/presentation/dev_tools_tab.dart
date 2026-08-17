import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/tool_registry.dart';
import 'batch_rename_workspace.dart';
import 'adb_workspace.dart';
import 'api_workspace.dart';
import 'database_workspace.dart';
import 'duplicate_files_workspace.dart';
import 'file_hash_workspace.dart';
import 'file_search_workspace.dart';
import 'git_workspace.dart';
import 'github_diagnostics_workspace.dart';
import 'programmer_calculator_workspace.dart';
import 'remote_workspace.dart';
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
    this.fileSearchDirectoryPicker,
    this.fileSearchRunner,
    this.fileSearchReveal,
    this.initialDatabasePath,
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
    this.githubDiagnostics,
  });

  final FileHashPicker? fileHashPickFiles;
  final FileHashCalculator? fileHashCalculator;
  final FileSearchDirectoryPicker? fileSearchDirectoryPicker;
  final FileSearchRunner? fileSearchRunner;
  final FileSearchReveal? fileSearchReveal;
  final String? initialDatabasePath;
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
  final GithubDiagnosticsRunner? githubDiagnostics;

  @override
  State<DevToolsTab> createState() => _DevToolsTabState();
}

class _DevToolsTabState extends State<DevToolsTab> {
  String _query = '';
  ToolSpec _selected = devToolRegistry.first;
  String? _utilityInitialToolId;
  List<String> _hashInitialPaths = const <String>[];
  int _hashRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialDatabasePath != null) {
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'database_manager',
      );
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
  }

  void _openHashFor(String path) {
    setState(() {
      _hashInitialPaths = <String>[path];
      _hashRequestSerial++;
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'file_hash',
      );
    });
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
    final ToolSpec tool = _selected;
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
      return RemoteWorkspace(
        startSession: widget.remoteStartSession,
        initialProfiles: widget.initialRemoteSessionProfiles,
        onProfilesChanged: widget.onRemoteSessionProfilesChanged,
        readCredential: widget.remoteCredentialRead,
        writeCredential: widget.remoteCredentialWrite,
        deleteCredential: widget.remoteCredentialDelete,
        profileIdGenerator: widget.remoteProfileIdGenerator,
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
      );
    }
    if (tool.id == 'github_diagnostics') {
      return GithubDiagnosticsWorkspace(
        runDiagnostics: widget.githubDiagnostics,
      );
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
    return const Center(child: Text('该工具暂不可用'));
  }
}
