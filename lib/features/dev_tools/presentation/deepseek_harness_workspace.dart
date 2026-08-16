import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/deepseek_harness_service.dart';

typedef HarnessDirectoryPicker = Future<String?> Function();

class DeepSeekHarnessWorkspace extends StatefulWidget {
  const DeepSeekHarnessWorkspace({
    super.key,
    this.initialWorkspace = '',
    this.onWorkspaceChanged,
    this.checkEnvironment = DeepSeekHarnessService.checkEnvironment,
    this.startSession = DeepSeekHarnessService.start,
    this.openBrowser = DeepSeekHarnessService.openBrowser,
    this.pickDirectory,
  });

  final String initialWorkspace;
  final Future<void> Function(String workspace)? onWorkspaceChanged;
  final HarnessEnvironmentChecker checkEnvironment;
  final HarnessSessionStarter startSession;
  final HarnessBrowserOpener openBrowser;
  final HarnessDirectoryPicker? pickDirectory;

  @override
  State<DeepSeekHarnessWorkspace> createState() =>
      _DeepSeekHarnessWorkspaceState();
}

class _DeepSeekHarnessWorkspaceState extends State<DeepSeekHarnessWorkspace> {
  static const int _port = 3080;
  late final TextEditingController _workspaceController;
  HarnessEnvironmentReport? _environment;
  HarnessSessionHandle? _session;
  StreamSubscription<String>? _outputSubscription;
  bool _checking = false;
  bool _starting = false;
  bool _serverReady = false;
  bool _openedAutomatically = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _workspaceController = TextEditingController(text: widget.initialWorkspace);
    unawaited(_check());
  }

  @override
  void dispose() {
    _workspaceController.dispose();
    unawaited(_outputSubscription?.cancel());
    final HarnessSessionHandle? session = _session;
    if (session != null && session.running) unawaited(session.stop());
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final HarnessEnvironmentReport report = await widget.checkEnvironment();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _environment = report;
    });
  }

  Future<void> _pickWorkspace() async {
    final String? path = widget.pickDirectory != null
        ? await widget.pickDirectory!()
        : await getDirectoryPath(
            confirmButtonText: '选择工作区',
            initialDirectory: _workspaceController.text.trim().isEmpty
                ? null
                : _workspaceController.text.trim(),
          );
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _workspaceController.text = path.trim());
    await widget.onWorkspaceChanged?.call(path.trim());
  }

  Future<void> _start() async {
    if (_environment?.ready != true) {
      await _check();
      if (_environment?.ready != true) return;
    }
    final HarnessLaunchSpec spec = HarnessLaunchSpec(
      workspace: _workspaceController.text.trim(),
      port: _port,
    );
    setState(() {
      _starting = true;
      _serverReady = false;
      _openedAutomatically = false;
      _log = '正在启动官方 @deepseek-ai/dsh…\n首次运行需要下载组件，请稍候。\n';
    });
    try {
      spec.validate();
      await widget.onWorkspaceChanged?.call(spec.workspace);
      final HarnessSessionHandle session = await widget.startSession(spec);
      if (!mounted) {
        await session.stop();
        return;
      }
      _session = session;
      await _outputSubscription?.cancel();
      _outputSubscription = session.output.listen(_onOutput);
      setState(() => _starting = false);
      unawaited(
        session.exitCode.then((int code) {
          if (!mounted || _session != session) return;
          setState(() {
            _serverReady = false;
            _log = _appendLog(_log, '\nHarness 已退出（代码 $code）。\n');
          });
        }),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _log = _appendLog(_log, '\n启动失败：$error\n');
      });
    }
  }

  void _onOutput(String output) {
    if (!mounted) return;
    final bool ready =
        output.contains('http://127.0.0.1:$_port') ||
        output.contains('http://localhost:$_port');
    setState(() {
      _log = _appendLog(_log, output);
      if (ready) _serverReady = true;
    });
    if (ready && !_openedAutomatically) {
      _openedAutomatically = true;
      unawaited(_open());
    }
  }

  Future<void> _open() async {
    final HarnessSessionHandle? session = _session;
    if (session == null) return;
    try {
      await widget.openBrowser(session.url);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法打开浏览器：$error')));
    }
  }

  Future<void> _stop() async {
    final HarnessSessionHandle? session = _session;
    if (session == null) return;
    setState(() => _log = _appendLog(_log, '\n正在停止 Harness…\n'));
    await session.stop();
    if (!mounted) return;
    setState(() {
      _session = null;
      _serverReady = false;
      _starting = false;
    });
  }

  static String _appendLog(String current, String addition) {
    final String combined = '$current$addition';
    return combined.length <= 12000
        ? combined
        : combined.substring(combined.length - 12000);
  }

  @override
  Widget build(BuildContext context) {
    final bool running = _session?.running == true;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.smart_toy_outlined, color: colors.primary),
            const SizedBox(width: 10),
            Text(
              'DeepSeek Harness',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 10),
            const _PreviewBadge(),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '在选定项目中启动官方智能开发代理。配置模型、审批操作和管理会话都在同一个控制台完成。',
          style: TextStyle(color: context.vibe.muted),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '1  运行环境',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(
                    _environment?.ready == true
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                    color: _environment?.ready == true
                        ? VibekitsColors.primary
                        : VibekitsColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _checking
                          ? '正在检查 Node.js 与 npx…'
                          : _environment?.message ?? '等待检查',
                    ),
                  ),
                  if (_environment?.nodeVersion != null)
                    Text(
                      'Node ${_environment!.nodeVersion}',
                      style: TextStyle(fontSize: 12, color: context.vibe.muted),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '重新检查',
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '2  选择项目',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('harness-workspace'),
                controller: _workspaceController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: '选择允许代理访问的项目文件夹',
                  prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                  suffixIcon: TextButton(
                    key: const Key('harness-pick-workspace'),
                    onPressed: running || _starting ? null : _pickWorkspace,
                    child: const Text('选择'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Harness 可以读写该工作区并执行命令。建议先提交 Git，并在控制台逐项审批高风险操作。',
                style: TextStyle(fontSize: 12, color: context.vibe.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '3  启动控制台',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    key: const Key('harness-primary-action'),
                    onPressed: _starting
                        ? null
                        : running
                        ? _open
                        : _start,
                    icon: Icon(running ? Icons.open_in_new : Icons.play_arrow),
                    label: Text(
                      _starting
                          ? '正在启动…'
                          : running
                          ? '打开控制台'
                          : '启动 Harness',
                    ),
                  ),
                  if (running)
                    OutlinedButton.icon(
                      key: const Key('harness-stop'),
                      onPressed: _stop,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('停止'),
                    ),
                  if (running)
                    Chip(
                      avatar: Icon(
                        _serverReady ? Icons.check_circle : Icons.sync,
                        size: 16,
                      ),
                      label: Text(_serverReady ? '控制台已就绪' : '服务启动中'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '首次启动会从 npm 下载 DeepSeek 官方包；API 密钥在官方控制台中写入，不经过 Vibekits。',
                style: TextStyle(fontSize: 12, color: context.vibe.muted),
              ),
            ],
          ),
        ),
        if (_log.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '运行日志',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _log,
                  key: const Key('harness-log'),
                  style: const TextStyle(
                    fontFamily: 'Cascadia Mono',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: VibekitsColors.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text('开发者预览 · MIT', style: TextStyle(fontSize: 11)),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.vibe.border),
    ),
    child: child,
  );
}
