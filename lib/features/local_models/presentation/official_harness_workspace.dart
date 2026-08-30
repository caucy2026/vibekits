import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/feishu_harness_tasks.dart';
import '../../dev_tools/domain/harness_session_store.dart';
import '../../dev_tools/domain/harness_agent_preferences.dart';
import '../../dev_tools/domain/harness_runtime_log_store.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/harness_work_status.dart';
import '../../dev_tools/domain/lan_peer_discovery_service.dart';
import '../../dev_tools/domain/mcp_capability_directory.dart';
import '../../dev_tools/domain/mcp_capability_models.dart';
import '../../dev_tools/domain/mcp_device_identity.dart';
import '../../dev_tools/domain/platform_credential_store.dart';
import '../../dev_tools/domain/rustdesk_harness_link_status.dart';
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
    this.initialDownloadDirectory = '',
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
    this.preapprovedToolIds = const <String>{},
  });

  final String initialWorkspace;
  final String initialDebugDirectory;
  final String initialDownloadDirectory;
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
  final Set<String> preapprovedToolIds;

  @override
  State<OfficialHarnessWorkspace> createState() =>
      _OfficialHarnessWorkspaceState();
}

class _OfficialHarnessWorkspaceState extends State<OfficialHarnessWorkspace> {
  static const String _credentialKey = 'deepseek-api-key';
  static Future<String>? _conversationUxScript;
  final WebviewController _webview = WebviewController();
  HarnessSessionHandle? _session;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<dynamic>? _webMessageSubscription;
  StreamSubscription<LoadingState>? _loadingStateSubscription;
  bool _loading = true;
  bool _starting = false;
  bool _webviewReady = false;
  bool _restartOverlay = false;
  String _status = '正在准备官方 Harness…';
  String _diagnostics = '';
  final StringBuffer _pendingDiagnostics = StringBuffer();
  Timer? _diagnosticsTimer;
  final Set<String> _sessionApprovedToolIds = <String>{};
  HarnessAgentPermissionMode _permissionMode =
      HarnessAgentPermissionMode.assisted;
  final Set<String> _deletingSessionIds = <String>{};
  final McpDeviceIdentity _mcpIdentity = McpDeviceIdentity.forVibekits();
  final McpExposurePreferences _mcpExposurePreferences =
      McpExposurePreferences();
  bool _mcpExposureEnabled = true;
  bool _quickActionsExpanded = false;

