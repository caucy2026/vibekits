import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows and macOS use the official Harness interaction entry', () {
    final String source = File(
      'lib/features/local_models/presentation/local_models_tab.dart',
    ).readAsStringSync();

    expect(source, contains('OfficialHarnessWorkspace('));
    expect(source, contains("Platform.environment['FLUTTER_TEST']"));
    // The custom Flutter workspace remains a deterministic test/mobile
    // fallback, not a second Windows/macOS product experience.
    expect(source, contains('DeepSeekAgentWorkspace('));
    expect(source, contains('!Platform.isAndroid'));
    expect(source, contains('!Platform.isIOS'));
  });

  test('official Harness entry receives VibeKits services as adapters', () {
    final String source = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();

    expect(source, contains('HarnessRemoteWorkspaceLauncher?'));
    expect(source, contains('HarnessScreenshotOcrRunner?'));
    expect(source, contains('String initialDownloadDirectory'));
    expect(source, contains('VibekitsHarnessToolBridge('));
  });

  test('official and fallback Harness action rails stay scrollable', () {
    final String official = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();
    final String fallback = File(
      'lib/features/local_models/presentation/deepseek_agent_workspace.dart',
    ).readAsStringSync();

    expect(official, contains("Key('harness-quick-actions-rail-scroll')"));
    expect(official, contains('child: ListView('));
    expect(fallback, contains('Widget _buildCrossPlatformToolRail()'));
    expect(fallback, contains('child: ListView('));
  });

  test('remote management never replaces either Harness workspace', () {
    final String official = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();
    final String fallback = File(
      'lib/features/local_models/presentation/deepseek_agent_workspace.dart',
    ).readAsStringSync();

    expect(official, contains('HarnessRemoteManagementBridge.bind'));
    expect(fallback, contains('HarnessRemoteManagementBridge.bind'));
    expect(official, contains("'远程状态'"));
    expect(fallback, contains("'远程状态'"));
    expect(official, contains("'远程仿真中'"));
    expect(fallback, contains("'远程仿真中'"));
    expect(
      official,
      contains('if (!simulator.enabled) return const SizedBox.shrink();'),
    );
    expect(
      fallback,
      contains('if (!simulator.enabled) return const SizedBox.shrink();'),
    );
    expect(fallback, isNot(contains('agent-coordination-workspace')));
    expect(fallback, isNot(contains('agent-remote-assistance-button')));
    expect(fallback, isNot(contains('agent-coordination-switch')));
  });

  test('official plugin settings and inventory remain composed', () {
    final List<File> candidates = <File>[
      File(
        'native/harness/windows/runtime/node_modules/'
        '@deepseek-ai/dsh-web-app/cordis.patch.yml',
      ),
      File(
        'native/harness/macos/runtime/node_modules/'
        '@deepseek-ai/dsh-web-app/cordis.patch.yml',
      ),
    ];
    final File runtimeComposition = candidates.firstWhere(
      (File candidate) => candidate.existsSync(),
      orElse: () => throw StateError('prepared Harness runtime is missing'),
    );
    final String composition = runtimeComposition.readAsStringSync();

    expect(composition, contains('@deepseek-ai/dsh-host-plugin-inventory'));
    expect(
      composition,
      contains('@deepseek-ai/dsh-client-ui-settings-plugin-inventory'),
    );
    expect(
      composition,
      contains('@deepseek-ai/dsh-client-ui-settings-plugins'),
    );
  });

  test('official Web workspace uses one macOS and Windows bridge', () {
    final String source = File(
      'lib/features/local_models/presentation/harness_webview_bridge.dart',
    ).readAsStringSync();
    final String workspace = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();
    final String injectedUx = File(
      'assets/harness/codex_conversation_ux.js',
    ).readAsStringSync();

    expect(source, contains('Platform.isMacOS'));
    expect(source, contains('Platform.isWindows'));
    expect(source, contains("addJavaScriptChannel(\n        'VibekitsHost'"));
    expect(source, contains('win.WebviewController'));
    expect(source, isNot(contains('EagerGestureRecognizer')));
    expect(source, contains('return mac.WebViewWidget(controller: macos)'));
    expect(source, isNot(contains('clearRecoverableUiState')));
    expect(workspace, isNot(contains('_waitForHarnessContent')));
    expect(workspace, isNot(contains('HarnessPageNotRenderedException')));
    expect(workspace, contains('unawaited(_activateIndependentServices'));
    expect(source, contains('pruneOversizedHarnessAuthentication'));
    expect(source, contains("cookie.name.startsWith('dsh-auth-')"));
    expect(workspace, contains('pruneOversizedHarnessAuthentication()'));
    expect(workspace, isNot(contains('_scrollHarnessConversation')));
    expect(
      workspace,
      isNot(contains('Widget _buildHarnessWebview() => Listener(')),
    );
    expect(
      workspace,
      contains('_webview.build(permissionRequested: _handleWebPermission)'),
    );
    expect(injectedUx, contains('window.chrome.webview'));
    expect(injectedUx, contains('window.VibekitsHost'));
    expect(injectedUx, contains("value === 'AUTH'"));
    expect(injectedUx, contains('vibekits.inferenceError'));
    expect(
      workspace,
      contains("payload?['type'] == 'vibekits.inferenceError'"),
    );
    expect(workspace, contains('API 密钥无效，请检查 DeepSeek API Key 后重试。'));
    expect(injectedUx, contains('vibekits-selected-session-actions'));
    expect(injectedUx, contains('[role="treeitem"][aria-selected="true"]'));
  });

  test('macOS pointer recovery pauses behind Flutter overlays', () {
    final String appDelegate = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final String workspace = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();

    expect(appDelegate, contains('vibekits/harness_input'));
    expect(appDelegate, contains('self.webViewInputEnabled'));
    expect(appDelegate, contains('webViewResponder'));
    expect(workspace, contains('_withFlutterOverlay'));
    expect(workspace, contains('HarnessWebViewInputGate.runWithOverlay'));
    final String shell = File('lib/app/main_shell.dart').readAsStringSync();
    expect(shell, contains('HarnessWebViewInputGate.runWithOverlay<void>'));
    expect(workspace, contains('_blockNativeWebViewInput'));
    expect(workspace, contains('_unblockNativeWebViewInput'));
    final String gate = File(
      'lib/features/local_models/presentation/harness_webview_input_gate.dart',
    ).readAsStringSync();
    expect(gate, contains('setWebViewInputEnabled'));
    expect(gate, contains('static int _depth = 0'));
  });

  test('bundled Harness workers are tied to the desktop App lifetime', () {
    final String service = File(
      'lib/features/dev_tools/domain/deepseek_harness_service.dart',
    ).readAsStringSync();
    final String watchdog = File(
      'native/harness/vibekits-parent-watchdog.mjs',
    ).readAsStringSync();

    expect(service, contains('VIBEKITS_PARENT_PID'));
    expect(service, contains('vibekits-parent-watchdog.mjs'));
    expect(watchdog, contains('process.kill(parentPid, 0)'));
    expect(watchdog, contains("error?.code !== 'ESRCH'"));
  });

  test('session delete and cross-project move bridge both desktop WebViews', () {
    final String patch = File(
      'tool/patch_harness_runtime.mjs',
    ).readAsStringSync();
    final String workspace = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();
    final String service = File(
      'lib/features/dev_tools/domain/deepseek_harness_service.dart',
    ).readAsStringSync();
    final String rebind = File(
      'native/harness/vibekits-session-rebind.mjs',
    ).readAsStringSync();

    expect(patch, contains('window.chrome.webview.postMessage(message)'));
    expect(patch, contains('window.VibekitsHost?.postMessage(message)'));
    expect(patch, contains('vibekits.moveSession'));
    expect(workspace, contains('_confirmDeleteSession'));
    expect(workspace, contains('_confirmMoveSession'));
    expect(workspace, contains('移动会话并切换工作区权限？'));
    expect(service, contains('rebindSessionWorkspace'));
    expect(rebind, contains('projection.identity.cwd = target.path'));
    expect(rebind, contains('await rename(backupDir, sourceDir)'));
  });
}
