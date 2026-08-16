import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../dev_tools/domain/deepseek_harness_service.dart';

typedef AgentDirectoryPicker = Future<String?> Function();

class DeepSeekAgentWorkspace extends StatefulWidget {
  const DeepSeekAgentWorkspace({
    super.key,
    this.initialWorkspace = '',
    this.onWorkspaceChanged,
    this.checkEnvironment = DeepSeekHarnessService.checkEnvironment,
    this.runAgent = DeepSeekHarnessService.startAgent,
    this.pickDirectory,
  });

  final String initialWorkspace;
  final Future<void> Function(String workspace)? onWorkspaceChanged;
  final HarnessEnvironmentChecker checkEnvironment;
  final HarnessAgentRunner runAgent;
  final AgentDirectoryPicker? pickDirectory;

  @override
  State<DeepSeekAgentWorkspace> createState() => _DeepSeekAgentWorkspaceState();
}

class _DeepSeekAgentWorkspaceState extends State<DeepSeekAgentWorkspace> {
  late final TextEditingController _workspace = TextEditingController(
    text: widget.initialWorkspace,
  );
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_AgentMessage> _messages = <_AgentMessage>[];
  HarnessEnvironmentReport? _environment;
  HarnessAgentHandle? _handle;
  StreamSubscription<String>? _outputSubscription;
  bool _checking = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _checkEnvironment();
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _handle?.stop();
    _workspace.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkEnvironment() async {
    setState(() => _checking = true);
    final HarnessEnvironmentReport report = await widget.checkEnvironment();
    if (!mounted) return;
    setState(() {
      _environment = report;
      _checking = false;
    });
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
    setState(() => _workspace.text = path.trim());
    await widget.onWorkspaceChanged?.call(path.trim());
  }

  Future<void> _run() async {
    final String prompt = _composer.text.trim();
    if (_running || prompt.isEmpty) return;
    final HarnessAgentRequest request = HarnessAgentRequest(
      workspace: _workspace.text.trim(),
      prompt: prompt,
    );
    try {
      request.validate();
    } on FormatException catch (error) {
      _show(error.message);
      return;
    }
    await widget.onWorkspaceChanged?.call(request.workspace);
    final int assistantIndex = _messages.length + 1;
    setState(() {
      _messages
        ..add(_AgentMessage.user(prompt))
        ..add(const _AgentMessage.assistant(''));
      _composer.clear();
      _running = true;
    });
    _scrollToEnd();
    try {
      final HarnessAgentHandle handle = await widget.runAgent(request);
      if (!mounted) {
        await handle.stop();
        return;
      }
      _handle = handle;
      _outputSubscription = handle.output.listen((String chunk) {
        if (!mounted || assistantIndex >= _messages.length) return;
        setState(() {
          _messages[assistantIndex] = _AgentMessage.assistant(
            '${_messages[assistantIndex].text}$chunk',
          );
        });
        _scrollToEnd();
      });
      final int code = await handle.exitCode;
      final Future<void>? cancelOutput = _outputSubscription?.cancel();
      if (cancelOutput != null) unawaited(cancelOutput);
      if (!mounted) return;
      setState(() {
        _running = false;
        _handle = null;
        if (_messages[assistantIndex].text.trim().isEmpty) {
          _messages[assistantIndex] = _AgentMessage.assistant(
            code == 0 ? '任务已完成。' : '智能体退出，代码 $code。请检查模型配置。',
          );
        } else if (code != 0) {
          _messages[assistantIndex] = _AgentMessage.assistant(
            '${_messages[assistantIndex].text}\n\n进程退出代码：$code',
          );
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _handle = null;
        _messages[assistantIndex] = _AgentMessage.assistant('启动失败：$error');
      });
    }
    _scrollToEnd();
  }

  Future<void> _stop() async {
    final HarnessAgentHandle? handle = _handle;
    if (handle == null) return;
    await handle.stop();
    if (mounted) {
      setState(() {
        _running = false;
        _handle = null;
      });
    }
  }

  void _scrollToEnd() {
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

  void _show(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final HarnessEnvironmentReport? environment = _environment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('agent-workspace'),
                  controller: _workspace,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: '工作区',
                    hintText: '选择智能体可操作的项目目录',
                    prefixIcon: Icon(Icons.folder_outlined, size: 19),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('agent-pick-workspace'),
                onPressed: _running ? null : _pickWorkspace,
                child: const Text('选择'),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: environment?.message ?? '正在检查环境',
                child: Row(
                  children: <Widget>[
                    Icon(
                      _checking
                          ? Icons.sync
                          : environment?.ready == true
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 17,
                      color: environment?.ready == true
                          ? VibekitsColors.primary
                          : context.vibe.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _checking
                          ? '检查环境…'
                          : environment?.ready == true
                          ? '环境就绪'
                          : '需要 Node.js',
                      style: TextStyle(fontSize: 12, color: context.vibe.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '重新检查环境',
                onPressed: _running ? null : _checkEnvironment,
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.vibe.panelRaised,
                border: Border.all(color: context.vibe.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      key: const Key('agent-conversation'),
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) =>
                          _MessageBubble(message: _messages[index]),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('agent-composer'),
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !_running,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '描述任务，例如：检查项目并修复失败的测试',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              if (_running)
                FilledButton.tonalIcon(
                  key: const Key('agent-stop'),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止'),
                )
              else
                FilledButton.icon(
                  key: const Key('agent-send'),
                  onPressed: environment?.ready == true ? _run : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  label: const Text('运行'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.terminal, size: 38),
            const SizedBox(height: 12),
            const Text(
              'DeepSeek 智能体',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '选择项目目录并描述目标。智能体会读取项目、执行命令并流式返回结果；运行中可随时停止。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.vibe.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentMessage {
  const _AgentMessage._(this.text, this.user);
  const _AgentMessage.user(String text) : this._(text, true);
  const _AgentMessage.assistant(String text) : this._(text, false);

  final String text;
  final bool user;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _AgentMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: message.user
                ? Theme.of(context).colorScheme.primaryContainer
                : context.vibe.panel,
            border: Border.all(color: context.vibe.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            message.text.isEmpty ? '正在思考…' : message.text,
            key: message.user ? null : const Key('agent-response'),
            style: const TextStyle(height: 1.45),
          ),
        ),
      ),
    );
  }
}
