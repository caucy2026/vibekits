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

  test('official plugin settings and inventory remain composed', () {
    final String composition = File(
      'native/harness/macos/runtime/node_modules/'
      '@deepseek-ai/dsh-web-app/cordis.patch.yml',
    ).readAsStringSync();

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
    expect(workspace, contains('setWebViewInputEnabled'));
    expect(workspace, contains('_blockNativeWebViewInput'));
    expect(workspace, contains('_unblockNativeWebViewInput'));
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
