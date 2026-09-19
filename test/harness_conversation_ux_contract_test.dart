import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Harness conversation uses Codex density and wheel forwarding',
    () async {
      final String script = await File(
        'assets/harness/codex_conversation_ux.js',
      ).readAsString();

      expect(script, contains('[data-conversation-scroll]'));
      expect(script, contains('--dsh-content-font-size: 14px'));
      expect(script, contains('--dsh-content-font-size-secondary: 13px'));
      expect(
        script,
        contains("querySelectorAll('[data-conversation-scroll]')"),
      );
      expect(script, contains('导出会话日志'));
      expect(script, contains("window.addEventListener('wheel'"));
      expect(script, contains('passive: false'));
      expect(script, contains('line-height: 22px !important'));
      expect(script, contains('line-height: 20px !important'));
      expect(script, contains('[data-chat-flow]'));
      expect(script, contains('event.preventDefault()'));
      expect(script, contains('vibekits-scroll-to-latest'));
      expect(script, contains('滚动到最新消息'));
      expect(script, contains("scrollButton.textContent = '↓'"));
      expect(script, contains("distance > 72 ? 'true' : 'false'"));
      expect(
        script,
        contains(
          "host.scrollTo({ top: host.scrollHeight, behavior: 'smooth' })",
        ),
      );
      expect(script, contains("document.addEventListener('scroll'"));
    },
  );

  test('F1 through F12 switch visible sessions and focus the composer', () {
    final String script = File(
      'assets/harness/codex_conversation_ux.js',
    ).readAsStringSync();

    expect(script, contains("window.addEventListener('keydown'"));
    expect(script, contains('event.isComposing'));
    expect(script, contains(r'event.key.match(/^F([1-9]|1[0-2])$/)'));
    expect(script, contains('[role="treeitem"]:not([aria-expanded])'));
    expect(script, contains('row.offsetParent !== null'));
    expect(script, contains('row.getClientRects().length > 0'));
    expect(script, contains('visibleSessions[index]'));
    expect(script, contains('target.click()'));
    expect(script, contains('[data-composer-card]'));
    expect(script, contains("type: 'vibekits.sessionShortcutMissing'"));

    final String workspace = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();
    expect(workspace, contains('LogicalKeyboardKey.f1'));
    expect(workspace, contains('LogicalKeyboardKey.f12'));
    expect(workspace, contains('_focusHarnessSessionAt'));
    expect(workspace, contains('__vibekitsFocusSessionAt'));
    expect(workspace, contains('HardwareKeyboard.instance.addHandler'));
    expect(workspace, contains('HardwareKeyboard.instance.removeHandler'));
    expect(workspace, contains('_handleHarnessFunctionKey'));
  });

  test('Official Harness behavior bundles remain byte-for-byte unpatched', () {
    final String macos = File(
      'tool/prepare_harness_runtime_macos.sh',
    ).readAsStringSync();
    final String windows = File(
      'tool/prepare_harness_runtime.ps1',
    ).readAsStringSync();
    final String workspace = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();

    expect(macos, isNot(contains('patch_harness_runtime.mjs')));
    expect(windows, isNot(contains('patch_harness_runtime.mjs')));
    expect(workspace, isNot(contains('harness_message_queue_bridge.js')));
    expect(workspace, isNot(contains('_messageQueueBridgeScript')));
  });

  test(
    'macOS runtime keeps the official native builtin loader on both architectures',
    () {
      final String prepare = File(
        'tool/prepare_harness_runtime_macos.sh',
      ).readAsStringSync();

      expect(prepare, contains('node-addon-require-builtin-darwin-arm64'));
      expect(prepare, contains('node-addon-require-builtin-darwin-x64'));
      expect(
        prepare,
        isNot(
          contains(
            r'"$TARGET/node_modules/node-addon-require-builtin-darwin-arm64"',
          ),
        ),
      );
      expect(prepare, contains("'@modelcontextprotocol/sdk@1.30.0'"));
      final String windowsPrepare = File(
        'tool/prepare_harness_runtime.ps1',
      ).readAsStringSync();
      expect(windowsPrepare, contains("'@modelcontextprotocol/sdk@1.30.0'"));
    },
  );
}
