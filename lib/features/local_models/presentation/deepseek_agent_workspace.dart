import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_theme.dart';
import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/feishu_harness_tasks.dart';
import '../../dev_tools/domain/harness_agent_preferences.dart';
import '../../dev_tools/domain/harness_conversation_store.dart';
import '../../dev_tools/domain/harness_work_status.dart';
import '../../dev_tools/domain/harness_tool_activity_store.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/lan_harness_key_receiver.dart';
import '../../dev_tools/domain/lan_peer_discovery_service.dart';
import '../../dev_tools/domain/lmcp_exposure_server.dart';
import '../../dev_tools/domain/mcp_capability_directory.dart';
import '../../dev_tools/domain/mcp_capability_models.dart';
import '../../dev_tools/domain/mcp_device_identity.dart';
import '../../dev_tools/domain/mcp_tool_reputation_store.dart';
import 'mcp_exposure_consent_dialog.dart';
import 'mcp_reputation_badge.dart';
import '../../dev_tools/domain/platform_credential_store.dart';
import '../../dev_tools/domain/rustdesk_harness_link_status.dart';

typedef AgentDirectoryPicker = Future<String?> Function();
typedef AgentCredentialReader = Future<String?> Function(String key);
typedef AgentCredentialWriter = Future<void> Function(String key, String value);

String _initialHarnessWorkspace(String configured) {
  final String value = configured.trim();
  if (!Platform.isAndroid && !Platform.isIOS) return value;
  if (value.isNotEmpty && Directory(value).isAbsolute) {
    try {
      Directory(value).createSync(recursive: true);
      return value;
    } on Object {
      // Fall through to the app-owned mobile workspace.
    }
  }
  final Directory directory = Directory(
    '${Directory.systemTemp.parent.path}${Platform.pathSeparator}files'
    '${Platform.pathSeparator}Vibekits${Platform.pathSeparator}workspace',
  );
  directory.createSync(recursive: true);
  return directory.path;
}

class DeepSeekAgentWorkspace extends StatefulWidget {
  const DeepSeekAgentWorkspace({
    super.key,
    this.initialWorkspace = '',
    this.onWorkspaceChanged,
    this.initialDebugDirectory = '',
    this.onDebugDirectoryChanged,
    this.onRunningChanged,
    this.checkEnvironment = DeepSeekHarnessService.checkEnvironment,
    this.runAgent = DeepSeekHarnessService.startAgent,
    this.listModels = DeepSeekHarnessService.listModels,
    this.pickDirectory,
    this.debugDirectoryPicker,
    this.credentialReader,
    this.credentialWriter,
    this.loadConversation = HarnessConversationStore.load,
    this.saveConversation = HarnessConversationStore.save,
    this.loadWorkspaceCatalog = HarnessConversationStore.loadWorkspaceCatalog,
    this.saveWorkspaceCatalog = HarnessConversationStore.saveWorkspaceCatalog,
    this.loadPermissionMode = HarnessAgentPreferencesStore.loadPermissionMode,
    this.savePermissionMode = HarnessAgentPreferencesStore.savePermissionMode,
    this.externalPrompt = '',
    this.externalPromptSerial = 0,
  });

  final String initialWorkspace;
  final Future<void> Function(String workspace)? onWorkspaceChanged;
  final String initialDebugDirectory;
  final Future<void> Function(String directory)? onDebugDirectoryChanged;
  final ValueChanged<bool>? onRunningChanged;
  final HarnessEnvironmentChecker checkEnvironment;
  final HarnessAgentRunner runAgent;
  final HarnessModelLister listModels;
  final AgentDirectoryPicker? pickDirectory;
  final AgentDirectoryPicker? debugDirectoryPicker;
  final AgentCredentialReader? credentialReader;
  final AgentCredentialWriter? credentialWriter;
  final HarnessConversationLoader loadConversation;
  final HarnessConversationSaver saveConversation;
  final HarnessWorkspaceCatalogLoader loadWorkspaceCatalog;
  final HarnessWorkspaceCatalogSaver saveWorkspaceCatalog;
  final HarnessAgentPermissionLoader loadPermissionMode;
  final HarnessAgentPermissionSaver savePermissionMode;
  final String externalPrompt;
  final int externalPromptSerial;

  @override
  State<DeepSeekAgentWorkspace> createState() => _DeepSeekAgentWorkspaceState();
}

