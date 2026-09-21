import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/presentation/harness_webview_input_gate.dart';

void main() {
  tearDown(HarnessWebViewInputGate.resetForTesting);

  test('嵌套 Flutter 弹层期间只关闭一次 WebView 输入并在最后恢复', () async {
    final values = <bool>[];
    HarnessWebViewInputGate.testSetter = (enabled) async {
      values.add(enabled);
    };

    await HarnessWebViewInputGate.acquire();
    await HarnessWebViewInputGate.acquire();
    expect(values, <bool>[false]);
    expect(HarnessWebViewInputGate.depth, 2);

    await HarnessWebViewInputGate.release();
    expect(values, <bool>[false]);
    await HarnessWebViewInputGate.release();
    expect(values, <bool>[false, true]);
    expect(HarnessWebViewInputGate.depth, 0);
  });

  test('弹层抛错也恢复 WebView 输入', () async {
    final values = <bool>[];
    HarnessWebViewInputGate.testSetter = (enabled) async {
      values.add(enabled);
    };

    await expectLater(
      HarnessWebViewInputGate.runWithOverlay<void>(() async {
        throw StateError('dialog failed');
      }),
      throwsStateError,
    );
    expect(values, <bool>[false, true]);
    expect(HarnessWebViewInputGate.depth, 0);
  });

  test('离开 Harness 后后台 WebView 不得截获其他一级页面点击', () async {
    final values = <bool>[];
    HarnessWebViewInputGate.testSetter = (bool enabled) async {
      values.add(enabled);
    };

    await HarnessWebViewInputGate.setWorkspaceActive(false);
    await HarnessWebViewInputGate.acquire();
    await HarnessWebViewInputGate.release();
    expect(values, <bool>[false]);
    expect(HarnessWebViewInputGate.workspaceActive, isFalse);

    await HarnessWebViewInputGate.setWorkspaceActive(true);
    expect(values, <bool>[false, true]);
  });

  test('切回 Harness 时若仍有弹层则保持 WebView 输入关闭', () async {
    final values = <bool>[];
    HarnessWebViewInputGate.testSetter = (bool enabled) async {
      values.add(enabled);
    };

    await HarnessWebViewInputGate.setWorkspaceActive(false);
    await HarnessWebViewInputGate.acquire();
    await HarnessWebViewInputGate.setWorkspaceActive(true);
    expect(values, <bool>[false]);

    await HarnessWebViewInputGate.release();
    expect(values, <bool>[false, true]);
  });

  test('切到 OCR 时隐藏原生 WebView 并在返回 Harness 后恢复', () async {
    final values = <bool>[];
    HarnessWebViewInputGate.testSetter = (bool enabled) async {
      values.add(enabled);
    };

    await HarnessWebViewInputGate.setSurfaceActive(false);
    expect(HarnessWebViewInputGate.surfaceActive, isFalse);
    expect(values, <bool>[false]);

    await HarnessWebViewInputGate.setWorkspaceActive(false);
    await HarnessWebViewInputGate.setSurfaceActive(true);
    expect(values, <bool>[false]);

    await HarnessWebViewInputGate.setWorkspaceActive(true);
    expect(values, <bool>[false, true]);
  });
}
