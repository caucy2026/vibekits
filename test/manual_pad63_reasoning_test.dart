import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  test(
    'PAD63 final Harness streams a source-free reasoning task',
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
        'requestId': 'pad63-reasoning-dev228-20260923-1',
        'text': '请计算 11×13 并说明推导步骤，用于验证 PAD 推理过程、进度和结果显示。不要读取工作区或设备文件。',
        },
      );
      final data = Map<String, Object?>.from(
        (prompt['structuredContent'] as Map)['data'] as Map,
      );
      expect(data['accepted'], true);
      final sessionId = data['sessionId'] as String;
      for (var attempt = 0; attempt < 50; attempt++) {
        final response = await controller.call(
          '6795854383',
          'vibekits.harness.session_status',
          <String, Object?>{'sessionId': sessionId},
        );
        final status = Map<String, Object?>.from(
          (response['structuredContent'] as Map)['data'] as Map,
        );
        if (status['phase'] == 'completed' || status['phase'] == 'failed') {
          print(
            'PAD63 FINAL: phase=${status['phase']} cursor=${status['cursor']}',
          );
          expect(status['phase'], 'completed');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      fail('PAD63 final Harness did not finish within 100 seconds');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
