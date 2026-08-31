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
      expect(script, contains('font-size: 12px !important'));
      expect(
        script,
        contains("querySelectorAll('[data-conversation-scroll]')"),
      );
      expect(script, contains('导出会话日志'));
      expect(script, contains("window.addEventListener('wheel'"));
      expect(script, contains('passive: false'));
      expect(script, contains('font-size: 14px !important'));
      expect(script, contains('font-size: 13px !important'));
      expect(script, contains('[data-chat-flow]'));
      expect(script, contains('event.preventDefault()'));
      expect(script, contains('vibekits-scroll-to-latest'));
      expect(script, contains('滚动到最新消息'));
      expect(script, contains("scrollButton.textContent = '↓'"));
      expect(script, contains("distance > 72 ? 'true' : 'false'"));
      expect(
        script,
        contains("host.scrollTo({ top: host.scrollHeight, behavior: 'smooth' })"),
      );
      expect(script, contains("document.addEventListener('scroll'"));
    },
  );
}
