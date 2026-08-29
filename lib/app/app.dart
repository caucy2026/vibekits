import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/dev_tools/domain/harness_tool_activity_store.dart';
import '../features/dev_tools/domain/harness_tool_bridge.dart';
import '../features/dev_tools/domain/harness_agent_preferences.dart';
import '../features/dev_tools/domain/harness_tool_server.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'dropped_file_router.dart';
import 'main_shell.dart';

/// Vibekits 应用根组件。
class VibekitsApp extends StatefulWidget {
  const VibekitsApp({
    super.key,
    this.settingsController,
    this.initialFilePath,
    this.initialFilePaths = const <String>[],
    this.initialWorkspaceId,
    this.preapprovedExternalToolIds = const <String>{},
    this.droppedFiles,
    this.dropClassifier,
  });

  final AppSettingsController? settingsController;
  final String? initialFilePath;
  final List<String> initialFilePaths;
  final String? initialWorkspaceId;
  final Set<String> preapprovedExternalToolIds;
  final Stream<List<String>>? droppedFiles;
  final Future<DroppedFileRoute> Function(String path)? dropClassifier;

  @override
  State<VibekitsApp> createState() => _VibekitsAppState();
}

class _VibekitsAppState extends State<VibekitsApp> {
  static final bool _isFlutterTest = Platform.environment.containsKey(
    'FLUTTER_TEST',
  );

  late final AppSettingsController _settings =
      widget.settingsController ?? AppSettingsController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  HarnessToolServer? _externalToolServer;
  Future<void>? _settingsLoad;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
    if (widget.settingsController == null) {
      _settingsLoad = _settings.load();
    }
    // The external Harness/MCP endpoint is a desktop integration. Starting a
    // local socket server on Android adds cold-start work and keeps resources
    // alive without providing a usable mobile workflow.
    if (!_isFlutterTest && !Platform.isAndroid && !Platform.isIOS) {
      unawaited(_startExternalToolServer());
    }
  }

  Future<void> _startExternalToolServer() async {
    try {
      await _settingsLoad;
      final HarnessToolServer server = await HarnessToolServer.start(
        bridge: VibekitsHarnessToolBridge(
          activityRecorder: HarnessToolActivityStore.record,
          downloadDirectory: _settings.value.toolDownloadDirectory,
        ),
        approve: _approveExternalTool,
        connectionFile: HarnessToolServer.defaultConnectionFile(),
      );
      if (!mounted) {
        await server.close();
        return;
      }
      _externalToolServer = server;
    } on Object {
      // MCP is an optional integration. A publishing failure must never block
      // the desktop UI or unrelated offline tools.
    }
  }

  Future<bool> _approveExternalTool(HarnessToolApprovalRequest request) async {
    final HarnessAgentPermissionMode permissionMode =
        await HarnessAgentPreferencesStore.loadPermissionMode();
    if (request.tool.risk == HarnessToolRisk.readOnly ||
        widget.preapprovedExternalToolIds.contains(request.tool.id) ||
        permissionMode == HarnessAgentPermissionMode.fullAccess ||
        (permissionMode == HarnessAgentPermissionMode.assisted &&
            request.tool.risk != HarnessToolRisk.destructive)) {
      return true;
    }
    if (!mounted) return false;
    final BuildContext? navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return false;
    final bool? approved = await showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('允许外部智能体调用 ${request.tool.name}？'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(request.tool.description),
              if (request.target.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('目标：${request.target}'),
              ],
              const SizedBox(height: 12),
              const Text('本次批准只用于这一项工具调用，不会自动批准后续操作。'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('允许一次'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    final HarnessToolServer? server = _externalToolServer;
    if (server != null) unawaited(server.close());
    if (widget.settingsController == null) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Vibekits',
      debugShowCheckedModeBanner: false,
      theme: VibekitsTheme.light(),
      darkTheme: VibekitsTheme.dark(),
      themeMode: _settings.value.themeMode,
      home: MainShell(
        settingsController: _settings,
        preapprovedHarnessToolIds: widget.preapprovedExternalToolIds,
        initialFilePath: widget.initialFilePath,
        initialFilePaths: widget.initialFilePaths,
        initialWorkspaceId: widget.initialWorkspaceId,
        droppedFiles: widget.droppedFiles,
        dropClassifier: widget.dropClassifier,
      ),
    );
  }
}
