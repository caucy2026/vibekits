import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test('Harness 被动识别真实系统日志串口', () async {
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.serialAutoDetectId,
          arguments: const <String, Object?>{'listenMs': 300},
          approve: (_) async => true,
        );
    expect(result.ok, isTrue, reason: result.error);
    expect(result.data?['selected'], isA<Map<Object?, Object?>>());
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  });
}
