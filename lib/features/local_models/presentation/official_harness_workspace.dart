import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/harness_session_store.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/harness_work_status.dart';
import '../../dev_tools/domain/platform_credential_store.dart';
import '../../dev_tools/domain/rustdesk_harness_share_service.dart';

typedef OfficialHarnessCredentialReader = Future<String?> Function(String key);
typedef OfficialHarnessCredentialDeleter = Future<void> Function(String key);
typedef OfficialHarnessWebStarter = Future<HarnessSessionHandle> Function(
  HarnessWebRequest request,
);

/// Hosts the official `@deepseek-ai/dsh-web-app` inside Vibekits.
///
/// Workspace/session/conversation/permission state is owned by DSH itself.
/// Vibekits only supplies the bundled runtime, credential, debug paths and MCP
/// bridge, avoiding a second incompatible conversation model in Flutter.
class OfficialHarnessWorkspace extends StatefulWidget {
  const OfficialHarnessWorkspace({
    super.key,
    this.initialWorkspace = '',
    this.initialDebugDirectory = '',
    this.onRunningChanged,
    this.credentialReader,
    this.credentialDeleter,
    this.remoteWorkspaceLauncher,
    this.screenshotOcrRunner,
    this.externalPrompt = '',
    this.externalPromptSerial = 0,
    this.startWeb = DeepSeekHarnessService.startWebAgent,
    this.findPort = DeepSeekHarnessService.findFreeLoopbackPort,
    this.rustDeskExecutable = '',
    this.rustDeskWebClientUrl = '',
  });

  final String initialWorkspace;
  final String initialDebugDirectory;
  final ValueChanged<bool>? onRunningChanged;
  final OfficialHarnessCredentialReader? credentialReader;
  final OfficialHarnessCredentialDeleter? credentialDeleter;
  final HarnessRemoteWorkspaceLauncher? remoteWorkspaceLauncher;
  final HarnessScreenshotOcrRunner? screenshotOcrRunner;
  final String externalPrompt;
  final int externalPromptSerial;
  final OfficialHarnessWebStarter startWeb;
  final Future<int> Function() findPort;
  final String rustDeskExecutable;
  final String rustDeskWebClientUrl;

  @override
  State<OfficialHarnessWorkspace> createState() =>
      _OfficialHarnessWorkspaceState();
}

