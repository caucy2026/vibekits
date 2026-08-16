import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/tool_registry.dart';
import '../domain/tool_result.dart';
import '../domain/deepseek_harness_service.dart';
import 'batch_rename_workspace.dart';
import 'api_workspace.dart';
import 'database_workspace.dart';
import 'deepseek_harness_workspace.dart';
import 'duplicate_files_workspace.dart';
import 'file_hash_workspace.dart';
import 'git_workspace.dart';
import 'github_diagnostics_workspace.dart';
import 'programmer_calculator_workspace.dart';
import 'remote_workspace.dart';

/// T4 开发工具 Tab。
///
/// 左侧为工具分组与搜索，右侧为通用输入/输出工作区。
/// M1 提供离线工具（DEV-001～DEV-003），网络与文件工具在 M6 补齐。
class DevToolsTab extends StatefulWidget {
  const DevToolsTab({
    super.key,
    this.fileHashPickFiles,
    this.fileHashCalculator,
    this.initialDatabasePath,
    this.databasePickFile,
    this.databaseInspect,
    this.databaseLoadPage,
    this.databaseRunQuery,
    this.initialRemoteDatabaseProfiles = const <String>[],
    this.onRemoteDatabaseProfilesChanged,
    this.remoteStartSession,
    this.apiExecute,
    this.gitInspect,
    this.gitPickDirectory,
    this.githubDiagnostics,
    this.initialHarnessWorkspace = '',
    this.onHarnessWorkspaceChanged,
    this.harnessCheckEnvironment = DeepSeekHarnessService.checkEnvironment,
    this.harnessStartSession = DeepSeekHarnessService.start,
    this.harnessOpenBrowser = DeepSeekHarnessService.openBrowser,
    this.harnessPickDirectory,
  });

  final FileHashPicker? fileHashPickFiles;
  final FileHashCalculator? fileHashCalculator;
  final String? initialDatabasePath;
  final SqliteFilePicker? databasePickFile;
  final SqliteInspector? databaseInspect;
  final SqlitePageLoader? databaseLoadPage;
  final SqliteQueryRunner? databaseRunQuery;
  final List<String> initialRemoteDatabaseProfiles;
  final Future<void> Function(List<String> profiles)?
  onRemoteDatabaseProfilesChanged;
  final RemoteSessionStarter? remoteStartSession;
  final ApiExecutor? apiExecute;
  final GitInspector? gitInspect;
  final GitDirectoryPicker? gitPickDirectory;
  final GithubDiagnosticsRunner? githubDiagnostics;
  final String initialHarnessWorkspace;
  final Future<void> Function(String workspace)? onHarnessWorkspaceChanged;
  final HarnessEnvironmentChecker harnessCheckEnvironment;
  final HarnessSessionStarter harnessStartSession;
  final HarnessBrowserOpener harnessOpenBrowser;
  final HarnessDirectoryPicker? harnessPickDirectory;

  @override
  State<DevToolsTab> createState() => _DevToolsTabState();
}

