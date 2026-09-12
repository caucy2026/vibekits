import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../app/platform_storage_layout.dart';
import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/cluster_task_settings.dart';
import '../../dev_tools/domain/feishu_harness_tasks.dart';
import '../../dev_tools/domain/harness_session_store.dart';
import '../../dev_tools/domain/harness_startup_recovery.dart';
import '../../dev_tools/domain/harness_agent_preferences.dart';
import '../../dev_tools/domain/harness_runtime_log_store.dart';
import '../../dev_tools/domain/harness_legacy_modules.dart';
import '../../dev_tools/domain/harness_message_queue.dart';
import '../../dev_tools/domain/harness_remote_controller_session.dart';
import '../../dev_tools/domain/harness_remote_controller_runtime.dart';
import '../../dev_tools/domain/harness_remote_access_settings.dart';
import '../../dev_tools/domain/harness_simulator_access_settings.dart';
import '../../dev_tools/domain/harness_simulator_controller.dart';
import '../../dev_tools/domain/harness_simulator_target_runtime.dart';
import '../../dev_tools/domain/harness_remote_execution.dart';
import '../../dev_tools/domain/harness_remote_host_runtime.dart';
import '../../dev_tools/domain/harness_remote_identity.dart';
import '../../dev_tools/domain/harness_remote_management_bridge.dart';
import '../../dev_tools/domain/harness_remote_peer_store.dart';
import '../../dev_tools/domain/harness_remote_pairing.dart';
import '../../dev_tools/domain/harness_remote_pairing_service.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../../dev_tools/domain/harness_tool_activity_store.dart';
import '../../dev_tools/domain/harness_work_status.dart';
import '../../dev_tools/domain/lan_peer_discovery_service.dart';
import '../../dev_tools/domain/lmcp_exposure_server.dart';
import '../../dev_tools/domain/mcp_capability_directory.dart';
import '../../dev_tools/domain/mcp_capability_models.dart';
import '../../dev_tools/domain/mcp_device_identity.dart';
import '../../dev_tools/domain/mcp_tool_reputation_store.dart';
import '../../dev_tools/domain/platform_credential_store.dart';
import '../../dev_tools/domain/rustdesk_harness_link_status.dart';
import '../../dev_tools/domain/rustdesk_harness_share_service.dart';
import '../../dev_tools/presentation/harness_remote_read_only_panel.dart';
import 'mcp_exposure_consent_dialog.dart';
import 'mcp_reputation_badge.dart';
import 'harness_webview_bridge.dart';
import 'harness_webview_input_gate.dart';

