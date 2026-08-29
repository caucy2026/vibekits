import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test('Harness 通过串口控制台发送 logcat 并读取返回', () async {
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.serialTransactId,
          arguments: const <String, Object?>{
            'port': 'COM33',
            'baudRate': 115200,
            'dataBits': 8,
            'stopBits': 1,
            'parity': 'none',
            'flowControl': 'none',
            'mode': 'text',
            'data': 'logcat',
            'lineEnding': 'crlf',
            'waitMs': 5000,
          },
          approve: (_) async => true,
        );
    expect(result.ok, isTrue, reason: result.error);
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  });
}
