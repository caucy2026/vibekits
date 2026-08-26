import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 默认双屏入口与长按单屏入口完整注册', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final shortcuts = File('android/app/src/main/res/xml/shortcuts.xml')
        .readAsStringSync();

    expect(manifest, contains('.DualScreenLaunchActivity'));
    expect(manifest, contains('android.intent.category.LAUNCHER'));
    expect(manifest, isNot(contains('.DualScreenCompanionActivity')));
    expect(manifest, contains('.SingleScreenActivity'));
    expect(manifest, contains('@xml/shortcuts'));
    expect(shortcuts, contains('android:shortcutId="single_screen"'));
    expect(shortcuts, contains('action.SINGLE_SCREEN'));
  });

  test('双屏启动从任意屏收敛到 D0 并枚举真实外接屏', () {
    final router = File(
      'android/app/src/main/kotlin/com/vibekits/vibekits/'
      'DualScreenLaunchActivity.kt',
    ).readAsStringSync();
    final main = File(
      'android/app/src/main/kotlin/com/vibekits/vibekits/MainActivity.kt',
    ).readAsStringSync();

    expect(router, contains('finishAndRemoveTask()'));
    expect(router, contains('DISPLAY_TASK_RELEASE_DELAY_MS = 400L'));
    expect(router, contains('launchDisplayId = Display.DEFAULT_DISPLAY'));
    expect(main, contains('ContinuousDisplayCoordinator'));
    expect(main, contains('ContinuousCanvasPresentation'));
    expect(main, contains('it.displayId != Display.DEFAULT_DISPLAY'));
    expect(main, contains('it.state == Display.STATE_ON'));
    expect(main, contains('display.mode.physicalWidth == CANVAS_WIDTH'));
    expect(main, contains('handler.postDelayed(retryAttach, ATTACH_RETRY_MS)'));
    expect(
      main,
      contains('window?.decorView?.post { applyImmersiveCanvas(window) }'),
    );
    expect(main, isNot(contains('Process.killProcess')));
  });

  test('双屏异显使用唯一 Flutter 状态树而不是第二 Activity', () {
    final shell = File('lib/app/main_shell.dart').readAsStringSync();
    final displayContext = File('lib/app/android_display_context.dart')
        .readAsStringSync();
    expect(displayContext, contains("MethodChannel('vibekits/display')"));
    expect(displayContext, contains("role == 'continuous_canvas'"));
    expect(shell, contains('_selectedIndex = 0'));
    expect(shell, contains('initialLargeModelView: Platform.isAndroid'));
    expect(shell, contains("? 'agent'"));
    expect(shell, isNot(contains("? 'system_resources'")));
  });

  test('主要图表具有面向用户的文字说明', () {
    final resources = File(
      'lib/features/dev_tools/presentation/system_resource_workspace.dart',
    ).readAsStringSync();
    final audio = File(
      'lib/features/dev_tools/presentation/audio_debug_workspace.dart',
    ).readAsStringSync();
    final network = File(
      'lib/features/dev_tools/presentation/network_virtualization_workspace.dart',
    ).readAsStringSync();

    expect(resources, contains('图表说明：CPU'));
    expect(resources, contains('每条磁盘图表'));
    expect(audio, contains('横向表示播放时间'));
    expect(audio, contains('横向从低频到高频'));
    expect(network, contains('橙色：上传'));
    expect(network, contains('活动连接'));
  });

  test('1920x2560 连续画布提供双视口、触摸回送和统一退出', () {
    final native = File(
      'android/app/src/main/kotlin/com/vibekits/vibekits/MainActivity.kt',
    ).readAsStringSync();
    final shell = File('lib/app/main_shell.dart').readAsStringSync();

    expect(native, contains('CANVAS_WIDTH = 1920'));
    expect(native, contains('VIEWPORT_HEIGHT = 1280'));
    expect(native, contains('CANVAS_HEIGHT = 2560'));
    expect(native, contains('authoritative.translationY = -VIEWPORT_HEIGHT'));
    expect(native, contains('source.draw(canvas)'));
    expect(native, contains('source.dispatchTouchEvent(logicalEvent)'));
    expect(
      native,
      contains('override fun getRenderMode(): RenderMode = RenderMode.texture'),
    );
    expect(native, contains('applyImmersiveCanvas(window)'));
    expect(native, contains('WindowInsets.Type.statusBars()'));
    expect(native, contains('WindowInsets.Type.navigationBars()'));
    expect(native, contains('"exitApp"'));
    expect(shell, contains('NavigationDestinationLabelBehavior.alwaysShow'));
    expect(shell, contains("Key('android-exit-app')"));
    expect(shell, contains('退出应用（关闭两屏）'));
  });
}
