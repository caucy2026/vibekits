import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/dev_tools/domain/harness_tool_activity_store.dart';
import '../features/dev_tools/domain/harness_tool_bridge.dart';
import '../features/dev_tools/domain/harness_agent_preferences.dart';
import '../features/dev_tools/domain/harness_status_ipc_publisher.dart';
import '../features/dev_tools/domain/harness_simulator_target_runtime.dart';
import '../features/dev_tools/domain/harness_tool_server.dart';
import '../features/dev_tools/domain/harness_work_status.dart';
import '../features/dev_tools/domain/lan_peer_discovery_service.dart';
import '../features/dev_tools/domain/lmcp_exposure_server.dart';
import '../features/dev_tools/domain/mcp_capability_directory.dart';
import '../features/dev_tools/domain/mcp_device_identity.dart';
import '../features/dev_tools/presentation/lmcp_inbound_call_overlay.dart';
import '../features/about/domain/marketing_cache_service.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'app_version.dart';
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
  HarnessStatusIpcPublisher? _harnessStatusPublisher;
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
    if (!_isFlutterTest) {
      if (!Platform.isAndroid && !Platform.isIOS) {
        unawaited(_startMcpFabricAndExternalToolServer());
        unawaited(_startHarnessStatusPublisher());
      }
      // Simulator hosting is available on desktop and Android. The mobile
      // relay is a separate bounded service; it does not start the desktop
      // MCP server or WebView.
      unawaited(HarnessSimulatorTargetRuntime.shared.restore());
    }
    if (!_isFlutterTest) MarketingCacheService.instance.start();
  }

  Future<void> _startHarnessStatusPublisher() async {
    final HarnessStatusIpcPublisher publisher = HarnessStatusIpcPublisher(
      snapshotProvider: () => HarnessWorkStatusHub.registryLatest.toJson(),
      snapshotStream: () => HarnessWorkStatusHub.registryChanges.map(
        (HarnessWorkRegistrySnapshot snapshot) => snapshot.toJson(),
      ),
      publisherVersion: AppVersion.semantic,
    );
    _harnessStatusPublisher = publisher;
    final HarnessStatusIpcStartResult result = await publisher.start();
    if (!mounted) {
      await publisher.stop();
      return;
    }
    if (!result.available) {
      debugPrint('Harness status IPC unavailable: ${result.reason}');
    }
  }

  /// Starts discovery and the three-tier capability directory for the entire
  /// desktop process, not only while a Harness workspace happens to be open.
  /// This keeps LAN presence, catalog revisions and tool routing live while
  /// the user navigates to Cleaner, Documents or another top-level page.
  Future<void> _startMcpFabricAndExternalToolServer() async {
    VibekitsHarnessToolBridge? bridge;
    try {
      await _settingsLoad;
      final McpDeviceIdentity identity = McpDeviceIdentity.forVibekits();
      final McpCapabilityDirectory directory = McpCapabilityDirectory.instance;
      bridge = VibekitsHarnessToolBridge(
        activityRecorder: HarnessToolActivityStore.record,
        downloadDirectory: _settings.value.toolDownloadDirectory,
        mcpCatalogLoader: directory.exportForHarness,
        mcpToolInvoker:
            (
              String instanceId,
              String toolName,
              Map<String, Object?> arguments,
            ) => directory.invokeTool(
              instanceId: instanceId,
              toolName: toolName,
              arguments: arguments,
            ),
        mcpSchedulePlanner: (String toolName, String taskId) =>
            directory.planScheduledTool(toolName: toolName, taskId: taskId),
        mcpAutoInvoker:
            (
              toolName,
              taskId,
              idempotencyKey,
              scopeDigest,
              arguments,
              requestedSlots,
              ttlSeconds,
            ) => directory.scheduleAndInvoke(
              toolName: toolName,
              taskId: taskId,
              idempotencyKey: idempotencyKey,
              scopeDigest: scopeDigest,
              arguments: arguments,
              requestedSlots: requestedSlots,
              ttlSeconds: ttlSeconds,
            ),
        mcpReputationLoader: directory.exportReputations,
        mcpReputationRater:
            (String tier, String instanceId, String toolName, int rating) =>
                directory.rateTool(
                  tierName: tier,
                  instanceId: instanceId,
                  toolName: toolName,
                  rating: rating,
                ),
      );
      final VibekitsHarnessToolBridge activeBridge = bridge;
      // Publish the process-local bridge before starting optional discovery
      // and provider scans.  A slow network interface, malformed third-party
      // registration, or unavailable LAN must never make the original local
      // Harness/MCP integration disappear or leave a stale connection file.
      final HarnessToolServer server = await HarnessToolServer.start(
        bridge: bridge,
        approve: _approveExternalTool,
        connectionFile: HarnessToolServer.defaultConnectionFile(),
      );
      if (!mounted) {
        await server.close();
        return;
      }
      _externalToolServer = server;
      bridge = null; // Ownership transferred to HarnessToolServer.

      try {
        await LanPeerDiscoveryService.instance.start(
          instanceId: identity.instanceId,
          name: identity.displayName,
          capabilityDigest: VibekitsHarnessToolBridge.protocolVersion,
          appId: identity.appId,
          appVersion: VibekitsLmcpExposureServer.currentAppVersion,
          hardwareCode: identity.hardwareCode,
          // Receiving is process-wide. Publishing remains controlled by the
          // explicit MCP consent flow in the Harness workspace.
          exposureEnabled: false,
        );
      } on Object catch (error) {
        debugPrint('LAN MCP discovery unavailable: $error');
      }
      try {
        await directory.start(appBridge: activeBridge);
      } on Object catch (error) {
        debugPrint('MCP capability directory unavailable: $error');
      }
    } on Object catch (error) {
      await bridge?.dispose();
      // MCP is an optional integration. A publishing failure must never block
      // the desktop UI or unrelated offline tools.
      debugPrint('Process-wide MCP fabric unavailable: $error');
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
    final HarnessStatusIpcPublisher? statusPublisher = _harnessStatusPublisher;
    if (statusPublisher != null) unawaited(statusPublisher.stop());
    if (!_isFlutterTest && !Platform.isAndroid && !Platform.isIOS) {
      unawaited(McpCapabilityDirectory.instance.dispose());
      unawaited(LanPeerDiscoveryService.instance.stop());
    }
    if (!_isFlutterTest) MarketingCacheService.instance.stop();
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
      builder: (BuildContext context, Widget? child) =>
          LmcpInboundCallOverlay(child: child ?? const SizedBox.shrink()),
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
