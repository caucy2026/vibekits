import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  test(
    'PAD63 Harness writes native Android Tetris source',
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
          'requestId': 'pad63-tetris-native-apk-20260923-1',
          'text':
              '这次不是网页。请在当前 PAD 本机工作区用 vibekits.workspace.write_text 创建 tetris-apk/TetrisActivity.java，写一个能编译成真正 Android APK 的完整原生 Java Activity，包名 com.vibekits.tetris.demo，不依赖 AndroidX、Kotlin、网络或外部资源。使用自定义 View + Canvas 画 10×20 俄罗斯方块，1920×1280 横屏适配，包含七种方块、左右移动、旋转、加速下落、碰撞、消行、计分、暂停和重新开始，屏幕上有可点击的大触摸按钮。请先调用 workspace.list_files，再写入源文件，最后用 workspace.read_text 读回核对。禁止创建 HTML，也不要声称已编译或安装 APK，因为构建与安装由控制端在取回你写的源码后完成。',
        },
      );
      print('PAD63 TETRIS PROMPT: $prompt');
      final envelope = Map<String, Object?>.from(
        prompt['structuredContent'] as Map,
      );
      expect(envelope['ok'], true, reason: '$prompt');
      final data = Map<String, Object?>.from(envelope['data'] as Map);
      expect(data['accepted'], true);
      final sessionId = data['sessionId'] as String;
      for (var attempt = 0; attempt < 45; attempt++) {
        final status = await controller.call(
          '6795854383',
          'vibekits.harness.session_status',
          <String, Object?>{'sessionId': sessionId},
        );
        final data = Map<String, Object?>.from(
          (status['structuredContent'] as Map)['data'] as Map,
        );
        if (data['phase'] == 'completed' || data['phase'] == 'failed') {
          print('PAD63 TETRIS FINAL STATUS: $data');
          final history = await controller.call(
            '6795854383',
            'vibekits.harness.session_history',
            <String, Object?>{'sessionId': sessionId, 'cursor': 0},
          );
          final historyData = Map<String, Object?>.from(
            (history['structuredContent'] as Map)['data'] as Map,
          );
          print(
            'PAD63 NATIVE SOURCE HISTORY: cursor=${historyData['cursor']} hasMore=${historyData['hasMore']}',
          );
          expect(data['phase'], 'completed');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      fail('PAD63 Harness did not finish the Tetris task within 90 seconds');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