  @override
  void initState() {
    super.initState();
    _sessionApprovedToolIds.addAll(widget.preapprovedToolIds);
    // Let the workspace frame paint before credential, port and DSH startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  @override
  void didUpdateWidget(covariant OfficialHarnessWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sessionApprovedToolIds.addAll(widget.preapprovedToolIds);
    if (widget.externalPromptSerial != oldWidget.externalPromptSerial &&
        _webviewReady) {
      unawaited(_injectExternalPrompt());
    }
  }

  Future<void> _initialize() async {
    try {
      _mcpExposureEnabled = await _mcpExposurePreferences.loadEnabled();
      await LanPeerDiscoveryService.instance.start(
        instanceId: _mcpIdentity.instanceId,
        name: _mcpIdentity.displayName,
        capabilityDigest: VibekitsHarnessToolBridge.protocolVersion,
        appId: _mcpIdentity.appId,
        hardwareCode: _mcpIdentity.hardwareCode,
        exposureEnabled: _mcpExposureEnabled,
      );
      _permissionMode = await HarnessAgentPreferencesStore.loadPermissionMode();
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
      _sessionApprovedToolIds.addAll(widget.preapprovedToolIds);
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
    final Stopwatch startup = Stopwatch()..start();
    try {
      final bool officialCredentialReady =
          await DeepSeekHarnessService.hasOfficialDeepSeekCredential();
      final String key = officialCredentialReady
          ? ''
          : await (widget.credentialReader ?? PlatformCredentialStore.read)(
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
      if (mounted) {
        setState(() => _status = '正在启动本地 DSH…');
      }
      final VibekitsHarnessToolBridge toolBridge = VibekitsHarnessToolBridge(
        remoteWorkspaceLauncher: widget.remoteWorkspaceLauncher,
        screenshotOcrRunner: widget.screenshotOcrRunner,
        downloadDirectory: widget.initialDownloadDirectory,
      );
      await McpCapabilityDirectory.instance.start(appBridge: toolBridge);
      final HarnessSessionHandle session = await widget.startWeb(
        HarnessWebRequest(
          workspace: workspace,
          apiKey: '',
          port: port,
          debugDirectory: widget.initialDebugDirectory,
          permissionMode: _permissionMode,
          approveTool: _approveVibekitsTool,
          toolBridge: toolBridge,
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
        // DSH cold start can emit hundreds of small chunks. Rebuilding the
        // complete Web workspace for every chunk competes with WebView2 and
        // Node startup. Coalesce diagnostics into at most ten UI updates/sec.
        _pendingDiagnostics.write(chunk);
        _diagnosticsTimer ??= Timer(
          const Duration(milliseconds: 100),
          _flushPendingDiagnostics,
        );
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
        _loadingStateSubscription = _webview.loadingState.listen((
          LoadingState state,
        ) {
          if (state == LoadingState.navigationCompleted) {
            unawaited(_installCodexConversationUx());
          }
        });
      }
      await _webview.loadUrl(session.url.toString());
      await _installCodexConversationUx();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 600)).then((_) {
          if (mounted && identical(_session, session)) {
            return _installCodexConversationUx();
          }
        }),
      );
      unawaited(_injectExternalPrompt());
      setState(() {
        _starting = false;
        _loading = false;
        _restartOverlay = false;
        _status = '官方 Harness 已就绪（${startup.elapsedMilliseconds} ms）';
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

  void _flushPendingDiagnostics() {
    _diagnosticsTimer = null;
    if (!mounted || _pendingDiagnostics.isEmpty) return;
    final String pending = _pendingDiagnostics.toString();
    _pendingDiagnostics.clear();
    setState(() {
      _diagnostics = '$_diagnostics$pending';
      if (_diagnostics.length > 12000) {
        _diagnostics = _diagnostics.substring(_diagnostics.length - 12000);
      }
    });
  }

  Future<void> _installCodexConversationUx() async {
    try {
      final String script = await (_conversationUxScript ??= rootBundle
          .loadString('assets/harness/codex_conversation_ux.js'));
      await _webview.executeScript(script);
    } on Object {
      // The official workspace must remain usable if a visual enhancement
      // cannot be injected on an older WebView2 runtime.
    }
  }

  void _scrollHarnessConversation(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent ||
        !_webviewReady ||
        signal.localPosition.dx < 300 ||
        signal.scrollDelta.dy == 0) {
      return;
    }
    final double delta = signal.scrollDelta.dy;
    unawaited(
      _webview.executeScript('''
        (() => {
          const host = [...document.querySelectorAll('[data-conversation-scroll]')]
            .find((element) => element instanceof HTMLElement &&
              element.offsetParent !== null && element.clientHeight > 0);
          if (!(host instanceof HTMLElement)) return false;
          host.scrollTop += ${delta.toStringAsFixed(2)};
          return true;
        })()
      '''),
    );
  }

  Widget _buildHarnessWebview() => Listener(
    onPointerSignal: _scrollHarnessConversation,
    child: Webview(_webview, permissionRequested: _handleWebPermission),
  );

  Future<bool> _approveVibekitsTool(HarnessToolApprovalRequest request) async {
    if (request.tool.risk == HarnessToolRisk.readOnly ||
        _sessionApprovedToolIds.contains(request.tool.id) ||
        _permissionMode == HarnessAgentPermissionMode.fullAccess ||
        (_permissionMode == HarnessAgentPermissionMode.assisted &&
            request.tool.risk != HarnessToolRisk.destructive)) {
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
  const visible = (element) => {
    if (!(element instanceof HTMLElement)) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 40 && rect.height > 18 &&
      style.display !== 'none' && style.visibility !== 'hidden';
  };
  const active = document.activeElement;
  const activeEditor = active instanceof Element
    ? active.closest('input, textarea, [contenteditable]:not([contenteditable="false"])')
    : null;
  const fallback = Array.from(document.querySelectorAll(
    'textarea:not([disabled]):not([readonly]), input:not([disabled]):not([readonly]), '
      + '[contenteditable]:not([contenteditable="false"])'
  )).filter(visible).at(-1);
  const element = activeEditor || fallback;
  if (!(element instanceof HTMLElement)) return false;
  const pasted = $value;
  element.focus();
  if (element instanceof HTMLInputElement ||
      element instanceof HTMLTextAreaElement) {
    if (element.disabled || element.readOnly) return false;
    const start = element.selectionStart ?? element.value.length;
    const end = element.selectionEnd ?? start;
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
  }

  // DSH uses a contenteditable rich-text composer. execCommand is retained by
  // WebView2 specifically for editing hosts and lets React/ProseMirror observe
  // the same beforeinput/input sequence as a normal keyboard paste.
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0 ||
      !element.contains(selection.anchorNode)) {
    const range = document.createRange();
    range.selectNodeContents(element);
    range.collapse(false);
    selection?.removeAllRanges();
    selection?.addRange(range);
  }
  if (!document.execCommand('insertText', false, pasted)) {
    const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
    if (!range) return false;
    range.deleteContents();
    const node = document.createTextNode(pasted);
    range.insertNode(node);
    range.setStartAfter(node);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);
    element.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      inputType: 'insertFromPaste',
      data: pasted,
    }));
  }
  return true;
})()
''');
  }

  Future<void> _copyFromFocusedWebSelection() async {
    if (!_webviewReady) return;
    final dynamic selected = await _webview.executeScript('''