typedef OfficialHarnessCredentialReader = Future<String?> Function(String key);
typedef OfficialHarnessCredentialDeleter = Future<void> Function(String key);
typedef OfficialHarnessWebStarter =
    Future<HarnessSessionHandle> Function(HarnessWebRequest request);

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
  static const bool _pointerDiagnostics = bool.fromEnvironment(
    'VIBEKITS_POINTER_DIAGNOSTICS',
  );
  static final File _pointerDiagnosticLog = File(
    '${Directory.systemTemp.path}/vibekits-harness-pointer-probe.log',
  );
  static const String _credentialKey = 'deepseek-api-key';
  static Future<String>? _conversationUxScript;
  static Future<String>? _messageQueueBridgeScript;
  final HarnessWebViewBridge _webview = HarnessWebViewBridge();
  HarnessSessionHandle? _session;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<dynamic>? _webMessageSubscription;
  StreamSubscription<void>? _loadingStateSubscription;
  StreamSubscription<String>? _navigationDiagnosticSubscription;
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
  final Set<String> _movingSessionIds = <String>{};
  final McpDeviceIdentity _mcpIdentity = McpDeviceIdentity.forVibekits();
  final McpExposurePreferences _mcpExposurePreferences =
      McpExposurePreferences();
  bool _mcpExposureEnabled = false;
  bool _mcpExposureChanging = false;
  bool _restoreMcpExposureOnStart = false;
  VibekitsHarnessToolBridge? _mcpExposureBridge;
  bool _quickActionsExpanded = false;
  HarnessWorkspaceStatusContext? _workStatusContext;
  final HarnessStartupRecovery _startupRecovery = HarnessStartupRecovery();
  Timer? _restartTimer;
  Timer? _stabilityTimer;
  bool _disposing = false;
  final HarnessRemoteHostRuntime _remoteHostRuntime =
      HarnessRemoteHostRuntime.shared;
  Timer? _remoteAuthorizationTimer;
  bool _remoteAuthorizationInFlight = false;
  String _activeRemoteWorkspaceId = '';
  Future<void>? _independentServicesFuture;
  StreamSubscription<HarnessRemoteControllerSession?>?
  _remoteControllerSubscription;
  late final HarnessMessageQueueRepository _messageQueue =
      HarnessMessageQueueRepository(
        root: Directory(PlatformStorageLayout.current().harnessQueueDirectory),
      );
  HarnessMessageQueueScheduler? _messageQueueScheduler;
  String _queueWorkspaceId = '';
  String _queueSessionId = '';
  int _queuedMessageCount = 0;
  bool _queuePersistencePending = false;
  bool _harnessBusy = false;
  bool _harnessApprovalWaiting = false;
  bool _queueAdapterCompatible = false;
  bool _queueDialogOpen = false;
  String _pendingQueueIdempotencyKey = '';
  Completer<bool>? _pendingQueueAcceptance;

  @override
  void initState() {
    super.initState();
    HarnessRemoteManagementBridge.bind(
      owner: this,
      startHost: _startRemoteHostForCurrentSession,
      stopHost: _remoteHostRuntime.stop,
      localWorkspaceIds: () => <String>{
        if (_activeRemoteWorkspaceId.isNotEmpty) _activeRemoteWorkspaceId,
      },
    );
    _remoteControllerSubscription = HarnessRemoteControllerRuntime
        .instance
        .changes
        .listen((_) {
          if (mounted) setState(() {});
        });
    if (_pointerDiagnostics) {
      _pointerDiagnosticLog.writeAsStringSync('');
      GestureBinding.instance.pointerRouter.addGlobalRoute(
        _recordFlutterPointer,
      );
    }
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
      final Future<void> webviewInitialization = _webview.initialize();
      final Future<HarnessAgentPermissionMode> permissionMode =
          HarnessAgentPreferencesStore.loadPermissionMode();
      _permissionMode = await permissionMode;
      await _start(retries: 2, webviewInitialization: webviewInitialization);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '官方 Harness 初始化失败：$error';
      });
    }
  }

  Future<void> _initializeIndependentServices() async {
    try {
      _restoreMcpExposureOnStart = await _mcpExposurePreferences.loadEnabled();
      if (Platform.environment['FLUTTER_TEST'] != 'true') {
        await HarnessRemoteAccessSettings().loadEnabled();
        await LanPeerDiscoveryService.instance.start(
          instanceId: _mcpIdentity.instanceId,
          name: _mcpIdentity.displayName,
          capabilityDigest: VibekitsHarnessToolBridge.protocolVersion,
          appId: _mcpIdentity.appId,
          appVersion: VibekitsLmcpExposureServer.currentAppVersion,
          hardwareCode: _mcpIdentity.hardwareCode,
          exposureEnabled: false,
        );
      }
    } on Object {
      // These modules expose their own state. A remote/LAN failure must not
      // change, restart or cover the local Harness workspace.
    }
  }

  Future<void> _ensureIndependentServices() {
    return _independentServicesFuture ??= _initializeIndependentServices();
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
    _activeRemoteWorkspaceId = workspace;
    _workStatusContext ??= HarnessWorkStatusHub.activateWorkspace(
      workspaceRef: workspace,
      workspaceLabel: _workspaceLabel(workspace),
      sessionRef: 'vibekits-harness-${identityHashCode(this)}',
    );
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
        activityRecorder: _recordHarnessToolActivity,
        remoteWorkspaceLauncher: widget.remoteWorkspaceLauncher,
        screenshotOcrRunner: widget.screenshotOcrRunner,
        downloadDirectory: widget.initialDownloadDirectory,
        mcpCatalogLoader: McpCapabilityDirectory.instance.exportForHarness,
        mcpToolInvoker:
            (
              String instanceId,
              String toolName,
              Map<String, Object?> arguments,
            ) => McpCapabilityDirectory.instance.invokeTool(
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
      );
      _mcpExposureBridge = toolBridge;
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
          if (_starting) {
            setState(() {
              _status = 'Harness 启动进程提前退出（代码 $code），正在恢复…';
            });
            return;
          }
          _scheduleUnexpectedExitRecovery(code);
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
        _webMessageSubscription = _webview.messages.listen(_handleWebMessage);
        _loadingStateSubscription = _webview.pageFinished.listen((_) {
          unawaited(_installCodexConversationUx());
        });
        _navigationDiagnosticSubscription = _webview.navigationDiagnostics
            .listen((String detail) {
              unawaited(
                HarnessRuntimeLogStore.appendWorkEvent(<String, Object?>{
                  'type': 'harness.web.navigation',
                  'detail': detail,
                  'at': DateTime.now().toUtc().toIso8601String(),
                }),
              );
            });
      }
      final bool repairedAuthentication = await _webview
          .pruneOversizedHarnessAuthentication();
      if (repairedAuthentication) {
        unawaited(
          HarnessRuntimeLogStore.appendWorkEvent(<String, Object?>{
            'type': 'harness.web.authentication_repaired',
            'at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
      // A listening HTTP port only proves that Node bound the socket. Do not
      // report Harness ready until the native WebView has completed its first
      // navigation as well; otherwise the shell can look idle while the real
      // editor has not received input yet.
      final Future<void> firstPage = _webview.pageFinished.first.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('Harness 页面在 45 秒内未完成装载'),
      );
      await _webview.loadUrl(session.url);
      await firstPage;
      if (!mounted || !identical(_session, session)) return;
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
      unawaited(_activateIndependentServices(toolBridge, session));
      _stabilityTimer?.cancel();
      _stabilityTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && identical(_session, session) && session.running) {
          _startupRecovery.markStable();
        }
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

  Future<void> _activateIndependentServices(
    VibekitsHarnessToolBridge bridge,
    HarnessSessionHandle session,
  ) async {
    try {
      await _ensureIndependentServices();
      await McpCapabilityDirectory.instance.start(appBridge: bridge);
      if (_restoreMcpExposureOnStart) await _startMcpExposure(bridge);
      _mcpExposureEnabled = VibekitsLmcpExposureServer.instance.running;
      if (mounted) setState(() {});
    } on Object {
      // Local Harness keeps working even when optional MCP discovery or
      // publishing is unavailable. The MCP settings page owns its retry UI.
    }
    if (!mounted || !identical(_session, session)) return;
    try {
      await _startRemoteHost(session.url);
    } on Object {
      // Remote transport owns its status. It cannot alter or restart Harness.
    }
  }

  void _scheduleUnexpectedExitRecovery(int code) {
    _stabilityTimer?.cancel();
    final Duration? delay = _startupRecovery.nextDelay();
    if (delay == null || _disposing) {
      setState(() {
        _starting = false;
        _loading = false;
        _restartOverlay = false;
        _status = 'Harness 连续异常退出（最后代码 $code），请查看日志后重试';
      });
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.failed,
        message: 'Harness 连续异常退出（代码 $code）',
      );
      return;
    }
    setState(() {
      _starting = false;
      _loading = false;
      _restartOverlay = _webviewReady;
      _status =
          'Harness 异常退出（代码 $code），'
          '${delay.inMilliseconds} ms 后自动恢复';
    });
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.starting,
      message: 'Harness 异常退出，正在自动恢复',
    );
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (!mounted || _disposing || _session != null) return;
      unawaited(_start(retries: 1, preserveWebview: _webviewReady));
    });
  }

  void _retryManually() {
    _restartTimer?.cancel();
    _startupRecovery.markStable();
    unawaited(_start(retries: 2, preserveWebview: _webviewReady));
  }

  Future<void> _startRemoteHost(Uri endpoint) async {
    if (!HarnessRemoteAccessSettings.enabled) return;
    try {
      final RustDeskHostInfo carrier =
          await RustDeskHarnessShareService.inspect(
            configuredExecutable: widget.rustDeskExecutable,
          );
      if (!carrier.available || carrier.executable.isEmpty) {
        throw StateError('REMOTE_CARRIER_UNAVAILABLE');
      }
      if (!carrier.callable) {
        await RustDeskHarnessShareService.launchHost(carrier.executable);
      }
      await HarnessRemotePairingHost.instance.start();
      await _remoteHostRuntime.stop();
      final bool started = await _remoteHostRuntime.start(endpoint);
      if (!started) {
        throw StateError('REMOTE_PAIRING_SCOPE_NOT_PERSISTED');
      }
      _startRemoteAuthorizationMonitor();
    } on Object {
      // Remote assistance is optional and must not change Harness state.
      rethrow;
    }
  }

  void _startRemoteAuthorizationMonitor() {
    if (_remoteAuthorizationTimer != null || _disposing) return;
    unawaited(_authorizeRememberedRemoteConnections());
    _remoteAuthorizationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_authorizeRememberedRemoteConnections()),
    );
  }

  Future<void> _authorizeRememberedRemoteConnections() async {
    if (_remoteAuthorizationInFlight ||
        _disposing ||
        !HarnessRemoteAccessSettings.enabled) {
      return;
    }
    _remoteAuthorizationInFlight = true;
    try {
      // Registration can finish after application startup. A cached offline
      // inspection would otherwise prevent remembered peers from ever being
      // authorized until the settings dialog was opened manually.
      final host = await RustDeskHarnessShareService.inspect(
        configuredExecutable: widget.rustDeskExecutable,
      );
      if (!host.available || !host.callable || host.executable.isEmpty) return;
      final rememberedIds = (await HarnessRemotePeerStore().load())
          .where((peer) => peer.remembered && peer.connectionReady)
          .map((peer) => peer.routingId)
          .toSet();
      if (rememberedIds.isEmpty) return;
      final connections = await RustDeskHarnessShareService.connections(
        host.executable,
      );
      for (final connection in connections) {
        if (!connection.authorized &&
            !connection.disconnected &&
            rememberedIds.contains(connection.peerId)) {
          await RustDeskHarnessShareService.decideConnection(
            host.executable,
            connectionId: connection.connectionId,
            allow: true,
          );
        }
      }
    } on Object {
      // The next bounded poll retries. Local Harness remains fully usable.
    } finally {
      _remoteAuthorizationInFlight = false;
    }
  }

  Future<void> _startRemoteHostForCurrentSession() async {
    final HarnessSessionHandle? session = _session;
    if (session == null || !session.running) {
      throw StateError('REMOTE_HARNESS_SESSION_NOT_READY');
    }
    await _startRemoteHost(session.url);
  }

  static String _workspaceLabel(String workspace) {
    final String normalized = workspace.replaceAll('\\', '/');
    final List<String> segments = normalized
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? '工作区' : segments.last;
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
      await _webview.executeScriptVoid(script);
      final String queueScript = await (_messageQueueBridgeScript ??= rootBundle
          .loadString('assets/harness/harness_message_queue_bridge.js'));
      await _webview.executeScriptVoid(queueScript);
      await _publishQueueCountToWeb();
      if (_pointerDiagnostics) {
        await _webview.executeScriptVoid('''
          (() => {
            if (window.__vibekitsPointerProbeInstalled) return;
            window.__vibekitsPointerProbeInstalled = true;
            for (const eventName of ['mousedown', 'mouseup', 'click']) {
              document.addEventListener(eventName, (event) => {
                const target = event.target instanceof Element
                  ? (event.target.getAttribute('aria-label') ||
                    event.target.getAttribute('title') ||
                    event.target.textContent || event.target.tagName)
                  : 'unknown';
                window.VibekitsHost?.postMessage(JSON.stringify({
                  type: 'vibekits.pointerProbe',
                  layer: 'dom',
                  event: eventName,
                  x: event.clientX,
                  y: event.clientY,
                  target: String(target).trim().slice(0, 80),
                }));
              }, true);
            }
          })();
        ''');
      }
    } on Object {
      // The official workspace must remain usable if a visual enhancement
      // cannot be injected on an older WebView2 runtime.
    }
  }

  void _recordFlutterPointer(PointerEvent event) {
    if (!_pointerDiagnostics || event is! PointerDownEvent) return;
    _appendPointerDiagnostic(
      'flutter down x=${event.position.dx.toStringAsFixed(1)} '
      'y=${event.position.dy.toStringAsFixed(1)}',
    );
  }

  void _appendPointerDiagnostic(String line) {
    try {
      _pointerDiagnosticLog.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // A diagnostic-only write must never interfere with Harness input.
    }
  }

  // Keep the native platform view as the direct child. A Flutter [Listener]
  // around an AppKitView can win macOS pointer routing before WKWebView sees
  // mouse-down/up, leaving the official page painted but non-interactive.
  // WKWebView owns click, drag, selection and wheel scrolling natively.
  Widget _buildHarnessWebview() =>
      _webview.build(permissionRequested: _handleWebPermission);

  Future<void> _blockNativeWebViewInput() => HarnessWebViewInputGate.acquire();

  Future<void> _unblockNativeWebViewInput() =>
      HarnessWebViewInputGate.release();

  Future<T?> _withFlutterOverlay<T>(Future<T?> Function() present) async {
    return HarnessWebViewInputGate.runWithOverlay(present);
  }

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
        await _withFlutterOverlay<_ToolApprovalDecision>(
          () => showDialog<_ToolApprovalDecision>(
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
          ),
        );
    if (decision == _ToolApprovalDecision.allowSession) {
      _sessionApprovedToolIds.add(request.tool.id);
      return true;
    }
    return decision == _ToolApprovalDecision.allowOnce;
  }

  Future<void> _startMcpExposure(VibekitsHarnessToolBridge bridge) =>
      VibekitsLmcpExposureServer.instance.start(
        instanceId: _mcpIdentity.instanceId,
        displayName: _mcpIdentity.displayName,
        appId: _mcpIdentity.appId,
        appVersion: VibekitsLmcpExposureServer.currentAppVersion,
        hardwareCode: _mcpIdentity.hardwareCode,
        bridge: bridge,
      );

  Future<void> _waitUntilReady(Uri url) async {
    const Duration startupLimit = Duration(minutes: 3);
    final Stopwatch stopwatch = Stopwatch()..start();
    int lastReportedSecond = -1;
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
          final Uri currentUrl = _session?.url ?? url;
          // DSH announces its short-lived browser bootstrap token after the
          // port is bound. Navigating to the bare loopback URL in that window
          // can complete as an empty document, so both must be ready.
          if ((currentUrl.queryParameters['token'] ?? '').isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            continue;
          }
          // Only test the listening socket. Any HTTP request could enter or
          // consume DSH's browser authentication flow, whose cookie belongs
          // exclusively to WKWebView/WebView2.
          final Socket socket = await Socket.connect(
            currentUrl.host,
            currentUrl.port,
            timeout: const Duration(milliseconds: 500),
          );
          socket.destroy();
          return;
        } on Object {
          // Server is still composing the official Web profile.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw TimeoutException('本地 DSH 在 3 分钟内未完成启动，请查看 Harness 调试日志');
    } finally {
      stopwatch.stop();
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
    final String prompt = widget.externalPrompt.trim();
    if (prompt.isEmpty) return;
    if (_queueContextReady && _queueAdapterCompatible) {
      await _messageQueue.enqueue(
        workspaceId: _queueWorkspaceId,
        sessionId: _queueSessionId,
        text: prompt,
        source: HarnessMessageSource.appMcp,
      );
      await _refreshQueueCount();
      if (!_harnessBusy && !_harnessApprovalWaiting) {
        await _messageQueueScheduler?.dispatchNext();
        await _refreshQueueCount();
      }
      return;
    }
    await _injectPrompt(prompt);
  }

  bool get _queueContextReady =>
      _queueWorkspaceId.isNotEmpty && _queueSessionId.isNotEmpty;

  Future<void> _setQueueContext(String workspaceId, String sessionId) async {
    final String workspace = workspaceId.trim();
    final String session = sessionId.trim();
    if (workspace.isEmpty || session.isEmpty) return;
    if (_queueWorkspaceId == workspace && _queueSessionId == session) return;
    _pendingQueueAcceptance?.complete(false);
    _pendingQueueAcceptance = null;
    _pendingQueueIdempotencyKey = '';
    _queueWorkspaceId = workspace;
    _queueSessionId = session;
    _messageQueueScheduler = HarnessMessageQueueScheduler(
      repository: _messageQueue,
      workspaceId: workspace,
      sessionId: session,
      submit: _submitQueuedMessage,
    );
    await _messageQueue.load(
      workspaceId: workspace,
      sessionId: session,
      recover: true,
    );
    _messageQueueScheduler?.updateHarnessState(
      busy: _harnessBusy || !_queueAdapterCompatible,
      approvalWaiting: _harnessApprovalWaiting,
    );
    await _refreshQueueCount();
  }

  Future<bool> _submitQueuedMessage(String text, String idempotencyKey) async {
    if (!_webviewReady || !_queueAdapterCompatible) return false;
    final Completer<bool> acceptance = Completer<bool>();
    _pendingQueueAcceptance?.complete(false);
    _pendingQueueAcceptance = acceptance;
    _pendingQueueIdempotencyKey = idempotencyKey;
    try {
      final dynamic submitted = await _webview.executeScript('''
window.__vibekitsHarnessQueueBridge?.submit(
  ${jsonEncode(text)}, ${jsonEncode(idempotencyKey)}
) === true
''');
      if (submitted != true && submitted.toString().toLowerCase() != 'true') {
        return false;
      }
      return await acceptance.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
    } finally {
      if (identical(_pendingQueueAcceptance, acceptance)) {
        _pendingQueueAcceptance = null;
        _pendingQueueIdempotencyKey = '';
      }
    }
  }

  Future<void> _refreshQueueCount() async {
    if (!_queueContextReady) return;
    final List<HarnessQueueItem> items = await _messageQueue.load(
      workspaceId: _queueWorkspaceId,
      sessionId: _queueSessionId,
      recover: false,
    );
    final int count = items
        .where((HarnessQueueItem item) => item.editable)
        .length;
    final bool persistencePending = _messageQueue.persistencePending(
      workspaceId: _queueWorkspaceId,
      sessionId: _queueSessionId,
    );
    if (mounted &&
        (count != _queuedMessageCount ||
            persistencePending != _queuePersistencePending)) {
      setState(() {
        _queuedMessageCount = count;
        _queuePersistencePending = persistencePending;
      });
    }
    await _publishQueueCountToWeb();
  }

  Future<void> _publishQueueCountToWeb() async {
    if (!_webviewReady) return;
    try {
      await _webview.executeScriptVoid(
        'window.__vibekitsHarnessQueueBridge?.setQueueCount('
        '$_queuedMessageCount);',
      );
    } on Object {
      // Navigation can replace the DOM while this optional badge is updating.
    }
  }

  Future<String> _composerText() async {
    if (!_webviewReady) return '';
    try {
      final dynamic value = await _webview.executeScript(
        'window.__vibekitsHarnessQueueBridge?.composerText?.() || ""',
      );
      return value?.toString() ?? '';
    } on Object {
      return '';
    }
  }

  Future<void> _clearComposer() async {
    if (!_webviewReady) return;
    await _webview.executeScriptVoid(
      'window.__vibekitsHarnessQueueBridge?.clearComposer();',
    );
  }

  Future<void> _enqueueMessage(
    String text, {
    HarnessMessageMode mode = HarnessMessageMode.queued,
  }) async {
    if (!_queueContextReady || text.trim().isEmpty) return;
    await _messageQueue.enqueue(
      workspaceId: _queueWorkspaceId,
      sessionId: _queueSessionId,
      text: text,
      mode: mode,
    );
    await _clearComposer();
    await _refreshQueueCount();
    if (!_harnessBusy && !_harnessApprovalWaiting) {
      await _messageQueueScheduler?.dispatchNext();
      await _refreshQueueCount();
    }
  }

  Future<void> _requestImmediateInterrupt(String text) async {
    if (!_queueContextReady || text.trim().isEmpty || !mounted) return;
    final bool confirmed =
        await _withFlutterOverlay<bool>(
          () => showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('立即打断当前任务？'),
              content: const Text('当前执行会先收到停止请求；确认停止后，再发送这条消息。'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('停止并发送'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _enqueueMessage(text, mode: HarnessMessageMode.interrupt);
    if (!_harnessBusy) return;
    await _webview.executeScriptVoid(
      'window.__vibekitsHarnessQueueBridge?.cancel();',
    );
  }

  Future<void> _showMessageQueue() async {
    if (_queueDialogOpen || !_queueContextReady || !mounted) return;
    _queueDialogOpen = true;
    final TextEditingController newMessage = TextEditingController(
      text: await _composerText(),
    );
    try {
      await _withFlutterOverlay<void>(() async {
        await showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext dialogContext, StateSetter setDialogState) {
              Future<void> mutate(Future<void> Function() operation) async {
                await operation();
                await _refreshQueueCount();
                if (dialogContext.mounted) setDialogState(() {});
              }

              return AlertDialog(
                title: Text(
                  '待执行消息 · $_queuedMessageCount'
                  '${_queuePersistencePending ? ' · 尚未持久化' : ''}',
                ),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 620,
                    maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.7,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: newMessage,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: '输入下一条任务；当前任务运行时输入仍可编辑',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: () async {
                              final String text = newMessage.text;
                              Navigator.pop(dialogContext);
                              await _requestImmediateInterrupt(text);
                            },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('立即打断'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => mutate(() async {
                              await _enqueueMessage(newMessage.text);
                              newMessage.clear();
                            }),
                            icon: const Icon(Icons.playlist_add_rounded),
                            label: const Text('排队下一条'),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Flexible(
                        child: FutureBuilder<List<HarnessQueueItem>>(
                          future: _messageQueue.load(
                            workspaceId: _queueWorkspaceId,
                            sessionId: _queueSessionId,
                            recover: false,
                          ),
                          builder: (BuildContext context, snapshot) {
                            final List<HarnessQueueItem> items =
                                snapshot.data
                                    ?.where(
                                      (HarnessQueueItem item) => item.editable,
                                    )
                                    .toList() ??
                                <HarnessQueueItem>[];
                            if (items.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('暂无待执行消息'),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: items.length,
                              itemBuilder: (BuildContext context, int index) {
                                final HarnessQueueItem item = items[index];
                                return Tooltip(
                                  message: item.text,
                                  child: ListTile(
                                    dense: true,
                                    leading: Text('${index + 1}'),
                                    title: TextFormField(
                                      key: ValueKey<String>(item.id),
                                      initialValue: item.text,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onFieldSubmitted: (String value) =>
                                          mutate(
                                            () => _messageQueue.edit(
                                              workspaceId: _queueWorkspaceId,
                                              sessionId: _queueSessionId,
                                              itemId: item.id,
                                              text: value,
                                            ),
                                          ),
                                    ),
                                    subtitle: Text(
                                      '${item.source.name} · '
                                      '${item.createdAt.toLocal()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Wrap(
                                      spacing: 0,
                                      children: <Widget>[
                                        IconButton(
                                          tooltip: '上移',
                                          onPressed: index == 0
                                              ? null
                                              : () => mutate(
                                                  () => _messageQueue.move(
                                                    workspaceId:
                                                        _queueWorkspaceId,
                                                    sessionId: _queueSessionId,
                                                    itemId: item.id,
                                                    delta: -1,
                                                  ),
                                                ),
                                          icon: const Icon(Icons.arrow_upward),
                                        ),
                                        IconButton(
                                          tooltip: '下移',
                                          onPressed: index == items.length - 1
                                              ? null
                                              : () => mutate(
                                                  () => _messageQueue.move(
                                                    workspaceId:
                                                        _queueWorkspaceId,
                                                    sessionId: _queueSessionId,
                                                    itemId: item.id,
                                                    delta: 1,
                                                  ),
                                                ),
                                          icon: const Icon(
                                            Icons.arrow_downward,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '立即执行',
                                          onPressed: () => mutate(() async {
                                            await _messageQueue.promote(
                                              workspaceId: _queueWorkspaceId,
                                              sessionId: _queueSessionId,
                                              itemId: item.id,
                                            );
                                            if (!_harnessBusy &&
                                                !_harnessApprovalWaiting) {
                                              await _messageQueueScheduler
                                                  ?.dispatchNext();
                                            }
                                          }),
                                          icon: const Icon(Icons.play_arrow),
                                        ),
                                        IconButton(
                                          tooltip: '删除',
                                          onPressed: () => mutate(
                                            () => _messageQueue.remove(
                                              workspaceId: _queueWorkspaceId,
                                              sessionId: _queueSessionId,
                                              itemId: item.id,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'),
                  ),
                ],
              );
            },
          ),
        );
      });
    } finally {
      newMessage.dispose();
      _queueDialogOpen = false;
    }
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
    if (payload?['type'] == 'vibekits.harnessEvent') {
      unawaited(_handleHarnessEvent(payload!));
      return;
    }
    if (payload?['type'] == 'vibekits.queue.open') {
      unawaited(() async {
        await _setQueueContext(
          payload?['workspaceId']?.toString() ?? '',
          payload?['sessionId']?.toString() ?? '',
        );
        await _showMessageQueue();
      }());
      return;
    }
    if (payload?['type'] == 'vibekits.queue.steered') {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('已补充当前任务'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    if (_pointerDiagnostics && payload?['type'] == 'vibekits.pointerProbe') {
      _appendPointerDiagnostic(
        'dom ${payload?['event']} x=${payload?['x']} y=${payload?['y']} '
        'target=${payload?['target']}',
      );
      return;
    }
    if (payload?['type'] == 'vibekits.inferenceError') {
      final String code = (payload?['code'] as String? ?? '').trim();
      final String detail = (payload?['message'] as String? ?? '').trim();
      final String message = code == 'AUTH'
          ? 'API 密钥无效，请检查 DeepSeek API Key 后重试。'
          : detail.isEmpty
          ? '推理失败，请检查模型配置后重试。'
          : detail;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
          ),
        );
      return;
    }
    if (payload?['type'] == 'vibekits.workspaceSnapshot') {
      final Object? rawWorkspaces = payload?['workspaces'];
      if (rawWorkspaces is! List) return;
      final List<HarnessWorkspaceSummary> workspaces =
          <HarnessWorkspaceSummary>[
            for (final Object? raw in rawWorkspaces)
              if (raw is Map &&
                  (raw['label'] as String? ?? '').trim().isNotEmpty)
                HarnessWorkspaceSummary(
                  workspaceRef:
                      (raw['workspaceRef'] as String? ?? raw['label'] as String)
                          .trim(),
                  label: (raw['label'] as String).trim(),
                  active: raw['active'] == true,
                ),
          ];
      HarnessWorkStatusHub.syncWorkspaceInventory(workspaces);
      return;
    }
    if (payload?['type'] == 'vibekits.moveSession') {
      final String sessionId = (payload?['sessionId'] as String? ?? '').trim();
      final String sourceWorkspaceId =
          (payload?['sourceWorkspaceId'] as String? ?? '').trim();
      final String targetWorkspaceId =
          (payload?['targetWorkspaceId'] as String? ?? '').trim();
      final String sourceLabel = (payload?['sourceLabel'] as String? ?? '')
          .trim();
      final String targetLabel = (payload?['targetLabel'] as String? ?? '')
          .trim();
      unawaited(
        _confirmMoveSession(
          sessionId: sessionId,
          sourceWorkspaceId: sourceWorkspaceId,
          targetWorkspaceId: targetWorkspaceId,
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
        ),
      );
      return;
    }
    if (payload?['type'] != 'vibekits.deleteSession') return;
    final String sessionId = (payload?['sessionId'] as String? ?? '').trim();
    final String title = (payload?['title'] as String? ?? '').trim();
    unawaited(_confirmDeleteSession(sessionId, title));
  }

  Future<void> _handleHarnessEvent(Map<String, dynamic> payload) async {
    await _setQueueContext(
      payload['workspaceId']?.toString() ?? '',
      payload['sessionId']?.toString() ?? '',
    );
    final String event = payload['event']?.toString() ?? '';
    _queueAdapterCompatible = payload['compatible'] == true;
    _harnessBusy = payload['busy'] == true;
    _harnessApprovalWaiting = payload['approvalWaiting'] == true;
    _messageQueueScheduler?.updateHarnessState(
      busy: _harnessBusy || !_queueAdapterCompatible,
      approvalWaiting: _harnessApprovalWaiting,
    );
    if (event == 'message.accepted') {
      final String key = payload['idempotencyKey']?.toString() ?? '';
      if (key.isNotEmpty && key == _pendingQueueIdempotencyKey) {
        final Completer<bool>? acceptance = _pendingQueueAcceptance;
        if (acceptance != null && !acceptance.isCompleted) {
          acceptance.complete(true);
        }
      }
    } else if (event == 'turn.completed' ||
        event == 'turn.failed' ||
        event == 'turn.cancelled') {
      await _messageQueueScheduler?.onTurnFinished();
    }
    await _refreshQueueCount();
  }

  Future<void> _confirmMoveSession({
    required String sessionId,
    required String sourceWorkspaceId,
    required String targetWorkspaceId,
    required String sourceLabel,
    required String targetLabel,
  }) async {
    if (!mounted ||
        _starting ||
        sessionId.isEmpty ||
        sourceWorkspaceId.isEmpty ||
        targetWorkspaceId.isEmpty ||
        sourceWorkspaceId == targetWorkspaceId ||
        !_movingSessionIds.add(sessionId)) {
      return;
    }
    final bool confirmed =
        await _withFlutterOverlay<bool>(
          () => showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('移动会话并切换工作区权限？'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  '会话将从“${sourceLabel.isEmpty ? '原项目' : sourceLabel}”移动到'
                  '“${targetLabel.isEmpty ? '目标项目' : targetLabel}”。\n\n'
                  '后续文件读取、写入和命令执行将以目标项目目录为工作区。'
                  '为保证权限边界一致，当前 Harness 运行会先安全停止，迁移成功后自动恢复。',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('移动并切换权限'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      _movingSessionIds.remove(sessionId);
      return;
    }
    setState(() => _status = '正在安全迁移会话工作区…');
    try {
      final HarnessSessionHandle? session = _session;
      _session = null;
      if (session != null && session.running) {
        await session.stop();
        widget.onRunningChanged?.call(false);
      }
      await DeepSeekHarnessService.rebindSessionWorkspace(
        sessionId: sessionId,
        sourceWorkspaceId: sourceWorkspaceId,
        targetWorkspaceId: targetWorkspaceId,
      );
      if (!mounted) return;
      setState(() => _status = '会话已移动，正在按新工作区权限恢复…');
      await _start(preserveWebview: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = '移动会话失败，原项目保持不变：$error');
      await _start(preserveWebview: true);
    } finally {
      _movingSessionIds.remove(sessionId);
    }
  }

  Future<void> _confirmDeleteSession(String sessionId, String title) async {
    if (!mounted ||
        _starting ||
        sessionId.isEmpty ||
        !_deletingSessionIds.add(sessionId)) {
      return;
    }
    final bool confirmed =
        await _withFlutterOverlay<bool>(
          () => showDialog<bool>(
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
    if (status == HarnessToolActivityStatus.denied ||
        Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }
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

  @override
  void dispose() {
    _disposing = true;
    HarnessRemoteManagementBridge.unbind(this);
    _restartTimer?.cancel();
    _stabilityTimer?.cancel();
    _remoteAuthorizationTimer?.cancel();
    _remoteControllerSubscription?.cancel();
    if (_pointerDiagnostics) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        _recordFlutterPointer,
      );
    }
    _diagnosticsTimer?.cancel();
    _outputSubscription?.cancel();
    _webMessageSubscription?.cancel();
    _loadingStateSubscription?.cancel();
    _navigationDiagnosticSubscription?.cancel();
    final HarnessSessionHandle? session = _session;
    if (session != null && session.running) unawaited(session.stop());
    // The app-wide remote endpoint is owned by the explicit assistance switch,
    // not by this rebuildable workspace state.
    // The first-pair listener belongs to the application-level remote access
    // switch, not to this responsive workspace widget. A window resize, tab
    // change, or workspace rebuild must never make an enabled Mac disappear
    // while a PAD is pairing. The explicit "关闭远程协助" action owns stop().
    widget.onRunningChanged?.call(false);
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.stopped,
      message: 'Harness 工作区已关闭',
    );
    final HarnessWorkspaceStatusContext? workStatusContext = _workStatusContext;
    if (workStatusContext != null) {
      HarnessWorkStatusHub.clearWorkspace(workStatusContext);
    }
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
                  harnessStartupDiagnostic(_diagnostics),
                  maxLines: 6,
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
                  onPressed: _retryManually,
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
    final HarnessRemoteControllerSession? remoteSession =
        HarnessRemoteControllerRuntime.instance.session;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        paste: () => unawaited(_pasteIntoFocusedWebField()),
        pastePlain: () => unawaited(_pasteIntoFocusedWebField()),
        pasteInsert: () => unawaited(_pasteIntoFocusedWebField()),
        copy: () => unawaited(_copyFromFocusedWebSelection()),
      },
      child: Column(
        children: <Widget>[
          _buildRemoteAssistanceBar(),
          Expanded(
            child: remoteSession != null
                ? _buildRemoteWorkspace(remoteSession)
                : Row(
                    children: <Widget>[
                      Expanded(
                        child: Stack(
                          children: <Widget>[
                            _buildHarnessWebview(),
                            if (_quickActionsExpanded)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => setState(
                                    () => _quickActionsExpanded = false,
                                  ),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withValues(alpha: 0.90),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
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
                                  stream:
                                      McpCapabilityDirectory.instance.changes,
                                  initialData:
                                      McpCapabilityDirectory.instance.snapshot,
                                  builder:
                                      (
                                        BuildContext context,
                                        AsyncSnapshot<McpCapabilitySnapshot>
                                        snapshot,
                                      ) {
                                        final int count =
                                            snapshot.data?.local.length ?? 0;
                                        return _mcpDeviceButton(
                                          key: const Key(
                                            'harness-local-mcp-devices',
                                          ),
                                          icon: Icons.memory_outlined,
                                          label: '本机',
                                          tooltip: '本机 MCP：查看同一台电脑上其他进程提供的接口',
                                          count: count,
                                          onTap: () => _showMcpDevices(
                                            McpCapabilityTier.local,
                                          ),
                                        );
                                      },
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 142,
                                child: StreamBuilder<McpCapabilitySnapshot>(
                                  stream:
                                      McpCapabilityDirectory.instance.changes,
                                  initialData:
                                      McpCapabilityDirectory.instance.snapshot,
                                  builder:
                                      (
                                        BuildContext context,
                                        AsyncSnapshot<McpCapabilitySnapshot>
                                        snapshot,
                                      ) {
                                        final int count =
                                            snapshot.data?.lan.length ?? 0;
                                        return _mcpDeviceButton(
                                          key: const Key(
                                            'harness-lan-mcp-devices',
                                          ),
                                          icon: Icons.hub_outlined,
                                          label: '局域网',
                                          tooltip: '局域网 MCP：查看同一网络内其他设备提供的接口',
                                          count: count,
                                          onTap: () => _showMcpDevices(
                                            McpCapabilityTier.lan,
                                          ),
                                        );
                                      },
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 186,
                                child: Material(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surface.withValues(alpha: 0.94),
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
                                              key: Key(
                                                'harness-feishu-${task.id}',
                                              ),
                                              value: task,
                                              child: Text(task.label),
                                            ),
                                        ],
                                    child: const SizedBox(
                                      width: 92,
                                      height: 36,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: <Widget>[
                                          Icon(Icons.forum_outlined, size: 16),
                                          SizedBox(width: 6),
                                          Text(
                                            '飞书',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(Icons.arrow_drop_down, size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 230,
                                child: Material(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surface.withValues(alpha: 0.94),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: <Widget>[
                                            Icon(
                                              Icons.receipt_long_outlined,
                                              size: 16,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              '日志',
                                              style: TextStyle(fontSize: 12),
                                            ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteWorkspace(HarnessRemoteControllerSession session) {
    return Padding(
      key: const Key('official-harness-remote-workspace'),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final projectHeight = math.min(
            220.0,
            math.max(140.0, constraints.maxHeight * 0.24),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: projectHeight,
                child: HarnessRemoteReadOnlyPanel(
                  peerRoutingId: session.peer.routingId,
                  model: session.model,
                  onDisconnect: () => unawaited(
                    HarnessRemoteControllerRuntime.instance.close(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('harness-remote-command-scroll'),
                  primary: false,
                  child: HarnessRemoteCommandPanel(
                    model: session.model,
                    client: session.client,
                    allowedOperations: session.peer.operations,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRemoteAssistanceBar() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 14),
            const Icon(Icons.monitor_heart_outlined, size: 19),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '远程状态',
                key: Key('official-harness-remote-status-title'),
                maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            StreamBuilder<HarnessSimulatorTargetSnapshot>(
              stream: HarnessSimulatorTargetRuntime.shared.changes,
              initialData: HarnessSimulatorTargetRuntime.shared.latest,
              builder: (BuildContext context, snapshot) {
                final simulator =
                    snapshot.data ??
                    HarnessSimulatorTargetRuntime.shared.latest;
                if (!simulator.enabled) return const SizedBox.shrink();
                final (Color color, String label) = switch (simulator.phase) {
                  HarnessSimulatorTargetPhase.disabled => (colors.outline, ''),
                  HarnessSimulatorTargetPhase.starting => (
                    Colors.orange,
                    '局域网仿真准备中',
                  ),
                  HarnessSimulatorTargetPhase.ready => (
                    Colors.blue,
                    '局域网仿真可连接',
                  ),
                  HarnessSimulatorTargetPhase.connected => (
                    Colors.green,
                    '局域网仿真中',
                  ),
                  HarnessSimulatorTargetPhase.error => (Colors.red, '局域网仿真异常'),
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    key: const Key('official-harness-simulator-status'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
            StreamBuilder<RustDeskHarnessLinkSnapshot>(
              stream: RustDeskHarnessLinkStatusHub.changes,
              initialData: RustDeskHarnessLinkStatusHub.latest,
              builder: (BuildContext context, snapshot) {
                final controllerSession =
                    HarnessRemoteControllerRuntime.instance.session;
                if (controllerSession != null) {
                  return Row(
                    key: const Key('official-harness-remote-link-status'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: controllerSession.model.stale
                              ? Colors.orange
                              : Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        controllerSession.model.stale ? '协同恢复中' : '协同已连接',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 10),
                    ],
                  );
                }
                final link =
                    snapshot.data ?? RustDeskHarnessLinkStatusHub.latest;
                final (Color color, String label) = switch (link.phase) {
                  RustDeskHarnessLinkPhase.connected => (Colors.green, '已连接'),
                  RustDeskHarnessLinkPhase.clientFound => (Colors.blue, '协同就绪'),
                  RustDeskHarnessLinkPhase.handshaking => (
                    Colors.orange,
                    '协同连接中',
                  ),
                  RustDeskHarnessLinkPhase.incompatible ||
                  RustDeskHarnessLinkPhase.stale => (Colors.red, '协同异常'),
                  RustDeskHarnessLinkPhase.disconnected => (
                    Colors.blue,
                    '协同断开',
                  ),
                };
                return Row(
                  key: const Key('official-harness-remote-link-status'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      link.phase == RustDeskHarnessLinkPhase.connected
                          ? '协同已连接'
                          : label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRuntimeLogs() async {
    await _withFlutterOverlay<void>(
      () => showDialog<void>(
        context: context,
        builder: (BuildContext context) => const _HarnessRuntimeLogDialog(),
      ),
    );
  }

  Widget _buildQuickActionsRail() => Container(
    width: 60,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border(
        left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: ListView(
      key: const Key('harness-quick-actions-rail-scroll'),
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      children: <Widget>[
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
                key: const Key('rail-app-mcp'),
                icon: Icons.apps_rounded,
                badge:
                    snapshot.data?.app
                        .expand((McpDeviceCapability item) => item.tools)
                        .length ??
                    0,
                tooltip: '本 APP MCP：查看 VibeKits 对外公开的全部工具和参数',
                onPressed: () => _showMcpDevices(McpCapabilityTier.app),
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
          onOpened: () => unawaited(_blockNativeWebViewInput()),
          onCanceled: () => unawaited(_unblockNativeWebViewInput()),
          onSelected: (FeishuHarnessTask task) {
            unawaited(_unblockNativeWebViewInput());
            unawaited(_selectFeishuTask(task));
          },
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
        _railAction(
          key: const Key('rail-mcp-settings'),
          icon: Icons.settings_outlined,
          tooltip: 'MCP 设置',
          onPressed: _showMcpSettings,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
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

  Future<void> _showMcpSettings() async => _withFlutterOverlay<void>(
    () => showDialog<void>(
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
    ),
  );

  Widget _buildMcpExposureControl() => Material(
    color:
        (_mcpExposureEnabled
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest)
            .withValues(alpha: 0.96),
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
            Icon(
              _mcpExposureEnabled ? Icons.api_rounded : Icons.api_outlined,
              size: 17,
              color: _mcpExposureEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              _mcpExposureChanging
                  ? '处理中'
                  : 'MCP ${_mcpExposureEnabled ? '开' : '关'}',
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
                  onChanged: _mcpExposureChanging
                      ? null
                      : (bool enabled) => unawaited(_setMcpExposure(enabled)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _setMcpExposure(bool enabled) async {
    if (_mcpExposureEnabled == enabled || _mcpExposureChanging) return;
    final VibekitsHarnessToolBridge? bridge = _mcpExposureBridge;
    if (bridge == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('MCP 工具目录尚未就绪，请稍后重试')));
      return;
    }
    if (enabled) {
      late final LmcpInstanceCertificate identity;
      try {
        identity = await VibekitsLmcpExposureServer.instance.prepareIdentity(
          displayName: _mcpIdentity.displayName,
        );
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('准备 MCP 实例证书失败：$error')));
        }
        return;
      }
      if (!mounted) return;
      final List<McpToolInterface> tools = McpCapabilityDirectory
          .instance
          .snapshot
          .app
          .expand((McpDeviceCapability device) => device.tools)
          .toList(growable: false);
      final bool allowed =
          await _withFlutterOverlay<bool>(
            () => showMcpExposureConsentDialog(
              context: context,
              deviceName: _mcpIdentity.displayName,
              tools: tools,
              certificateFingerprint: identity.fingerprint,
            ),
          ) ??
          false;
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
      _restoreMcpExposureOnStart = enabled;
      if (mounted) {
        setState(
          () =>
              _mcpExposureEnabled = VibekitsLmcpExposureServer.instance.running,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存 MCP 开关失败：$error')));
    } finally {
      if (mounted) setState(() => _mcpExposureChanging = false);
    }
  }

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

  Future<void> _showMcpDevices(McpCapabilityTier tier) async {
    await _withFlutterOverlay<void>(
      () => showDialog<void>(
        context: context,
        builder: (BuildContext context) => _McpDeviceListDialog(tier: tier),
      ),
    );
  }
}

class _McpDeviceListDialog extends StatelessWidget {
  const _McpDeviceListDialog({required this.tier});

  final McpCapabilityTier tier;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<Map<String, McpToolReputation>>(
    future: McpCapabilityDirectory.instance.loadReputations(),
    builder: (BuildContext context, reputationSnapshot) => AlertDialog(
      title: Text(switch (tier) {
        McpCapabilityTier.app => '本 APP MCP 工具',
        McpCapabilityTier.local => '本机 MCP 设备',
        McpCapabilityTier.lan => '局域网 MCP 设备',
      }),
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
                final List<McpDeviceCapability> devices = switch (tier) {
                  McpCapabilityTier.app => catalog.app,
                  McpCapabilityTier.local => catalog.local,
                  McpCapabilityTier.lan => catalog.lan,
                };
                if (devices.isEmpty) {
                  return Center(
                    child: Text(switch (tier) {
                      McpCapabilityTier.app => '本 APP 工具目录尚未初始化。',
                      McpCapabilityTier.local =>
                        '尚未发现本机其他 MCP 进程。提供者上线并发布注册文件后会自动出现。',
                      McpCapabilityTier.lan =>
                        '尚未发现局域网 MCP 设备。设备上线、离线和接口变化会实时更新。',
                    }, textAlign: TextAlign.center),
                  );
                }
                return ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final McpDeviceCapability device = devices[index];
                    final Map<String, McpToolReputation> reputations =
                        reputationSnapshot.data ??
                        const <String, McpToolReputation>{};
                    final int scoredTools = device.tools.where((
                      McpToolInterface tool,
                    ) {
                      final McpToolReputation? score = reputationForTool(
                        reputations,
                        device,
                        tool,
                      );
                      return score != null &&
                          (score.totalCalls > 0 || score.manualRating != null);
                    }).length;
                    return ListTile(
                      key: Key('mcp-device-${device.id}'),
                      leading: Icon(switch (tier) {
                        McpCapabilityTier.app => Icons.apps_rounded,
                        McpCapabilityTier.local => Icons.memory_outlined,
                        McpCapabilityTier.lan => Icons.computer_outlined,
                      }),
                      title: Text(device.name),
                      subtitle: Text(
                        '${device.appId} ${device.appVersion} · ${device.transport} · '
                        '${device.tools.length} 个接口'
                        '${scoredTools == 0 ? '' : ' · $scoredTools 个已评分'}',
                      ),
                      trailing: Chip(
                        avatar: Icon(
                          device.callable
                              ? Icons.check_circle_outline
                              : Icons.visibility_outlined,
                          size: 16,
                        ),
                        label: Text(device.callable ? '可调用' : '仅发现'),
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (BuildContext context) =>
                            _McpDeviceDetailsDialog(
                              device: device,
                              reputations: reputations,
                            ),
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
    ),
  );
}

class _McpDeviceDetailsDialog extends StatelessWidget {
  const _McpDeviceDetailsDialog({
    required this.device,
    required this.reputations,
  });

  final McpDeviceCapability device;
  final Map<String, McpToolReputation> reputations;

  @override
  Widget build(BuildContext context) {
    final bool continuousCanvas = MediaQuery.sizeOf(context).height > 900;
    return AlertDialog(
      // A 1920x2560 KEMI canvas is two physical 1920x1280 panels. Centering a
      // dialog in that canvas straddles the untouchable seam. Pin bounded
      // dialogs to the top panel; ordinary desktop/single-screen windows keep
      // Material's centered behavior.
      alignment: continuousCanvas ? Alignment.topCenter : null,
      insetPadding: continuousCanvas
          ? const EdgeInsets.fromLTRB(40, 24, 40, 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
              '调用状态：${device.callable ? '可调用' : '仅发现，不可调用'}\n'
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
                            '${tool.title.isEmpty ? tool.description : tool.title} · 风险 ${tool.risk.isEmpty ? '提供者未声明' : tool.risk}',
                          ),
                          trailing: McpReputationBadge(
                            reputation: reputationForTool(
                              reputations,
                              device,
                              tool,
                            ),
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
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: SelectableText(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(tool.inputSchema),
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

class HarnessRemoteShareDialog extends StatefulWidget {
  const HarnessRemoteShareDialog({
    super.key,
    required this.configuredExecutable,
    required this.webClientUrl,
    required this.onPaired,
    required this.onHostStopped,
    this.embedded = false,
    this.controllerOnly,
    this.onConnectionChanged,
    this.localWorkspaceIds,
  });

  final String configuredExecutable;
  final String webClientUrl;
  final Future<void> Function() onPaired;
  final Future<void> Function() onHostStopped;
  final bool embedded;

  /// Forces the surface into an outbound-only controller role. Android PADs
  /// use this mode: they can assist another Harness, but never expose their
  /// own workspace or start the inbound pairing host.
  final bool? controllerOnly;
  final void Function(bool connected, String peerId)? onConnectionChanged;
  final Set<String> Function()? localWorkspaceIds;

  @override
  State<HarnessRemoteShareDialog> createState() =>
      _HarnessRemoteShareDialogState();
}

class _HarnessRemoteShareDialogState extends State<HarnessRemoteShareDialog> {
  late Future<RustDeskHostInfo> _host = _inspectHost();
  late Future<List<RustDeskHarnessIncomingConnection>> _incoming =
      _loadIncoming();
  late Future<List<HarnessRemotePeer>> _rememberedPeers =
      Platform.environment['FLUTTER_TEST'] == 'true'
      ? Future<List<HarnessRemotePeer>>.value(const <HarnessRemotePeer>[])
      : HarnessRemotePeerStore().load();
  Timer? _incomingTimer;
  bool _incomingRefreshInFlight = false;
  final TextEditingController _remoteId = TextEditingController();
  final TextEditingController _remoteWorkspaceId = TextEditingController();
  final TextEditingController _localPassword = TextEditingController(
    text: HarnessRemoteAccessSettings.defaultPassword,
  );
  final TextEditingController _remotePassword = TextEditingController(
    text: HarnessRemoteAccessSettings.defaultPassword,
  );
  final HarnessRemoteAccessSettings _accessSettings =
      HarnessRemoteAccessSettings();
  bool _remoteEnabled = false;
  bool _passwordSaving = false;
  bool _obscureLocalPassword = true;
  bool _obscureRemotePassword = true;
  bool _forceRelay = false;
  bool _connecting = false;
  bool _simulatorConnecting = false;
  String? _simulatorRoutingId;
  int _simulatorToolCount = 0;
  int _connectGeneration = 0;
  DateTime? _remoteSessionConnectedAt;
  DateTime? _lastAutomaticReconnectAt;
  String _message = '';
  HarnessRemoteControllerSession? _remoteSession =
      HarnessRemoteControllerRuntime.instance.session;
  VoidCallback? _remoteModelListener;
  bool _reportedRemoteLive = false;

  bool get _controllerOnly => widget.controllerOnly ?? Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _remoteEnabled = _controllerOnly || HarnessRemoteAccessSettings.enabled;
    final existingSession = _remoteSession;
    if (existingSession != null) _bindRemoteSession(existingSession);
    unawaited(_loadRemoteSettings());
    _incomingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshIncoming());
      unawaited(_reconnectStaleRemoteSession());
    });
  }

  @override
  void dispose() {
    _connectGeneration++;
    _incomingTimer?.cancel();
    _detachRemoteModelListener();
    _remoteId.dispose();
    _remoteWorkspaceId.dispose();
    _localPassword.dispose();
    _remotePassword.dispose();
    super.dispose();
  }

  void _detachRemoteModelListener() {
    final session = _remoteSession;
    final listener = _remoteModelListener;
    if (session != null && listener != null) {
      session.model.removeListener(listener);
    }
    _remoteModelListener = null;
  }

  void _reportRemoteLive(bool live, String peerId) {
    if (_reportedRemoteLive == live) return;
    _reportedRemoteLive = live;
    widget.onConnectionChanged?.call(live, live ? peerId : '');
  }

  void _bindRemoteSession(HarnessRemoteControllerSession session) {
    _detachRemoteModelListener();
    void listener() {
      if (!mounted || _remoteSession != session) return;
      final live = !session.model.stale;
      _reportRemoteLive(live, session.peer.routingId);
      setState(() {
        if (live) {
          _message = '远端项目状态已同步，协同连接可用';
        } else if (!_connecting) {
          _message = '远程状态已中断，正在后台自动重连…';
        }
      });
    }

    _remoteModelListener = listener;
    session.model.addListener(listener);
    listener();
  }

  Future<RustDeskHostInfo> _inspectHost() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return const RustDeskHostInfo(
        executable: '/test/vibekits-harness-relay',
        id: '1554650784',
        available: true,
        callable: true,
        rendezvousOnline: true,
        registrationKeyConfirmed: true,
        state: 'registered',
        message: '测试 Harness 网络身份已就绪',
      );
    }
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

  Future<List<RustDeskHarnessIncomingConnection>> _loadIncoming() async {
    final RustDeskHostInfo host = await _host;
    return _loadIncomingForHost(host);
  }

  Future<List<RustDeskHarnessIncomingConnection>> _loadIncomingForHost(
    RustDeskHostInfo host,
  ) async {
    if (!_remoteEnabled ||
        !host.available ||
        !host.callable ||
        host.executable.isEmpty) {
      return const [];
    }
    try {
      var connections = await RustDeskHarnessShareService.connections(
        host.executable,
      );
      final rememberedIds = (await HarnessRemotePeerStore().load())
          .where((peer) => peer.remembered && peer.connectionReady)
          .map((peer) => peer.routingId)
          .toSet();
      var authorizedRemembered = false;
      for (final connection in connections) {
        if (!connection.authorized &&
            !connection.disconnected &&
            rememberedIds.contains(connection.peerId)) {
          await RustDeskHarnessShareService.decideConnection(
            host.executable,
            connectionId: connection.connectionId,
            allow: true,
          );
          authorizedRemembered = true;
        }
      }
      if (authorizedRemembered) {
        connections = await RustDeskHarnessShareService.connections(
          host.executable,
        );
      }
      return connections;
    } on Object {
      return const [];
    }
  }

  Future<void> _refreshIncoming() async {
    if (!mounted || _incomingRefreshInFlight) return;
    _incomingRefreshInFlight = true;
    // The native relay may still be registering when the dialog first opens.
    // Refresh both host state and connections so a later registration or a
    // provider-first incoming connection appears without closing the dialog.
    final hostFuture = _inspectHost();
    final future = hostFuture.then(_loadIncomingForHost);
    setState(() {
      _host = hostFuture;
      _incoming = future;
    });
    try {
      await future;
    } finally {
      _incomingRefreshInFlight = false;
    }
  }

  Future<void> _reconnectStaleRemoteSession() async {
    final session = _remoteSession;
    if (!mounted ||
        !_remoteEnabled ||
        _connecting ||
        session == null ||
        !session.model.stale) {
      return;
    }
    final now = DateTime.now();
    // A new model starts stale until its first authenticated snapshot lands.
    // Do not tear down that healthy initial handshake.  Once a previously
    // synchronized carrier goes stale, retry silently with a bounded cadence.
    if (_remoteSessionConnectedAt case final connectedAt?
        when now.difference(connectedAt) < const Duration(seconds: 4)) {
      return;
    }
    if (_lastAutomaticReconnectAt case final attemptedAt?
        when now.difference(attemptedAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastAutomaticReconnectAt = now;
    final host = await _inspectHost();
    if (!mounted || _remoteSession != session || !session.model.stale) return;
    await _connectRemote(host, automatic: true);
  }

  Future<void> _loadRemoteSettings() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      if (_controllerOnly && mounted) setState(() => _remoteEnabled = true);
      return;
    }
    if (_controllerOnly) {
      // A PAD is an outbound-only controller. Inspecting the native carrier
      // registers its RustDesk routing identity; it must not enable inbound
      // access, start HarnessRemotePairingHost, or persist host settings.
      final host = await _host;
      if (!mounted) return;
      setState(() {
        _remoteEnabled = true;
        _message = host.available
            ? 'PAD 协助端网络已就绪，请输入对方 Harness ID'
            : 'PAD 协助端网络正在初始化…';
      });
      return;
    }
    final values = await Future.wait<Object>([
      _accessSettings.loadPassword(),
      _accessSettings.loadEnabled(),
    ]);
    final password = values[0] as String;
    final enabled = values[1] as bool;
    if (!mounted) return;
    setState(() {
      _localPassword.text = password;
      _remoteEnabled = enabled;
    });
  }

  Future<void> _saveLocalPassword() async {
    if (_passwordSaving) return;
    setState(() => _passwordSaving = true);
    try {
      await _accessSettings.savePassword(_localPassword.text);
      if (mounted) setState(() => _message = '本机远程协助密码已更新；仅用于新的首次配对');
    } on Object catch (error) {
      if (mounted) setState(() => _message = '密码保存失败：$error');
    } finally {
      if (mounted) setState(() => _passwordSaving = false);
    }
  }

  Future<void> _decide(
    RustDeskHostInfo host,
    RustDeskHarnessIncomingConnection connection,
    bool allow,
  ) async {
    try {
      await RustDeskHarnessShareService.decideConnection(
        host.executable,
        connectionId: connection.connectionId,
        allow: allow,
      );
      if (!mounted) return;
      setState(() {
        _message = allow
            ? '已允许 ${connection.peerName.isEmpty ? connection.peerId : connection.peerName} 本次连接'
            : connection.authorized
            ? '已强制断开 ${connection.peerName.isEmpty ? connection.peerId : connection.peerName}'
            : '已拒绝 ${connection.peerName.isEmpty ? connection.peerId : connection.peerName}';
        _incoming = _loadIncoming();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '授权操作失败：$error');
    }
  }

  Future<void> _launchHost(RustDeskHostInfo host) async {
    try {
      await _accessSettings.savePassword(_localPassword.text);
      await _accessSettings.saveEnabled(true);
      await HarnessRemotePairingHost.instance.start();
      await RustDeskHarnessShareService.launchHost(host.executable);
      // Always ask the execution runtime to start.  It owns the authoritative
      // credential check and returns REMOTE_PAIRING_SCOPE_NOT_PERSISTED when
      // this is a genuine first-use wait.  Duplicating that check here caused
      // an enabled-looking UI with no 32146 listener after a remembered peer
      // had already been approved.
      try {
        await widget.onPaired();
      } on StateError catch (error) {
        if (!error.toString().contains('REMOTE_PAIRING_SCOPE_NOT_PERSISTED')) {
          rethrow;
        }
      }
      RustDeskHarnessLinkStatusHub.clientFound();
      if (mounted) {
        setState(() {
          _remoteEnabled = true;
          _message = '远程协助已打开，RustDesk P2P 优先，失败自动经 HBBR 中继';
          _host = _inspectHost();
          _incoming = _loadIncoming();
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '启动失败：$error');
    }
  }

  Future<void> _stopHost() async {
    try {
      await _accessSettings.saveEnabled(false);
      await _disconnectRemote();
      await HarnessRemotePairingHost.instance.stop();
      await widget.onHostStopped();
      if (!HarnessSimulatorAccessSettings.enabled) {
        await RustDeskHarnessShareService.stopHost(
          configuredExecutable: widget.configuredExecutable,
        );
      }
      RustDeskHarnessLinkStatusHub.disconnected();
      if (mounted) {
        setState(() {
          _remoteEnabled = false;
          _message = '本机 Harness 中继已停止，所有隧道与待授权连接已关闭';
          // Re-read the lightweight registered identity so the local ID stays
          // visible while application-level remote access remains closed.
          _host = _inspectHost();
          _incoming = Future<List<RustDeskHarnessIncomingConnection>>.value(
            const <RustDeskHarnessIncomingConnection>[],
          );
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '停止中继失败：$error');
    }
  }

  Future<void> _connectRemote(
    RustDeskHostInfo host, {
    bool automatic = false,
  }) async {
    if (_connecting) return;
    if (!_remoteEnabled) {
      setState(() => _message = '请先打开远程协助模式');
      return;
    }
    final int generation = ++_connectGeneration;
    setState(() {
      _connecting = true;
      _message = automatic
          ? '远程通道短暂中断，正在后台自动重连…'
          : '正在建立 Harness ${_forceRelay ? '强制中继' : '直连/中继'}数据通道…';
    });
    try {
      final previous = HarnessRemoteControllerRuntime.instance.session;
      _detachRemoteModelListener();
      _remoteSession = null;
      _remoteSessionConnectedAt = null;
      _reportRemoteLive(false, '');
      await previous?.close();
      final routingId = _remoteId.text.trim();
      final peers = await HarnessRemotePeerStore().load();
      final matching = peers.where((peer) => peer.routingId == routingId);
      HarnessRemotePeer peer;
      var reconnectingRememberedPeer = false;
      if (matching.isEmpty || !matching.first.connectionReady) {
        final workspaceId = _remoteWorkspaceId.text.trim();
        if (!host.callable || host.id.isEmpty) {
          throw StateError('本机 Harness ID 尚未完成中继注册，不能发起配对');
        }
        final approval = await HarnessRemotePairingClient().pair(
          executable: host.executable,
          localRoutingId: host.id,
          remoteRoutingId: routingId,
          requestedWorkspaceIds: <String>{
            workspaceId.isEmpty
                ? HarnessRemotePairingRequest.currentWorkspaceCatalogScope
                : workspaceId,
          },
          requestedOperations: HarnessRemoteExecution.sessionOperations,
          forceRelay: _forceRelay,
          password: _remotePassword.text,
        );
        peer = approval.controllerRecord(remembered: true);
        _message = '首次配对完成，核对码 ${approval.comparisonCode}；正在建立正式通道';
      } else {
        peer = matching.first;
        reconnectingRememberedPeer = true;
      }
      final identity = await HarnessRemoteIdentityStore.instance.loadOrCreate();
      HarnessRemoteControllerSession session;
      try {
        session = await HarnessRemoteControllerSession.connect(
          executable: host.executable,
          peer: peer,
          identity: identity,
          forceRelay: _forceRelay,
          timeout: reconnectingRememberedPeer
              ? const Duration(seconds: 5)
              : const Duration(seconds: 25),
          // The project/status projection is rendered directly from the model.
          // Official conversation event injection remains a separate gate.
          applyOfficialEvents: (_) async {},
          restoreOfficialSnapshot: (_) async {},
        );
      } on TimeoutException catch (_) {
        if (!reconnectingRememberedPeer) rethrow;
        if (mounted && generation == _connectGeneration) {
          setState(() => _message = '原授权已失效，正在安全重新配对；请在执行端允许本次连接…');
        }
        final approval = await HarnessRemotePairingClient().pair(
          executable: host.executable,
          localRoutingId: host.id,
          remoteRoutingId: routingId,
          requestedWorkspaceIds: peer.workspaceIds,
          requestedOperations: peer.operations.intersection(
            HarnessRemoteExecution.sessionOperations,
          ),
          forceRelay: _forceRelay,
          password: _remotePassword.text,
        );
        peer = approval.controllerRecord(remembered: true);
        session = await HarnessRemoteControllerSession.connect(
          executable: host.executable,
          peer: peer,
          identity: identity,
          forceRelay: _forceRelay,
          applyOfficialEvents: (_) async {},
          restoreOfficialSnapshot: (_) async {},
        );
      }
      if (!mounted || generation != _connectGeneration) {
        await session.close();
        return;
      }
      setState(() {
        _remoteSession = session;
        _remoteSessionConnectedAt = DateTime.now();
        _message = '端到端证书与 Harness hello 已通过，正在同步远端项目状态';
      });
      await HarnessRemoteControllerRuntime.instance.adopt(session);
      _bindRemoteSession(session);
      await HarnessRemotePeerStore().save(
        peer.connectedNow(transport: _forceRelay ? 'relay' : 'direct'),
      );
      if (mounted) {
        setState(() => _rememberedPeers = HarnessRemotePeerStore().load());
      }
    } on Object catch (error) {
      if (mounted && generation == _connectGeneration) {
        _reportRemoteLive(false, '');
        setState(() {
          _message = automatic ? '后台重连未成功，将自动继续尝试' : '连接失败：$error';
        });
      }
    } finally {
      if (mounted && generation == _connectGeneration) {
        setState(() => _connecting = false);
      }
    }
  }

  void _cancelConnect() {
    if (!_connecting) return;
    _connectGeneration++;
    setState(() {
      _connecting = false;
      _message = '已取消连接；迟到的通道会被自动关闭';
    });
  }

  Future<void> _connectRemembered(
    RustDeskHostInfo host,
    HarnessRemotePeer peer,
  ) async {
    _remoteId.text = peer.routingId;
    await _connectRemote(host);
  }

  Future<void> _connectSimulator(String routingId) async {
    final id = routingId.trim();
    if (_simulatorConnecting || id.isEmpty) {
      if (id.isEmpty && mounted) setState(() => _message = '请输入对方 Harness ID');
      return;
    }
    setState(() {
      _simulatorConnecting = true;
      _message = '正在按 ID 建立仿真调试通道并读取远端工具目录…';
    });
    try {
      await HarnessSimulatorController.shared.connect(
        id,
        forceRelay: _forceRelay,
      );
      final tools = HarnessSimulatorController.shared.catalog(id);
      // Listing the catalog proves only that the tunnel and MCP handshake are
      // alive. Run one bounded, read-only target call as part of the explicit
      // connect action so the UI never reports a usable simulator when remote
      // execution itself is broken.
      await HarnessSimulatorController.shared.call(
        id,
        VibekitsHarnessToolBridge.deviceProcessesId,
        const <String, Object?>{'query': 'Vibekits', 'limit': 10},
      );
      final capabilityResult = await HarnessSimulatorController.shared.call(
        id,
        VibekitsHarnessToolBridge.capabilityCheckId,
        const <String, Object?>{},
      );
      final structured = capabilityResult['structuredContent'];
      final capabilityData = structured is Map && structured['data'] is Map
          ? Map<String, Object?>.from(structured['data']! as Map)
          : const <String, Object?>{};
      final platform = capabilityData['platform'];
      final storage = platform is Map && platform['storageLocations'] is Map
          ? Map<String, Object?>.from(platform['storageLocations']! as Map)
          : const <String, Object?>{};
      final probeRoot = '${storage['downloads'] ?? ''}'.trim();
      if (probeRoot.isEmpty) {
        throw StateError('远端未返回可验证的受控文件目录');
      }
      await HarnessSimulatorController.shared
          .call(id, VibekitsHarnessToolBridge.fileSearchId, <String, Object?>{
            'root': probeRoot,
            'query': '__vibekits_simulator_probe__',
            'mode': 'name',
            'maxResults': 1,
          });
      if (!mounted) return;
      setState(() {
        _simulatorRoutingId = id;
        _simulatorToolCount = tools.length;
        _message = '仿真调试已连接 $id · ${tools.length} 项工具 · 进程与文件自检通过';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '仿真连接失败：$error');
    } finally {
      if (mounted) setState(() => _simulatorConnecting = false);
    }
  }

  Future<void> _disconnectSimulator() async {
    final id = _simulatorRoutingId;
    if (id == null) return;
    await HarnessSimulatorController.shared.disconnect(id);
    if (!mounted) return;
    setState(() {
      _simulatorRoutingId = null;
      _simulatorToolCount = 0;
      _message = '仿真调试通道已断开';
    });
  }

  Future<void> _disconnectRemote() async {
    final session = _remoteSession;
    _detachRemoteModelListener();
    _reportRemoteLive(false, '');
    if (session == null) return;
    setState(() {
      _remoteSession = null;
      _remoteSessionConnectedAt = null;
      _message = '正在断开 Harness 数据通道…';
    });
    await HarnessRemoteControllerRuntime.instance.close();
    RustDeskHarnessLinkStatusHub.disconnected();
    if (mounted) setState(() => _message = 'Harness 数据通道已断开');
  }

  Future<void> _approvePairing(
    RustDeskHostInfo host,
    HarnessRemotePendingPairing pending,
  ) async {
    try {
      final nativeConnections = await RustDeskHarnessShareService.connections(
        host.executable,
      );
      final nativeAuthorized = nativeConnections.any(
        (connection) =>
            connection.peerId == pending.request.routingId &&
            connection.authorized &&
            !connection.disconnected,
      );
      if (!nativeAuthorized) {
        throw StateError('PAIRING_NATIVE_CALLER_NOT_AUTHORIZED');
      }
      var grantedWorkspaceIds = pending.request.requestedWorkspaceIds;
      if (grantedWorkspaceIds.contains(
        HarnessRemotePairingRequest.currentWorkspaceCatalogScope,
      )) {
        grantedWorkspaceIds = widget.localWorkspaceIds?.call() ?? const {};
        if (grantedWorkspaceIds.isEmpty) {
          throw StateError('PAIRING_LOCAL_WORKSPACE_UNAVAILABLE');
        }
      }
      final approval = await HarnessRemotePairingHost.instance.approve(
        nonce: pending.request.nonce,
        hostRoutingId: host.id,
        grantedWorkspaceIds: grantedWorkspaceIds,
        grantedOperations: pending.request.requestedOperations.intersection(
          HarnessRemoteExecution.sessionOperations,
        ),
      );
      await widget.onPaired();
      final peers = HarnessRemotePeerStore().load();
      if (mounted) {
        setState(() {
          _rememberedPeers = peers;
          _message =
              '已持久授权 ${pending.request.routingId}；双方核对码 ${approval.comparisonCode}';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '首次配对失败：$error');
    }
  }

  Future<void> _forgetPeer(String routingId) async {
    await HarnessRemotePeerStore().forget(routingId);
    if (_remoteSession?.peer.routingId == routingId) {
      await _disconnectRemote();
    }
    if (mounted) {
      setState(() {
        _rememberedPeers = HarnessRemotePeerStore().load();
        _message = '已从本机连接历史移除 $routingId；执行端授权需在执行端撤销';
      });
    }
  }

  Widget _buildEmbeddedConnector(RustDeskHostInfo host) {
    final HarnessRemoteControllerSession? session = _remoteSession;
    if (session != null) {
      final bool live = !session.model.stale;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            key: const Key('harness-coordination-live-bar'),
            color: live
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    live ? Icons.circle : Icons.sync_problem_rounded,
                    size: live ? 11 : 19,
                    color: live ? const Color(0xFF16845B) : null,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      live
                          ? '协同模式 · 已连接 ${session.peer.routingId}'
                          : '协同模式 · 正在恢复 ${session.peer.routingId} 的数据同步',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('harness-coordination-disconnect'),
                    onPressed: _disconnectRemote,
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: const Text('断开'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: HarnessRemoteReadOnlyPanel(
              peerRoutingId: session.peer.routingId,
              model: session.model,
              onReconnect: () => unawaited(_connectRemote(host)),
              onDisconnect: () => unawaited(_disconnectRemote()),
            ),
          ),
          const SizedBox(height: 10),
          HarnessRemoteCommandPanel(
            model: session.model,
            client: session.client,
            allowedOperations: session.peer.operations,
          ),
        ],
      );
    }
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('连接远程设备', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _remoteSession == null || _remoteSession!.model.stale
                  ? '输入同一个设备 ID，可选择协同项目或仿真调试整机。'
                  : '协同连接已建立；下方内容全部来自 ${_remoteSession!.peer.routingId}。',
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('harness-coordination-peer-id'),
                    controller: _remoteId,
                    enabled:
                        _remoteEnabled &&
                        !_connecting &&
                        _remoteSession == null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '对方 Harness ID',
                      hintText: '输入 6～16 位数字 ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('harness-coordination-connect'),
                  onPressed: _connecting
                      ? _cancelConnect
                      : _remoteEnabled && host.available
                      ? (_remoteSession == null
                            ? () => _connectRemote(host)
                            : _disconnectRemote)
                      : null,
                  icon: _connecting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _remoteSession == null
                              ? Icons.link_rounded
                              : Icons.link_off_rounded,
                        ),
                  label: Text(
                    _connecting
                        ? '取消'
                        : _remoteSession == null
                        ? '协同'
                        : '断开',
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  key: const Key('harness-simulator-connect'),
                  onPressed: _simulatorConnecting || !host.available
                      ? null
                      : _simulatorRoutingId == null
                      ? () => _connectSimulator(_remoteId.text)
                      : _disconnectSimulator,
                  icon: _simulatorConnecting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _simulatorRoutingId == null
                              ? Icons.developer_mode_rounded
                              : Icons.link_off_rounded,
                        ),
                  label: Text(
                    _simulatorConnecting
                        ? '连接中'
                        : _simulatorRoutingId == null
                        ? '仿真'
                        : '断开仿真',
                  ),
                ),
              ],
            ),
            if (_simulatorRoutingId != null) ...<Widget>[
              const SizedBox(height: 10),
              Material(
                key: const Key('harness-simulator-live-bar'),
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.circle,
                        size: 10,
                        color: Color(0xFF16845B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '仿真调试 · $_simulatorRoutingId · $_simulatorToolCount 项工具',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_connecting) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              const Text('正在查找设备、建立 P2P/中继通道并校验身份…'),
            ],
            if (_message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(_message),
            ],
            if (_remoteSession == null)
              ExpansionTile(
                key: const Key('harness-coordination-first-connect-options'),
                tilePadding: EdgeInsets.zero,
                title: const Text('首次连接选项'),
                subtitle: const Text('默认密码 12345678；连接过的设备通常不需要展开'),
                children: <Widget>[
                  TextField(
                    key: const Key('harness-coordination-peer-password'),
                    controller: _remotePassword,
                    obscureText: _obscureRemotePassword,
                    enabled:
                        _remoteEnabled &&
                        !_connecting &&
                        _remoteSession == null,
                    decoration: InputDecoration(
                      labelText: '协助密码',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: _obscureRemotePassword ? '显示密码' : '隐藏密码',
                        onPressed: _remoteEnabled
                            ? () => setState(
                                () => _obscureRemotePassword =
                                    !_obscureRemotePassword,
                              )
                            : null,
                        icon: Icon(
                          _obscureRemotePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('harness-coordination-workspace-id'),
                    controller: _remoteWorkspaceId,
                    enabled:
                        _remoteEnabled &&
                        !_connecting &&
                        _remoteSession == null,
                    decoration: const InputDecoration(
                      labelText: '首次授权工作区 ID',
                      helperText: '可选；留空时由执行端确认其当前项目列表',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  CheckboxListTile(
                    key: const Key('harness-coordination-force-relay'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _forceRelay,
                    onChanged: _remoteEnabled && !_connecting
                        ? (bool? value) =>
                              setState(() => _forceRelay = value ?? false)
                        : null,
                    title: const Text('强制经 HBBR 中继'),
                    subtitle: const Text('验收用；日常保持关闭，由系统优先 P2P、失败自动中继'),
                  ),
                ],
              ),
            if (_remoteSession == null)
              FutureBuilder<List<HarnessRemotePeer>>(
                future: _rememberedPeers,
                builder: (context, snapshot) {
                  final peers = snapshot.data ?? const <HarnessRemotePeer>[];
                  if (peers.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Divider(),
                      Text(
                        '最近连接',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      for (final peer in peers)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history_rounded),
                          title: Text(peer.routingId),
                          subtitle: Text(
                            '${peer.lastTransport == 'relay' ? '中继' : '直连'} · ${peer.workspaceIds.length} 个工作区',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              FilledButton.tonal(
                                onPressed: _remoteEnabled && !_connecting
                                    ? () => _connectRemembered(host, peer)
                                    : null,
                                child: const Text('协同'),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonal(
                                key: Key(
                                  'harness-simulator-connect-${peer.routingId}',
                                ),
                                onPressed: _simulatorConnecting
                                    ? null
                                    : () => _connectSimulator(peer.routingId),
                                child: const Text('仿真'),
                              ),
                              IconButton(
                                key: Key(
                                  'harness-coordination-forget-${peer.routingId}',
                                ),
                                tooltip: '移除失效配对记录',
                                onPressed: _remoteEnabled && !_connecting
                                    ? () => _forgetPeer(peer.routingId)
                                    : null,
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalIdentityCard(RustDeskHostInfo host) => _advancedHoverHint(
    context,
    message: '远程协助和局域网仿真共用此 ID。将 ID 告知已获授权的设备即可建立连接。',
    child: Container(
      key: const Key('advanced-local-device-id-card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.badge_outlined),
          const SizedBox(width: 12),
          Text('本机 ID', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              host.id.isEmpty ? '正在注册…' : host.id,
              key: const Key('advanced-local-device-id'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            key: const Key('advanced-copy-local-id'),
            tooltip: '复制本机 ID',
            onPressed: host.callable && host.id.isNotEmpty
                ? () async {
                    await Clipboard.setData(ClipboardData(text: host.id));
                    if (mounted) setState(() => _message = '已复制本机 ID');
                  }
                : null,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmbeddedMode(RustDeskHostInfo host) => _controllerOnly
      ? _buildEmbeddedConnector(host)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildLocalIdentityCard(host),
            const SizedBox(height: 12),
            _buildEmbeddedConnector(host),
            const SizedBox(height: 8),
            // Authorization is time-sensitive. Never hide an incoming native
            // connection or certificate pairing request inside a collapsed
            // settings section.
            _buildNativeConnections(host),
            _buildPendingPairings(host),
            StreamBuilder<HarnessSimulatorTargetSnapshot>(
              stream: HarnessSimulatorTargetRuntime.shared.changes,
              initialData: HarnessSimulatorTargetRuntime.shared.latest,
              builder: (BuildContext context, snapshot) {
                final simulator =
                    snapshot.data ??
                    HarnessSimulatorTargetRuntime.shared.latest;
                final changing =
                    simulator.phase == HarnessSimulatorTargetPhase.starting;
                final status =
                    simulator.phase == HarnessSimulatorTargetPhase.error
                    ? simulator.message
                    : simulator.phase == HarnessSimulatorTargetPhase.connected
                    ? '使用中'
                    : simulator.ready
                    ? '已开启'
                    : changing
                    ? '正在开启…'
                    : '未开启';
                final endpoint = simulator.sshEndpoint.isEmpty
                    ? 'SSH 端口 22'
                    : simulator.sshEndpoint;
                return _advancedHoverHint(
                  context,
                  message: simulator.ready
                      ? '系统 SSH：$endpoint'
                            '${simulator.sshUsername.isEmpty ? '' : '\n用户：${simulator.sshUsername}'}'
                            '\n通过本机 ID 建立 P2P 或中继仿真通道。'
                      : '开启后 macOS 会请求管理员授权，并启动系统 SSH 服务。',
                  child: SwitchListTile(
                    key: const Key('advanced-simulator-access-enabled'),
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.developer_mode_rounded),
                    value:
                        simulator.enabled &&
                        simulator.phase != HarnessSimulatorTargetPhase.error,
                    onChanged: host.available && !changing
                        ? (bool value) => unawaited(
                            value
                                ? HarnessSimulatorTargetRuntime.shared.enable()
                                : HarnessSimulatorTargetRuntime.shared
                                      .disable(),
                          )
                        : null,
                    title: const Text('局域网仿真'),
                    subtitle: Text(status),
                  ),
                );
              },
            ),
            const _ClusterTaskSettingsSection(),
            _advancedHoverHint(
              context,
              message: '允许已配对设备查看本机 Harness 状态并发送指令；连接设置仅在展开后显示。',
              child: ExpansionTile(
                key: const Key('harness-coordination-local-access'),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: const Text('协同访问本机'),
                subtitle: Text('本机 ID ${host.id.isEmpty ? '正在注册…' : host.id}'),
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _remoteEnabled,
                    onChanged: host.available && !_connecting
                        ? (bool value) =>
                              value ? _launchHost(host) : _stopHost()
                        : null,
                    title: Text(_remoteEnabled ? '允许接入已打开' : '允许接入已关闭'),
                  ),
                  if (_remoteEnabled)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: const Key(
                              'advanced-local-assistance-password',
                            ),
                            controller: _localPassword,
                            obscureText: _obscureLocalPassword,
                            enabled: !_passwordSaving,
                            decoration: InputDecoration(
                              labelText: '本机协同密码',
                              helperText: '默认 12345678；只用于新的首次配对',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: _obscureLocalPassword
                                    ? '显示密码'
                                    : '隐藏密码',
                                onPressed: () => setState(
                                  () => _obscureLocalPassword =
                                      !_obscureLocalPassword,
                                ),
                                icon: Icon(
                                  _obscureLocalPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          key: const Key('advanced-save-local-password'),
                          onPressed: _passwordSaving
                              ? null
                              : _saveLocalPassword,
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );

  Widget _buildPendingPairings(
    RustDeskHostInfo host,
  ) => StreamBuilder<List<HarnessRemotePendingPairing>>(
    stream: HarnessRemotePairingHost.instance.changes,
    initialData: HarnessRemotePairingHost.instance.pending,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 10),
          Text('首次证书配对', style: Theme.of(context).textTheme.titleSmall),
          for (final pending in rows)
            ListTile(
              key: Key('harness-pairing-${pending.request.nonce}'),
              contentPadding: EdgeInsets.zero,
              title: Text('调用方 ${pending.request.routingId}'),
              subtitle: Text(
                '工作区：${pending.request.requestedWorkspaceIds.contains(HarnessRemotePairingRequest.currentWorkspaceCatalogScope) ? '本机当前项目列表' : pending.request.requestedWorkspaceIds.join(', ')}\n'
                '证书：${pending.request.certificateSha256.substring(0, 16)}…',
              ),
              trailing: Wrap(
                spacing: 6,
                children: <Widget>[
                  TextButton(
                    onPressed: () => unawaited(
                      HarnessRemotePairingHost.instance.reject(
                        pending.request.nonce,
                      ),
                    ),
                    child: const Text('拒绝'),
                  ),
                  FilledButton(
                    onPressed: () => _approvePairing(host, pending),
                    child: const Text('确认并记住'),
                  ),
                ],
              ),
            ),
          const Divider(),
        ],
      );
    },
  );

  Widget _buildNativeConnections(
    RustDeskHostInfo host,
  ) => FutureBuilder<List<RustDeskHarnessIncomingConnection>>(
    future: _incoming,
    builder: (BuildContext context, snapshot) {
      final connections =
          snapshot.data ?? const <RustDeskHarnessIncomingConnection>[];
      final pending = connections
          .where(
            (connection) => !connection.authorized && !connection.disconnected,
          )
          .toList();
      final active = connections
          .where(
            (connection) => connection.authorized && !connection.disconnected,
          )
          .toList();
      if (pending.isEmpty && active.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (pending.isNotEmpty)
            Text('等待网络连接授权', style: Theme.of(context).textTheme.titleSmall),
          for (final connection in pending)
            ListTile(
              key: Key('harness-remote-approval-${connection.connectionId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                connection.peerName.isEmpty
                    ? '调用方 ${connection.peerId}'
                    : connection.peerName,
              ),
              subtitle: Text('ID：${connection.peerId} · 只开放 Harness 消息通道'),
              trailing: Wrap(
                spacing: 6,
                children: <Widget>[
                  TextButton(
                    onPressed: () => _decide(host, connection, false),
                    child: const Text('拒绝'),
                  ),
                  FilledButton(
                    onPressed: () => _decide(host, connection, true),
                    child: const Text('允许本次连接'),
                  ),
                ],
              ),
            ),
          if (active.isNotEmpty)
            Text('正在使用 Harness', style: Theme.of(context).textTheme.titleSmall),
          for (final connection in active)
            ListTile(
              key: Key('harness-remote-active-${connection.connectionId}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_rounded),
              title: Text(
                connection.peerName.isEmpty
                    ? connection.peerId
                    : connection.peerName,
              ),
              subtitle: Text(
                '调用方 ID：${connection.peerId} · '
                '连接 ${connection.connectionId}',
              ),
              trailing: OutlinedButton.icon(
                onPressed: () => _decide(host, connection, false),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('强制断开'),
              ),
            ),
          const Divider(),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return FutureBuilder<RustDeskHostInfo>(
        future: _host,
        builder:
            (BuildContext context, AsyncSnapshot<RustDeskHostInfo> snapshot) {
              final RustDeskHostInfo host =
                  snapshot.data ??
                  const RustDeskHostInfo(
                    executable: '',
                    id: '',
                    available: false,
                    state: 'loading',
                    message: '正在读取本机统一 ID 和网络引擎状态…',
                  );
              return SingleChildScrollView(
                key: const Key('harness-coordination-main-workspace'),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                child: _buildEmbeddedMode(host),
              );
            },
      );
    }
    final dialog = AlertDialog(
      // Android secondary displays can expose both 1920x1280 panels as one
      // continuous Flutter canvas. A centered dialog then straddles the physical
      // seam and its controls cannot be tapped. Keep this operational dialog on
      // the active top panel; desktop platforms retain Material's centered UI.
      alignment: Platform.isAndroid ? Alignment.topCenter : null,
      insetPadding: Platform.isAndroid
          ? const EdgeInsets.fromLTRB(24, 18, 24, 18)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      title: const Text('Harness 远程协助'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          // AlertDialog only constrains width. On Android secondary displays a
          // long pairing/connection list could otherwise grow below the safe
          // touch area: the button was visible in a raw framebuffer capture but
          // sat below the app's interactive viewport. Keep one bounded scroll
          // surface so every approval, revoke, and disconnect action remains
          // reachable on macOS, Windows, and compact/rotated Android displays.
          constraints: BoxConstraints(
            // KEMI dual-screen devices expose one 1920x2560 continuous Flutter
            // canvas even though the user can only touch one 1920x1280 panel at
            // a time. A percentage-only constraint therefore places the lower
            // actions on the other physical panel. Cap the logical height so the
            // complete dialog remains scrollable inside either single display.
            maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.72, 430),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!widget.embedded)
                  FutureBuilder<RustDeskHostInfo>(
                    future: _host,
                    builder: (context, snapshot) => snapshot.hasData
                        ? _buildNativeConnections(snapshot.data!)
                        : const SizedBox.shrink(),
                  ),
                if (!widget.embedded)
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
                              status.busy
                                  ? Icons.sync_rounded
                                  : Icons.task_alt_rounded,
                            ),
                            title: Text(status.message),
                            subtitle: Text(
                              status.target.isEmpty
                                  ? '只分享阶段、工具名和脱敏目标'
                                  : status.target,
                            ),
                          );
                        },
                  ),
                if (!widget.embedded) const Divider(),
                if (!widget.embedded)
                  StreamBuilder<RustDeskHarnessLinkSnapshot>(
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
                if (!widget.embedded) const Divider(),
                FutureBuilder<RustDeskHostInfo>(
                  future: _host,
                  builder: (BuildContext context, AsyncSnapshot<RustDeskHostInfo> snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final RustDeskHostInfo host = snapshot.data!;
                    if (widget.embedded) return _buildEmbeddedMode(host);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SelectableText(host.message),
                        const SizedBox(height: 8),
                        Text(
                          '本机 Harness ID',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        if (host.id.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          SelectableText(
                            host.id,
                            key: const Key('harness-relay-routing-id'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ] else ...<Widget>[
                          const SizedBox(height: 8),
                          const Text('正在获取或注册本机 ID…'),
                        ],
                        if (widget.embedded) ...<Widget>[
                          const SizedBox(height: 12),
                          _buildEmbeddedConnector(host),
                        ],
                        // First-use consent is time-sensitive. Keep it above
                        // connection history and peer lists so compact displays
                        // never hide the only action that can finish pairing.
                        _buildPendingPairings(host),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          key: const Key('harness-remote-enabled'),
                          contentPadding: EdgeInsets.zero,
                          value: _remoteEnabled,
                          onChanged: host.available && !_connecting
                              ? (bool value) =>
                                    value ? _launchHost(host) : _stopHost()
                              : null,
                          title: Text(_remoteEnabled ? '远程协助已打开' : '远程协助已关闭'),
                          subtitle: Text(
                            _remoteEnabled
                                ? '可接受连接，也可输入对方 ID 发起协助'
                                : '仅显示本机 ID；不开放项目、会话或命令通道',
                          ),
                        ),
                        if (!Platform.isAndroid)
                          StreamBuilder<HarnessSimulatorTargetSnapshot>(
                            stream:
                                HarnessSimulatorTargetRuntime.shared.changes,
                            initialData:
                                HarnessSimulatorTargetRuntime.shared.latest,
                            builder: (BuildContext context, snapshot) {
                              final simulator =
                                  snapshot.data ??
                                  HarnessSimulatorTargetRuntime.shared.latest;
                              final changing =
                                  simulator.phase ==
                                  HarnessSimulatorTargetPhase.starting;
                              return SwitchListTile(
                                key: const Key(
                                  'harness-simulator-access-enabled',
                                ),
                                contentPadding: EdgeInsets.zero,
                                value:
                                    simulator.enabled &&
                                    simulator.phase !=
                                        HarnessSimulatorTargetPhase.error,
                                onChanged: host.available && !changing
                                    ? (bool value) => unawaited(
                                        value
                                            ? HarnessSimulatorTargetRuntime
                                                  .shared
                                                  .enable()
                                            : HarnessSimulatorTargetRuntime
                                                  .shared
                                                  .disable(),
                                      )
                                    : null,
                                title: Text(
                                  simulator.ready
                                      ? '允许作为仿真机 · 已打开'
                                      : changing
                                      ? '正在准备仿真机…'
                                      : '允许作为仿真机',
                                ),
                                subtitle: Text(
                                  simulator.ready
                                      ? '其他开发者或智能体只需本机同一 ID；终端、文件、日志和 MCP 通过加密隧道访问'
                                      : simulator.phase ==
                                            HarnessSimulatorTargetPhase.error
                                      ? simulator.message
                                      : '默认关闭；开启后由系统请求必要授权',
                                ),
                                secondary: const Icon(
                                  Icons.developer_mode_rounded,
                                ),
                              );
                            },
                          ),
                        if (_remoteEnabled) ...<Widget>[
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  key: const Key(
                                    'harness-remote-local-password',
                                  ),
                                  controller: _localPassword,
                                  obscureText: _obscureLocalPassword,
                                  enabled: !_passwordSaving,
                                  decoration: InputDecoration(
                                    labelText: '本机协助密码',
                                    helperText: '默认 12345678，可修改；只校验新的首次配对',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      tooltip: _obscureLocalPassword
                                          ? '显示密码'
                                          : '隐藏密码',
                                      onPressed: () => setState(
                                        () => _obscureLocalPassword =
                                            !_obscureLocalPassword,
                                      ),
                                      icon: Icon(
                                        _obscureLocalPassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                key: const Key('harness-remote-save-password'),
                                onPressed: _passwordSaving
                                    ? null
                                    : _saveLocalPassword,
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: host.callable && host.id.isNotEmpty
                                  ? () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: host.id),
                                      );
                                      if (mounted) {
                                        setState(
                                          () => _message = '已复制 Harness 本机 ID',
                                        );
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('复制本机 ID'),
                            ),
                            IconButton(
                              tooltip: '刷新 Harness 网络注册状态',
                              onPressed: () => setState(() {
                                _host = _inspectHost();
                              }),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        if (Platform.isMacOS) ...<Widget>[
                          const SizedBox(height: 12),
                          FutureBuilder<List<HarnessRemotePeer>>(
                            future: _rememberedPeers,
                            builder: (context, snapshot) {
                              final peers = snapshot.data ?? const [];
                              if (peers.isEmpty) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const SizedBox(height: 10),
                                  Text(
                                    '之前连接过的记录',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  for (final peer in peers)
                                    ListTile(
                                      key: Key(
                                        'harness-peer-${peer.routingId}',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      onTap: () {
                                        _remoteId.text = peer.routingId;
                                        setState(
                                          () => _message =
                                              '已选择 ${peer.routingId}，可直接重新连接',
                                        );
                                      },
                                      leading: const Icon(
                                        Icons.devices_rounded,
                                      ),
                                      title: Text(peer.routingId),
                                      subtitle: Text(
                                        '${peer.lastTransport == 'relay' ? '中继' : '直连'} · '
                                        '${peer.workspaceIds.length} 个工作区 · '
                                        '${peer.lastConnectedAt.toLocal()}',
                                      ),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: <Widget>[
                                          FilledButton.tonalIcon(
                                            key: Key(
                                              'harness-peer-connect-${peer.routingId}',
                                            ),
                                            onPressed:
                                                _remoteEnabled &&
                                                    host.available &&
                                                    !_connecting
                                                ? () => _connectRemembered(
                                                    host,
                                                    peer,
                                                  )
                                                : null,
                                            icon: const Icon(
                                              Icons.link_rounded,
                                              size: 18,
                                            ),
                                            label: const Text('连接'),
                                          ),
                                          IconButton(
                                            tooltip: '从本机历史移除',
                                            onPressed: () =>
                                                _forgetPeer(peer.routingId),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '协助另一台 Harness',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  key: const Key('harness-remote-peer-id'),
                                  controller: _remoteId,
                                  enabled:
                                      _remoteEnabled &&
                                      host.available &&
                                      !_connecting,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '对方 Harness ID',
                                    hintText: '输入 6～16 位数字 ID',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                key: const Key('harness-remote-connect'),
                                onPressed:
                                    _remoteEnabled &&
                                        host.available &&
                                        !_connecting
                                    ? () => _connectRemote(host)
                                    : null,
                                icon: _connecting
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.link_rounded),
                                label: const Text('连接'),
                              ),
                              if (_remoteSession != null) ...<Widget>[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  key: const Key('harness-remote-disconnect'),
                                  onPressed: _disconnectRemote,
                                  icon: const Icon(Icons.link_off_rounded),
                                  label: const Text('断开'),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('harness-remote-peer-password'),
                            controller: _remotePassword,
                            obscureText: _obscureRemotePassword,
                            enabled: _remoteEnabled && !_connecting,
                            decoration: InputDecoration(
                              labelText: '对方协助密码',
                              helperText: '首次连接默认使用 12345678；已配对记录无需再次输入',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: _obscureRemotePassword
                                    ? '显示密码'
                                    : '隐藏密码',
                                onPressed: _remoteEnabled
                                    ? () => setState(
                                        () => _obscureRemotePassword =
                                            !_obscureRemotePassword,
                                      )
                                    : null,
                                icon: Icon(
                                  _obscureRemotePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('harness-remote-workspace-id'),
                            controller: _remoteWorkspaceId,
                            enabled: _remoteEnabled && !_connecting,
                            decoration: const InputDecoration(
                              labelText: '首次配对的远端工作区 ID',
                              helperText: '仅首次连接需要；执行端将再次显示并确认这个最小授权范围',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _forceRelay,
                            onChanged: !_remoteEnabled || _connecting
                                ? null
                                : (bool? value) => setState(
                                    () => _forceRelay = value ?? false,
                                  ),
                            title: const Text('强制经 HBBS/HBBR 中继验收'),
                            subtitle: const Text(
                              '默认先尝试点对点，失败自动走中继；此选项用于验证纯中继路径。',
                            ),
                          ),
                          if (_remoteSession != null) ...<Widget>[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 280,
                              child: HarnessRemoteReadOnlyPanel(
                                peerRoutingId: _remoteSession!.peer.routingId,
                                model: _remoteSession!.model,
                                onReconnect: () =>
                                    unawaited(_connectRemote(host)),
                                onDisconnect: () =>
                                    unawaited(_disconnectRemote()),
                              ),
                            ),
                            const SizedBox(height: 12),
                            HarnessRemoteCommandPanel(
                              model: _remoteSession!.model,
                              client: _remoteSession!.client,
                              allowedOperations:
                                  _remoteSession!.peer.operations,
                            ),
                          ],
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  '本机 ID 来自独立 Harness 网络身份，必须经过 hbbs 注册确认。连接优先直连，'
                  '失败时由 hbbr 原样中继端到端加密的 Harness 协议。'
                  '该通道只传输项目、会话、状态、命令、反馈和停止事件；'
                  '不传输桌面画面或远程控制输入，也不依赖其他 App 或插件。',
                  style: TextStyle(fontSize: 12),
                ),
                if (_message.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(_message),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: widget.embedded
          ? const <Widget>[]
          : <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
    );
    return dialog;
  }
}

Widget _advancedHoverHint(
  BuildContext context, {
  required String message,
  required Widget child,
}) => Tooltip(
  message: message,
  waitDuration: const Duration(milliseconds: 350),
  showDuration: const Duration(seconds: 8),
  exitDuration: Duration.zero,
  preferBelow: false,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.inverseSurface,
    borderRadius: BorderRadius.circular(12),
    boxShadow: const <BoxShadow>[
      BoxShadow(blurRadius: 12, color: Color(0x33000000)),
    ],
  ),
  textStyle: TextStyle(
    color: Theme.of(context).colorScheme.onInverseSurface,
    fontSize: 13,
  ),
  child: child,
);

class _ClusterTaskSettingsSection extends StatefulWidget {
  const _ClusterTaskSettingsSection();

  @override
  State<_ClusterTaskSettingsSection> createState() =>
      _ClusterTaskSettingsSectionState();
}

class _ClusterTaskSettingsSectionState
    extends State<_ClusterTaskSettingsSection> {
  final ClusterTaskSettings _settings = ClusterTaskSettings();
  final TextEditingController _serverUrl = TextEditingController();
  final TextEditingController _trustedHosts = TextEditingController();
  final TextEditingController _signingKey = TextEditingController();
  ClusterTaskConfiguration _configuration = ClusterTaskSettings.latest;
  bool _loading = true;
  bool _saving = false;
  bool _expanded = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    _trustedHosts.dispose();
    _signingKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      if (!mounted) return;
      setState(() {
        _configuration = ClusterTaskSettings.latest;
        _loading = false;
      });
      return;
    }
    final configuration = await _settings.load();
    if (!mounted) return;
    setState(() {
      _configuration = configuration;
      _serverUrl.text = configuration.serverUrl;
      _trustedHosts.text = configuration.trustedHosts.join(', ');
      _signingKey.text = configuration.signingPublicKey;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      final configuration = await _settings.saveConfiguration(
        serverUrl: _serverUrl.text,
        trustedHosts: _trustedHosts.text.split(','),
        signingPublicKey: _signingKey.text,
      );
      if (!mounted) return;
      setState(() {
        _configuration = configuration;
        _message = configuration.configured
            ? '配置已保存；等待任务服务协议和签名公钥完成联调后才允许接收任务'
            : '配置已保存；请补全 HTTPS 服务、可信域和签名公钥';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      final configuration = await _settings.saveEnabled(value);
      if (!mounted) return;
      setState(() => _configuration = configuration);
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _advancedHoverHint(
    context,
    message: _configuration.configured
        ? '从已配置的可信服务接收签名任务。点击设置按钮可修改服务器。'
        : '开关默认开启；服务器未配置时仅等待配置，不联网、不领取任务。',
    child: ExpansionTile(
      key: const Key('advanced-cluster-task-center'),
      tilePadding: EdgeInsets.zero,
      onExpansionChanged: (value) => setState(() => _expanded = value),
      leading: const Icon(Icons.account_tree_outlined),
      title: const Text('集群任务'),
      subtitle: Text(
        _loading
            ? '正在读取…'
            : !_configuration.enabled
            ? '已关闭'
            : _configuration.configured
            ? '已开启'
            : '等待配置服务器',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_expanded ? Icons.expand_less : Icons.settings_outlined),
          const SizedBox(width: 8),
          Switch(
            key: const Key('advanced-cluster-task-enabled'),
            value: _configuration.enabled,
            onChanged: _loading || _saving ? null : _setEnabled,
          ),
        ],
      ),
      children: <Widget>[
        TextField(
          key: const Key('advanced-cluster-server-url'),
          controller: _serverUrl,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: '任务服务 HTTPS 地址',
            hintText: 'https://example.com/api/v1/agents',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('advanced-cluster-trusted-hosts'),
          controller: _trustedHosts,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: '可信任务描述域名',
            helperText: '多个域名用英文逗号分隔；任务 URL 只能来自这些域名',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('advanced-cluster-signing-key'),
          controller: _signingKey,
          enabled: !_saving,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '任务签名公钥',
            helperText: '仅保存公钥；任务签名验证失败时绝不进入 Harness',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const Key('advanced-cluster-save'),
            onPressed: _loading || _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存配置'),
          ),
        ),
        if (_message.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Text(_message)),
        ],
      ],
    ),
  );
}

enum _ToolApprovalDecision { deny, allowOnce, allowSession }
