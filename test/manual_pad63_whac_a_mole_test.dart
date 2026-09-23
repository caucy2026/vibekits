import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  test(
    'dispatch PAD Harness native Whac-a-Mole build continuation',
    () async {
      final controller = HarnessSimulatorController(
        resolveHost: () async => const RustDeskHostInfo(
          executable:
              '/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev225-harness-market/build/macos/Build/Products/Release/Vibekits.app/Contents/Helpers/VibeKitsHarnessRelay.app/Contents/MacOS/vibekits-harness-relay',
          id: '1554650784',
          available: true,
          callable: true,
          message: 'ready',
        ),
      );
      addTearDown(controller.closeAll);
      final connected = await controller.connect(
        '6795854383',
        timeout: const Duration(seconds: 35),
      );
      expect(connected['connected'], true);
      final prompt = await controller.call(
        '6795854383',
        'vibekits.harness.session_prompt',
        const <String, Object?>{
          'requestId': 'pad63-whac-impact-build-20260923-7',
          'text':
              '继续当前 PAD 本机原生打地鼠任务。新的 WhacActivity.java 已更新为每次触摸锤子挥击、命中头部局部碎裂并逐渐恢复。请调用一次 vibekits.http.request POST http://127.0.0.1:18473/build，触发 PAD 本机 Java 编译、签名、覆盖安装和启动；然后调用 GET /status 核对结果，不要在 Mac 编译或代装。',
        },
      );
      debugPrint('WHAC PROMPT: $prompt');
      final envelope = Map<String, Object?>.from(
        prompt['structuredContent'] as Map,
      );
      expect(envelope['ok'], true, reason: '$prompt');
      final data = Map<String, Object?>.from(envelope['data'] as Map);
      final sessionId = data['sessionId'] as String;
      debugPrint('WHAC SESSION ID: $sessionId');
      expect(data['accepted'], true);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