(() => {
  const element = document.activeElement;
  if (element instanceof HTMLInputElement ||
      element instanceof HTMLTextAreaElement) {
    const start = element.selectionStart ?? 0;
    const end = element.selectionEnd ?? start;
    return start === end ? '' : element.value.slice(start, end);
  }
  return window.getSelection()?.toString() || '';
})()
''');
    final String text = selected is String ? selected : '${selected ?? ''}';
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _injectExternalPrompt() async {
    await _injectPrompt(widget.externalPrompt);
  }

  Future<bool> _injectPrompt(String rawPrompt) async {
    final String prompt = rawPrompt.trim();
    if (prompt.isEmpty || !_webviewReady) return false;
    final String value = jsonEncode(prompt);
    for (int attempt = 0; attempt < 30; attempt++) {
      if (!mounted || !_webviewReady) return false;
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
          return true;
        }
      } on Object {
        // The official app may still be replacing its initial loading DOM.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> _selectFeishuTask(FeishuHarnessTask task) async {
    final bool inserted = await _injectPrompt(task.prompt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inserted
              ? '已把“${task.label}”放入 Harness，请确认后发送'
              : 'Harness 输入框尚未就绪，请稍后重试',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
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
    if (!mounted ||
        _starting ||
        sessionId.isEmpty ||
        !_deletingSessionIds.add(sessionId)) {
      return;
    }
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
    if (!confirmed || !mounted) {
      _deletingSessionIds.remove(sessionId);
      return;
    }
    setState(() => _status = '正在删除会话…');
    try {
      // DSH keeps its workspace/session projection in memory. Editing only the
      // durable files leaves an undeletable ghost row until the backend exits.
      // Stop it first so it cannot rewrite the stale projection on shutdown.
      final HarnessSessionHandle? session = _session;
      _session = null;
      if (session != null && session.running) {
        await session.stop();
        widget.onRunningChanged?.call(false);
      }
      await HarnessSessionStore().deleteSession(sessionId);
      if (!mounted) return;
      setState(() => _status = '会话已删除，正在刷新列表…');
      await _start(preserveWebview: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '删除会话失败：$error';
      });
    } finally {
      _deletingSessionIds.remove(sessionId);
    }
  }

  @override
  void dispose() {
    _diagnosticsTimer?.cancel();
    _outputSubscription?.cancel();
    _webMessageSubscription?.cancel();
    _loadingStateSubscription?.cancel();
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
          _buildHarnessWebview(),
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
    final ShortcutActivator pastePlain = SingleActivator(
      LogicalKeyboardKey.keyV,
      control: !Platform.isMacOS,
      meta: Platform.isMacOS,
      shift: true,
    );
    const ShortcutActivator pasteInsert = SingleActivator(
      LogicalKeyboardKey.insert,
      shift: true,
    );
    final ShortcutActivator copy = SingleActivator(
      LogicalKeyboardKey.keyC,
      control: !Platform.isMacOS,
      meta: Platform.isMacOS,
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        paste: () => unawaited(_pasteIntoFocusedWebField()),
        pastePlain: () => unawaited(_pasteIntoFocusedWebField()),
        pasteInsert: () => unawaited(_pasteIntoFocusedWebField()),
        copy: () => unawaited(_copyFromFocusedWebSelection()),
      },
      child: Row(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                _buildHarnessWebview(),
                if (_quickActionsExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () =>
                          setState(() => _quickActionsExpanded = false),
                    ),
                  ),
                if (_quickActionsExpanded)
                  Positioned(
                    right: 8,
                    top: 50,
                    child: IgnorePointer(
                      child: Container(
                        width: 104,
                        height: 264,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface
                              .withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: 0.55),
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x24000000),
                              blurRadius: 18,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_quickActionsExpanded) ...<Widget>[
                  Positioned(
                    right: 12,
                    top: 54,
                    child: _buildMcpExposureControl(),
                  ),
                  Positioned(
                    right: 12,
                    top: 98,
                    child: StreamBuilder<McpCapabilitySnapshot>(
                      stream: McpCapabilityDirectory.instance.changes,
                      initialData: McpCapabilityDirectory.instance.snapshot,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<McpCapabilitySnapshot> snapshot,
                          ) {
                            final int count = snapshot.data?.local.length ?? 0;
                            return _mcpDeviceButton(
                              key: const Key('harness-local-mcp-devices'),
                              icon: Icons.memory_outlined,
                              label: '本机',
                              tooltip: '本机 MCP：查看同一台电脑上其他进程提供的接口',
                              count: count,
                              onTap: () =>
                                  _showMcpDevices(McpCapabilityTier.local),
                            );
                          },
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 142,
                    child: StreamBuilder<McpCapabilitySnapshot>(
                      stream: McpCapabilityDirectory.instance.changes,
                      initialData: McpCapabilityDirectory.instance.snapshot,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<McpCapabilitySnapshot> snapshot,
                          ) {
                            final int count = snapshot.data?.lan.length ?? 0;
                            return _mcpDeviceButton(
                              key: const Key('harness-lan-mcp-devices'),
                              icon: Icons.hub_outlined,
                              label: '局域网',
                              tooltip: '局域网 MCP：查看同一网络内其他设备提供的接口',
                              count: count,
                              onTap: () =>
                                  _showMcpDevices(McpCapabilityTier.lan),
                            );
                          },
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 186,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: 0.94),
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      child: PopupMenuButton<FeishuHarnessTask>(
                        key: const Key('harness-feishu-tasks'),
                        tooltip: '把飞书只读任务交给 Harness',
                        onSelected: (FeishuHarnessTask task) =>
                            unawaited(_selectFeishuTask(task)),
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<FeishuHarnessTask>>[
                              for (final FeishuHarnessTask task
                                  in FeishuHarnessTasks.quickTasks)
                                PopupMenuItem<FeishuHarnessTask>(
                                  key: Key('harness-feishu-${task.id}'),
                                  value: task,
                                  child: Text(task.label),
                                ),
                            ],
                        child: const SizedBox(
                          width: 92,
                          height: 36,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(Icons.forum_outlined, size: 16),
                              SizedBox(width: 6),
                              Text('飞书', style: TextStyle(fontSize: 12)),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    // Keep this VibeKits extension separate from DSH's native
                    // "Session log" action at the far-right edge.
                    right: 12,
                    top: 274,
                    child: StreamBuilder<RustDeskHarnessLinkSnapshot>(
                      stream: RustDeskHarnessLinkStatusHub.changes,
                      initialData: RustDeskHarnessLinkStatusHub.latest,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<RustDeskHarnessLinkSnapshot> snapshot,
                          ) {
                            final RustDeskHarnessLinkSnapshot link =
                                snapshot.data ??
                                RustDeskHarnessLinkStatusHub.latest;
                            final Color indicator = switch (link.phase) {
                              RustDeskHarnessLinkPhase.connected => const Color(
                                0xFF16845B,
                              ),
                              RustDeskHarnessLinkPhase.clientFound ||
                              RustDeskHarnessLinkPhase.handshaking =>
                                const Color(0xFFE99A22),
                              RustDeskHarnessLinkPhase.incompatible ||
                              RustDeskHarnessLinkPhase.stale => Theme.of(
                                context,
                              ).colorScheme.error,
                              RustDeskHarnessLinkPhase.disconnected => Theme.of(
                                context,
                              ).colorScheme.outline,
                            };
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
                                  message: link.message,
                                  child: SizedBox(
                                    width: 92,
                                    height: 36,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        Icon(
                                          Icons.screen_share_outlined,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '远程',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          key: const Key(
                                            'rustdesk-link-indicator',
                                          ),
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: indicator,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 230,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: 0.94),
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        key: const Key('harness-runtime-logs'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showRuntimeLogs,
                        child: const Tooltip(
                          message: '查看 Harness 启动、运行、工具调用和错误日志',
                          child: SizedBox(
                            width: 92,
                            height: 36,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.receipt_long_outlined, size: 16),
                                SizedBox(width: 6),
                                Text('日志', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildQuickActionsRail(),
        ],
      ),
    );
  }

  Future<void> _showRuntimeLogs() => showDialog<void>(
    context: context,
    builder: (BuildContext context) => const _HarnessRuntimeLogDialog(),
  );

  Widget _buildQuickActionsRail() => Container(
    width: 60,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border(
        left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Column(
      children: <Widget>[
        const SizedBox(height: 10),
        _railAction(
          key: const Key('rail-mcp-exposure'),
          icon: _mcpExposureEnabled ? Icons.api_rounded : Icons.api_outlined,
          tooltip:
              '${_mcpIdentity.displayName}\nMCP ${_mcpExposureEnabled ? '已开启' : '已关闭'}，点击切换',
          caption: 'MCP',
          active: _mcpExposureEnabled,
          onPressed: () => unawaited(_setMcpExposure(!_mcpExposureEnabled)),
        ),
        StreamBuilder<McpCapabilitySnapshot>(
          stream: McpCapabilityDirectory.instance.changes,
          initialData: McpCapabilityDirectory.instance.snapshot,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<McpCapabilitySnapshot> snapshot,
              ) => _railAction(
                key: const Key('rail-local-mcp'),
                icon: Icons.memory_outlined,
                badge: snapshot.data?.local.length ?? 0,
                tooltip: '本机 MCP 设备：点击查看接口详情',
                onPressed: () => _showMcpDevices(McpCapabilityTier.local),
              ),
        ),
        StreamBuilder<McpCapabilitySnapshot>(
          stream: McpCapabilityDirectory.instance.changes,
          initialData: McpCapabilityDirectory.instance.snapshot,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<McpCapabilitySnapshot> snapshot,
              ) => _railAction(
                key: const Key('rail-lan-mcp'),
                icon: Icons.hub_outlined,
                badge: snapshot.data?.lan.length ?? 0,
                tooltip: '局域网 MCP 设备：点击查看接口详情',
                onPressed: () => _showMcpDevices(McpCapabilityTier.lan),
              ),
        ),
        PopupMenuButton<FeishuHarnessTask>(
          key: const Key('rail-feishu'),
          tooltip: '飞书任务：查看谁在找我等只读任务',
          onSelected: (FeishuHarnessTask task) =>
              unawaited(_selectFeishuTask(task)),
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<FeishuHarnessTask>>[
                for (final FeishuHarnessTask task
                    in FeishuHarnessTasks.quickTasks)
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
        _railAction(
          key: const Key('rail-runtime-logs'),
          icon: Icons.receipt_long_outlined,
          tooltip: 'Harness 运行日志：查看启动、工具调用和错误',
          onPressed: _showRuntimeLogs,
        ),
        StreamBuilder<RustDeskHarnessLinkSnapshot>(
          stream: RustDeskHarnessLinkStatusHub.changes,
          initialData: RustDeskHarnessLinkStatusHub.latest,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<RustDeskHarnessLinkSnapshot> snapshot,
              ) {
                final RustDeskHarnessLinkSnapshot link =
                    snapshot.data ?? RustDeskHarnessLinkStatusHub.latest;
                return _railAction(
                  key: const Key('rail-remote-share'),
                  icon: Icons.screen_share_outlined,
                  tooltip: '远程分享：${link.message}',
                  active: link.phase == RustDeskHarnessLinkPhase.connected,
                  onPressed: _showRemoteShare,
                );
              },
        ),
        _railAction(
          key: const Key('rail-mcp-settings'),
          icon: Icons.settings_outlined,
          tooltip: 'MCP 与协同设置',
          onPressed: _showMcpSettings,
        ),
        const Spacer(),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Tooltip(
            message: '预留给后续快捷功能',
            child: Icon(Icons.more_horiz_rounded, size: 18),
          ),
        ),
      ],
    ),
  );

  Widget _railAction({
    required Key key,
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
              key: key,
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
              right: 5,
              top: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _showMcpSettings() => showDialog<void>(
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
                    await _setMcpExposure(enabled);
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

  Widget _buildMcpExposureControl() => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
    elevation: 2,
    borderRadius: BorderRadius.circular(22),
    child: Tooltip(
      message:
          '${_mcpIdentity.displayName}\n${_mcpExposureEnabled ? '已发布 MCP；关闭后其他 VibeKits 会立即移除本设备' : 'MCP 发布已关闭；本机仍继续发现其他设备'}',
      child: SizedBox(
        width: 92,
        height: 40,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 7),
            const Icon(Icons.api_outlined, size: 17),
            const SizedBox(width: 4),
            Text(
              'MCP',
              key: const Key('harness-mcp-device-name'),
              style: const TextStyle(fontSize: 11),
            ),
            SizedBox(
              width: 38,
              child: Transform.scale(
                scale: 0.72,
                child: Switch(
                  key: const Key('harness-mcp-exposure-switch'),
                  value: _mcpExposureEnabled,
                  onChanged: (bool enabled) =>
                      unawaited(_setMcpExposure(enabled)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _setMcpExposure(bool enabled) async {
    if (_mcpExposureEnabled == enabled) return;
    if (enabled && !await _confirmMcpExposureRisk()) return;
    setState(() => _mcpExposureEnabled = enabled);
    LanPeerDiscoveryService.instance.setExposureEnabled(enabled);
    try {
      await _mcpExposurePreferences.saveEnabled(enabled);
    } on Object catch (error) {
      if (!mounted) return;
      LanPeerDiscoveryService.instance.setExposureEnabled(!enabled);
      setState(() => _mcpExposureEnabled = !enabled);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存 MCP 开关失败：$error')));
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

  Widget _mcpDeviceButton({
    required Key key,
    required IconData icon,
    required String label,
    required String tooltip,
    required int count,
    required VoidCallback onTap,
  }) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
    elevation: 2,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 92,
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 16),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 5),
              Text('$count', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showMcpDevices(McpCapabilityTier tier) => showDialog<void>(
    context: context,
    builder: (BuildContext context) => _McpDeviceListDialog(tier: tier),
  );

  Future<void> _showRemoteShare() => showDialog<void>(
    context: context,
    builder: (BuildContext context) => _HarnessRemoteShareDialog(
      configuredExecutable: widget.rustDeskExecutable,
      webClientUrl: widget.rustDeskWebClientUrl,
    ),
  );
}

class _McpDeviceListDialog extends StatelessWidget {
  const _McpDeviceListDialog({required this.tier});

  final McpCapabilityTier tier;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tier == McpCapabilityTier.local ? '本机 MCP 设备' : '局域网 MCP 设备'),
    content: SizedBox(
      width: 680,
      height: 440,
      child: StreamBuilder<McpCapabilitySnapshot>(
        stream: McpCapabilityDirectory.instance.changes,
        initialData: McpCapabilityDirectory.instance.snapshot,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<McpCapabilitySnapshot> snapshot,
            ) {
              final McpCapabilitySnapshot catalog =
                  snapshot.data ?? McpCapabilityDirectory.instance.snapshot;
              final List<McpDeviceCapability> devices =
                  tier == McpCapabilityTier.local ? catalog.local : catalog.lan;
              if (devices.isEmpty) {
                return Center(
                  child: Text(
                    tier == McpCapabilityTier.local
                        ? '尚未发现本机其他 MCP 进程。提供者上线并发布注册文件后会自动出现。'
                        : '尚未发现局域网 MCP 设备。设备上线、离线和接口变化会实时更新。',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final McpDeviceCapability device = devices[index];
                  return ListTile(
                    key: Key('mcp-device-${device.id}'),
                    leading: Icon(
                      tier == McpCapabilityTier.local
                          ? Icons.memory_outlined
                          : Icons.computer_outlined,
                    ),
                    title: Text(device.name),
                    subtitle: Text(
                      '${device.appId} ${device.appVersion} · ${device.transport} · '
                      '${device.tools.length} 个接口',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (BuildContext context) =>
                          _McpDeviceDetailsDialog(device: device),
                    ),
                  );
                },
              );
            },
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

class _McpDeviceDetailsDialog extends StatelessWidget {
  const _McpDeviceDetailsDialog({required this.device});

  final McpDeviceCapability device;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${device.name} · MCP 接口详情'),
    content: SizedBox(
      width: 760,
      height: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            '实例：${device.id}\n应用：${device.appId} ${device.appVersion}\n'
            '硬件识别码：${device.hardwareCode.isEmpty ? '未提供' : device.hardwareCode}\n'
            '连接：${device.transport} · ${device.endpoint}\n'
            '目录版本：${device.catalogRevision.isEmpty ? '未提供' : device.catalogRevision}',
          ),
          const SizedBox(height: 12),
          Text(
            '工具接口（${device.tools.length}）',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Divider(),
          Expanded(
            child: device.tools.isEmpty
                ? const Center(child: Text('设备已发现，但尚未返回 tools/list 接口目录。'))
                : ListView.builder(
                    itemCount: device.tools.length,
                    itemBuilder: (BuildContext context, int index) {
                      final McpToolInterface tool = device.tools[index];
                      return ExpansionTile(
                        key: Key('mcp-tool-${device.id}-${tool.name}'),
                        title: SelectableText(tool.name),
                        subtitle: Text(
                          tool.title.isEmpty ? tool.description : tool.title,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SelectableText(
                            tool.description.isEmpty
                                ? '提供者未填写用途说明'
                                : tool.description,
                          ),
                          const SizedBox(height: 10),
                          const Text('inputSchema（调用参数的唯一依据）'),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: SelectableText(
                              const JsonEncoder.withIndent('  ')
                                  .convert(tool.inputSchema),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
  );
}

class _HarnessRuntimeLogDialog extends StatefulWidget {
  const _HarnessRuntimeLogDialog();

  @override
  State<_HarnessRuntimeLogDialog> createState() =>
      _HarnessRuntimeLogDialogState();
}

class _HarnessRuntimeLogDialogState extends State<_HarnessRuntimeLogDialog> {
  List<HarnessRuntimeLogEntry> _logs = const <HarnessRuntimeLogEntry>[];
  HarnessRuntimeLogEntry? _selected;
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final List<HarnessRuntimeLogEntry> logs =
        await HarnessRuntimeLogStore.listLogs();
    HarnessRuntimeLogEntry? selected = _selected;
    if (selected == null ||
        !logs.any(
          (HarnessRuntimeLogEntry item) => item.path == selected!.path,
        )) {
      selected = logs.isEmpty ? null : logs.first;
    }
    final String content = selected == null
        ? ''
        : await HarnessRuntimeLogStore.readTail(selected.path);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _selected = selected;
      _content = content;
      _loading = false;
    });
  }

  Future<void> _select(HarnessRuntimeLogEntry entry) async {
    setState(() {
      _selected = entry;
      _loading = true;
    });
    final String content = await HarnessRuntimeLogStore.readTail(entry.path);
    if (!mounted || _selected?.path != entry.path) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 1040,
      height: 660,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Harness 运行日志'),
            subtitle: SelectableText(
              HarnessRuntimeLogStore.rootPath,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: '刷新',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 310,
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (BuildContext context, int index) {
                      final HarnessRuntimeLogEntry entry = _logs[index];
                      return ListTile(
                        dense: true,
                        selected: entry.path == _selected?.path,
                        onTap: () => _select(entry),
                        title: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          '${entry.modified.toLocal()} · ${_logSize(entry.size)}',
                          maxLines: 1,
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _selected == null
                      ? const Center(child: Text('还没有 Harness 运行日志'))
                      : Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: SelectableText(
                              _content,
                              style: const TextStyle(
                                fontFamily: 'Cascadia Mono',
                                fontSize: 11,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  static String _logSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
  }
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
  late final Future<RustDeskHostInfo> _host = _inspectHost();
  String _message = '';
  String _resolvedWebClientUrl = '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolveWebClientUrl());
  }

  Future<RustDeskHostInfo> _inspectHost() async {
    final RustDeskHostInfo host = await RustDeskHarnessShareService.inspect(
      configuredExecutable: widget.configuredExecutable,
    );
    if (host.available &&
        RustDeskHarnessLinkStatusHub.latest.phase ==
            RustDeskHarnessLinkPhase.disconnected) {
      RustDeskHarnessLinkStatusHub.clientFound();
    }
    return host;
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
      RustDeskHarnessLinkStatusHub.clientFound();
      if (mounted) setState(() => _message = 'KEMI远程办公已启动，等待状态协议连接');
    } on Object catch (error) {
      if (mounted) setState(() => _message = '启动失败：$error');
    }
  }

  Future<void> _openWeb() async {
    try {
      await RustDeskHarnessShareService.openWebClient(_resolvedWebClientUrl);
      if (mounted) setState(() => _message = '已打开KEMI远程办公网页端');
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
          StreamBuilder<RustDeskHarnessLinkSnapshot>(
            stream: RustDeskHarnessLinkStatusHub.changes,
            initialData: RustDeskHarnessLinkStatusHub.latest,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<RustDeskHarnessLinkSnapshot> snapshot,
                ) {
                  final RustDeskHarnessLinkSnapshot link =
                      snapshot.data ?? RustDeskHarnessLinkStatusHub.latest;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      link.connected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: link.connected
                          ? const Color(0xFF16845B)
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(link.message),
                    subtitle: const Text('只有完成本机协议握手且心跳有效才显示已连接'),
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
                            label: const Text('启动KEMI远程办公'),
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
            'KEMI远程办公底层兼容 RustDesk，通过 hbbs/hbbr 查看并操作本机 Vibekits。'
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
