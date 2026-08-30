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
import '../../dev_tools/domain/harness_tool_activity_store.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/lan_harness_key_receiver.dart';
import '../../dev_tools/domain/lan_peer_discovery_service.dart';
import '../../dev_tools/domain/mcp_capability_directory.dart';
import '../../dev_tools/domain/mcp_capability_models.dart';
import '../../dev_tools/domain/mcp_device_identity.dart';
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
  final List<_AgentMessage> _messages = <_AgentMessage>[];
  final List<HarnessConversationSession> _sessions =
      <HarnessConversationSession>[];
  String? _activeSessionId;
  HarnessEnvironmentReport? _environment;
  HarnessAgentHandle? _handle;
  StreamSubscription<String>? _outputSubscription;
  Stopwatch? _runClock;
  bool _checking = true;
  bool _running = false;
  bool _stopping = false;
  bool _stopRequested = false;
  HarnessAgentPermissionMode _permissionMode =
      HarnessAgentPermissionMode.assisted;
  final List<_AgentProgressStep> _progressSteps = <_AgentProgressStep>[];
  bool _progressExpanded = true;
  int _progressSequence = 0;
  int _conversationEpoch = 0;
  final McpDeviceIdentity _mcpIdentity = McpDeviceIdentity.forVibekits();
  final McpExposurePreferences _mcpExposurePreferences =
      McpExposurePreferences();
  bool _mcpExposureEnabled = true;

  @override
  void initState() {
    super.initState();
    _adoptExternalPrompt();
    unawaited(_loadSettings());
    unawaited(_restoreConversation(widget.initialWorkspace));
    unawaited(_initializeMcp());
    _checkEnvironment();
  }

  Future<void> _initializeMcp() async {
    try {
      _mcpExposureEnabled = await _mcpExposurePreferences.loadEnabled();
      await LanPeerDiscoveryService.instance.start(
        instanceId: _mcpIdentity.instanceId,
        name: _mcpIdentity.displayName,
        hardwareCode: _mcpIdentity.hardwareCode,
        appId: _mcpIdentity.appId,
        capabilityDigest: VibekitsHarnessToolBridge.protocolVersion,
        exposureEnabled: _mcpExposureEnabled,
      );
      await McpCapabilityDirectory.instance.start(
        appBridge: VibekitsHarnessToolBridge(),
      );
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) _show('MCP 局域网发现启动失败：$error');
    }
  }

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
    unawaited(_persistConversation());
    _conversationEpoch++;
    _outputSubscription?.cancel();
    _handle?.stop();
    _workspace.dispose();
    _composer.dispose();
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _debugDirectory.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setRunning(bool value) {
    if (_running == value) return;
    _running = value;
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

  Future<void> _adoptWorkspace(String workspace, {bool notify = true}) async {
    final String target = workspace.trim();
    if (_running || target == _workspace.text.trim()) return;
    await _persistConversation();
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
        target != _workspace.text.trim() ||
        _running) {
      return;
    }
    setState(() {
      _sessions
        ..clear()
        ..addAll(project?.sessions ?? const <HarnessConversationSession>[]);
      _activeSessionId = project?.activeSessionId;
      final HarnessConversationSession? active = _sessions
          .where(
            (HarnessConversationSession session) =>
                session.id == _activeSessionId,
          )
          .firstOrNull;
      _messages
        ..clear()
        ..addAll(
          active?.messages.map(
                (HarnessConversationMessage message) => _AgentMessage._(
                  text: message.text,
                  user: message.user,
                  elapsed: message.elapsedMs == null
                      ? null
                      : Duration(milliseconds: message.elapsedMs!),
                  exitCode: message.exitCode,
                  stopped: message.stopped,
                ),
              ) ??
              const <_AgentMessage>[],
        );
    });
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
    final HarnessAgentRequest request = HarnessAgentRequest(
      workspace: _workspace.text.trim(),
      prompt: _contextualPrompt(prompt),
      apiKey: _apiKey.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      debugDirectory: _debugDirectory.text.trim(),
      permissionMode: _permissionMode,
      approveTool: _approveHarnessTool,
      toolBridge: VibekitsHarnessToolBridge(
        activityRecorder: _recordHarnessToolActivity,
      ),
    );
    if (request.apiKey.isEmpty) {
      _show('请先点右上角设置并填写 DeepSeek API Key');
      return;
    }
    try {
      request.validate();
    } on FormatException catch (error) {
      _show(error.message);
      return;
    }
    await widget.onWorkspaceChanged?.call(request.workspace);
    final int assistantIndex = _messages.length + 1;
    _runClock = Stopwatch()..start();
    setState(() {
      _ensureActiveSession(prompt);
      _messages
        ..add(_AgentMessage.user(prompt))
        ..add(const _AgentMessage.assistant(''));
      _composer.clear();
      _setRunning(true);
      _stopping = false;
      _stopRequested = false;
      _progressSteps
        ..clear()
        ..add(
          _AgentProgressStep(
            id: 'understand',
            title: '理解任务',
            detail: '正在分析目标、约束和当前工作区上下文',
            state: _AgentProgressState.active,
          ),
        );
      _progressExpanded = true;
    });
    unawaited(_persistConversation());
    _scrollToEnd(force: true);
    try {
      final HarnessAgentHandle handle = await widget.runAgent(request);
      if (!mounted) {
        await handle.stop();
        return;
      }
      _handle = handle;
      _replaceProgress(
        'understand',
        state: _AgentProgressState.completed,
        detail: '目标与上下文已整理，正在规划下一步',
      );
      _upsertProgress(
        const _AgentProgressStep(
          id: 'plan',
          title: '规划操作',
          detail: 'Harness 正在选择回复方式或可用工具',
          state: _AgentProgressState.active,
        ),
      );
      _outputSubscription = handle.output.listen((String chunk) {
        if (!mounted || assistantIndex >= _messages.length) return;
        final String clean = chunk.replaceAll(_ansiEscape, '');
        if (clean.isEmpty) return;
        final bool stickToBottom = _nearBottom;
        setState(() {
          _replaceProgress(
            'plan',
            state: _AgentProgressState.completed,
            detail: '执行路径已确定',
          );
          _upsertProgress(
            const _AgentProgressStep(
              id: 'response',
              title: '生成回复',
              detail: '正在整理执行结果并流式输出',
              state: _AgentProgressState.active,
            ),
          );
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            text: '${_messages[assistantIndex].text}$clean',
          );
        });
        _scrollToEnd(force: stickToBottom);
      });
      final int code = await handle.exitCode;
      final Future<void>? cancelOutput = _outputSubscription?.cancel();
      if (cancelOutput != null) unawaited(cancelOutput);
      if (!mounted) return;
      _runClock?.stop();
      setState(() {
        _completeActiveProgress(
          failed: code != 0 && !_stopRequested,
          detail: _stopRequested
              ? '任务已停止'
              : code == 0
              ? '回复与工具结果已完成'
              : 'Harness 退出代码 $code',
        );
        _setRunning(false);
        _stopping = false;
        _handle = null;
        final _AgentMessage current = _messages[assistantIndex];
        String text = current.text;
        if (text.trim().isEmpty) {
          text = _stopRequested
              ? '任务已停止。'
              : code == 0
              ? '任务已完成。'
              : '智能体退出，代码 $code。请检查模型配置。';
        } else if (code != 0 && !_stopRequested) {
          text = '$text\n\n进程退出代码：$code';
        }
        _messages[assistantIndex] = current.copyWith(
          text: text,
          elapsed: _runClock?.elapsed,
          exitCode: code,
          stopped: _stopRequested,
        );
      });
      await _persistConversation();
    } on Object catch (error) {
      if (!mounted) return;
      _runClock?.stop();
      setState(() {
        _completeActiveProgress(failed: true, detail: '启动失败：$error');
        _setRunning(false);
        _stopping = false;
        _handle = null;
        _messages[assistantIndex] = _messages[assistantIndex].copyWith(
          text: '启动失败：$error',
          elapsed: _runClock?.elapsed,
          exitCode: -1,
        );
      });
      await _persistConversation();
    }
    _scrollToEnd(force: true);
    _composerFocus.requestFocus();
  }

  Future<void> _stop() async {
    final HarnessAgentHandle? handle = _handle;
    if (handle == null || _stopping) return;
    setState(() {
      _stopping = true;
      _stopRequested = true;
    });
    await handle.stop();
  }

  Future<bool> _approveHarnessTool(HarnessToolApprovalRequest request) async {
    if (!mounted) return false;
    final String progressId = 'tool:${request.tool.id}:${_progressSequence++}';
    setState(() {
      _completeActiveProgress(detail: 'Harness 已选择工具操作');
      _progressSteps.add(
        _AgentProgressStep(
          id: progressId,
          toolId: request.tool.id,
          title: '调用 ${request.tool.name}',
          detail: request.target.isEmpty
              ? _approvalScope(request)
              : '${request.target} · ${_approvalScope(request)}',
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
                request.arguments.entries
                    .map(
                      (MapEntry<String, Object?> item) =>
                          '${item.key}: ${item.value}',
                    )
                    .join('\n'),
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
        );
      });
    }
    return allowed;
  }

  Future<void> _recordHarnessToolActivity({
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
    if (!mounted) return;
    setState(() {
      final int index = _progressSteps.lastIndexWhere(
        (_AgentProgressStep step) =>
            step.toolId == toolId && step.state == _AgentProgressState.active,
      );
      final _AgentProgressState state = switch (status) {
        HarnessToolActivityStatus.succeeded => _AgentProgressState.completed,
        HarnessToolActivityStatus.failed ||
        HarnessToolActivityStatus.denied => _AgentProgressState.failed,
      };
      final String detail = <String>[
        if (target.isNotEmpty) target,
        switch (status) {
          HarnessToolActivityStatus.succeeded => '执行成功',
          HarnessToolActivityStatus.failed => '执行失败',
          HarnessToolActivityStatus.denied => '未获批准',
        },
        '${DateTime.now().difference(startedAt).inMilliseconds} ms',
      ].join(' · ');
      if (index >= 0) {
        _progressSteps[index] = _progressSteps[index].copyWith(
          state: state,
          detail: detail,
        );
      } else {
        _progressSteps.add(
          _AgentProgressStep(
            id: 'tool:$toolId:${_progressSequence++}',
            toolId: toolId,
            title: '调用 $toolName',
            detail: detail,
            state: state,
          ),
        );
      }
      _upsertProgress(
        const _AgentProgressStep(
          id: 'continue',
          title: '继续分析',
          detail: '正在根据工具结果决定下一步',
          state: _AgentProgressState.active,
        ),
      );
    });
  }

  void _upsertProgress(_AgentProgressStep step) {
    final int index = _progressSteps.indexWhere(
      (_AgentProgressStep value) => value.id == step.id,
    );
    if (index < 0) {
      _progressSteps.add(step);
    } else {
      _progressSteps[index] = step;
    }
  }

  void _replaceProgress(
    String id, {
    String? detail,
    _AgentProgressState? state,
  }) {
    final int index = _progressSteps.indexWhere(
      (_AgentProgressStep step) => step.id == id,
    );
    if (index < 0) return;
    _progressSteps[index] = _progressSteps[index].copyWith(
      detail: detail,
      state: state,
    );
  }

  void _completeActiveProgress({bool failed = false, String? detail}) {
    for (int index = 0; index < _progressSteps.length; index++) {
      if (_progressSteps[index].state != _AgentProgressState.active) continue;
      _progressSteps[index] = _progressSteps[index].copyWith(
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
    if (_running || _workspace.text.trim().isEmpty) return;
    if (_messages.isEmpty && _activeSessionId != null) return;
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
      _sessions.insert(0, session);
      _activeSessionId = session.id;
      _messages.clear();
      _progressSteps.clear();
    });
    await _persistConversation();
    _composerFocus.requestFocus();
  }

  Future<void> _switchSession(String sessionId) async {
    if (_running || sessionId == _activeSessionId) return;
    await _persistConversation();
    if (!mounted) return;
    final HarnessConversationSession? session = _sessions
        .where(
          (HarnessConversationSession candidate) => candidate.id == sessionId,
        )
        .firstOrNull;
    if (session == null) return;
    setState(() {
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
            ),
          ),
        );
      _progressSteps.clear();
    });
    await _persistConversation();
    _scrollToEnd(force: true);
  }

  bool get _nearBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels < 120;

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
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
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
        final bool showSessionSidebar = constraints.maxWidth >= 1020;
        return Row(
          children: <Widget>[
            if (showSessionSidebar) ...<Widget>[
              SizedBox(width: 236, child: _buildSessionSidebar(environment)),
              VerticalDivider(width: 1, color: context.vibe.border),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: _buildChatWorkbench(environment),
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
    child: Column(
      children: <Widget>[
        const SizedBox(height: 10),
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
        const Spacer(),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
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
    if (enabled && !await _confirmMcpExposureRisk()) return;
    LanPeerDiscoveryService.instance.setExposureEnabled(enabled);
    setState(() => _mcpExposureEnabled = enabled);
    try {
      await _mcpExposurePreferences.saveEnabled(enabled);
    } on Object catch (error) {
      LanPeerDiscoveryService.instance.setExposureEnabled(!enabled);
      if (mounted) setState(() => _mcpExposureEnabled = !enabled);
      if (mounted) _show('保存 MCP 开关失败：$error');
    }
  }

  Future<bool> _confirmMcpExposureRisk() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('开启本机 MCP？'),
          content: const SizedBox(
            width: 520,
            child: Text(
              '开启后，本 APP 会在本机和局域网发布设备名称、硬件识别码、'
              '版本、连接端点和 MCP 工具清单。\n\n'
              '被发现的 Harness 可以读取工具参数并调用普通 MCP 工具，'
              '工具可能按其功能读取数据、写入文件或控制设备，后续不再逐次弹窗。'
              '远程 Harness 任务控制仍使用独立的授权流程。\n\n'
              '请仅在可信的本机和局域网中开启。关闭后会发送 goodbye，'
              '并从其他 VibeKits 的动态列表中消失。',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认开启'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showMcpDevices(McpCapabilityTier tier) async {
    final McpCapabilitySnapshot snapshot = await McpCapabilityDirectory.instance
        .snapshotForTask();
    if (!mounted) return;
    final List<McpDeviceCapability> devices = tier == McpCapabilityTier.local
        ? snapshot.local
        : snapshot.lan;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          tier == McpCapabilityTier.local ? '本机 MCP 设备' : '局域网 MCP 设备',
        ),
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
                          '${device.hardwareCode} · ${device.tools.length} 个接口',
                        ),
                        children: <Widget>[
                          for (final McpToolInterface tool in device.tools)
                            ListTile(
                              dense: true,
                              title: SelectableText(tool.name),
                              subtitle: Text(tool.description),
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

  Widget _buildChatWorkbench(HarnessEnvironmentReport? environment) {
    return Column(
      children: <Widget>[
        _buildHeader(environment),
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
                : ListView.separated(
                    key: const Key('agent-conversation'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    itemCount: _messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
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
                                () => _progressExpanded = !_progressExpanded,
                              )
                            : null,
                      );
                    },
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
    final String workspaceName = workspace.isEmpty
        ? '尚未选择项目'
        : workspace.replaceAll('\\', '/').split('/').last;
    return Material(
      key: const Key('agent-session-sidebar'),
      color: context.vibe.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton.tonalIcon(
              key: const Key('agent-new-session-sidebar'),
              onPressed: workspace.isEmpty || _running ? null : _newTask,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建会话'),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '项目',
                style: TextStyle(
                  color: context.vibe.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.folder_outlined, size: 18),
              title: Text(
                workspaceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: workspace.isEmpty ? const Text('点击选择工作区') : null,
              onTap: _running ? null : _pickWorkspace,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '会话',
                style: TextStyle(
                  color: context.vibe.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _sessions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        workspace.isEmpty ? '选择项目后开始会话' : '暂无会话',
                        style: TextStyle(
                          color: context.vibe.muted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 3),
                      itemBuilder: (BuildContext context, int index) {
                        final HarnessConversationSession session =
                            _sessions[index];
                        final bool selected = session.id == _activeSessionId;
                        return ListTile(
                          key: Key('agent-session-${session.id}'),
                          dense: true,
                          selected: selected,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.09),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Icon(
                            selected
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                            size: 15,
                          ),
                          title: Text(
                            session.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: _running
                              ? null
                              : () => _switchSession(session.id),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(
                environment?.ready == true
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 17,
              ),
              title: Text(
                environment?.ready == true ? 'Harness 已就绪' : '检查连接',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                _model.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
              onTap: _running ? null : _showSettings,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(HarnessEnvironmentReport? environment) {
    final String workspace = _workspace.text.trim();
    final String workspaceName = workspace.isEmpty
        ? '选择工作区'
        : workspace.replaceAll('\\', '/').split('/').last;
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          Tooltip(
            message: workspace.isEmpty ? '选择智能体可操作的项目目录' : workspace,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: TextButton.icon(
                key: const Key('agent-pick-workspace'),
                onPressed: _running ? null : _pickWorkspace,
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
          Tooltip(
            message: environment?.message ?? '正在检查环境',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_checking)
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
                Text(
                  _checking
                      ? '检查中'
                      : environment?.ready == true
                      ? 'Harness 就绪'
                      : '连接未就绪',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '重新检查',
            onPressed: _running ? null : _checkEnvironment,
            icon: const Icon(Icons.refresh, size: 18),
          ),
          if (Platform.isAndroid && _apiKey.text.isEmpty)
            OutlinedButton.icon(
              key: const Key('agent-lan-key-header'),
              onPressed: _running ? null : _receiveKeyOverLan,
              icon: const Icon(Icons.qr_code_2_outlined, size: 18),
              label: const Text('扫码输入 Key'),
            )
          else
            IconButton(
              key: const Key('agent-settings'),
              tooltip: _apiKey.text.isEmpty ? '设置模型与 API Key' : '模型设置',
              onPressed: _running ? null : _showSettings,
              icon: Icon(
                _apiKey.text.isEmpty ? Icons.key_outlined : Icons.tune_outlined,
                size: 18,
              ),
            ),
          IconButton(
            key: const Key('agent-new-task'),
            tooltip: '新任务',
            onPressed: workspace.isEmpty || _running ? null : _newTask,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: AnimatedBuilder(
          animation: _composerFocus,
          builder: (BuildContext context, Widget? child) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: context.vibe.panelRaised,
              border: Border.all(
                color: _composerFocus.hasFocus
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.55)
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
                        onTap: _running ? null : _showSettings,
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
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.10),
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
  });

  const _AgentMessage.user(String text) : this._(text: text, user: true);
  const _AgentMessage.assistant(String text) : this._(text: text, user: false);

  final String text;
  final bool user;
  final Duration? elapsed;
  final int? exitCode;
  final bool stopped;

  _AgentMessage copyWith({
    String? text,
    Duration? elapsed,
    int? exitCode,
    bool? stopped,
  }) => _AgentMessage._(
    text: text ?? this.text,
    user: user,
    elapsed: elapsed ?? this.elapsed,
    exitCode: exitCode ?? this.exitCode,
    stopped: stopped ?? this.stopped,
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.progressSteps = const <_AgentProgressStep>[],
    this.progressExpanded = true,
    this.onToggleProgress,
  });

  final _AgentMessage message;
  final List<_AgentProgressStep> progressSteps;
  final bool progressExpanded;
  final VoidCallback? onToggleProgress;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('回复已复制')));
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
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.10),
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
                child: message.text.isEmpty
                    ? progressSteps.isEmpty
                          ? Row(
                              children: <Widget>[
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '正在分析…',
                                  style: TextStyle(color: context.vibe.muted),
                                ),
                              ],
                            )
                          : _AgentProgressView(
                              steps: progressSteps,
                              expanded: progressExpanded,
                              onToggle: onToggleProgress,
                            )
                    : MarkdownBody(
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
    return Container(
      key: const Key('agent-reasoning-progress'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.vibe.canvas,
        border: Border.all(color: context.vibe.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            child: Row(
              children: <Widget>[
                _ProgressStateIcon(state: latest.state),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    latest.title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
              ],
            ),
          ),
          if (expanded) ...<Widget>[
            const SizedBox(height: 7),
            for (int index = 0; index < steps.length; index++)
              Padding(
                key: Key('agent-progress-step-${steps[index].id}'),
                padding: EdgeInsets.only(
                  left: 2,
                  bottom: index == steps.length - 1 ? 0 : 7,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _ProgressStateIcon(state: steps[index].state),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            steps[index].title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            steps[index].detail,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: context.vibe.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
