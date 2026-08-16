import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/domain/onnx_bridge.dart';

void main() {
  test('PP-OCRv6 tiny detection model executes through Windows bridge', () {
    if (!Platform.isWindows) return;
    final String nativeDirectory = [
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'runner',
      'Debug',
    ].join(Platform.pathSeparator);
    final String modelPath = [
      Directory.current.path,
      'test_data',
      'models',
      'ppocrv6_tiny',
      'det.onnx',
    ].join(Platform.pathSeparator);
    if (!File('$nativeDirectory${Platform.pathSeparator}vibekits_onnx.dll')
        .existsSync()) {
      fail('先执行 flutter build windows --debug 生成 ONNX 桥接 DLL');
    }

    final OnnxBridge bridge = OnnxBridge.load(nativeDirectory: nativeDirectory);
    final OnnxSession session = bridge.openSession(modelPath);
    try {
      final OnnxTensorResult output = session.run(
        Float32List(3 * 64 * 64),
        const <int>[1, 3, 64, 64],
      );
      expect(output.shape, const <int>[1, 1, 64, 64]);
      expect(output.values.length, 64 * 64);
      expect(output.values.every((double value) => value.isFinite), isTrue);
    } finally {
      session.close();
    }
  });
}
