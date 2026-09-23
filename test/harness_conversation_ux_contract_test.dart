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
    expect(script, contains("'a[href], [role=\"link\"], [data-session-id]'"));
    expect(script, isNot(contains('a[href], button')));
    expect(script, contains('activationTarget.click()'));
    expect(script, contains("target.scrollIntoView({ block: 'nearest' })"));
    expect(script, contains('window.setTimeout(focusVisibleComposer, 120)'));
    expect(script, contains('[data-composer-card]'));
    expect(script, contains("type: 'vibekits.sessionShortcutMissing'"));
    expect(script, contains("type: 'vibekits.sessionFocused'"));

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
    expect(workspace, contains("'vibekits/harness_input'"));
    expect(workspace, contains("'sessionFunctionKey'"));
    expect(workspace, contains("'setHarnessShortcutsEnabled'"));

    final String appDelegate = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    expect(appDelegate, contains('installHarnessFunctionKeyMonitor'));
    expect(appDelegate, contains('sessionFunctionKey'));
    expect(appDelegate, contains('setHarnessShortcutsEnabled'));
    expect(appDelegate, contains('applicationWillFinishLaunching'));
    expect(appDelegate, contains('applicationWillTerminate'));
    expect(appDelegate, isNot(contains('super.applicationWillTerminate')));
    expect(appDelegate, contains('withBundleIdentifier: bundleId'));
    expect(appDelegate, contains('Darwin.exit(EXIT_SUCCESS)'));
    expect(appDelegate, isNot(contains('NSApp.terminate(nil)')));
  });

  test('session context menu adds context continuation and navigation', () {
    final String script = File(
      'assets/harness/codex_conversation_ux.js',
    ).readAsStringSync();

    expect(script, contains("window.addEventListener('contextmenu'"));
    expect(script, contains('const rowsAtPointer = visibleSessionRows()'));
    expect(script, contains('contextSessionRow = actionRow'));
    expect(script, contains('button[aria-label^="会话“"]'));
    expect(script, contains('event.stopImmediatePropagation()'));
    expect(script, contains("label === '归档会话'"));
    expect(script, contains('vibekits-continue-session-menu-item'));
    expect(script, contains('vibekits-delete-session-menu-item'));
    expect(script, contains("replaceMenuItemLabel(deleteItem, '删除会话')"));
    expect(script, contains('replaceDeleteSessionIcon(deleteItem)'));
    expect(script, contains("type: 'vibekits.deleteSession'"));
    expect(script, contains("confirmed: true"));
    expect(script, contains("confirm.textContent = '确认删除'"));
    expect(script, contains("confirm.textContent = '正在删除…'"));
    expect(script, contains("document.body.appendChild(backdrop)"));
    expect(
      script,
      contains("confirm.className = 'vibekits-delete-confirm-button'"),
    );
    expect(script, contains("content.setAttribute('data-delete-message', '')"));
    expect(script, contains('window.__vibekitsSetSessionDeleteState'));
    expect(script, contains("state === 'deleted'"));
    expect(script, contains("row.style.maxHeight = '0'"));
    expect(script, contains("action?.closest('[role=\"treeitem\"]')"));
    expect(
      script,
      contains('window.setTimeout(decorateSessionContextMenu, 30)'),
    );
    expect(
      script,
      isNot(contains('const sessionId = sessionIdForRow(row) ||')),
    );
    expect(
      script,
      contains('isCurrent: sessionId === window.__vibekitsCurrentSessionId()'),
    );
    expect(
      script,
      contains(
        "menu.querySelectorAll(\n      '.vibekits-child-session-menu-item',",
      ),
    );
    expect(
      script,
      contains('for (const duplicate of existingActions.slice(1))'),
    );
    expect(
      script,
      contains('for (const duplicate of existingDeleteActions.slice(1))'),
    );
    expect(script, isNot(contains('menu.appendChild(child)')));
    expect(
      script,
      contains(
        'color-mix(in srgb, var(--dsw-alias-label-primary) 78%, #b98223 22%)',
      ),
    );
    expect(script, isNot(contains('color: #2563eb !important')));
    expect(script, isNot(contains('color: #5c7898 !important')));
    expect(script, contains('template.cloneNode(true)'));
    expect(script, contains('replaceMenuItemLabel(item, \'派生会话\')'));
    expect(script, contains('replaceNewSessionIcon(item)'));
    expect(script, contains('M21 15a4 4 0 0 1-4 4H8l-5 3V7'));
    expect(script, isNot(contains("item.textContent = '派生会话'")));
    expect(script, contains("item.title = '压缩当前会话上下文并创建派生会话继续开发'"));
    expect(script, contains('const labelledTitle = actionLabel.match('));
    expect(script, isNot(contains("item.textContent = '整理上下文并继续'")));
    expect(script, contains("type: 'vibekits.continueSession'"));
    expect(script, isNot(contains('preparedChildId,')));
    expect(script, contains('__vibekitsOpenNewestEmptySession'));
    expect(script, contains('const sourceSessionId = sessionIdForRow(row)'));
    expect(script, contains("replaceMenuItemLabel(item, '正在创建…')"));
    expect(script, isNot(contains('activationTarget?.click()')));
    expect(script, contains('window.chrome.webview.postMessage(message)'));
    expect(script, contains("document.addEventListener('click', (event) =>"));
    expect(
      script.indexOf('postHostMessage(request);'),
      lessThan(script.indexOf('window.__vibekitsSetContinuationProgress?.(')),
    );
    expect(script, contains('__vibekitsSetContinuationRelations'));
    expect(script, contains('__vibekitsOpenSession'));
    expect(script, contains('__vibekitsOpenNewestEmptySession'));
    expect(script, contains(r'/^(?:新会话|新建会话|New session)$/i'));
    expect(script, contains(r'/^(?:新建会话|New session)$/i'));
    expect(script, contains(r'/(?:新建会话|New session in)/i'));
    expect(script, contains('/^(展开其余|Show .*more)/i'));
    expect(script, contains('scroller.scrollTop = 0'));
    expect(
      script,
      contains(r'currentTitle.startsWith(`${item.sourceTitleSnapshot} `)'),
    );
    expect(script, isNot(contains('打开继续会话')));
    expect(script, isNot(contains('继续会话已删除')));
    expect(script, isNot(contains("'新会话'")));
    expect(script, contains(r'`派生自《${relation.sourceTitleSnapshot}》`'));
    expect(script, contains('.vibekits-continuation-source-card'));
    expect(script, contains('.vibekits-continuation-progress'));
    expect(script, contains('.vibekits-continuation-retry'));
    expect(
      RegExp(r'#b98223').allMatches(script).length,
      greaterThanOrEqualTo(10),
      reason: '所有 VibeKits 新增的 Harness 操作都应只混入少量暖黄色',
    );
    expect(script, isNot(contains('#6f8cff')));
    expect(script, contains('@supports not (color: color-mix'));
    expect(script, contains('stroke: currentColor !important'));
    expect(
      script,
      contains('continuationProgress.sessionIds.includes(current)'),
    );
    expect(
      script,
      contains('continuationProgress.sessionTitles.includes(currentTitle)'),
    );
    expect(script, contains('document.body.appendChild(card)'));
    expect(script, contains('position: fixed; z-index: 1200'));
    expect(script, contains(': (continuationProgress?.sessionTitles || [])'));
    expect(
      script,
      contains(
        "sessionStorage.setItem(\n        'vibekits.continuation.progress'",
      ),
    );
    expect(script, contains('来源会话已删除'));
    expect(script, contains('if (existing instanceof HTMLButtonElement)'));
    expect(
      script,
      isNot(
        contains(
          "document.getElementById('vibekits-continuation-source-card')?.remove()",
        ),
      ),
    );

    final String workspace = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();
    expect(workspace, isNot(contains('void _showHarnessNotice')));
    expect(script, contains('__vibekitsSetContinuationProgress'));
    expect(script, contains('continuationTitleSnapshot'));
    expect(script, contains('vibekitsContinuationTitle'));
    expect(script, contains('vibekits-continuation-spinner'));
    expect(workspace, contains('coordinator.createEmptyChild('));
    expect(workspace, contains('coordinator.prepareExistingChild('));
    expect(workspace, isNot(contains('_openOfficialUiBlank(')));
    expect(workspace, contains('onCreated: (String sessionId, String title)'));
    expect(
      workspace,
      contains("window.__vibekitsOpenSession?.(\${jsonEncode(sessionId)});"),
    );
    expect(
      workspace,
      contains('evaluateJavaScript calls here can deadlock WKWebView'),
    );
    expect(workspace, contains('__vibekitsOpenOnlyVisibleBlankSession'));
    final int sourceOverlayIndex = workspace.indexOf(
      "_setContinuationOverlay('正在创建派生会话…'",
    );
    final int createChildIndex = workspace.indexOf(
      'final child = await coordinator.createEmptyChild',
    );
    expect(sourceOverlayIndex, greaterThan(-1));
    expect(sourceOverlayIndex, lessThan(createChildIndex));
    expect(script, contains(r'/^(?:新会话|新建会话|New session)$/i'));
    expect(workspace, contains("<String>['新会话', 'New session', title]"));
    expect(workspace, contains('coordinator.completeChild('));
    expect(
      workspace,
      isNot(contains('harness.continuation.queue_context_deferred')),
    );
    expect(workspace, contains('harness.continuation.relation_ui_deferred'));
    expect(workspace, contains('_continuationsInProgress'));
    expect(workspace, contains('会话正在运行，请先停止当前任务再删除。'));
    expect(workspace, contains('removeContinuationSession(sessionId)'));
    expect(workspace, isNot(contains("'method': 'workspace.archiveSession'")));
    expect(workspace, contains('await store.containsSession(sessionId)'));
    expect(workspace, contains('_resolveAndConfirmDeleteSession'));
    expect(workspace, contains("payload?['confirmed'] == true"));
    expect(workspace, contains('confirmedAtSource: confirmedAtSource'));
    expect(workspace, contains('requestedTitle: normalizedTitle'));
    expect(workspace, contains('__vibekitsSelectVisibleSession'));
    expect(workspace, contains('__vibekitsOpenSessionByTitle'));
    expect(workspace, contains('String sessionTitle'));
    expect(
      workspace,
      isNot(contains('delete window.__vibekitsCurrentSessionId')),
    );
    expect(workspace, contains('_executeContinuationUi'));
    expect(workspace, contains('.timeout(const Duration(seconds: 2))'));
    expect(workspace, contains("'type': 'harness.continuation.failed'"));
    expect(workspace, isNot(contains('document.readyState === "complete"')));
    expect(workspace, isNot(contains('window.location.reload();')));
    expect(script, contains('openThroughOfficialWorkspace'));
    expect(script, contains(r"key.startsWith('__reactFiber$')"));
    expect(script, contains("typeof props.open === 'function'"));
    expect(workspace, contains('await _installCodexConversationUx();'));
    expect(workspace, contains('await _waitForRenderedHarnessSurface();'));
    expect(workspace, contains('页面完成导航后未渲染可交互界面'));
    expect(workspace, contains('__vibekitsOpenOnlyVisibleBlankSession'));
    expect(workspace, contains('onProgress: (String status) {'));
    expect(workspace, contains('window.__vibekitsSetContinuationProgress'));
    expect(workspace, contains('window.__vibekitsSetContinuationError'));
    expect(script, contains('vibekits-continuation-retry'));
    expect(script, contains("retry.textContent = '重试'"));
    expect(workspace, isNot(contains("_showHarnessNotice('整理失败")));
    expect(workspace, isNot(contains("_showHarnessNotice('派生会话服务尚未就绪")));
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
