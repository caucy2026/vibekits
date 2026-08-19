import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/platform_credential_store.dart';

typedef OfficialHarnessCredentialReader = Future<String?> Function(String key);
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
    this.startWeb = DeepSeekHarnessService.startWebAgent,
    this.findPort = DeepSeekHarnessService.findFreeLoopbackPort,
  });

  final String initialWorkspace;
  final String initialDebugDirectory;
  final ValueChanged<bool>? onRunningChanged;
  final OfficialHarnessCredentialReader? credentialReader;
  final OfficialHarnessWebStarter startWeb;
  final Future<int> Function() findPort;

  @override
  State<OfficialHarnessWorkspace> createState() =>
      _OfficialHarnessWorkspaceState();
}

class _OfficialHarnessWorkspaceState extends State<OfficialHarnessWorkspace> {
  static const String _credentialKey = 'deepseek-api-key';
  final WebviewController _webview = WebviewController();
  HarnessSessionHandle? _session;
  StreamSubscription<String>? _outputSubscription;
  bool _loading = true;
  bool _starting = false;
  bool _webviewReady = false;
  String _status = '正在准备官方 Harness…';
  String _diagnostics = '';
  final Set<String> _sessionApprovedToolIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _webview.initialize();
      _webviewReady = true;
      await _start();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '官方 Harness 初始化失败：$error';
      });
    }
  }

  Future<void> _start() async {
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
      _status = '正在启动官方 DSH Web…';
      _diagnostics = '';
    });
    try {
      final String key =
          await (widget.credentialReader ?? PlatformCredentialStore.read)(
            _credentialKey,
          ) ??
          '';
      final int port = await widget.findPort();
      final HarnessSessionHandle session = await widget.startWeb(
        HarnessWebRequest(
          workspace: workspace,
          apiKey: key,
          port: port,
          debugDirectory: widget.initialDebugDirectory,
          approveTool: _approveVibekitsTool,
          toolBridge: VibekitsHarnessToolBridge(),
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
        }),
      );
      await _waitUntilReady(session.url);
      if (!mounted || !identical(_session, session)) return;
      await _webview.loadUrl(session.url.toString());
      setState(() {
        _starting = false;
        _loading = false;
        _status = '官方 Harness 已就绪';
      });
    } on Object catch (error) {
      final HarnessSessionHandle? session = _session;
      _session = null;
      if (session != null && session.running) await session.stop();
      widget.onRunningChanged?.call(false);
      if (!mounted) return;
      setState(() {
        _starting = false;
        _loading = false;
        _status = '启动失败：$error';
      });
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
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 500);
    try {
      for (int attempt = 0; attempt < 80; attempt++) {
        if (_session?.running != true) {
          throw StateError('Harness 在控制台就绪前退出');
        }
        try {
          final HttpClientRequest request = await client
              .getUrl(url)
              .timeout(const Duration(milliseconds: 600));
          final HttpClientResponse response = await request.close().timeout(
            const Duration(milliseconds: 800),
          );
          await response.drain<void>();
          if (response.statusCode >= 200 && response.statusCode < 500) return;
        } on Object {
          // Server is still composing the official Web profile.
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw TimeoutException('官方 Web 控制台启动超时');
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    final HarnessSessionHandle? session = _session;
    if (session != null && session.running) unawaited(session.stop());
    widget.onRunningChanged?.call(false);
    _webview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    return Webview(_webview);
  }
}

enum _ToolApprovalDecision { deny, allowOnce, allowSession }
