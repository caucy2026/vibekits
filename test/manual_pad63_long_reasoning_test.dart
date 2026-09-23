import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

/// Real PAD63 soak test. Run explicitly; do not include in the unit suite.
void main() {
  test('PAD63 long streamed Harness task completes without a stalled session', () async {
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
    final connected = await controller.connect('6795854383', timeout: const Duration(seconds: 35));
    expect(connected['connected'], true);
    final prompt = await controller.call(
      '6795854383',
      'vibekits.harness.session_prompt',
      const <String, Object?>{
        'requestId': 'pad63-long-reasoning-perf-20260923-1',
        'text': '请在新会话完成一个较长但只读的 PAD Harness 稳定性任务：设计原生 Android 打地鼠游戏的测试计划，列出 12 个具体触摸、计时、计分、重玩、异常输入及横屏场景；每个场景给出操作、预期与失败定位方法。分步骤思考，最后给出结构化结果。不要访问文件、设备或网络，也不要安装软件。',
      },
    );
    final envelope = Map<String, Object?>.from(prompt['structuredContent'] as Map);
    expect(envelope['ok'], true, reason: '$prompt');
    final data = Map<String, Object?>.from(envelope['data'] as Map);
    expect(data['accepted'], true);
    final sessionId = data['sessionId'] as String;
    debugPrint('PAD63 long test session=$sessionId');
    for (var attempt = 0; attempt < 120; attempt++) {
      final response = await controller.call(
        '6795854383', 'vibekits.harness.session_status',
        <String, Object?>{'sessionId': sessionId},
      );
      final status = Map<String, Object?>.from(
        (response['structuredContent'] as Map)['data'] as Map,
      );
      final phase = status['phase'];
      if (phase == 'completed' || phase == 'failed') {
        debugPrint('PAD63 long test final=$phase cursor=${status['cursor']}');
        expect(phase, 'completed', reason: '$status');
        expect((status['cursor'] as num?)?.toInt() ?? 0, greaterThan(0));
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    fail('PAD63 long Harness task did not finish in 4 minutes');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