class _DeepSeekAgentWorkspaceState extends State<DeepSeekAgentWorkspace> {
  static const String _credentialKey = 'deepseek-api-key';
  static const List<String> _builtinModels = <String>[
    'deepseek-v4-flash',
    'deepseek-v4-pro',
  ];
  static const String _customModelValue = '__custom__';
  static const int _maxContextCharacters = 12000;
  static final RegExp _ansiEscape = RegExp(
    r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\))',
  );

  late final TextEditingController _workspace = TextEditingController(
    text: _initialHarnessWorkspace(widget.initialWorkspace),
  );
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController(
    text: DeepSeekHarnessService.defaultBaseUrl,
  );
  final TextEditingController _model = TextEditingController(
    text: DeepSeekHarnessService.defaultModel,
  );
  late final TextEditingController _debugDirectory = TextEditingController(
    text: widget.initialDebugDirectory.trim().isEmpty
        ? DeepSeekHarnessService.defaultDebugDirectory()
        : widget.initialDebugDirectory.trim(),
  );
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _workspaceSearch = TextEditingController();
  final List<_AgentMessage> _messages = <_AgentMessage>[];
  final List<HarnessConversationSession> _sessions =
      <HarnessConversationSession>[];
  final List<String> _workspaceCatalog = <String>[];
  final Map<String, String> _workspaceNames = <String, String>{};
  final Map<String, List<HarnessConversationSession>> _workspaceSessions =
      <String, List<HarnessConversationSession>>{};
  final Set<String> _collapsedWorkspaces = <String>{};
  final Map<String, String> _sessionDrafts = <String, String>{};
  String? _activeSessionId;
  HarnessWorkspaceStatusContext? _workStatusContext;
  bool _restoringComposerDraft = false;
  HarnessEnvironmentReport? _environment;
  final Map<String, _HarnessSessionRun> _sessionRuns =
      <String, _HarnessSessionRun>{};
  final List<_AgentProgressStep> _idleProgressSteps = <_AgentProgressStep>[];
  bool _checking = true;
  bool _reportedAnyRunning = false;
  HarnessAgentPermissionMode _permissionMode =
      HarnessAgentPermissionMode.assisted;
  bool _progressExpanded = false;
  int _idleProgressSequence = 0;
  int _conversationEpoch = 0;
  final McpDeviceIdentity _mcpIdentity = McpDeviceIdentity.forVibekits();
  final McpExposurePreferences _mcpExposurePreferences =
      McpExposurePreferences();
  bool _mcpExposureEnabled = false;
  bool _mcpExposureChanging = false;
  VibekitsHarnessToolBridge? _mcpExposureBridge;
  bool _sessionSidebarOpen = true;
  bool _workspaceSearchOpen = false;
  bool _workspaceCatalogLoading = true;
  bool _showScrollToLatest = false;

  String _sessionRunKey(String workspace, String sessionId) =>
      '$workspace\u0000$sessionId';

  _HarnessSessionRun? get _activeRun {
    final String workspace = _workspace.text.trim();
    final String? sessionId = _activeSessionId;
    if (workspace.isEmpty || sessionId == null) return null;
    return _sessionRuns[_sessionRunKey(workspace, sessionId)];
  }

  bool get _running => _activeRun != null;
  bool get _stopping => _activeRun?.stopping ?? false;
  HarnessAgentHandle? get _handle => _activeRun?.handle;
  List<_AgentProgressStep> get _progressSteps =>
      _activeRun?.progressSteps ?? _idleProgressSteps;

  bool _isSessionRunning(String workspace, String sessionId) =>
      _sessionRuns.containsKey(_sessionRunKey(workspace, sessionId));

  @override
  void initState() {
    super.initState();
    _composer.addListener(_captureComposerDraft);
    _scroll.addListener(_updateScrollToLatest);
    _adoptExternalPrompt();
    unawaited(_loadSettings());
    unawaited(_restoreConversation(widget.initialWorkspace));
    unawaited(_initializeWorkspaceCatalog());
    // Socket/timer behavior has dedicated LMCP tests. Ordinary widget tests
    // must not start the process-lifetime LAN discovery singleton.
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      unawaited(_initializeMcp());
    }
    _checkEnvironment();
  }

  Future<void> _initializeMcp() async {
    try {
      final bool shouldEnable = await _mcpExposurePreferences.loadEnabled();
      await LanPeerDiscoveryService.instance.start(
        instanceId: _mcpIdentity.instanceId,
        name: _mcpIdentity.displayName,
        hardwareCode: _mcpIdentity.hardwareCode,
        appId: _mcpIdentity.appId,
        appVersion: VibekitsLmcpExposureServer.currentAppVersion,
        capabilityDigest: VibekitsHarnessToolBridge.protocolVersion,
        exposureEnabled: false,
      );
      final VibekitsHarnessToolBridge bridge = _createMcpBridge();
      _mcpExposureBridge = bridge;
      await McpCapabilityDirectory.instance.start(appBridge: bridge);
      if (shouldEnable) await _startMcpExposure(bridge);
      _mcpExposureEnabled = VibekitsLmcpExposureServer.instance.running;
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) _show('MCP 局域网发现启动失败：$error');
    }
  }

  VibekitsHarnessToolBridge _createMcpBridge({
    bool agentOrchestrated = false,
    _HarnessSessionRun? run,
  }) => VibekitsHarnessToolBridge(
    activityRecorder:
        ({
          required String toolId,
          required String toolName,
          required String target,
          required Map<String, Object?> arguments,
          required Object? result,
          required HarnessToolActivityStatus status,
          required DateTime startedAt,
        }) => _recordHarnessToolActivity(
          run: run,
          toolId: toolId,
          toolName: toolName,
          target: target,
          arguments: arguments,
          result: result,
          status: status,
          startedAt: startedAt,
        ),
    mcpCatalogLoader: McpCapabilityDirectory.instance.exportForHarness,
    mcpToolInvoker:
        (String instanceId, String toolName, Map<String, Object?> arguments) =>
            McpCapabilityDirectory.instance.invokeTool(
              instanceId: instanceId,
              toolName: toolName,
              arguments: arguments,
            ),
    mcpSchedulePlanner: (String toolName, String taskId) =>
        McpCapabilityDirectory.instance.planScheduledTool(
          toolName: toolName,
          taskId: taskId,
        ),
    mcpAutoInvoker:
        (
          toolName,
          taskId,
          idempotencyKey,
          scopeDigest,
          arguments,
          requestedSlots,
          ttlSeconds,
        ) => McpCapabilityDirectory.instance.scheduleAndInvoke(
          toolName: toolName,
          taskId: taskId,
          idempotencyKey: idempotencyKey,
          scopeDigest: scopeDigest,
          arguments: arguments,
          requestedSlots: requestedSlots,
          ttlSeconds: ttlSeconds,
        ),
    mcpReputationLoader: McpCapabilityDirectory.instance.exportReputations,
    mcpReputationRater:
        (String tier, String instanceId, String toolName, int rating) =>
            McpCapabilityDirectory.instance.rateTool(
              tierName: tier,
              instanceId: instanceId,
              toolName: toolName,
              rating: rating,
            ),
    agentOrchestrated: agentOrchestrated,
    agentActive: agentOrchestrated && run != null
        ? () =>
              _sessionRuns[_sessionRunKey(run.workspace, run.sessionId)] ==
                  run &&
              !run.stopRequested
        : null,
  );

  Future<void> _startMcpExposure(VibekitsHarnessToolBridge bridge) =>
      VibekitsLmcpExposureServer.instance.start(
        instanceId: _mcpIdentity.instanceId,
        displayName: _mcpIdentity.displayName,
        appId: _mcpIdentity.appId,
        appVersion: VibekitsLmcpExposureServer.currentAppVersion,
        hardwareCode: _mcpIdentity.hardwareCode,
        bridge: bridge,
      );

  @override
  void didUpdateWidget(covariant DeepSeekAgentWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String restored = widget.initialWorkspace.trim();
    if (!_running &&
        restored != oldWidget.initialWorkspace.trim() &&
        restored != _workspace.text.trim()) {
      unawaited(_adoptWorkspace(restored, notify: false));
    }
    if (widget.externalPromptSerial != oldWidget.externalPromptSerial) {
      _adoptExternalPrompt();
    }
  }

  void _adoptExternalPrompt() {
    final String prompt = widget.externalPrompt.trim();
    if (prompt.isEmpty) return;
    _composer
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _composerFocus.requestFocus();
    });
  }

  Future<void> _loadSettings() async {
    try {
      final HarnessAgentPermissionMode permissionMode = await widget
          .loadPermissionMode();
      if (mounted) setState(() => _permissionMode = permissionMode);
      if (Platform.environment['FLUTTER_TEST'] == 'true' &&
          widget.credentialReader == null) {
        return;
      }
      _apiKey.text =
          await (widget.credentialReader ?? PlatformCredentialStore.read)(
            _credentialKey,
          ) ??
          '';
      if (mounted) setState(() {});
    } on Object {
      // Manual entry remains available when the system store is unavailable.
    }
  }

  @override
  void dispose() {
    _captureComposerDraft();
    unawaited(_persistConversation());
    _conversationEpoch++;
    for (final _HarnessSessionRun run in _sessionRuns.values) {
      run.outputSubscription?.cancel();
      run.handle?.stop();
    }
    _workspace.dispose();
    _composer
      ..removeListener(_captureComposerDraft)
      ..dispose();
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _debugDirectory.dispose();
    _composerFocus.dispose();
    _scroll
      ..removeListener(_updateScrollToLatest)
      ..dispose();
    _workspaceSearch.dispose();
    final HarnessWorkspaceStatusContext? workStatusContext = _workStatusContext;
    if (workStatusContext != null) {
      HarnessWorkStatusHub.clearWorkspace(workStatusContext);
    }
    super.dispose();
  }

  String get _composerDraftKey =>
      '${_workspace.text.trim()}::${_activeSessionId ?? 'new-session'}';

  void _captureComposerDraft() {
    if (_restoringComposerDraft) return;
    _sessionDrafts[_composerDraftKey] = _composer.text;
  }

  void _restoreComposerDraft() {
    final String draft = _sessionDrafts[_composerDraftKey] ?? '';
    _restoringComposerDraft = true;
    _composer
      ..text = draft
      ..selection = TextSelection.collapsed(offset: draft.length);
    _restoringComposerDraft = false;
  }

  void _syncHarnessWorkspaceStatus() {
    final String current = _workspace.text.trim();
    final Set<String> runningWorkspaces = _sessionRuns.values
        .map((_HarnessSessionRun run) => run.workspace)
        .toSet();
    HarnessWorkStatusHub.syncWorkspaceInventory(<HarnessWorkspaceSummary>[
      for (final String workspace in _workspaceCatalog)
        HarnessWorkspaceSummary(
          workspaceRef: workspace,
          label: _workspaceDisplayName(workspace),
          active: workspace == current || runningWorkspaces.contains(workspace),
        ),
    ]);
    final HarnessWorkspaceStatusContext? previous = _workStatusContext;
    if (previous != null) HarnessWorkStatusHub.clearWorkspace(previous);
    if (current.isEmpty) {
      _workStatusContext = null;
      return;
    }
    _workStatusContext = HarnessWorkStatusHub.activateWorkspace(
      workspaceRef: current,
      workspaceLabel: _workspaceDisplayName(current),
      sessionRef: _activeSessionId ?? 'workspace-inventory',
    );
    if (_sessionRuns.isNotEmpty) {
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.reasoning,
        message: _sessionRuns.length == 1
            ? 'Harness 有 1 个会话正在运行'
            : 'Harness 有 ${_sessionRuns.length} 个会话正在并行运行',
      );
    }
  }

  void _notifyRunningState() {
    final bool value = _sessionRuns.isNotEmpty;
    if (_reportedAnyRunning == value) return;
    _reportedAnyRunning = value;
    widget.onRunningChanged?.call(value);
  }

  Future<void> _checkEnvironment() async {
    setState(() => _checking = true);
    try {
      final HarnessEnvironmentReport report = await widget.checkEnvironment();
      if (!mounted) return;
      setState(() {
        _environment = report;
        _checking = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _environment = HarnessEnvironmentReport(
          ready: false,
          nodeVersion: null,
          npxVersion: null,
          message: '环境检查失败：$error',
        );
        _checking = false;
      });
    }
  }

  Future<void> _pickWorkspace() async {
    final String? path = widget.pickDirectory == null
        ? await getDirectoryPath(
            initialDirectory: _workspace.text.trim().isEmpty
                ? null
                : _workspace.text.trim(),
          )
        : await widget.pickDirectory!();
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _adoptWorkspace(path.trim());
    if (!mounted) return;
    _composerFocus.requestFocus();
  }

  Future<void> _initializeWorkspaceCatalog() async {
    final String current = _workspace.text.trim();
    if (Platform.environment['FLUTTER_TEST'] == 'true' &&
        widget.loadWorkspaceCatalog ==
            HarnessConversationStore.loadWorkspaceCatalog) {
      if (!mounted) return;
      setState(() {
        _workspaceCatalog
          ..clear()
          ..addAll(<String>[if (current.isNotEmpty) current]);
        _workspaceCatalogLoading = false;
      });
      _syncHarnessWorkspaceStatus();
      return;
    }
    List<String> workspaces;
    Map<String, String> workspaceNames = <String, String>{};
    try {
      workspaces = await widget.loadWorkspaceCatalog();
      if (widget.loadWorkspaceCatalog ==
          HarnessConversationStore.loadWorkspaceCatalog) {
        workspaceNames = await HarnessConversationStore.loadWorkspaceNames();
      }
    } on Object {
      workspaces = <String>[];
    }
    final List<String> merged = <String>[
      if (current.isNotEmpty) current,
      ...workspaces.where((String item) => item.trim() != current),
    ];
    final Map<String, List<HarnessConversationSession>> projects =
        <String, List<HarnessConversationSession>>{};
    for (final String workspace in merged) {
      try {
        final HarnessConversationProject? project = await widget
            .loadConversation(workspace);
        projects[workspace] = List<HarnessConversationSession>.of(
          project?.sessions ?? const <HarnessConversationSession>[],
        );
      } on Object {
        projects[workspace] = <HarnessConversationSession>[];
      }
    }
    if (!mounted) return;
    setState(() {
      _workspaceCatalog
        ..clear()
        ..addAll(merged.take(HarnessConversationStore.maxWorkspaces));
      _workspaceNames
        ..clear()
        ..addAll(workspaceNames);
      _workspaceSessions
        ..clear()
        ..addAll(projects);
      _workspaceCatalogLoading = false;
    });
    _syncHarnessWorkspaceStatus();
    if (current.isNotEmpty && !workspaces.contains(current)) {
      await _saveWorkspaceCatalog();
    }
  }

  Future<void> _registerWorkspace(String workspace) async {
    final String target = workspace.trim();
    if (target.isEmpty || _workspaceCatalog.contains(target)) return;
    _workspaceCatalog.insert(0, target);
    _workspaceSessions.putIfAbsent(
      target,
      () => <HarnessConversationSession>[],
    );
    if (_workspaceCatalog.length > HarnessConversationStore.maxWorkspaces) {
      final String removed = _workspaceCatalog.removeLast();
      _workspaceSessions.remove(removed);
    }
    if (mounted) setState(() {});
    _syncHarnessWorkspaceStatus();
    await _saveWorkspaceCatalog();
  }

  Future<void> _saveWorkspaceCatalog() async {
    try {
      if (Platform.environment['FLUTTER_TEST'] == 'true' &&
          widget.saveWorkspaceCatalog ==
              HarnessConversationStore.saveWorkspaceCatalog) {
        return;
      }
      await widget.saveWorkspaceCatalog(
        List<String>.unmodifiable(_workspaceCatalog),
      );
    } on Object catch (error) {
      if (mounted) _show('保存工作区列表失败：$error');
    }
  }

  String _workspaceDisplayName(String workspace) =>
      _workspaceNames[workspace] ??
      workspace.replaceAll('\\', '/').split('/').last;

  Future<void> _renameWorkspace(String workspace) async {
    String draft = _workspaceDisplayName(workspace);
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('修改项目名称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              key: const Key('agent-workspace-name-field'),
              initialValue: draft,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: '显示名称',
                helperText: '只修改 VibeKits 中的名称，不重命名磁盘目录',
              ),
              onChanged: (String input) => draft = input,
              onFieldSubmitted: (String input) =>
                  Navigator.pop(dialogContext, input.trim()),
            ),
            Text(
              workspace,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.vibe.muted),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('agent-save-workspace-name'),
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    final String name = value.trim();
    if (name.isEmpty) {
      _show('项目名称不能为空');
      return;
    }
    setState(() => _workspaceNames[workspace] = name);
    _syncHarnessWorkspaceStatus();
    try {
      if (widget.saveWorkspaceCatalog ==
          HarnessConversationStore.saveWorkspaceCatalog) {
        await HarnessConversationStore.saveWorkspaceName(workspace, name);
      }
    } on Object catch (error) {
      if (mounted) _show('保存项目名称失败：$error');
    }
  }

  Future<void> _revealWorkspace(String workspace) async {
    if (!Platform.isMacOS) {
      _show('当前平台暂不支持在 Finder 中显示');
      return;
    }
    final ProcessResult result = await Process.run('/usr/bin/open', <String>[
      '-R',
      workspace,
    ]);
    if (result.exitCode != 0 && mounted) _show('无法在 Finder 中显示该项目');
  }

  Future<void> _removeWorkspace(String workspace) async {
    if (_workspaceCatalog.length <= 1) {
      _show('至少保留一个项目');
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('移除项目？'),
        content: Text(
          '将“${_workspaceDisplayName(workspace)}”从侧边栏移除。\n\n'
          '不会删除磁盘目录或历史会话文件。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('agent-confirm-remove-workspace'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (workspace == _workspace.text.trim()) {
      final String replacement = _workspaceCatalog.firstWhere(
        (String candidate) => candidate != workspace,
      );
      await _adoptWorkspace(replacement);
      if (!mounted) return;
    }
    setState(() {
      _workspaceCatalog.remove(workspace);
      _workspaceSessions.remove(workspace);
      _workspaceNames.remove(workspace);
      _collapsedWorkspaces.remove(workspace);
    });
    _syncHarnessWorkspaceStatus();
    await _saveWorkspaceCatalog();
    if (widget.saveWorkspaceCatalog ==
        HarnessConversationStore.saveWorkspaceCatalog) {
      await HarnessConversationStore.saveWorkspaceName(workspace, null);
    }
  }

  Future<void> _showWorkspaceContextMenu(
    String workspace,
    Offset globalPosition,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final String? action = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 214, maxWidth: 248),
      items: <PopupMenuEntry<String>>[
        _workspaceMenuItem('rename', Icons.edit_outlined, '编辑名称'),
        if (Platform.isMacOS)
          _workspaceMenuItem(
            'finder',
            Icons.folder_open_outlined,
            '在 Finder 中显示',
          ),
        const PopupMenuDivider(),
        _workspaceMenuItem('new', Icons.add_comment_outlined, '在此新建会话'),
        if (workspace != _workspace.text.trim())
          _workspaceMenuItem('switch', Icons.login_outlined, '切换到此项目'),
        const PopupMenuDivider(),
        _workspaceMenuItem('remove', Icons.close, '移除项目', destructive: true),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _renameWorkspace(workspace);
      case 'finder':
        await _revealWorkspace(workspace);
      case 'new':
        await _newSessionInWorkspace(workspace);
      case 'switch':
        await _adoptWorkspace(workspace);
      case 'remove':
        await _removeWorkspace(workspace);
    }
  }

  PopupMenuItem<String> _workspaceMenuItem(
    String value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) => PopupMenuItem<String>(
    value: value,
    height: 42,
    child: Row(
      children: <Widget>[
        Icon(
          icon,
          size: 17,
          color: destructive
              ? const Color(0xFFB42318)
              : const Color(0xFF343832),
        ),
        const SizedBox(width: 11),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: destructive
                ? const Color(0xFFB42318)
                : const Color(0xFF242722),
          ),
        ),
      ],
    ),
  );

  Future<void> _adoptWorkspace(String workspace, {bool notify = true}) async {
    final String target = workspace.trim();
    if (target == _workspace.text.trim()) return;
    if (!Directory(target).isAbsolute || !Directory(target).existsSync()) {
      if (mounted) _show('工作区不存在或无法访问：$target');
      return;
    }
    _captureComposerDraft();
    await _persistConversation();
    if (!mounted) return;
    await _registerWorkspace(target);
    if (!mounted) return;
    setState(() {
      _workspace.text = target;
      _messages.clear();
      _sessions.clear();
      _activeSessionId = null;
      _progressSteps.clear();
    });
    if (notify) await widget.onWorkspaceChanged?.call(target);
    await _restoreConversation(target);
    if (mounted) {
      _syncHarnessWorkspaceStatus();
      _restoreComposerDraft();
    }
  }

  Future<void> _restoreConversation(String workspace) async {
    final String target = workspace.trim();
    final int epoch = ++_conversationEpoch;
    if (target.isEmpty) return;
    HarnessConversationProject? project;
    try {
      project = await widget.loadConversation(target);
    } on Object {
      return;
    }
    if (!mounted ||
        epoch != _conversationEpoch ||
        target != _workspace.text.trim()) {
      return;
    }
    final List<HarnessConversationSession> restoredSessions =
        List<HarnessConversationSession>.of(
          _workspaceSessions[target] ??
              project?.sessions ??
              const <HarnessConversationSession>[],
        );
    final String? restoredActiveSessionId = project?.activeSessionId;
    setState(() {
      _sessions
        ..clear()
        ..addAll(restoredSessions);
      _workspaceSessions[target] = List<HarnessConversationSession>.of(
        restoredSessions,
      );
      _activeSessionId = restoredActiveSessionId;
      final HarnessConversationSession? active = _sessions
          .where(
            (HarnessConversationSession session) =>
                session.id == _activeSessionId,
          )
          .firstOrNull;
      final _HarnessSessionRun? activeRun = restoredActiveSessionId == null
          ? null
          : _sessionRuns[_sessionRunKey(target, restoredActiveSessionId)];
      _messages
        ..clear()
        ..addAll(
          activeRun?.messages ??
              active?.messages.map(
                (HarnessConversationMessage message) => _AgentMessage._(
                  text: message.text,
                  user: message.user,
                  elapsed: message.elapsedMs == null
                      ? null
                      : Duration(milliseconds: message.elapsedMs!),
                  exitCode: message.exitCode,
                  stopped: message.stopped,
                  executionTrace: message.executionTrace,
                ),
              ) ??
              const <_AgentMessage>[],
        );
    });
    _syncHarnessWorkspaceStatus();
    _restoreComposerDraft();
    _scrollToEnd(force: true);
  }

  Future<void> _persistConversation() async {
    final String workspace = _workspace.text.trim();
    if (workspace.isEmpty) return;
    final DateTime now = DateTime.now();
    final List<HarnessConversationMessage> messages =
        <HarnessConversationMessage>[
          for (final _AgentMessage message in _messages)
            HarnessConversationMessage(
              text: message.text,
              user: message.user,
              elapsedMs: message.elapsed?.inMilliseconds,
              exitCode: message.exitCode,
              stopped: message.stopped,
              executionTrace: message.executionTrace,
            ),
        ];
    final String? activeId = _activeSessionId;
    final List<HarnessConversationSession> sessions =
        List<HarnessConversationSession>.of(_sessions);
    if (activeId != null) {
      final int index = sessions.indexWhere(
        (HarnessConversationSession session) => session.id == activeId,
      );
      final HarnessConversationSession updated = HarnessConversationSession(
        id: activeId,
        title: _conversationTitle(messages),
        messages: messages,
        createdAt: index < 0 ? now : sessions[index].createdAt,
        updatedAt: now,
      );
      if (index < 0) {
        sessions.insert(0, updated);
      } else {
        sessions[index] = updated;
      }
    }
    sessions.sort(
      (HarnessConversationSession left, HarnessConversationSession right) =>
          right.updatedAt.compareTo(left.updatedAt),
    );
    _sessions
      ..clear()
      ..addAll(sessions);
    _workspaceSessions[workspace] = List<HarnessConversationSession>.of(
      sessions,
    );
    try {
      await widget.saveConversation(
        HarnessConversationProject(
          workspace: workspace,
          sessions: sessions,
          activeSessionId: activeId,
          updatedAt: now,
        ),
      );
    } on Object {
      // A read-only workspace must not make the agent UI unusable.
    }
  }

  List<HarnessConversationMessage> _storedMessages(
    Iterable<_AgentMessage> messages,
  ) => <HarnessConversationMessage>[
    for (final _AgentMessage message in messages)
      HarnessConversationMessage(
        text: message.text,
        user: message.user,
        elapsedMs: message.elapsed?.inMilliseconds,
        exitCode: message.exitCode,
        stopped: message.stopped,
        executionTrace: message.executionTrace,
      ),
  ];

  bool _viewingRun(_HarnessSessionRun run) =>
      _workspace.text.trim() == run.workspace &&
      _activeSessionId == run.sessionId;

  void _syncRunningSessionCache(_HarnessSessionRun run) {
    final String workspace = run.workspace;
    final String sessionId = run.sessionId;
    final List<_AgentMessage> messages = run.messages;
    final List<HarnessConversationSession> sessions =
        List<HarnessConversationSession>.of(
          _workspaceSessions[workspace] ??
              (_workspace.text.trim() == workspace
                  ? _sessions
                  : const <HarnessConversationSession>[]),
        );
    final int index = sessions.indexWhere(
      (HarnessConversationSession session) => session.id == sessionId,
    );
    final DateTime now = DateTime.now();
    final List<HarnessConversationMessage> stored = _storedMessages(messages);
    final HarnessConversationSession updated = index < 0
        ? HarnessConversationSession(
            id: sessionId,
            title: _conversationTitle(stored),
            messages: stored,
            createdAt: now,
            updatedAt: now,
          )
        : sessions[index].copyWith(
            title: _conversationTitle(stored),
            messages: stored,
            updatedAt: now,
          );
    if (index < 0) {
      sessions.insert(0, updated);
    } else {
      sessions[index] = updated;
    }
    _workspaceSessions[workspace] = sessions;
    if (_workspace.text.trim() == workspace) {
      final int visibleIndex = _sessions.indexWhere(
        (HarnessConversationSession session) => session.id == sessionId,
      );
      if (visibleIndex < 0) {
        _sessions.insert(0, updated);
      } else {
        _sessions[visibleIndex] = updated;
      }
    }
  }

  Future<void> _persistRunningConversation(_HarnessSessionRun run) async {
    final String workspace = run.workspace;
    final String sessionId = run.sessionId;
    _syncRunningSessionCache(run);
    try {
      await widget.saveConversation(
        HarnessConversationProject(
          workspace: workspace,
          sessions: List<HarnessConversationSession>.unmodifiable(
            _workspaceSessions[workspace] ??
                const <HarnessConversationSession>[],
          ),
          activeSessionId: sessionId,
          updatedAt: DateTime.now(),
        ),
      );
    } on Object {
      // A read-only workspace must not interrupt a running Harness task.
    }
  }

  String _conversationTitle(List<HarnessConversationMessage> messages) {
    final String title =
        messages
            .where((HarnessConversationMessage message) => message.user)
            .map((HarnessConversationMessage message) => message.text.trim())
            .where((String text) => text.isNotEmpty)
            .firstOrNull ??
        '新会话';
    return title.length <= 36 ? title : '${title.substring(0, 36)}…';
  }

  void _ensureActiveSession(String prompt) {
    if (_activeSessionId != null) return;
    final DateTime now = DateTime.now();
    final String id = 'session-${now.microsecondsSinceEpoch}';
    _activeSessionId = id;
    _sessions.insert(
      0,
      HarnessConversationSession(
        id: id,
        title: prompt.trim().isEmpty ? '新会话' : prompt.trim(),
        messages: const <HarnessConversationMessage>[],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  String _contextualPrompt(String prompt) {
    if (_messages.isEmpty) return prompt;
    final String history = _messages
        .where((_AgentMessage message) => message.text.trim().isNotEmpty)
        .map(
          (_AgentMessage message) =>
              '${message.user ? '用户' : '智能体'}：${message.text.trim()}',
        )
        .join('\n\n');
    final String bounded = history.length <= _maxContextCharacters
        ? history
        : history.substring(history.length - _maxContextCharacters);
    return '继续同一个项目任务。以下是本次会话最近的上下文：\n\n'
        '$bounded\n\n用户的新要求：$prompt';
  }

  Future<void> _run() async {
    final String prompt = _composer.text.trim();
    if (_running || prompt.isEmpty) return;
    if (_apiKey.text.trim().isEmpty) {
      _show('请先点右上角设置并填写 DeepSeek API Key');
      return;
    }
    _ensureActiveSession(prompt);
    final String workspace = _workspace.text.trim();
    final String sessionId = _activeSessionId!;
    final String runKey = _sessionRunKey(workspace, sessionId);
    final List<_AgentMessage> runMessages = <_AgentMessage>[
      ..._messages,
      _AgentMessage.user(prompt),
      const _AgentMessage.assistant(''),
    ];
    final _HarnessSessionRun run = _HarnessSessionRun(
      workspace: workspace,
      sessionId: sessionId,
      messages: runMessages,
      assistantIndex: runMessages.length - 1,
      clock: Stopwatch()..start(),
      progressSteps: <_AgentProgressStep>[
        _AgentProgressStep(
          id: 'understand',
          title: '理解任务',
          detail: '正在分析目标、约束和当前工作区上下文',
          state: _AgentProgressState.active,
        ),
      ],
    );
    final VibekitsHarnessToolBridge toolBridge = _createMcpBridge(
      agentOrchestrated: true,
      run: run,
    );
    run.toolBridge = toolBridge;
    final HarnessAgentRequest request = HarnessAgentRequest(
      workspace: workspace,
      prompt: _contextualPrompt(prompt),
      apiKey: _apiKey.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      debugDirectory: _debugDirectory.text.trim(),
      permissionMode: _permissionMode,
      approveTool: (HarnessToolApprovalRequest request) =>
          _approveHarnessTool(run, request),
      toolBridge: toolBridge,
    );
    try {
      request.validate();
    } on FormatException catch (error) {
      _show(error.message);
      return;
    }
    setState(() {
      _messages
        ..clear()
        ..addAll(run.messages);
      _composer.clear();
      _progressExpanded = false;
      _sessionRuns[runKey] = run;
      _syncRunningSessionCache(run);
      _notifyRunningState();
    });
    _syncHarnessWorkspaceStatus();
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.reasoning,
      message: 'Harness 正在处理当前项目任务',
    );
    unawaited(_persistConversation());
    _scrollToEnd(force: true);
    try {
      await widget.onWorkspaceChanged?.call(request.workspace);
      final HarnessAgentHandle handle = await widget.runAgent(request);
      if (!mounted) {
        await handle.stop();
        return;
      }
      run.handle = handle;
      _replaceProgress(
        'understand',
        state: _AgentProgressState.completed,
        detail: '目标与上下文已整理，正在规划下一步',
        run: run,
      );
      _upsertProgress(
        const _AgentProgressStep(
          id: 'plan',
          title: '规划操作',
          detail: 'Harness 正在选择回复方式或可用工具',
          state: _AgentProgressState.active,
        ),
        run: run,
      );
      run.outputSubscription = handle.output.listen((String chunk) {
        if (!mounted ||
            _sessionRuns[runKey] != run ||
            run.assistantIndex >= run.messages.length) {
          return;
        }
        final String clean = chunk.replaceAll(_ansiEscape, '');
        if (clean.isEmpty) return;
        final bool stickToBottom = _nearBottom;
        setState(() {
          _replaceProgress(
            'plan',
            state: _AgentProgressState.completed,
            detail: '执行路径已确定',
            run: run,
          );
          _upsertProgress(
            const _AgentProgressStep(
              id: 'response',
              title: '生成回复',
              detail: '正在整理执行结果并流式输出',
              state: _AgentProgressState.active,
            ),
            run: run,
          );
          run.messages[run.assistantIndex] = run.messages[run.assistantIndex]
              .copyWith(text: '${run.messages[run.assistantIndex].text}$clean');
          if (_viewingRun(run)) {
            _messages
              ..clear()
              ..addAll(run.messages);
          }
          _syncRunningSessionCache(run);
        });
        if (_viewingRun(run)) {
          _scrollToEnd(force: stickToBottom);
        }
      });
      final int code = await handle.exitCode;
      final Completer<void>? stopCleanup = run.stopCleanup;
      if (run.stopRequested && stopCleanup != null) await stopCleanup.future;
      final Future<void>? cancelOutput = run.outputSubscription?.cancel();
      if (cancelOutput != null) unawaited(cancelOutput);
      if (!mounted) return;
      run.clock.stop();
      setState(() {
        _completeActiveProgress(
          failed: code != 0 && !run.stopRequested,
          detail: run.stopRequested
              ? '任务已停止'
              : code == 0
              ? '回复与工具结果已完成'
              : 'Harness 退出代码 $code',
          run: run,
        );
        run.stopping = false;
        run.handle = null;
        final _AgentMessage current = run.messages[run.assistantIndex];
        String text = current.text;
        if (text.trim().isEmpty) {
          text = run.stopRequested
              ? '任务已停止。'
              : code == 0
              ? '任务已完成。'
              : '智能体退出，代码 $code。请检查模型配置。';
        } else if (code != 0 && !run.stopRequested) {
          text = '$text\n\n进程退出代码：$code';
        }
        run.messages[run.assistantIndex] = current.copyWith(
          text: text,
          elapsed: run.clock.elapsed,
          exitCode: code,
          stopped: run.stopRequested,
          executionTrace: _formatExecutionTrace(run: run),
        );
        if (_viewingRun(run)) {
          _messages
            ..clear()
            ..addAll(run.messages);
        }
        _syncRunningSessionCache(run);
        if (_sessionRuns[runKey] == run) _sessionRuns.remove(runKey);
        _notifyRunningState();
      });
      if (_sessionRuns.isNotEmpty) {
        HarnessWorkStatusHub.publish(
          phase: HarnessWorkPhase.reasoning,
          message: '当前会话已结束，仍有 ${_sessionRuns.length} 个会话正在运行',
        );
      } else {
        HarnessWorkStatusHub.publish(
          phase: code == 0 || run.stopRequested
              ? HarnessWorkPhase.ready
              : HarnessWorkPhase.failed,
          message: run.stopRequested
              ? 'Harness 已停止，工作区就绪'
              : code == 0
              ? 'Harness 任务完成，工作区就绪'
              : 'Harness 任务执行失败',
        );
      }
      await _persistRunningConversation(run);
    } on Object catch (error) {
      if (!mounted) return;
      run.clock.stop();
      setState(() {
        _completeActiveProgress(failed: true, detail: '启动失败：$error', run: run);
        run.stopping = false;
        run.handle = null;
        run.messages[run.assistantIndex] = run.messages[run.assistantIndex]
            .copyWith(
              text: '启动失败：$error',
              elapsed: run.clock.elapsed,
              exitCode: -1,
              executionTrace: _formatExecutionTrace(run: run),
            );
        if (_viewingRun(run)) {
          _messages
            ..clear()
            ..addAll(run.messages);
        }
        _syncRunningSessionCache(run);
        if (_sessionRuns[runKey] == run) _sessionRuns.remove(runKey);
        _notifyRunningState();
      });
      HarnessWorkStatusHub.publish(
        phase: _sessionRuns.isEmpty
            ? HarnessWorkPhase.failed
            : HarnessWorkPhase.reasoning,
        message: _sessionRuns.isEmpty
            ? 'Harness 启动失败'
            : '一个会话启动失败，仍有 ${_sessionRuns.length} 个会话正在运行',
      );
      await _persistRunningConversation(run);
    }
    _syncHarnessWorkspaceStatus();
    if (_viewingRun(run)) {
      _scrollToEnd(force: true);
      _composerFocus.requestFocus();
    }
  }

  Future<void> _stop() async {
    final _HarnessSessionRun? run = _activeRun;
    final HarnessAgentHandle? handle = run?.handle;
    if (run == null || handle == null || run.stopping) return;
    final VibekitsHarnessToolBridge? toolBridge = run.toolBridge;
    final Completer<void> cleanup = Completer<void>();
    setState(() {
      run.stopping = true;
      run.stopRequested = true;
      run.stopCleanup = cleanup;
      _upsertProgress(
        const _AgentProgressStep(
          id: 'stop',
          title: '停止任务',
          detail: '正在停止模型并清理任务启动的外部动作',
          state: _AgentProgressState.active,
        ),
        run: run,
      );
    });
    Object? modelStopError;
    try {
      await handle.stop();
    } on Object catch (error) {
      modelStopError = error;
    }
    try {
      final List<Map<String, Object?>> cleaned =
          await toolBridge?.stopAgentOwnedActivities() ??
          const <Map<String, Object?>>[];
      if (mounted) {
        setState(() {
          _replaceProgress(
            'stop',
            state:
                modelStopError != null ||
                    cleaned.any(
                      (Map<String, Object?> item) => item['stopped'] == false,
                    )
                ? _AgentProgressState.failed
                : _AgentProgressState.completed,
            detail: <String>[
              if (modelStopError == null)
                '模型进程：已停止'
              else
                '模型进程：停止异常 $modelStopError',
              if (cleaned.isEmpty)
                '外部资源：未发现由本任务启动的 Android 应用'
              else
                ...cleaned.map(
                  (Map<String, Object?> item) =>
                      '外部资源：${item['package']}@${item['serial']} '
                      '${item['stopped'] == true ? '已停止并验证' : '清理失败'}',
                ),
            ].join('\n'),
            run: run,
          );
          _syncExecutionTraceToRunningMessage(run);
        });
      }
    } finally {
      if (!cleanup.isCompleted) cleanup.complete();
    }
  }

  Future<bool> _approveHarnessTool(
    _HarnessSessionRun run,
    HarnessToolApprovalRequest request,
  ) async {
    if (!mounted) return false;
    final String progressId =
        'tool:${request.tool.id}:${run.progressSequence++}';
    setState(() {
      _completeActiveProgress(detail: 'Harness 已选择工具操作', run: run);
      run.progressSteps.add(
        _AgentProgressStep(
          id: progressId,
          toolId: request.tool.id,
          title: '调用 ${request.tool.name}',
          detail: <String>[
            if (request.target.isNotEmpty) '目标：${request.target}',
            '参数：${HarnessToolActivityStore.summarizeForDisplay(request.arguments)}',
            '授权：${_approvalScope(request)}',
          ].join('\n'),
          state: _AgentProgressState.active,
        ),
      );
    });
    if (_permissionMode == HarnessAgentPermissionMode.fullAccess ||
        (_permissionMode == HarnessAgentPermissionMode.assisted &&
            request.tool.risk != HarnessToolRisk.destructive)) {
      setState(() {
        _replaceProgress(
          progressId,
          detail: '${_permissionModeLabel(_permissionMode)} · 正在执行',
          run: run,
        );
      });
      return true;
    }
    final _ApprovalDecision? decision = await showDialog<_ApprovalDecision>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('允许 ${request.tool.name}？'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(request.tool.description),
              const SizedBox(height: 12),
              Text('目标：${request.target}'),
              const SizedBox(height: 6),
              Text(
                '授权范围：${_approvalScope(request)}',
                style: TextStyle(color: context.vibe.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SelectableText(
                HarnessToolActivityStore.summarizeForDisplay(request.arguments),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _ApprovalDecision.deny),
            child: const Text('拒绝'),
          ),
          FilledButton(
            key: const Key('agent-approve-once'),
            onPressed: () =>
                Navigator.pop(dialogContext, _ApprovalDecision.allowOnce),
            child: const Text('允许一次'),
          ),
        ],
      ),
    );
    final bool allowed = decision == _ApprovalDecision.allowOnce;
    if (mounted) {
      setState(() {
        _replaceProgress(
          progressId,
          state: allowed
              ? _AgentProgressState.active
              : _AgentProgressState.failed,
          detail: allowed ? '已批准，正在执行' : '用户拒绝执行',
          run: run,
        );
      });
    }
    return allowed;
  }

  Future<void> _recordHarnessToolActivity({
    _HarnessSessionRun? run,
    required String toolId,
    required String toolName,
    required String target,
    required Map<String, Object?> arguments,
    required Object? result,
    required HarnessToolActivityStatus status,
    required DateTime startedAt,
  }) async {
    await HarnessToolActivityStore.record(
      toolId: toolId,
      toolName: toolName,
      target: target,
      arguments: arguments,
      result: result,
      status: status,
      startedAt: startedAt,
    );
    if (status != HarnessToolActivityStatus.denied &&
        Platform.environment['FLUTTER_TEST'] != 'true') {
      final double quality = status == HarnessToolActivityStatus.succeeded
          ? result is Map
                ? inferMcpCompletionQuality(Map<String, Object?>.from(result))
                : 1
          : 0;
      await McpCapabilityDirectory.instance.recordAppToolResult(
        toolName: toolId,
        succeeded: status == HarnessToolActivityStatus.succeeded && quality > 0,
        completionQuality: quality,
        latencyMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
    }
    if (!mounted) return;
    setState(() {
      final List<_AgentProgressStep> progress =
          run?.progressSteps ?? _idleProgressSteps;
      final int index = progress.lastIndexWhere(
        (_AgentProgressStep step) =>
            step.toolId == toolId && step.state == _AgentProgressState.active,
      );
      final _AgentProgressState state = switch (status) {
        HarnessToolActivityStatus.succeeded => _AgentProgressState.completed,
        HarnessToolActivityStatus.failed ||
        HarnessToolActivityStatus.denied => _AgentProgressState.failed,
      };
      final String detail = <String>[
        if (target.isNotEmpty) '目标：$target',
        '参数：${HarnessToolActivityStore.summarizeForDisplay(arguments)}',
        '结果：${HarnessToolActivityStore.summarizeForDisplay(result)}',
        switch (status) {
          HarnessToolActivityStatus.succeeded => '状态：执行成功',
          HarnessToolActivityStatus.failed => '状态：执行失败',
          HarnessToolActivityStatus.denied => '状态：未获批准',
        },
        '耗时：${DateTime.now().difference(startedAt).inMilliseconds} ms',
      ].join('\n');
      if (index >= 0) {
        progress[index] = progress[index].copyWith(
          state: state,
          detail: detail,
        );
      } else {
        progress.add(
          _AgentProgressStep(
            id: 'tool:$toolId:${run?.progressSequence++ ?? _idleProgressSequence++}',
            toolId: toolId,
            title: '调用 $toolName',
            detail: detail,
            state: state,
          ),
        );
      }
      if (run != null &&
          _sessionRuns[_sessionRunKey(run.workspace, run.sessionId)] == run &&
          !run.stopRequested) {
        _upsertProgress(
          const _AgentProgressStep(
            id: 'continue',
            title: '继续分析',
            detail: '正在根据工具结果决定下一步',
            state: _AgentProgressState.active,
          ),
          run: run,
        );
      }
      if (run != null) _syncExecutionTraceToRunningMessage(run);
    });
  }

  String _formatExecutionTrace({_HarnessSessionRun? run}) {
    final List<_AgentProgressStep> progress =
        run?.progressSteps ?? _progressSteps;
    if (progress.isEmpty) return '';
    return <String>[
      '### 执行时间线',
      for (final _AgentProgressStep step in progress)
        '${switch (step.state) {
          _AgentProgressState.active => '◌',
          _AgentProgressState.completed => '✓',
          _AgentProgressState.failed => '!',
        }} **${step.title}** — ${_readableTimelineDetail(step.detail)}',
    ].join('\n');
  }

  void _syncExecutionTraceToRunningMessage(_HarnessSessionRun run) {
    final List<_AgentMessage> messages = run.messages;
    final int index = messages.lastIndexWhere(
      (_AgentMessage message) => !message.user,
    );
    if (index < 0) return;
    messages[index] = messages[index].copyWith(
      executionTrace: _formatExecutionTrace(run: run),
    );
    _syncRunningSessionCache(run);
  }

  void _upsertProgress(_AgentProgressStep step, {_HarnessSessionRun? run}) {
    final List<_AgentProgressStep> progress =
        run?.progressSteps ?? _progressSteps;
    final int index = progress.indexWhere(
      (_AgentProgressStep value) => value.id == step.id,
    );
    if (index < 0) {
      progress.add(step);
    } else {
      progress[index] = step;
    }
  }

  void _replaceProgress(
    String id, {
    String? detail,
    _AgentProgressState? state,
    _HarnessSessionRun? run,
  }) {
    final List<_AgentProgressStep> progress =
        run?.progressSteps ?? _progressSteps;
    final int index = progress.indexWhere(
      (_AgentProgressStep step) => step.id == id,
    );
    if (index < 0) return;
    progress[index] = progress[index].copyWith(detail: detail, state: state);
  }

  void _completeActiveProgress({
    bool failed = false,
    String? detail,
    _HarnessSessionRun? run,
  }) {
    final List<_AgentProgressStep> progress =
        run?.progressSteps ?? _progressSteps;
    for (int index = 0; index < progress.length; index++) {
      if (progress[index].state != _AgentProgressState.active) continue;
      progress[index] = progress[index].copyWith(
        state: failed
            ? _AgentProgressState.failed
            : _AgentProgressState.completed,
        detail: detail,
      );
    }
  }

  String _approvalScope(HarnessToolApprovalRequest request) {
    final Object? rawArguments = request.arguments['arguments'];
    if (rawArguments is List && rawArguments.isNotEmpty) {
      return rawArguments.take(2).map((Object? value) => '$value').join(' ');
    }
    final String method = '${request.arguments['method'] ?? ''}'.trim();
    if (method.isNotEmpty) return method.toUpperCase();
    return request.tool.name;
  }

  Future<void> _newTask() async {
    if (_workspace.text.trim().isEmpty) return;
    if (_messages.isEmpty && _activeSessionId != null) return;
    _captureComposerDraft();
    await _persistConversation();
    if (!mounted) return;
    final DateTime now = DateTime.now();
    final HarnessConversationSession session = HarnessConversationSession(
      id: 'session-${now.microsecondsSinceEpoch}',
      title: '新会话',
      messages: const <HarnessConversationMessage>[],
      createdAt: now,
      updatedAt: now,
    );
    setState(() {
      _collapsedWorkspaces.remove(_workspace.text.trim());
      _sessions.insert(0, session);
      _activeSessionId = session.id;
      _messages.clear();
      _progressSteps.clear();
    });
    _restoreComposerDraft();
    await _persistConversation();
    _composerFocus.requestFocus();
  }

  Future<void> _switchSession(String sessionId) async {
    if (sessionId == _activeSessionId) return;
    _captureComposerDraft();
    await _persistConversation();
    if (!mounted) return;
    final HarnessConversationSession? session = _sessions
        .where(
          (HarnessConversationSession candidate) => candidate.id == sessionId,
        )
        .firstOrNull;
    if (session == null) return;
    final _HarnessSessionRun? run =
        _sessionRuns[_sessionRunKey(_workspace.text.trim(), session.id)];
    setState(() {
      _activeSessionId = session.id;
      _messages
        ..clear()
        ..addAll(
          run?.messages ??
              session.messages.map(
                (HarnessConversationMessage message) => _AgentMessage._(
                  text: message.text,
                  user: message.user,
                  elapsed: message.elapsedMs == null
                      ? null
                      : Duration(milliseconds: message.elapsedMs!),
                  exitCode: message.exitCode,
                  stopped: message.stopped,
                  executionTrace: message.executionTrace,
                ),
              ),
        );
      if (run == null) _idleProgressSteps.clear();
    });
    _restoreComposerDraft();
    await _persistConversation();
    _scrollToEnd(force: true);
  }

  Future<void> _newSessionInWorkspace(String workspace) async {
    if (workspace != _workspace.text.trim()) {
      await _adoptWorkspace(workspace);
      if (!mounted || workspace != _workspace.text.trim()) return;
    }
    await _newTask();
  }

  Future<void> _activateWorkspaceSession(
    String workspace,
    String sessionId,
  ) async {
    if (workspace != _workspace.text.trim()) {
      await _adoptWorkspace(workspace);
      if (!mounted || workspace != _workspace.text.trim()) return;
    }
    await _switchSession(sessionId);
  }

  Future<void> _requestMoveSession(
    String sourceWorkspace,
    HarnessConversationSession session,
    String targetWorkspace,
  ) async {
    if (_isSessionRunning(sourceWorkspace, session.id) ||
        sourceWorkspace == targetWorkspace) {
      return;
    }
    if (!Directory(targetWorkspace).existsSync()) {
      _show('目标工作区不存在或无法访问');
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('移动会话并重新绑定工作区权限？'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            '“${session.title}”将从\n$sourceWorkspace\n移动到\n$targetWorkspace\n\n'
            '后续 Harness 命令的 workspace-write 根目录会改为目标项目；'
            '源项目权限不会跟随会话带过去。只迁移会话记录，不移动任何项目文件。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('agent-confirm-move-session'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移动'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _moveSession(sourceWorkspace, session, targetWorkspace);
  }

  Future<void> _moveSession(
    String sourceWorkspace,
    HarnessConversationSession session,
    String targetWorkspace,
  ) async {
    if (sourceWorkspace == _workspace.text.trim()) {
      await _persistConversation();
    }
    final HarnessConversationProject? source = await widget.loadConversation(
      sourceWorkspace,
    );
    final HarnessConversationProject? target = await widget.loadConversation(
      targetWorkspace,
    );
    final List<HarnessConversationSession> sourceSessions =
        List<HarnessConversationSession>.of(
          source?.sessions ??
              _workspaceSessions[sourceWorkspace] ??
              const <HarnessConversationSession>[],
        )..removeWhere(
          (HarnessConversationSession candidate) => candidate.id == session.id,
        );
    final List<HarnessConversationSession> targetSessions =
        List<HarnessConversationSession>.of(
          target?.sessions ??
              _workspaceSessions[targetWorkspace] ??
              const <HarnessConversationSession>[],
        )..removeWhere(
          (HarnessConversationSession candidate) => candidate.id == session.id,
        );
    targetSessions.insert(0, session.copyWith(updatedAt: DateTime.now()));
    final DateTime now = DateTime.now();
    try {
      // Save the destination first: an interrupted move may temporarily leave
      // a duplicate, but must never lose the only copy of a conversation.
      await widget.saveConversation(
        HarnessConversationProject(
          workspace: targetWorkspace,
          sessions: targetSessions,
          activeSessionId: session.id,
          updatedAt: now,
        ),
      );
      await widget.saveConversation(
        HarnessConversationProject(
          workspace: sourceWorkspace,
          sessions: sourceSessions,
          activeSessionId: source?.activeSessionId == session.id
              ? sourceSessions.firstOrNull?.id
              : source?.activeSessionId,
          updatedAt: now,
        ),
      );
    } on Object catch (error) {
      if (mounted) _show('移动会话失败；源记录仍保留：$error');
      return;
    }
    _workspaceSessions[sourceWorkspace] = sourceSessions;
    _workspaceSessions[targetWorkspace] = targetSessions;
    if (_workspace.text.trim() == sourceWorkspace) {
      _sessions
        ..clear()
        ..addAll(sourceSessions);
      if (_activeSessionId == session.id) {
        _activeSessionId = sourceSessions.firstOrNull?.id;
        _messages.clear();
      }
    }
    if (_workspace.text.trim() == targetWorkspace) {
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(targetSessions);
        _activeSessionId = session.id;
        _messages
          ..clear()
          ..addAll(
            session.messages.map(
              (HarnessConversationMessage message) => _AgentMessage._(
                text: message.text,
                user: message.user,
                elapsed: message.elapsedMs == null
                    ? null
                    : Duration(milliseconds: message.elapsedMs!),
                exitCode: message.exitCode,
                stopped: message.stopped,
                executionTrace: message.executionTrace,
              ),
            ),
          );
      });
    } else {
      await _adoptWorkspace(targetWorkspace);
      if (!mounted) return;
      await _switchSession(session.id);
    }
    if (mounted) _show('会话已移动，权限根目录已切换到目标工作区');
  }

  Future<void> _showWorkspaceManager() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('管理工作区'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) =>
                ListView.separated(
                  itemCount: _workspaceCatalog.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final String workspace = _workspaceCatalog[index];
                    final bool active = workspace == _workspace.text.trim();
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(_workspaceDisplayName(workspace)),
                      subtitle: Text(workspace),
                      trailing: active
                          ? const Chip(label: Text('当前'))
                          : IconButton(
                              tooltip: '从列表移除（不删除会话或项目文件）',
                              onPressed: () async {
                                _workspaceCatalog.remove(workspace);
                                _workspaceSessions.remove(workspace);
                                await _saveWorkspaceCatalog();
                                if (mounted) setState(() {});
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                      onTap: active
                          ? null
                          : () async {
                              Navigator.pop(dialogContext);
                              await _adoptWorkspace(workspace);
                            },
                    );
                  },
                ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  bool get _nearBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels < 120;

  void _updateScrollToLatest() {
    if (!_scroll.hasClients || !mounted) return;
    final bool show =
        _scroll.position.maxScrollExtent - _scroll.position.pixels > 72;
    if (show != _showScrollToLatest) {
      setState(() => _showScrollToLatest = show);
    }
  }

  void _scrollToEnd({required bool force}) {
    if (!force) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _useSuggestion(String value) {
    _composer
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    _composerFocus.requestFocus();
  }

  void _show(String message) {
    if (Scaffold.maybeOf(context) == null) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _receiveKeyOverLan() async {
    final bool? received = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _LanHarnessKeyDialog(
        onKeyReceived: (String key) async {
          await (widget.credentialWriter ?? PlatformCredentialStore.write)(
            _credentialKey,
            key,
          );
          _apiKey.text = key;
          if (mounted) setState(() {});
        },
      ),
    );
    if (received == true && mounted) {
      _show('API Key 已从局域网页面安全保存');
    }
  }

  Future<void> _showSettings() async {
    // The settings dialog must appear immediately even when the activity
    // settings file is on a slow/redirected profile. Logging defaults to on.
    final bool initialLoggingEnabled =
        await HarnessToolActivityStore.loadLoggingEnabled().timeout(
          const Duration(milliseconds: 50),
          onTimeout: () => true,
        );
    if (!mounted) return;
    bool loggingEnabled = initialLoggingEnabled;
    String modelChoice = _builtinModels.contains(_model.text.trim())
        ? _model.text.trim()
        : _customModelValue;
    final TextEditingController customModel = TextEditingController(
      text: modelChoice == _customModelValue ? _model.text.trim() : '',
    );
    List<String> availableModels = <String>[
      ..._builtinModels,
      if (_model.text.trim().isNotEmpty &&
          !_builtinModels.contains(_model.text.trim()))
        _model.text.trim(),
    ];
    bool loadingModels = false;
    bool loadedFromEndpoint = false;
    String? modelError;
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder:
            (
              BuildContext dialogContext,
              void Function(void Function()) setStateDialog,
            ) => AlertDialog(
              title: const Text('Harness 模型设置'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        key: const Key('agent-api-key'),
                        controller: _apiKey,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-…',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                      ),
                      if (Platform.isAndroid) ...<Widget>[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('agent-lan-key-input'),
                            onPressed: _receiveKeyOverLan,
                            icon: const Icon(Icons.qr_code_2_outlined),
                            label: const Text('同局域网扫码输入 Key'),
                          ),
                        ),
                      ],
                      SwitchListTile(
                        key: const Key('agent-tool-logging'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('记录工具调用'),
                        subtitle: const Text('默认开启；可在对应工具中查看和删除记录'),
                        value: loggingEnabled,
                        onChanged: (bool value) =>
                            setStateDialog(() => loggingEnabled = value),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('agent-debug-directory'),
                        controller: _debugDirectory,
                        decoration: InputDecoration(
                          labelText: '调试文件目录',
                          helperText:
                              '日志、截图和临时文件分别保存到 logs / screenshots / temp',
                          suffixIcon: IconButton(
                            key: const Key('agent-pick-debug-directory'),
                            tooltip: '选择目录',
                            onPressed: () async {
                              final String? selected =
                                  widget.debugDirectoryPicker == null
                                  ? await getDirectoryPath(
                                      initialDirectory: _debugDirectory.text
                                          .trim(),
                                    )
                                  : await widget.debugDirectoryPicker!();
                              if (selected == null ||
                                  selected.trim().isEmpty ||
                                  !dialogContext.mounted) {
                                return;
                              }
                              setStateDialog(
                                () => _debugDirectory.text = selected.trim(),
                              );
                            },
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('agent-base-url'),
                        controller: _baseUrl,
                        decoration: const InputDecoration(labelText: 'API 地址'),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const Key('agent-load-models'),
                          onPressed: loadingModels
                              ? null
                              : () async {
                                  setStateDialog(() {
                                    loadingModels = true;
                                    modelError = null;
                                  });
                                  try {
                                    final List<String> models = await widget
                                        .listModels(
                                          _apiKey.text.trim(),
                                          _baseUrl.text.trim(),
                                        );
                                    if (!dialogContext.mounted) return;
                                    setStateDialog(() {
                                      availableModels = models;
                                      loadingModels = false;
                                      loadedFromEndpoint = true;
                                      if (!models.contains(modelChoice)) {
                                        modelChoice = models.first;
                                        _model.text = models.first;
                                      }
                                    });
                                  } on Object catch (error) {
                                    if (!dialogContext.mounted) return;
                                    setStateDialog(() {
                                      loadingModels = false;
                                      modelError = '$error';
                                    });
                                  }
                                },
                          icon: loadingModels
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh, size: 17),
                          label: Text(loadingModels ? '正在验证' : '验证 Key 并加载模型'),
                        ),
                      ),
                      if (modelError != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            modelError!,
                            key: const Key('agent-model-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          loadedFromEndpoint
                              ? '来自当前 API 的 /models 实时结果'
                              : 'DeepSeek 官方 V4 模型 · 验证后以 /models 返回为准',
                          style: TextStyle(
                            color: context.vibe.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        key: const Key('agent-model-select'),
                        decoration: BoxDecoration(
                          border: Border.all(color: context.vibe.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (final String model in availableModels)
                              _ModelChoiceTile(
                                key: Key('agent-model-$model'),
                                label: model,
                                selected: modelChoice == model,
                                onTap: () => setStateDialog(() {
                                  modelChoice = model;
                                  _model.text = model;
                                }),
                              ),
                            _ModelChoiceTile(
                              key: const Key('agent-model-custom'),
                              label: '自定义模型 ID',
                              selected: modelChoice == _customModelValue,
                              onTap: () => setStateDialog(
                                () => modelChoice = _customModelValue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (modelChoice == _customModelValue) ...<Widget>[
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('agent-model'),
                          controller: customModel,
                          decoration: const InputDecoration(labelText: '自定义模型'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('保存'),
                ),
              ],
            ),
      ),
    );
    if (save != true) return;
    try {
      final HarnessDebugPaths debug =
          await DeepSeekHarnessService.prepareDebugDirectory(
            _debugDirectory.text,
          );
      _debugDirectory.text = debug.root.path;
      await widget.onDebugDirectoryChanged?.call(debug.root.path);
    } on Object catch (error) {
      if (mounted) _show('调试目录不可用：$error');
      return;
    }
    if (loggingEnabled != initialLoggingEnabled) {
      await HarnessToolActivityStore.setLoggingEnabled(loggingEnabled);
    }
    if (modelChoice == _customModelValue &&
        customModel.text.trim().isNotEmpty) {
      _model.text = customModel.text.trim();
    }
    if (_model.text.trim().isEmpty) {
      _model.text = DeepSeekHarnessService.defaultModel;
      modelChoice = DeepSeekHarnessService.defaultModel;
    }
    try {
      if (Platform.environment['FLUTTER_TEST'] == 'true' &&
          widget.credentialWriter == null) {
        if (mounted) setState(() {});
        return;
      }
      await (widget.credentialWriter ?? PlatformCredentialStore.write)(
        _credentialKey,
        _apiKey.text.trim(),
      );
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) _show('设置仅用于当前会话：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final HarnessEnvironmentReport? environment = _environment;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The Harness tab is usually about 776 px wide inside the application
        // shell. Requiring 1020 px made the session controls unreachable on a
        // normal 800 px window even though the panel fits comfortably.
        final bool sidebarCanFit = constraints.maxWidth >= 720;
        final bool showSessionSidebar = sidebarCanFit && _sessionSidebarOpen;
        return Row(
          children: <Widget>[
            if (showSessionSidebar) ...<Widget>[
              SizedBox(width: 236, child: _buildSessionSidebar(environment)),
              VerticalDivider(width: 1, color: context.vibe.border),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: _buildChatWorkbench(
                  environment,
                  showSessionSidebar: showSessionSidebar,
                  sidebarCanFit: sidebarCanFit,
                ),
              ),
            ),
            _buildCrossPlatformToolRail(),
          ],
        );
      },
    );
  }

  Widget _buildCrossPlatformToolRail() => Container(
    width: 60,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border(left: BorderSide(color: context.vibe.border)),
    ),
    child: ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      children: <Widget>[
        _macRailAction(
          icon: _mcpExposureEnabled ? Icons.api_rounded : Icons.api_outlined,
          tooltip:
              '${_mcpIdentity.displayName}\nMCP ${_mcpExposureEnabled ? '已开启' : '已关闭'}，点击切换',
          caption: 'MCP',
          active: _mcpExposureEnabled,
          onPressed: _toggleMcpExposure,
        ),
        StreamBuilder<McpCapabilitySnapshot>(
          stream: McpCapabilityDirectory.instance.changes,
          initialData: McpCapabilityDirectory.instance.snapshot,
          builder: (_, AsyncSnapshot<McpCapabilitySnapshot> snapshot) =>
              _macRailAction(
                icon: Icons.apps_rounded,
                badge:
                    snapshot.data?.app
                        .expand((McpDeviceCapability item) => item.tools)
                        .length ??
                    0,
                tooltip: '本 APP MCP：查看 VibeKits 的完整工具目录',
                onPressed: () => _showMcpDevices(McpCapabilityTier.app),
              ),
        ),
        StreamBuilder<McpCapabilitySnapshot>(
          stream: McpCapabilityDirectory.instance.changes,
          initialData: McpCapabilityDirectory.instance.snapshot,
          builder: (_, AsyncSnapshot<McpCapabilitySnapshot> snapshot) =>
              _macRailAction(
                icon: Icons.memory_outlined,
                badge: snapshot.data?.local.length ?? 0,
                tooltip: '本机 MCP 设备',
                onPressed: () => _showMcpDevices(McpCapabilityTier.local),
              ),
        ),
        StreamBuilder<McpCapabilitySnapshot>(
          stream: McpCapabilityDirectory.instance.changes,
          initialData: McpCapabilityDirectory.instance.snapshot,
          builder: (_, AsyncSnapshot<McpCapabilitySnapshot> snapshot) =>
              _macRailAction(
                icon: Icons.hub_outlined,
                badge: snapshot.data?.lan.length ?? 0,
                tooltip: '局域网 MCP 设备',
                onPressed: () => _showMcpDevices(McpCapabilityTier.lan),
              ),
        ),
        PopupMenuButton<FeishuHarnessTask>(
          tooltip: '飞书任务',
          onSelected: (FeishuHarnessTask task) {
            _composer.text = task.prompt;
            _composer.selection = TextSelection.collapsed(
              offset: _composer.text.length,
            );
            _composerFocus.requestFocus();
          },
          itemBuilder: (_) => <PopupMenuEntry<FeishuHarnessTask>>[
            for (final FeishuHarnessTask task in FeishuHarnessTasks.quickTasks)
              PopupMenuItem<FeishuHarnessTask>(
                value: task,
                child: Text(task.label),
              ),
          ],
          child: const SizedBox(
            width: 52,
            height: 46,
            child: Icon(Icons.forum_outlined, size: 20),
          ),
        ),
        _macRailAction(
          icon: Icons.receipt_long_outlined,
          tooltip: 'Harness 工具调用记录',
          onPressed: _showRecentToolActivity,
        ),
        StreamBuilder<RustDeskHarnessLinkSnapshot>(
          stream: RustDeskHarnessLinkStatusHub.changes,
          initialData: RustDeskHarnessLinkStatusHub.latest,
          builder: (_, AsyncSnapshot<RustDeskHarnessLinkSnapshot> snapshot) {
            final RustDeskHarnessLinkSnapshot link =
                snapshot.data ?? RustDeskHarnessLinkStatusHub.latest;
            return _macRailAction(
              icon: Icons.screen_share_outlined,
              tooltip: '远程状态：${link.message}',
              active: link.phase == RustDeskHarnessLinkPhase.connected,
              onPressed: () => _show('远程状态：${link.message}'),
            );
          },
        ),
        _macRailAction(
          icon: Icons.settings_outlined,
          tooltip: 'MCP 与协同设置',
          onPressed: _showMacMcpSettings,
        ),
        const SizedBox(
          height: 34,
          child: Tooltip(message: '预留后续功能', child: Icon(Icons.more_horiz)),
        ),
      ],
    ),
  );

  Widget _macRailAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    int badge = 0,
    bool active = false,
    String? caption,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 52,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Semantics(
            label: tooltip,
            button: true,
            child: IconButton(
              onPressed: onPressed,
              padding: EdgeInsets.only(bottom: caption == null ? 0 : 8),
              icon: Icon(
                icon,
                size: 20,
                color: active ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
          if (caption != null)
            Positioned(
              bottom: 2,
              child: Text(
                caption,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: active ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
            ),
          if (badge > 0)
            Positioned(
              right: 4,
              top: 3,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 8,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _toggleMcpExposure() async {
    final bool enabled = !_mcpExposureEnabled;
    if (_mcpExposureChanging) return;
    final VibekitsHarnessToolBridge? bridge = _mcpExposureBridge;
    if (bridge == null) {
      _show('MCP 工具目录尚未就绪，请稍后重试');
      return;
    }
    if (enabled) {
      late final LmcpInstanceCertificate identity;
      try {
        identity = await VibekitsLmcpExposureServer.instance.prepareIdentity(
          displayName: _mcpIdentity.displayName,
        );
      } on Object catch (error) {
        if (mounted) _show('准备 MCP 实例证书失败：$error');
        return;
      }
      if (!mounted) return;
      final List<McpToolInterface> tools = McpCapabilityDirectory
          .instance
          .snapshot
          .app
          .expand((McpDeviceCapability device) => device.tools)
          .toList(growable: false);
      final bool allowed = await showMcpExposureConsentDialog(
        context: context,
        deviceName: _mcpIdentity.displayName,
        tools: tools,
        certificateFingerprint: identity.fingerprint,
      );
      if (!mounted || !allowed) return;
    }
    setState(() => _mcpExposureChanging = true);
    try {
      if (enabled) {
        await _startMcpExposure(bridge);
        try {
          await _mcpExposurePreferences.saveEnabled(true);
        } on Object {
          await VibekitsLmcpExposureServer.instance.stop();
          rethrow;
        }
      } else {
        try {
          await _mcpExposurePreferences.saveEnabled(false);
        } finally {
          await VibekitsLmcpExposureServer.instance.stop();
        }
      }
      if (mounted) {
        setState(
          () =>
              _mcpExposureEnabled = VibekitsLmcpExposureServer.instance.running,
        );
      }
    } on Object catch (error) {
      if (mounted) _show('保存 MCP 开关失败：$error');
    } finally {
      if (mounted) setState(() => _mcpExposureChanging = false);
    }
  }

  Future<void> _showMcpDevices(McpCapabilityTier tier) async {
    final McpCapabilitySnapshot snapshot = await McpCapabilityDirectory.instance
        .snapshotForTask();
    final Map<String, McpToolReputation> reputations =
        await McpCapabilityDirectory.instance.loadReputations();
    if (!mounted) return;
    final List<McpDeviceCapability> devices = switch (tier) {
      McpCapabilityTier.app => snapshot.app,
      McpCapabilityTier.local => snapshot.local,
      McpCapabilityTier.lan => snapshot.lan,
    };
    int scoredToolCount(McpDeviceCapability device) =>
        device.tools.where((McpToolInterface tool) {
          final McpToolReputation? score = reputationForTool(
            reputations,
            device,
            tool,
          );
          return score != null &&
              (score.totalCalls > 0 || score.manualRating != null);
        }).length;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(switch (tier) {
          McpCapabilityTier.app => '本 APP MCP 工具',
          McpCapabilityTier.local => '本机 MCP 设备',
          McpCapabilityTier.lan => '局域网 MCP 设备',
        }),
        content: SizedBox(
          width: 620,
          height: 420,
          child: devices.isEmpty
              ? const Center(child: Text('尚未发现设备；列表会在设备上线后自动更新。'))
              : ListView(
                  children: <Widget>[
                    for (final McpDeviceCapability device in devices)
                      ExpansionTile(
                        title: Text(device.name),
                        subtitle: Text(
                          '${device.hardwareCode} · ${device.tools.length} 个接口'
                          '${scoredToolCount(device) == 0 ? '' : ' · ${scoredToolCount(device)} 个已评分'}',
                        ),
                        children: <Widget>[
                          for (final McpToolInterface tool in device.tools)
                            ListTile(
                              dense: true,
                              title: SelectableText(tool.name),
                              subtitle: Text(
                                '${tool.description}\n风险：${tool.risk.isEmpty ? '提供者未声明' : tool.risk}',
                              ),
                              trailing: McpReputationBadge(
                                reputation: reputationForTool(
                                  reputations,
                                  device,
                                  tool,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecentToolActivity() async {
    final List<HarnessToolActivity> entries =
        await HarnessToolActivityStore.load(const <String>{});
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Harness 工具调用记录'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: entries.isEmpty
              ? const Center(child: Text('暂无调用记录'))
              : ListView(
                  children: <Widget>[
                    for (final HarnessToolActivity entry in entries.take(100))
                      ListTile(
                        dense: true,
                        title: Text(entry.toolName),
                        subtitle: Text(
                          '${entry.status.name} · ${entry.target}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMacMcpSettings() => showDialog<void>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        final McpCapabilitySnapshot snapshot =
            McpCapabilityDirectory.instance.snapshot;
        return AlertDialog(
          title: const Text('MCP 与协同设置'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(
                  '设备名称：${_mcpIdentity.displayName}\n'
                  '硬件识别码：${_mcpIdentity.hardwareCode}\n'
                  '实例 ID：${_mcpIdentity.instanceId}\n'
                  '发现地址：239.255.42.99:47831/UDP',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许发布本 APP 的 MCP 能力'),
                  subtitle: const Text('关闭后发送 goodbye；本机仍继续发现其他 MCP 设备'),
                  value: _mcpExposureEnabled,
                  onChanged: (bool enabled) async {
                    await _toggleMcpExposure();
                    setDialogState(() {});
                  },
                ),
                const Divider(),
                Text(
                  '本 APP ${snapshot.app.length} 台 · '
                  '本机 ${snapshot.local.length} 台 · '
                  '局域网 ${snapshot.lan.length} 台 · '
                  '目录版本 ${snapshot.version}',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await McpCapabilityDirectory.instance.refreshLocal();
                setDialogState(() {});
              },
              child: const Text('重新读取目录'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildChatWorkbench(
    HarnessEnvironmentReport? environment, {
    required bool showSessionSidebar,
    required bool sidebarCanFit,
  }) {
    return Column(
      children: <Widget>[
        _buildHeader(
          environment,
          showSessionSidebar: showSessionSidebar,
          sidebarCanFit: sidebarCanFit,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.vibe.panelRaised,
              border: Border.all(color: context.vibe.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _messages.isEmpty
                ? _buildEmptyState()
                : Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ListView.separated(
                          key: const Key('agent-conversation'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                          itemCount: _messages.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 16),
                          itemBuilder: (BuildContext context, int index) {
                            final bool activeAssistant =
                                _running &&
                                index == _messages.length - 1 &&
                                !_messages[index].user;
                            return _MessageBubble(
                              message: _messages[index],
                              progressSteps: activeAssistant
                                  ? List<_AgentProgressStep>.unmodifiable(
                                      _progressSteps,
                                    )
                                  : const <_AgentProgressStep>[],
                              progressExpanded: _progressExpanded,
                              onToggleProgress: activeAssistant
                                  ? () => setState(
                                      () => _progressExpanded =
                                          !_progressExpanded,
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: IgnorePointer(
                          ignoring: !_showScrollToLatest,
                          child: AnimatedOpacity(
                            opacity: _showScrollToLatest ? 1 : 0,
                            duration: const Duration(milliseconds: 140),
                            child: Center(
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                elevation: 4,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  key: const Key('agent-scroll-to-latest'),
                                  tooltip: '滚动到最新消息',
                                  onPressed: () => _scrollToEnd(force: true),
                                  icon: const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (_running) _buildProgressRow(),
        _buildComposer(environment),
      ],
    );
  }

  Widget _buildSessionSidebar(HarnessEnvironmentReport? environment) {
    final String workspace = _workspace.text.trim();
    final String query = _workspaceSearch.text.trim().toLowerCase();
    final List<String> visibleWorkspaces = _workspaceCatalog
        .where((String path) {
          if (query.isEmpty) return true;
          final String name = _workspaceDisplayName(path);
          final Iterable<HarnessConversationSession> sessions =
              path == workspace
              ? _sessions
              : _workspaceSessions[path] ??
                    const <HarnessConversationSession>[];
          return path.toLowerCase().contains(query) ||
              name.toLowerCase().contains(query) ||
              sessions.any(
                (HarnessConversationSession session) =>
                    session.title.toLowerCase().contains(query),
              );
        })
        .toList(growable: false);
    return Material(
      key: const Key('agent-session-sidebar'),
      color: context.vibe.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('agent-new-session-sidebar'),
                    onPressed: workspace.isEmpty ? null : _newTask,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建会话'),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('agent-close-session-sidebar'),
                  tooltip: '收起会话侧边栏',
                  onPressed: () => setState(() => _sessionSidebarOpen = false),
                  icon: const Icon(Icons.menu_open, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '工作区',
                      style: TextStyle(
                        color: context.vibe.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('agent-search-workspaces'),
                  tooltip: '搜索工作区和会话',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _workspaceSearchOpen = !_workspaceSearchOpen;
                    if (!_workspaceSearchOpen) _workspaceSearch.clear();
                  }),
                  icon: const Icon(Icons.search, size: 18),
                ),
                IconButton(
                  key: const Key('agent-manage-workspaces'),
                  tooltip: '管理工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: _workspaceCatalog.isEmpty
                      ? null
                      : _showWorkspaceManager,
                  icon: const Icon(Icons.tune, size: 18),
                ),
                IconButton(
                  key: const Key('agent-add-workspace'),
                  tooltip: '添加工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: _pickWorkspace,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                ),
              ],
            ),
            if (_workspaceSearchOpen) ...<Widget>[
              const SizedBox(height: 4),
              TextField(
                key: const Key('agent-workspace-search-field'),
                controller: _workspaceSearch,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索项目或会话',
                  prefixIcon: Icon(Icons.search, size: 17),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: _workspaceCatalogLoading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleWorkspaces.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty ? '点击文件夹 + 添加工作区' : '没有匹配的工作区或会话',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.vibe.muted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: visibleWorkspaces.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _buildWorkspaceGroup(
                            visibleWorkspaces[index],
                            query: query,
                          ),
                    ),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('agent-sidebar-settings'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.settings_outlined, size: 17),
              title: const Text('Harness 设置', style: TextStyle(fontSize: 12)),
              subtitle: Text(
                '${environment?.ready == true ? 'Harness 已就绪' : '连接未就绪'} · ${_model.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
              trailing: Icon(
                environment?.ready == true
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 16,
              ),
              onTap: _showSettings,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceGroup(String workspace, {required String query}) {
    final String current = _workspace.text.trim();
    final bool activeWorkspace = workspace == current;
    final bool runningWorkspace = _sessionRuns.values.any(
      (_HarnessSessionRun run) => run.workspace == workspace,
    );
    final String name = _workspaceDisplayName(workspace);
    final List<HarnessConversationSession> sessions =
        List<HarnessConversationSession>.of(
          activeWorkspace
              ? _sessions
              : _workspaceSessions[workspace] ??
                    const <HarnessConversationSession>[],
        );
    final List<HarnessConversationSession> visibleSessions = query.isEmpty
        ? sessions
        : sessions
              .where(
                (HarnessConversationSession session) =>
                    session.title.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final bool collapsed =
        query.isEmpty && _collapsedWorkspaces.contains(workspace);
    return DragTarget<_HarnessSessionDragPayload>(
      onWillAcceptWithDetails:
          (DragTargetDetails<_HarnessSessionDragPayload> details) =>
              !_isSessionRunning(
                details.data.workspace,
                details.data.session.id,
              ) &&
              details.data.workspace != workspace,
      onAcceptWithDetails:
          (DragTargetDetails<_HarnessSessionDragPayload> details) => unawaited(
            _requestMoveSession(
              details.data.workspace,
              details.data.session,
              workspace,
            ),
          ),
      builder:
          (
            BuildContext context,
            List<_HarnessSessionDragPayload?> candidates,
            List<dynamic> rejected,
          ) {
            final bool accepting = candidates.isNotEmpty;
            return Container(
              key: ValueKey<String>('agent-workspace-$workspace'),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: accepting
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12)
                    : null,
                border: accepting
                    ? Border.all(color: Theme.of(context).colorScheme.primary)
                    : null,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (TapDownDetails details) => unawaited(
                      _showWorkspaceContextMenu(
                        workspace,
                        details.globalPosition,
                      ),
                    ),
                    child: ListTile(
                      key: ValueKey<String>(
                        'agent-workspace-header-$workspace',
                      ),
                      dense: true,
                      selected: activeWorkspace,
                      contentPadding: const EdgeInsets.only(left: 8, right: 0),
                      leading: Tooltip(
                        message: collapsed ? '展开项目会话' : '折叠项目会话',
                        child: Icon(
                          collapsed
                              ? Icons.folder_outlined
                              : Icons.folder_open_outlined,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: accepting ? const Text('松开以移动并重绑定权限') : null,
                      onTap: () {
                        if (activeWorkspace) {
                          setState(() {
                            if (!_collapsedWorkspaces.remove(workspace)) {
                              _collapsedWorkspaces.add(workspace);
                            }
                          });
                          return;
                        }
                        setState(() => _collapsedWorkspaces.remove(workspace));
                        unawaited(_adoptWorkspace(workspace));
                      },
                      trailing: activeWorkspace
                          ? Builder(
                              builder: (BuildContext buttonContext) =>
                                  IconButton(
                                    key: ValueKey<String>(
                                      'agent-workspace-menu-$workspace',
                                    ),
                                    tooltip: '项目操作',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      final RenderBox box =
                                          buttonContext.findRenderObject()!
                                              as RenderBox;
                                      unawaited(
                                        _showWorkspaceContextMenu(
                                          workspace,
                                          box.localToGlobal(
                                            Offset(0, box.size.height),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.more_horiz,
                                      size: 18,
                                    ),
                                  ),
                            )
                          : runningWorkspace
                          ? SizedBox.square(
                              key: ValueKey<String>(
                                'agent-workspace-running-$workspace',
                              ),
                              dimension: 14,
                              child: const CircularProgressIndicator(
                                strokeWidth: 1.8,
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (!collapsed && visibleSessions.isEmpty && activeWorkspace)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(34, 0, 8, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '暂无会话',
                          style: TextStyle(
                            color: context.vibe.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  if (!collapsed)
                    for (final HarnessConversationSession session
                        in visibleSessions)
                      _buildDraggableSession(
                        workspace: workspace,
                        session: session,
                        activeWorkspace: activeWorkspace,
                      ),
                ],
              ),
            );
          },
    );
  }

  Widget _buildDraggableSession({
    required String workspace,
    required HarnessConversationSession session,
    required bool activeWorkspace,
  }) {
    final bool selected = activeWorkspace && session.id == _activeSessionId;
    final bool runningThisSession = _isSessionRunning(workspace, session.id);
    final Widget tile = ListTile(
      key: activeWorkspace
          ? Key('agent-session-${session.id}')
          : ValueKey<String>('agent-session-$workspace-${session.id}'),
      dense: true,
      selected: selected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.09),
      contentPadding: const EdgeInsets.only(left: 32, right: 0),
      leading: Tooltip(
        message: _workspaceCatalog.length < 2 ? '添加第二个工作区后可移动会话' : '按住并拖到目标工作区',
        child: Icon(
          Icons.drag_indicator,
          size: 17,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      title: Text(
        session.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _activateWorkspaceSession(workspace, session.id),
      trailing: selected
          ? _SessionMoveMenuButton(
              buttonKey: activeWorkspace
                  ? Key('agent-session-menu-${session.id}')
                  : ValueKey<String>(
                      'agent-session-menu-$workspace-${session.id}',
                    ),
              sourceWorkspace: workspace,
              session: session,
              activeWorkspace: activeWorkspace,
              workspaceNames: _workspaceNames,
              targets: _workspaceCatalog
                  .where((String candidate) => candidate != workspace)
                  .toList(growable: false),
              moveEnabled: !runningThisSession,
              onSelected: (String target) =>
                  _requestMoveSession(workspace, session, target),
            )
          : runningThisSession
          ? SizedBox.square(
              key: ValueKey<String>(
                'agent-session-running-$workspace-${session.id}',
              ),
              dimension: 14,
              child: const CircularProgressIndicator(strokeWidth: 1.8),
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );
    if (runningThisSession) return tile;
    return MouseRegion(
      cursor: _workspaceCatalog.length < 2
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      child: Draggable<_HarnessSessionDragPayload>(
        data: _HarnessSessionDragPayload(
          workspace: workspace,
          session: session,
        ),
        maxSimultaneousDrags: _workspaceCatalog.length < 2 ? 0 : 1,
        rootOverlay: true,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 190,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.drag_indicator, size: 17),
              title: Text(session.title, maxLines: 1),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: tile,
      ),
    );
  }

  Widget _buildHeader(
    HarnessEnvironmentReport? environment, {
    required bool showSessionSidebar,
    required bool sidebarCanFit,
  }) {
    final String workspace = _workspace.text.trim();
    final String workspaceName = workspace.isEmpty
        ? '选择工作区'
        : workspace.replaceAll('\\', '/').split('/').last;
    final bool runningTool = _progressSteps.any(
      (_AgentProgressStep step) =>
          step.toolId != null && step.state == _AgentProgressState.active,
    );
    final String runtimeLabel = _stopping
        ? 'Harness 停止并清理中'
        : runningTool
        ? 'Harness 正在调用工具'
        : _running
        ? 'Harness 推理中'
        : _checking
        ? '检查中'
        : environment?.ready == true
        ? 'Harness 就绪'
        : '连接未就绪';
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          if (!showSessionSidebar)
            IconButton(
              key: const Key('agent-open-session-sidebar'),
              tooltip: sidebarCanFit ? '打开会话侧边栏' : '窗口加宽后可打开会话侧边栏',
              onPressed: sidebarCanFit
                  ? () => setState(() => _sessionSidebarOpen = true)
                  : null,
              icon: const Icon(Icons.menu, size: 19),
            ),
          Tooltip(
            message: workspace.isEmpty ? '选择智能体可操作的项目目录' : workspace,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: TextButton.icon(
                key: const Key('agent-pick-workspace'),
                onPressed: _pickWorkspace,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(
                  workspaceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (workspace.isNotEmpty) ...<Widget>[
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                workspace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ),
          ] else
            const Spacer(),
          Flexible(
            child: Tooltip(
              message: '$runtimeLabel\n${environment?.message ?? '正在检查环境'}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_checking || _running)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: environment?.ready == true
                          ? context.vibe.success
                          : VibekitsColors.warning,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      runtimeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '重新检查',
            onPressed: _checkEnvironment,
            icon: const Icon(Icons.refresh, size: 18),
          ),
          if (Platform.isAndroid && _apiKey.text.isEmpty)
            OutlinedButton.icon(
              key: const Key('agent-lan-key-header'),
              onPressed: _receiveKeyOverLan,
              icon: const Icon(Icons.qr_code_2_outlined, size: 18),
              label: const Text('扫码输入 Key'),
            )
          else
            IconButton(
              key: const Key('agent-settings'),
              tooltip: _apiKey.text.isEmpty ? '设置模型与 API Key' : '模型设置',
              onPressed: _showSettings,
              icon: Icon(
                _apiKey.text.isEmpty ? Icons.key_outlined : Icons.tune_outlined,
                size: 18,
              ),
            ),
          IconButton(
            key: const Key('agent-new-task'),
            tooltip: '新任务',
            onPressed: workspace.isEmpty ? null : _newTask,
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow() {
    return Container(
      key: const Key('agent-progress'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Harness 正在处理任务 · 可切换到其他工具，任务会继续运行',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton.icon(
            key: const Key('agent-stop'),
            onPressed: _handle == null || _stopping ? null : _stop,
            icon: const Icon(Icons.stop, size: 16),
            label: Text(_stopping ? '停止中…' : '停止'),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(HarnessEnvironmentReport? environment) {
    final bool canRun = !_running;
    return Center(
      child: SizedBox(
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _composerFocus,
          builder: (BuildContext context, Widget? child) => AnimatedContainer(
            key: const Key('agent-composer-shell'),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: context.vibe.panelRaised,
              border: Border.all(
                color: _composerFocus.hasFocus
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.55)
                    : context.vibe.border,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.055),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 11, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.enter):
                        _SubmitAgentIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SubmitAgentIntent: CallbackAction<_SubmitAgentIntent>(
                        onInvoke: (_) {
                          if (canRun) unawaited(_run());
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      key: const Key('agent-composer'),
                      controller: _composer,
                      focusNode: _composerFocus,
                      minLines: 1,
                      maxLines: 7,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 15, height: 1.42),
                      decoration: const InputDecoration(
                        hintText: '向 Harness 描述任务…',
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.fromLTRB(0, 2, 4, 12),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Material(
                      color: context.vibe.canvas,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        key: const Key('agent-model-button'),
                        onTap: _showSettings,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.auto_awesome_outlined, size: 14),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 190,
                                ),
                                child: Text(
                                  _model.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.expand_more, size: 15),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<HarnessAgentPermissionMode>(
                      key: const Key('agent-permission-menu'),
                      tooltip: '工具权限',
                      offset: const Offset(0, -230),
                      onSelected: (HarnessAgentPermissionMode mode) {
                        setState(() => _permissionMode = mode);
                        unawaited(widget.savePermissionMode(mode));
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<HarnessAgentPermissionMode>>[
                            const PopupMenuItem<HarnessAgentPermissionMode>(
                              value: HarnessAgentPermissionMode.requestApproval,
                              height: 72,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.pan_tool_alt_outlined),
                                title: Text('请求批准'),
                                subtitle: Text('执行有副作用的操作前都先询问'),
                              ),
                            ),
                            const PopupMenuItem<HarnessAgentPermissionMode>(
                              value: HarnessAgentPermissionMode.assisted,
                              height: 72,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.shield_outlined),
                                title: Text('帮我批准'),
                                subtitle: Text('普通工具自动执行，仅破坏性操作询问'),
                              ),
                            ),
                            const PopupMenuItem<HarnessAgentPermissionMode>(
                              value: HarnessAgentPermissionMode.fullAccess,
                              height: 72,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.lock_open_outlined),
                                title: Text('完全访问权限'),
                                subtitle: Text('注册工具不再询问，底层安全边界仍生效'),
                              ),
                            ),
                          ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: context.vibe.canvas,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              _permissionModeIcon(_permissionMode),
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _permissionModeLabel(_permissionMode),
                              style: const TextStyle(fontSize: 12),
                            ),
                            const Icon(Icons.expand_more, size: 15),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        environment?.ready == true
                            ? _running
                                  ? '任务运行中，可随时停止'
                                  : 'Enter 发送 · Shift+Enter 换行'
                            : environment?.message ?? '正在检查 Harness 配置',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.vibe.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 36,
                      child: IconButton.filled(
                        key: const Key('agent-send'),
                        tooltip: '发送任务 (Enter)',
                        onPressed: canRun ? _run : null,
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minimumHeight = constraints.maxHeight > 32
            ? constraints.maxHeight - 32
            : 0;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.terminal, size: 25),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '今天要开发什么？',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '选择工作区后直接描述任务。Harness 会在同一会话中保留上下文、运行过程和结果。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.vibe.muted),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        ActionChip(
                          label: const Text('检查并修复失败测试'),
                          onPressed: () =>
                              _useSuggestion('检查项目并修复失败的测试，完成后运行全量验证。'),
                        ),
                        ActionChip(
                          label: const Text('审查当前改动'),
                          onPressed: () =>
                              _useSuggestion('审查当前 Git 改动，优先指出会影响用户的真实问题。'),
                        ),
                        ActionChip(
                          label: const Text('解释项目结构'),
                          onPressed: () =>
                              _useSuggestion('快速阅读项目，说明主要模块、入口和关键数据流。'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _LanHarnessKeyDialog extends StatefulWidget {
  const _LanHarnessKeyDialog({required this.onKeyReceived});

  final Future<void> Function(String key) onKeyReceived;

  @override
  State<_LanHarnessKeyDialog> createState() => _LanHarnessKeyDialogState();
}

final class _LanHarnessKeyDialogState extends State<_LanHarnessKeyDialog> {
  LanHarnessKeyReceiver? _receiver;
  String _status = '正在建立局域网页面…';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final LanHarnessKeyReceiver receiver =
          await LanHarnessKeyReceiver.start();
      if (!mounted) {
        await receiver.close();
        return;
      }
      setState(() {
        _receiver = receiver;
        _status =
            '请先确认手机和 Pad 已连接同一局域网\n'
            '然后用手机扫码，在网页粘贴 DeepSeek 授权码并确认';
      });
      final String key = await receiver.keyReceived;
      if (!mounted) return;
      setState(() {
        _saving = true;
        _status = '已收到，正在写入安卓安全存储…';
      });
      await widget.onKeyReceived(key);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = '$error';
      });
    }
  }

  @override
  void dispose() {
    final LanHarnessKeyReceiver? receiver = _receiver;
    if (receiver != null) unawaited(receiver.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LanHarnessKeyReceiver? receiver = _receiver;
    return AlertDialog(
      title: const Text('手机扫码输入 DeepSeek 授权码'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _saving ? Theme.of(context).colorScheme.primary : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (receiver == null)
              const SizedBox.square(
                dimension: 42,
                child: CircularProgressIndicator(),
              )
            else
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  key: const Key('agent-lan-key-qr'),
                  data: receiver.pageUri.toString(),
                  version: QrVersions.auto,
                  size: 210,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            if (receiver != null) ...<Widget>[
              const SizedBox(height: 8),
              SelectableText(
                receiver.pageUri.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              const Text(
                '步骤：同一局域网 → 手机扫码 → 粘贴授权码 → 确认\n'
                '二维码不包含授权码，成功一次后立即失效。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

enum _ApprovalDecision { deny, allowOnce }

String _permissionModeLabel(HarnessAgentPermissionMode mode) => switch (mode) {
  HarnessAgentPermissionMode.requestApproval => '请求批准',
  HarnessAgentPermissionMode.assisted => '帮我批准',
  HarnessAgentPermissionMode.fullAccess => '完全访问权限',
};

IconData _permissionModeIcon(HarnessAgentPermissionMode mode) => switch (mode) {
  HarnessAgentPermissionMode.requestApproval => Icons.pan_tool_alt_outlined,
  HarnessAgentPermissionMode.assisted => Icons.shield_outlined,
  HarnessAgentPermissionMode.fullAccess => Icons.lock_open_outlined,
};

enum _AgentProgressState { active, completed, failed }

String _readableTimelineDetail(String detail, {int maxLines = 4}) {
  final List<String> source = detail
      .split('\n')
      .map((String line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where((String line) => line.isNotEmpty)
      .toList(growable: false);
  if (source.isEmpty) return '已记录';

  String? firstWith(String prefix) =>
      source.where((String line) => line.startsWith(prefix)).firstOrNull;
  String compact(String line, {int limit = 128}) =>
      line.length <= limit ? line : '${line.substring(0, limit - 1)}…';

  final String? target = firstWith('目标：');
  final String? status = firstWith('状态：');
  final String? elapsed = firstWith('耗时：');
  final String? arguments = firstWith('参数：');
  final String? result = firstWith('结果：');
  final List<String> readable = <String>[
    if (target != null) compact(target),
    if (status != null || elapsed != null)
      <String>[?status, ?elapsed].join(' · '),
    if (arguments != null) compact(arguments),
    if (result != null) result.length <= 128 ? result : '结果：已保存完整输出，点击这一步查看',
  ];
  if (readable.isEmpty) {
    readable.addAll(source.map((String line) => compact(line)));
  }
  return readable.take(maxLines).join('\n');
}

class _AgentProgressStep {
  const _AgentProgressStep({
    required this.id,
    required this.title,
    required this.detail,
    required this.state,
    this.toolId,
  });

  final String id;
  final String title;
  final String detail;
  final _AgentProgressState state;
  final String? toolId;

  _AgentProgressStep copyWith({String? detail, _AgentProgressState? state}) =>
      _AgentProgressStep(
        id: id,
        title: title,
        detail: detail ?? this.detail,
        state: state ?? this.state,
        toolId: toolId,
      );
}

class _HarnessSessionRun {
  _HarnessSessionRun({
    required this.workspace,
    required this.sessionId,
    required this.messages,
    required this.assistantIndex,
    required this.clock,
    required this.progressSteps,
  });

  final String workspace;
  final String sessionId;
  final List<_AgentMessage> messages;
  final int assistantIndex;
  final Stopwatch clock;
  final List<_AgentProgressStep> progressSteps;
  HarnessAgentHandle? handle;
  VibekitsHarnessToolBridge? toolBridge;
  StreamSubscription<String>? outputSubscription;
  Completer<void>? stopCleanup;
  bool stopping = false;
  bool stopRequested = false;
  int progressSequence = 0;
}

class _SubmitAgentIntent extends Intent {
  const _SubmitAgentIntent();
}

class _ModelChoiceTile extends StatelessWidget {
  const _ModelChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _AgentMessage {
  const _AgentMessage._({
    required this.text,
    required this.user,
    this.elapsed,
    this.exitCode,
    this.stopped = false,
    this.executionTrace = '',
  });

  const _AgentMessage.user(String text) : this._(text: text, user: true);
  const _AgentMessage.assistant(String text) : this._(text: text, user: false);

  final String text;
  final bool user;
  final Duration? elapsed;
  final int? exitCode;
  final bool stopped;
  final String executionTrace;

  _AgentMessage copyWith({
    String? text,
    Duration? elapsed,
    int? exitCode,
    bool? stopped,
    String? executionTrace,
  }) => _AgentMessage._(
    text: text ?? this.text,
    user: user,
    elapsed: elapsed ?? this.elapsed,
    exitCode: exitCode ?? this.exitCode,
    stopped: stopped ?? this.stopped,
    executionTrace: executionTrace ?? this.executionTrace,
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.progressSteps = const <_AgentProgressStep>[],
    this.progressExpanded = false,
    this.onToggleProgress,
  });

  final _AgentMessage message;
  final List<_AgentProgressStep> progressSteps;
  final bool progressExpanded;
  final VoidCallback? onToggleProgress;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: SelectableText(message.text),
          ),
        ),
      );
    }
    final String footer = <String>[
      if (message.elapsed != null)
        '${(message.elapsed!.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
      if (message.stopped) '已停止',
      if (message.exitCode != null && message.exitCode != 0 && !message.stopped)
        '退出代码 ${message.exitCode}',
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 27,
          height: 27,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.terminal, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectionArea(
                key: const Key('agent-response'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (progressSteps.isNotEmpty)
                      _AgentProgressView(
                        steps: progressSteps,
                        expanded: progressExpanded,
                        onToggle: onToggleProgress,
                      )
                    else if (message.executionTrace.isNotEmpty)
                      _PersistedExecutionTrace(trace: message.executionTrace),
                    if (message.text.isNotEmpty)
                      MarkdownBody(
                        data: message.text,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(fontSize: 13.5, height: 1.55),
                          code: const TextStyle(
                            fontFamily: 'Cascadia Mono',
                            fontSize: 12.5,
                          ),
                          codeblockPadding: const EdgeInsets.all(11),
                          codeblockDecoration: BoxDecoration(
                            color: context.vibe.panelRaised,
                            border: Border.all(color: context.vibe.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      )
                    else if (progressSteps.isEmpty &&
                        message.executionTrace.isEmpty)
                      Row(
                        children: <Widget>[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在分析…',
                            style: TextStyle(color: context.vibe.muted),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (message.text.isNotEmpty) ...<Widget>[
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: '复制回复',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    if (footer.isNotEmpty)
                      Text(
                        footer,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.vibe.muted,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HarnessSessionDragPayload {
  const _HarnessSessionDragPayload({
    required this.workspace,
    required this.session,
  });

  final String workspace;
  final HarnessConversationSession session;
}

class _SessionMoveMenuButton extends StatefulWidget {
  const _SessionMoveMenuButton({
    required this.sourceWorkspace,
    required this.session,
    required this.activeWorkspace,
    required this.workspaceNames,
    required this.targets,
    required this.moveEnabled,
    required this.onSelected,
    this.buttonKey,
  });

  final Key? buttonKey;
  final String sourceWorkspace;
  final HarnessConversationSession session;
  final bool activeWorkspace;
  final Map<String, String> workspaceNames;
  final List<String> targets;
  final bool moveEnabled;
  final Future<void> Function(String target) onSelected;

  @override
  State<_SessionMoveMenuButton> createState() => _SessionMoveMenuButtonState();
}

class _SessionMoveMenuButtonState extends State<_SessionMoveMenuButton> {
  final MenuController _controller = MenuController();

  String _workspaceName(String path) =>
      widget.workspaceNames[path] ?? path.replaceAll('\\', '/').split('/').last;

  String _updatedTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const Color foreground = Color(0xFF20231F);
    const Color muted = Color(0xFF73776F);
    const Color accent = Color(0xFF3B6655);
    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      alignmentOffset: const Offset(8, -8),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.zero,
        ),
        backgroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
        elevation: const WidgetStatePropertyAll<double>(12),
        shadowColor: const WidgetStatePropertyAll<Color>(Color(0x33000000)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      menuChildren: <Widget>[
        Semantics(
          container: true,
          label: '会话所属项目与移动目标',
          child: SizedBox(
            width: 336,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0EB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          size: 19,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _workspaceName(widget.sourceWorkspace),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: foreground,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: <Widget>[
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: widget.activeWorkspace
                                        ? const Color(0xFF38A169)
                                        : const Color(0xFF97A09A),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  widget.activeWorkspace ? '当前项目' : '来源项目',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _updatedTime(widget.session.updatedAt),
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.account_tree_outlined,
                        size: 15,
                        color: muted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          widget.sourceWorkspace,
                          key: const Key('agent-session-source-workspace-path'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Divider(height: 1, color: Color(0xFFE6E9E4)),
                  ),
                  const Text(
                    '移动到项目',
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (!widget.moveEnabled)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 7),
                      child: Text(
                        '任务运行中，可查看归属；结束后可移动会话',
                        style: TextStyle(color: muted, fontSize: 10.5),
                      ),
                    ),
                  for (final String target in widget.targets)
                    Semantics(
                      button: true,
                      label: '移动会话到 ${_workspaceName(target)}',
                      child: InkWell(
                        key: ValueKey<String>(
                          'agent-session-move-target-$target',
                        ),
                        borderRadius: BorderRadius.circular(11),
                        onTap: widget.moveEnabled
                            ? () {
                                _controller.close();
                                unawaited(widget.onSelected(target));
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 9,
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.folder_outlined,
                                size: 19,
                                color: accent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      _workspaceName(target),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: foreground,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      target,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
      builder:
          (BuildContext context, MenuController controller, Widget? child) =>
              IconButton(
                key: widget.buttonKey,
                tooltip: '会话所属项目与移动',
                visualDensity: VisualDensity.compact,
                onPressed: controller.isOpen
                    ? controller.close
                    : controller.open,
                icon: const Icon(Icons.more_horiz, size: 18),
              ),
    );
  }
}

class _PersistedExecutionTrace extends StatefulWidget {
  const _PersistedExecutionTrace({required this.trace});

  final String trace;

  @override
  State<_PersistedExecutionTrace> createState() =>
      _PersistedExecutionTraceState();
}

class _PersistedExecutionTraceState extends State<_PersistedExecutionTrace> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final int stepCount = RegExp(
      r'^[◌✓!] \*\*',
      multiLine: true,
    ).allMatches(widget.trace).length;
    return Container(
      key: const Key('agent-persisted-execution-trace'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.vibe.canvas,
        border: Border.all(color: context.vibe.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const Key('agent-persisted-trace-toggle'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: context.vibe.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '执行时间线${stepCount == 0 ? '' : ' · $stepCount 步'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _expanded ? '收起' : '展开',
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              key: const Key('agent-persisted-trace-details'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
              child: MarkdownBody(
                data: widget.trace,
                selectable: false,
                styleSheet: MarkdownStyleSheet(
                  h3: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  p: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: context.vibe.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentProgressView extends StatelessWidget {
  const _AgentProgressView({
    required this.steps,
    required this.expanded,
    required this.onToggle,
  });

  final List<_AgentProgressStep> steps;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final _AgentProgressStep latest = steps.last;
    final int finished = steps
        .where(
          (_AgentProgressStep step) => step.state != _AgentProgressState.active,
        )
        .length;
    return Container(
      key: const Key('agent-reasoning-progress'),
      decoration: BoxDecoration(
        color: context.vibe.canvas,
        border: Border.all(color: context.vibe.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const Key('agent-progress-toggle'),
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: <Widget>[
                  _ProgressStateIcon(state: latest.state),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '执行时间线 · $finished/${steps.length} 步',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          latest.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.vibe.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    expanded ? '收起' : '展开',
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              key: const Key('agent-progress-details'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
              child: Column(
                children: <Widget>[
                  Divider(height: 1, color: context.vibe.border),
                  const SizedBox(height: 9),
                  for (int index = 0; index < steps.length; index++)
                    InkWell(
                      key: Key('agent-progress-step-${steps[index].id}'),
                      borderRadius: BorderRadius.circular(7),
                      onTap: steps[index].detail.length <= 180
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (BuildContext dialogContext) =>
                                  AlertDialog(
                                    title: Text(steps[index].title),
                                    content: SizedBox(
                                      width: 620,
                                      child: SingleChildScrollView(
                                        child: SelectableText(
                                          steps[index].detail,
                                          style: const TextStyle(
                                            fontFamily: 'Cascadia Mono',
                                            fontSize: 12,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text('关闭'),
                                      ),
                                    ],
                                  ),
                            ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: index == steps.length - 1 ? 0 : 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _ProgressStateIcon(
                                state: steps[index].state,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    steps[index].title,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _readableTimelineDetail(
                                      steps[index].detail,
                                    ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      color: context.vibe.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (steps[index].detail.length > 180)
                              Padding(
                                padding: const EdgeInsets.only(left: 6, top: 1),
                                child: Icon(
                                  Icons.open_in_new,
                                  size: 12,
                                  color: context.vibe.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressStateIcon extends StatelessWidget {
  const _ProgressStateIcon({required this.state});

  final _AgentProgressState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    _AgentProgressState.active => const SizedBox.square(
      dimension: 13,
      child: CircularProgressIndicator(strokeWidth: 1.8),
    ),
    _AgentProgressState.completed => Icon(
      Icons.check_circle_outline,
      size: 14,
      color: context.vibe.success,
    ),
    _AgentProgressState.failed => const Icon(
      Icons.error_outline,
      size: 14,
      color: VibekitsColors.danger,
    ),
  };
}