class _DevToolsTabState extends State<DevToolsTab> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _paramsController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();

  String _query = '';
  ToolSpec _selected = devToolRegistry.first;
  bool _outputIsError = false;
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDatabasePath != null) {
      _selected = devToolRegistry.firstWhere(
        (ToolSpec tool) => tool.id == 'database_manager',
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _paramsController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  List<ToolSpec> get _filteredTools {
    if (_query.trim().isEmpty) {
      return devToolRegistry;
    }
    final String lower = _query.trim().toLowerCase();
    return devToolRegistry
        .where(
          (ToolSpec tool) =>
              tool.name.toLowerCase().contains(lower) ||
              tool.description.toLowerCase().contains(lower),
        )
        .toList();
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
      _outputController.clear();
      _outputIsError = false;
    });
  }

  Future<void> _execute() async {
    final ToolSpec tool = _selected;
    setState(() => _executing = true);
    try {
      final ToolResult result = tool.runAsync != null
          ? await tool.runAsync!(_inputController.text, _paramsController.text)
          : tool.run!(_inputController.text, _paramsController.text);
      if (!mounted) return;
      setState(() {
        _executing = false;
        switch (result) {
          case ToolSuccess(:final String output):
            _outputController.text = output;
            _outputIsError = false;
          case ToolFailure(:final String message, :final int? position):
            _outputController.text = position == null
                ? message
                : '$message\n出错位置：$position';
            _outputIsError = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _outputController.text = '执行失败：$e';
        _outputIsError = true;
      });
    }
  }

  void _swap() {
    final String input = _inputController.text;
    final String output = _outputController.text;
    setState(() {
      _inputController.text = output;
      _outputController.clear();
      _outputIsError = false;
    });
    // 交换后输入更新，保留原输入作为提示性来源。
    if (input.isNotEmpty) {
      _outputController.text = '';
    }
  }

  void _clear() {
    setState(() {
      _inputController.clear();
      _outputController.clear();
      _outputIsError = false;
    });
  }

  Future<void> _copy() async {
    if (_outputController.text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _outputController.text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
    }
  }

  Future<void> _save() async {
    if (_outputController.text.isEmpty) {
      return;
    }
    final TextEditingController pathController = TextEditingController(
      text: '${Directory.systemTemp.path}${Platform.pathSeparator}output.txt',
    );
    final String? path = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('保存输出'),
          content: TextField(
            controller: pathController,
            autofocus: true,
            decoration: const InputDecoration(labelText: '目标文件路径'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(pathController.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      await File(path).writeAsString(_outputController.text, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已保存到 $path')));
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：${e.message}')));
      }
    }
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
    if (tool.id == 'deepseek_harness') {
      return DeepSeekHarnessWorkspace(
        initialWorkspace: widget.initialHarnessWorkspace,
        onWorkspaceChanged: widget.onHarnessWorkspaceChanged,
        checkEnvironment: widget.harnessCheckEnvironment,
        startSession: widget.harnessStartSession,
        openBrowser: widget.harnessOpenBrowser,
        pickDirectory: widget.harnessPickDirectory,
      );
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
      return RemoteWorkspace(startSession: widget.remoteStartSession);
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
    if (tool.id == 'file_hash') {
      return FileHashWorkspace(
        pickFiles: widget.fileHashPickFiles,
        calculate: widget.fileHashCalculator,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                tool.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              _OfflineBadge(offline: tool.offline),
              const Spacer(),
              Tooltip(
                message: tool.description,
                child: Icon(
                  Icons.help_outline,
                  size: 16,
                  color: context.vibe.muted,
                ),
              ),
            ],
          ),
          if (tool.paramLabel != null) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _paramsController,
                decoration: InputDecoration(
                  labelText: tool.paramLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 13),
              decoration: const InputDecoration(
                hintText: '输入',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              ElevatedButton(
                onPressed: _executing ? null : _execute,
                child: Text(_executing ? '执行中…' : '执行'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _outputController.text.isEmpty ? null : _swap,
                child: const Text('交换'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed:
                    _inputController.text.isEmpty &&
                        _outputController.text.isEmpty
                    ? null
                    : _clear,
                child: const Text('清空'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _outputController.text.isEmpty ? null : _copy,
                child: const Text('复制'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _outputController.text.isEmpty ? null : _save,
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _outputController,
              readOnly: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontFamily: 'Cascadia Mono',
                fontSize: 13,
                color: _outputIsError
                    ? VibekitsColors.danger
                    : Theme.of(context).colorScheme.onSurface,
              ),
              decoration: const InputDecoration(
                hintText: '输出',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: offline
            ? VibekitsColors.info.withValues(alpha: 0.10)
            : VibekitsColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        offline ? '离线' : '联网',
        style: TextStyle(
          fontSize: 11,
          color: offline ? VibekitsColors.info : VibekitsColors.warning,
        ),
      ),
    );
  }
}