class _OfficialHarnessWorkspaceState extends State<OfficialHarnessWorkspace> {
  static const String _credentialKey = 'deepseek-api-key';
  final WebviewController _webview = WebviewController();
  HarnessSessionHandle? _session;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<dynamic>? _webMessageSubscription;
  bool _loading = true;
  bool _starting = false;
  bool _webviewReady = false;
  bool _restartOverlay = false;
  String _status = '正在准备官方 Harness…';
  String _diagnostics = '';
  final Set<String> _sessionApprovedToolIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Let the workspace frame paint before credential, port and DSH startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  @override
  void didUpdateWidget(covariant OfficialHarnessWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalPromptSerial != oldWidget.externalPromptSerial &&
        _webviewReady) {
      unawaited(_injectExternalPrompt());
    }
  }

  Future<void> _initialize() async {
    try {
      final Future<void> webviewInitialization = _webview.initialize();
      await _start(webviewInitialization: webviewInitialization);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '官方 Harness 初始化失败：$error';
      });
    }
  }

  Future<void> _start({
    int retries = 0,
    bool preserveWebview = false,
    Future<void>? webviewInitialization,
  }) async {
    if (_starting) return;
    final String preferredWorkspace = widget.initialWorkspace.trim();
    final String workspace =
        preferredWorkspace.isNotEmpty &&
            Directory(preferredWorkspace).existsSync()
        ? preferredWorkspace
        : Directory.current.absolute.path;
    setState(() {
      _sessionApprovedToolIds.clear();
      _starting = true;
      _loading = true;
      _restartOverlay = preserveWebview;
      _status = '正在启动官方 DSH Web…';
      _diagnostics = '';
    });
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.starting,
      message: '正在启动本地 Harness',
      target: workspace,
    );
    try {
      final String key =
          await (widget.credentialReader ?? PlatformCredentialStore.read)(
            _credentialKey,
          ) ??
          '';
      final HarnessCredentialMigration migration =
          await DeepSeekHarnessService.migrateLegacyCredentialToOfficialStore(
            key,
          );
      if (migration != HarnessCredentialMigration.noLegacyCredential) {
        try {
          await (widget.credentialDeleter ?? PlatformCredentialStore.delete)(
            _credentialKey,
          );
        } on Object {
          // Migration is already durable. A stale legacy copy must never block
          // the official Web UI; it is no longer injected into the process.
        }
      }
      final int port = await widget.findPort();
      final HarnessSessionHandle session = await widget.startWeb(
        HarnessWebRequest(
          workspace: workspace,
          apiKey: '',
          port: port,
          debugDirectory: widget.initialDebugDirectory,
          approveTool: _approveVibekitsTool,
          toolBridge: VibekitsHarnessToolBridge(
            remoteWorkspaceLauncher: widget.remoteWorkspaceLauncher,
            screenshotOcrRunner: widget.screenshotOcrRunner,
          ),
        ),
      );
      if (!mounted) {
        await session.stop();
        return;
      }
      _session = session;
      widget.onRunningChanged?.call(true);
      await _outputSubscription?.cancel();
      _outputSubscription = session.output.listen((String chunk) {
        if (!mounted) return;
        setState(() {
          _diagnostics = '$_diagnostics$chunk';
          if (_diagnostics.length > 12000) {
            _diagnostics = _diagnostics.substring(_diagnostics.length - 12000);
          }
        });
      });
      unawaited(
        session.exitCode.then((int code) {
          if (!mounted || !identical(_session, session)) return;
          _session = null;
          widget.onRunningChanged?.call(false);
          setState(() {
            _loading = false;
            _status = '官方 Harness 已退出（代码 $code）';
          });
          HarnessWorkStatusHub.publish(
            phase: HarnessWorkPhase.stopped,
            message: 'Harness 已退出（代码 $code）',
          );
        }),
      );
      await _waitUntilReady(session.url);
      if (!mounted || !identical(_session, session)) return;
      if (!_webviewReady) {
        if (webviewInitialization == null) {
          await _webview.initialize();
        } else {
          await webviewInitialization;
        }
        if (!mounted || !identical(_session, session)) return;
        _webviewReady = true;
        _webMessageSubscription = _webview.webMessage.listen(_handleWebMessage);
      }
      await _webview.loadUrl(session.url.toString());
      unawaited(_injectExternalPrompt());
      setState(() {
        _starting = false;
        _loading = false;
        _restartOverlay = false;
        _status = '官方 Harness 已就绪';
      });
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.ready,
        message: 'Harness 已就绪',
        target: workspace,
      );
    } on Object catch (error) {
      final HarnessSessionHandle? session = _session;
      _session = null;
      if (session != null && session.running) await session.stop();
      widget.onRunningChanged?.call(false);
      if (!mounted) return;
      if (retries > 0) {
        setState(() {
          _starting = false;
          _status = '正在重新连接官方 Harness…';
        });
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        await _start(
          retries: retries - 1,
          preserveWebview: preserveWebview,
          webviewInitialization: webviewInitialization,
        );
        return;
      }
      setState(() {
        _starting = false;
        _loading = false;
        _restartOverlay = false;
        _status = '启动失败：$error';
      });
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.failed,
        message: 'Harness 启动失败',
      );
    }
  }

  Future<bool> _approveVibekitsTool(HarnessToolApprovalRequest request) async {
    if (request.tool.risk == HarnessToolRisk.readOnly ||
        _sessionApprovedToolIds.contains(request.tool.id)) {
      return true;
    }
    if (!mounted) return false;
    final _ToolApprovalDecision? decision =
        await showDialog<_ToolApprovalDecision>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text('允许 ${request.tool.name}？'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(request.tool.description),
                  if (request.target.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    SelectableText('目标：${request.target}'),
                  ],
                  if (request.arguments.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    SelectableText(
                      request.arguments.entries
                          .map((item) => '${item.key}: ${item.value}')
                          .join('\n'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _ToolApprovalDecision.deny),
                child: const Text('拒绝'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _ToolApprovalDecision.allowSession,
                ),
                child: const Text('本次运行允许同类操作'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _ToolApprovalDecision.allowOnce,
                ),
                child: const Text('允许一次'),
              ),
            ],
          ),
        );
    if (decision == _ToolApprovalDecision.allowSession) {
      _sessionApprovedToolIds.add(request.tool.id);
      return true;
    }
    return decision == _ToolApprovalDecision.allowOnce;
  }

  Future<void> _waitUntilReady(Uri url) async {
    const Duration startupLimit = Duration(minutes: 3);
    final Stopwatch stopwatch = Stopwatch()..start();
    int lastReportedSecond = -1;
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 400);
    try {
      while (stopwatch.elapsed < startupLimit) {
        if (_session?.running != true) {
          throw StateError('Harness 在控制台就绪前退出');
        }
        final int elapsedSeconds = stopwatch.elapsed.inSeconds;
        if (elapsedSeconds >= 5 &&
            elapsedSeconds ~/ 5 != lastReportedSecond ~/ 5) {
          lastReportedSecond = elapsedSeconds;
          if (mounted) {
            setState(() {
              _status = elapsedSeconds < 30
                  ? '正在加载本地 DSH 组件…（$elapsedSeconds 秒）'
                  : '本地 DSH 首次装载较慢，仍在继续…（$elapsedSeconds 秒）';
            });
          }
        }
        try {
          final HttpClientRequest request = await client
              .getUrl(url)
              .timeout(const Duration(milliseconds: 500));
          final HttpClientResponse response = await request.close().timeout(
            const Duration(milliseconds: 700),
          );
          await response.drain<void>();
          if (response.statusCode >= 200 && response.statusCode < 500) return;
        } on Object {
          // Server is still composing the official Web profile.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw TimeoutException('本地 DSH 在 3 分钟内未完成启动，请查看 Harness 调试日志');
    } finally {
      stopwatch.stop();
      client.close(force: true);
    }
  }

  Future<void> _pasteIntoFocusedWebField() async {
    final String? text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || !_webviewReady) return;
    final String value = jsonEncode(text);
    await _webview.executeScript('''
(() => {
  const element = document.activeElement;
  if (!(element instanceof HTMLInputElement ||
        element instanceof HTMLTextAreaElement) ||
      element.disabled || element.readOnly) return false;
  const start = element.selectionStart ?? element.value.length;
  const end = element.selectionEnd ?? start;
  const pasted = $value;
  const next = element.value.slice(0, start) + pasted + element.value.slice(end);
  const prototype = element instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype
      : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
  if (setter) setter.call(element, next);
  else element.value = next;
  element.dispatchEvent(new InputEvent('input', {
    bubbles: true,
    inputType: 'insertFromPaste',
    data: pasted,
  }));
  element.setSelectionRange(start + pasted.length, start + pasted.length);
  return true;
})()
''');
  }

  Future<void> _injectExternalPrompt() async {
    final String prompt = widget.externalPrompt.trim();
    if (prompt.isEmpty || !_webviewReady) return;
    final String value = jsonEncode(prompt);
    for (int attempt = 0; attempt < 30; attempt++) {
      if (!mounted || !_webviewReady) return;
      try {
        final dynamic inserted = await _webview.executeScript('''
(() => {
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = window.getComputedStyle(element);
    return rect.width > 80 && rect.height > 20 &&
      style.display !== 'none' && style.visibility !== 'hidden';
  };
  const candidates = Array.from(document.querySelectorAll(
    'textarea:not([disabled]):not([readonly]), [contenteditable="true"]'
  )).filter(visible).sort((left, right) =>
    left.getBoundingClientRect().bottom - right.getBoundingClientRect().bottom
  );
  const element = candidates.at(-1);
  if (!element) return false;
  const prompt = $value;
  if (element instanceof HTMLTextAreaElement) {
    const setter = Object.getOwnPropertyDescriptor(
      HTMLTextAreaElement.prototype, 'value'
    )?.set;
    if (setter) setter.call(element, prompt);
    else element.value = prompt;
  } else {
    element.textContent = prompt;
  }
  element.dispatchEvent(new InputEvent('input', {
    bubbles: true,
    inputType: 'insertText',
    data: prompt,
  }));
  element.focus();
  return true;
})()
''');
        if (inserted == true || inserted.toString().toLowerCase() == 'true') {
          return;
        }
      } on Object {
        // The official app may still be replacing its initial loading DOM.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<WebviewPermissionDecision> _handleWebPermission(
    String url,
    WebviewPermissionKind kind,
    bool isUserInitiated,
  ) async {
    final Uri? origin = Uri.tryParse(url);
    final bool loopback =
        origin != null &&
        (origin.host == '127.0.0.1' || origin.host == 'localhost');
    if (loopback &&
        isUserInitiated &&
        kind == WebviewPermissionKind.clipboardRead) {
      return WebviewPermissionDecision.allow;
    }
    return WebviewPermissionDecision.deny;
  }

  void _handleWebMessage(dynamic message) {
    final Map<String, dynamic>? payload = message is Map
        ? Map<String, dynamic>.from(message)
        : message is String
        ? (jsonDecode(message) as Map?)?.cast<String, dynamic>()
        : null;
    if (payload?['type'] != 'vibekits.deleteSession') return;
    final String sessionId = (payload?['sessionId'] as String? ?? '').trim();
    final String title = (payload?['title'] as String? ?? '').trim();
    unawaited(_confirmDeleteSession(sessionId, title));
  }

  Future<void> _confirmDeleteSession(String sessionId, String title) async {
    if (!mounted || _starting || sessionId.isEmpty) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('删除这个会话？'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                '${title.isEmpty ? sessionId : title}\n\n聊天记录、推理过程和工具调用记录将被永久删除，无法从归档恢复。',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _starting = true;
      _loading = true;
      _restartOverlay = true;
      _status = '正在删除会话…';
    });
    try {
      final HarnessSessionHandle? session = _session;
      _session = null;
      if (session != null && session.running) await session.stop();
      widget.onRunningChanged?.call(false);
      await HarnessSessionStore().deleteSession(sessionId);
      _starting = false;
      await _start(retries: 1, preserveWebview: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _loading = false;
        _restartOverlay = false;
        _status = '删除会话失败：$error';
      });
    }
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _webMessageSubscription?.cancel();
    final HarnessSessionHandle? session = _session;
    if (session != null && session.running) unawaited(session.stop());
    widget.onRunningChanged?.call(false);
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.stopped,
      message: 'Harness 工作区已关闭',
    );
    _webview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_webviewReady && _restartOverlay) {
      return Stack(
        children: <Widget>[
          Webview(_webview, permissionRequested: _handleWebPermission),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: IgnorePointer(
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(_status, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!_webviewReady || _loading || _session == null) {
      return Center(
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_loading)
                const CircularProgressIndicator()
              else
                Icon(
                  Icons.error_outline_rounded,
                  size: 34,
                  color: Theme.of(context).colorScheme.error,
                ),
              const SizedBox(height: 14),
              Text(_status, textAlign: TextAlign.center),
              if (_diagnostics.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _diagnostics
                      .split('\n')
                      .where((line) => line.isNotEmpty)
                      .last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (!_starting && !_loading) ...<Widget>[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final ShortcutActivator paste = SingleActivator(
      LogicalKeyboardKey.keyV,
      control: !Platform.isMacOS,
      meta: Platform.isMacOS,
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        paste: () => unawaited(_pasteIntoFocusedWebField()),
      },
      child: Stack(
        children: <Widget>[
          Webview(_webview, permissionRequested: _handleWebPermission),
          Positioned(
            right: 12,
            top: 10,
            child: StreamBuilder<HarnessWorkSnapshot>(
              stream: HarnessWorkStatusHub.changes,
              initialData: HarnessWorkStatusHub.latest,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<HarnessWorkSnapshot> snapshot,
                  ) {
                    final HarnessWorkSnapshot status =
                        snapshot.data ?? HarnessWorkStatusHub.latest;
                    return Material(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: 0.94),
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        key: const Key('harness-remote-share'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showRemoteShare,
                        child: Tooltip(
                          message: status.busy
                              ? status.message
                              : 'Harness 远程分享',
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(
                              status.busy
                                  ? Icons.sync_rounded
                                  : Icons.screen_share_outlined,
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRemoteShare() => showDialog<void>(
    context: context,
    builder: (BuildContext context) => _HarnessRemoteShareDialog(
      configuredExecutable: widget.rustDeskExecutable,
      webClientUrl: widget.rustDeskWebClientUrl,
    ),
  );
}

class _HarnessRemoteShareDialog extends StatefulWidget {
  const _HarnessRemoteShareDialog({
    required this.configuredExecutable,
    required this.webClientUrl,
  });

  final String configuredExecutable;
  final String webClientUrl;

  @override
  State<_HarnessRemoteShareDialog> createState() =>
      _HarnessRemoteShareDialogState();
}

class _HarnessRemoteShareDialogState extends State<_HarnessRemoteShareDialog> {
  late final Future<RustDeskHostInfo> _host =
      RustDeskHarnessShareService.inspect(
        configuredExecutable: widget.configuredExecutable,
      );
  String _message = '';
  String _resolvedWebClientUrl = '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolveWebClientUrl());
  }

  Future<void> _resolveWebClientUrl() async {
    final String configured = widget.webClientUrl.trim();
    final String resolved = configured.isNotEmpty
        ? configured
        : await RustDeskHarnessShareService.discoverWebClientUrl();
    if (mounted) setState(() => _resolvedWebClientUrl = resolved);
  }

  Future<void> _launchHost(RustDeskHostInfo host) async {
    try {
      await RustDeskHarnessShareService.launchHost(host.executable);
      if (mounted) setState(() => _message = 'RustDesk 已启动');
    } on Object catch (error) {
      if (mounted) setState(() => _message = '启动失败：$error');
    }
  }

  Future<void> _openWeb() async {
    try {
      await RustDeskHarnessShareService.openWebClient(_resolvedWebClientUrl);
      if (mounted) setState(() => _message = '已打开 RustDesk 网页端');
    } on Object catch (error) {
      if (mounted) setState(() => _message = '打开失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Harness 远程分享'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          StreamBuilder<HarnessWorkSnapshot>(
            stream: HarnessWorkStatusHub.changes,
            initialData: HarnessWorkStatusHub.latest,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<HarnessWorkSnapshot> snapshot,
                ) {
                  final HarnessWorkSnapshot status =
                      snapshot.data ?? HarnessWorkStatusHub.latest;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      status.busy ? Icons.sync_rounded : Icons.task_alt_rounded,
                    ),
                    title: Text(status.message),
                    subtitle: Text(
                      status.target.isEmpty ? '只分享阶段、工具名和脱敏目标' : status.target,
                    ),
                  );
                },
          ),
          const Divider(),
          FutureBuilder<RustDeskHostInfo>(
            future: _host,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<RustDeskHostInfo> snapshot,
                ) {
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  final RustDeskHostInfo host = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SelectableText(host.message),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: host.available
                                ? () => _launchHost(host)
                                : null,
                            icon: const Icon(Icons.desktop_windows_outlined),
                            label: const Text('启动 RustDesk'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _resolvedWebClientUrl.isEmpty
                                ? null
                                : _openWeb,
                            icon: const Icon(Icons.open_in_browser_outlined),
                            label: const Text('打开网页端'),
                          ),
                        ],
                      ),
                      if (_resolvedWebClientUrl.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        SelectableText(
                          '网页端：$_resolvedWebClientUrl',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ],
                  );
                },
          ),
          const SizedBox(height: 12),
          const Text(
            'RustDesk 网页端通过 hbbs/hbbr 查看并操作本机 Vibekits。'
            'hbbr 不是通用 JSON 中继，因此不会把 API Key、提示词或文件正文发送给它。',
            style: TextStyle(fontSize: 12),
          ),
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(_message),
          ],
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

enum _ToolApprovalDecision { deny, allowOnce, allowSession }
