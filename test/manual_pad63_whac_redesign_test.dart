import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  test('PAD63 Harness continues remembered game work after restart', () async {
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
    expect(connected['connected'], true, reason: '$connected');
    final prompt = await controller.call(
      '6795854383',
      'vibekits.harness.session_prompt',
      const <String, Object?>{
        'requestId': 'pad63-whac-memory-after-restart-20260923-1',
        'text': '应用刚刚完整重启。只根据当前会话里已有的聊天记录，简短回答：我们刚才为 PAD 打地鼠改了哪两个源码文件、构建是否成功、游戏在哪个屏幕？不要调用工具，不要修改文件。',
      },
    );
    final envelope = Map<String, Object?>.from(
      prompt['structuredContent'] as Map,
    );
    expect(envelope['ok'], true, reason: '$prompt');
    final accepted = Map<String, Object?>.from(envelope['data'] as Map);
    expect(accepted['accepted'], true, reason: '$accepted');
    final sessionId = accepted['sessionId'] as String;
    expect(sessionId, 'session-1790161281297150');
    for (var attempt = 0; attempt < 90; attempt++) {
      final status = await controller.call(
        '6795854383',
        'vibekits.harness.session_status',
        <String, Object?>{'sessionId': sessionId},
      );
      final result = Map<String, Object?>.from(
        (status['structuredContent'] as Map)['data'] as Map,
      );
      final phase = result['phase'];
      if (phase == 'completed' || phase == 'failed' || phase == 'cancelled') {
        // ignore: avoid_print
        print('PAD63_WHAC_MEMORY_FINAL=$result');
        expect(phase, 'completed', reason: '$result');
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    fail('PAD63 Harness did not answer the post-restart memory question');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('read PAD63 Whac-a-Mole redesign history', () async {
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
    expect(connected['connected'], true, reason: '$connected');
    final history = await controller.call(
      '6795854383',
      'vibekits.harness.session_history',
      const <String, Object?>{
        'sessionId': 'session-1790161281297150',
        'cursor': 0,
      },
    );
    final envelope = Map<String, Object?>.from(
      history['structuredContent'] as Map,
    );
    expect(envelope['ok'], true, reason: '$history');
    final data = Map<String, Object?>.from(envelope['data'] as Map);
    final records = (data['records'] as List).cast<Map>();
    // ignore: avoid_print
    print('PAD63_REDESIGN_RECORD_TYPES=${records.map((r) => r['type']).toList()}');
    final complete = records.lastWhere((r) => r['type'] == 'complete');
    // ignore: avoid_print
    print('PAD63_REDESIGN_COMPLETE=${complete['text']}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('PAD63 Harness redesigns and builds native Whac-a-Mole on display 2', () async {
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
    expect(connected['connected'], true, reason: '$connected');

    final prompt = await controller.call(
      '6795854383',
      'vibekits.harness.session_prompt',
      const <String, Object?>{
        'requestId': 'pad63-whac-redesign-build-20260923-3',
        'text':
            '继续同一会话的打地鼠重设计；之前的用户授权仍然有效，不需要再询问。上轮已写入 49,689 字节新版 WhacActivity.java，但明确尚未编译、图标也未改。现在直接完成收尾：先把 whac-a-mole/icon-src/ic_launcher.layerlist.xml 的图标改成与新版深绿/琥珀色打地鼠界面统一的原创锤子与地鼠图标（构建桥会把它复制成实际 launcher 图标）；再调用 vibekits.http.request POST http://127.0.0.1:18473/build 让 PAD 本机编译、签名、安装、启动。随后 GET /status 直到 completed/failed，逐项核对退出码；若 javac 等步骤失败，读取错误，修正 WhacActivity.java，再构建一次。build_server.py 已有 am start --display 2，不必再探测它。最终只在看到八步全为 0 时报告成功，并说明游戏在第二屏、Harness 在第一屏；未成功就报告具体错误。不要在 Mac 代编译。',
      },
    );
    final envelope = Map<String, Object?>.from(
      prompt['structuredContent'] as Map,
    );
    expect(envelope['ok'], true, reason: '$prompt');
    final accepted = Map<String, Object?>.from(envelope['data'] as Map);
    expect(accepted['accepted'], true, reason: '$accepted');
    final sessionId = accepted['sessionId'] as String;
    // The ID is evidence for the subsequent process-restart persistence check.
    // ignore: avoid_print
    print('PAD63_WHAC_REDESIGN_SESSION_ID=$sessionId');

    for (var attempt = 0; attempt < 150; attempt++) {
      final status = await controller.call(
        '6795854383',
        'vibekits.harness.session_status',
        <String, Object?>{'sessionId': sessionId},
      );
      final result = Map<String, Object?>.from(
        (status['structuredContent'] as Map)['data'] as Map,
      );
      final phase = result['phase'];
      if (phase == 'completed' || phase == 'failed' || phase == 'cancelled') {
        // ignore: avoid_print
        print('PAD63_WHAC_REDESIGN_FINAL=$result');
        expect(phase, 'completed', reason: '$result');
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    fail('PAD63 Harness did not complete redesign within five minutes');
  }, timeout: const Timeout(Duration(minutes: 7)));
}
