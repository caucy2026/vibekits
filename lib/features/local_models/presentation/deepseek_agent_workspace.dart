import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../app/app_theme.dart';
import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/harness_conversation_store.dart';
import '../../dev_tools/domain/harness_tool_activity_store.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/platform_credential_store.dart';

typedef AgentDirectoryPicker = Future<String?> Function();
typedef AgentCredentialReader = Future<String?> Function(String key);
typedef AgentCredentialWriter = Future<void> Function(String key, String value);

class DeepSeekAgentWorkspace extends StatefulWidget {
  const DeepSeekAgentWorkspace({
    super.key,
    this.initialWorkspace = '',
    this.onWorkspaceChanged,
    this.onRunningChanged,
    this.checkEnvironment = DeepSeekHarnessService.checkEnvironment,
    this.runAgent = DeepSeekHarnessService.startAgent,
    this.listModels = DeepSeekHarnessService.listModels,
    this.pickDirectory,
    this.credentialReader,
    this.credentialWriter,
    this.loadConversation = HarnessConversationStore.load,
    this.saveConversation = HarnessConversationStore.save,
  });

  final String initialWorkspace;
  final Future<void> Function(String workspace)? onWorkspaceChanged;
  final ValueChanged<bool>? onRunningChanged;
  final HarnessEnvironmentChecker checkEnvironment;
  final HarnessAgentRunner runAgent;
  final HarnessModelLister listModels;
  final AgentDirectoryPicker? pickDirectory;
  final AgentCredentialReader? credentialReader;
  final AgentCredentialWriter? credentialWriter;
  final HarnessConversationLoader loadConversation;
  final HarnessConversationSaver saveConversation;

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
    text: widget.initialWorkspace,
  );
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController(
    text: DeepSeekHarnessService.defaultBaseUrl,
  );
  final TextEditingController _model = TextEditingController(
    text: DeepSeekHarnessService.defaultModel,
  );
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<_AgentMessage> _messages = <_AgentMessage>[];
  HarnessEnvironmentReport? _environment;
  HarnessAgentHandle? _handle;
  StreamSubscription<String>? _outputSubscription;
  Stopwatch? _runClock;
  bool _checking = true;
  bool _running = false;
  bool _stopping = false;
  bool _stopRequested = false;
  _AgentApprovalMode _approvalMode = _AgentApprovalMode.session;
  final Set<String> _sessionApprovals = <String>{};
  int _conversationEpoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_restoreConversation(widget.initialWorkspace));
    _checkEnvironment();
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
  }

  Future<void> _loadSettings() async {
    try {
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
      _sessionApprovals.clear();
    });
    if (notify) await widget.onWorkspaceChanged?.call(target);
    await _restoreConversation(target);
  }

  Future<void> _restoreConversation(String workspace) async {
    final String target = workspace.trim();
    final int epoch = ++_conversationEpoch;
    if (target.isEmpty) return;
    HarnessConversationSnapshot? snapshot;
    try {
      snapshot = await widget.loadConversation(target);
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
      _messages
        ..clear()
        ..addAll(
          snapshot?.messages.map(
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
    try {
      await widget.saveConversation(
        _workspace.text.trim(),
        <HarnessConversationMessage>[
          for (final _AgentMessage message in _messages)
            HarnessConversationMessage(
              text: message.text,
              user: message.user,
              elapsedMs: message.elapsed?.inMilliseconds,
              exitCode: message.exitCode,
              stopped: message.stopped,
            ),
        ],
      );
    } on Object {
      // A read-only workspace must not make the agent UI unusable.
    }
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
      approveTool: _approveHarnessTool,
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
      _messages
        ..add(_AgentMessage.user(prompt))
        ..add(const _AgentMessage.assistant(''));
      _composer.clear();
      _setRunning(true);
      _stopping = false;
      _stopRequested = false;
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
      _outputSubscription = handle.output.listen((String chunk) {
        if (!mounted || assistantIndex >= _messages.length) return;
        final String clean = chunk.replaceAll(_ansiEscape, '');
        if (clean.isEmpty) return;
        final bool stickToBottom = _nearBottom;
        setState(() {
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
    final String approvalKey = _approvalKey(request);
    if (_sessionApprovals.contains(approvalKey)) return true;
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
          if (_approvalMode == _AgentApprovalMode.session)
            OutlinedButton(
              key: const Key('agent-approve-session'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ApprovalDecision.allowSession),
              child: const Text('本会话允许同类操作'),
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
    if (decision == _ApprovalDecision.allowSession) {
      _sessionApprovals.add(approvalKey);
      if (mounted) setState(() {});
      return true;
    }
    return decision == _ApprovalDecision.allowOnce;
  }

  String _approvalKey(HarnessToolApprovalRequest request) =>
      '${request.tool.id}\u0000${request.target}\u0000${_approvalScope(request)}';

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
    if (_running || _messages.isEmpty) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('开始新任务？'),
        content: const Text('当前对话会从界面清除，工作区保持不变。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('新任务'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _messages.clear();
        _sessionApprovals.clear();
      });
      await _persistConversation();
      _composerFocus.requestFocus();
    }
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSettings() async {
    final bool initialLoggingEnabled =
        await HarnessToolActivityStore.loadLoggingEnabled();
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
          ],
        );
      },
    );
  }

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
                    itemBuilder: (BuildContext context, int index) =>
                        _MessageBubble(message: _messages[index]),
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
    final String sessionTitle =
        _messages
            .where((_AgentMessage message) => message.user)
            .map((_AgentMessage message) => message.text.trim())
            .firstOrNull ??
        '新会话';
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
              onPressed: _messages.isEmpty || _running ? null : _newTask,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.chat_bubble_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
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
            onPressed: _messages.isEmpty || _running ? null : _newTask,
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
                    PopupMenuButton<_ApprovalMenuAction>(
                      key: const Key('agent-permission-menu'),
                      tooltip: '工具权限',
                      onSelected: (_ApprovalMenuAction action) {
                        setState(() {
                          switch (action) {
                            case _ApprovalMenuAction.session:
                              _approvalMode = _AgentApprovalMode.session;
                            case _ApprovalMenuAction.alwaysAsk:
                              _approvalMode = _AgentApprovalMode.alwaysAsk;
                              _sessionApprovals.clear();
                            case _ApprovalMenuAction.clear:
                              _sessionApprovals.clear();
                          }
                        });
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<_ApprovalMenuAction>>[
                            const PopupMenuItem<_ApprovalMenuAction>(
                              value: _ApprovalMenuAction.session,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.shield_outlined),
                                title: Text('首次询问'),
                                subtitle: Text('同一目标的同类操作，本会话只确认一次'),
                              ),
                            ),
                            const PopupMenuItem<_ApprovalMenuAction>(
                              value: _ApprovalMenuAction.alwaysAsk,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.pan_tool_alt_outlined),
                                title: Text('每次询问'),
                                subtitle: Text('每个风险操作都单独确认'),
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<_ApprovalMenuAction>(
                              value: _ApprovalMenuAction.clear,
                              enabled: _sessionApprovals.isNotEmpty,
                              child: const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.restart_alt),
                                title: Text('清除本会话授权'),
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
                            const Icon(Icons.shield_outlined, size: 14),
                            const SizedBox(width: 5),
                            Text(
                              _approvalMode == _AgentApprovalMode.session
                                  ? '首次询问'
                                  : '每次询问',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (_sessionApprovals.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 4),
                              Text(
                                '${_sessionApprovals.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.vibe.muted,
                                ),
                              ),
                            ],
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

enum _AgentApprovalMode { session, alwaysAsk }

enum _ApprovalDecision { deny, allowOnce, allowSession }

enum _ApprovalMenuAction { session, alwaysAsk, clear }

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
  const _MessageBubble({required this.message});

  final _AgentMessage message;

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
                    ? Row(
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
