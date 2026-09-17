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

  test(
    'Harness queue bridge keeps official composer and exposes one protocol',
    () async {
      final String script = await File(
        'assets/harness/harness_message_queue_bridge.js',
      ).readAsString();

      expect(script, contains('vibekits.harnessEvent'));
      expect(script, contains("event: 'message.accepted'"));
      expect(script, contains("'turn.completed'"));
      expect(script, contains("'turn.failed'"));
      expect(script, contains('cancellationRequested'));
      expect(script, contains("event: 'approval.waiting'"));
      expect(script, contains('__vibekitsHarnessQueueBridge'));
      expect(script, contains('补充并纠正'));
      expect(script, contains('busySession'));
      expect(script, contains('外部待执行'));
      expect(script, contains('control.hidden = normalized === 0'));
      expect(script, isNot(contains('outerHTML =')));
    },
  );

  test('Harness runtime defaults busy input to same-turn correction', () async {
    final String patch = await File(
      'tool/patch_harness_runtime.mjs',
    ).readAsString();
    final String instructions = await File(
      'assets/harness/AGENTS.md',
    ).readAsString();

    expect(
      patch,
      contains('const DEFAULT_BUSY_ENTER_BEHAVIOR = "steer";'),
    );
    expect(patch, contains('补充并纠正'));
    expect(instructions, contains('运行中的补充与纠正'));
    expect(instructions, contains('以最新的明确输入为准'));
  });
}
