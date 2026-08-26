import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test('Harness 枚举本机真实串口并写入审计证据', () async {
    final List<Map<String, Object?>> activity = <Map<String, Object?>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      activityRecorder:
          ({
            required String toolId,
            required String toolName,
            required String target,
            required Map<String, Object?> arguments,
            required Object? result,
            required HarnessToolActivityStatus status,
            required DateTime startedAt,
          }) async {
            activity.add(<String, Object?>{
              'toolId': toolId,
              'toolName': toolName,
              'target': target,
              'arguments': arguments,
              'result': result,
              'status': status.name,
              'startedAt': startedAt.toIso8601String(),
            });
          },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.serialListPortsId,
      arguments: const <String, Object?>{},
      approve: (_) async => true,
    );
    expect(result.ok, isTrue, reason: result.error);
    final List<Object?> ports = List<Object?>.from(
      result.data?['ports'] as List? ?? const <Object?>[],
    );
    expect(ports, isNotEmpty, reason: '已连接串口时 Harness 不应返回空列表');
    expect(activity, hasLength(1));
    expect(
      activity.single['toolId'],
      VibekitsHarnessToolBridge.serialListPortsId,
    );
    expect(activity.single['status'], 'succeeded');

    final Directory evidence = Directory('build/acceptance/serial');
    await evidence.create(recursive: true);
    final Map<String, Object?> report = <String, Object?>{
      'protocol': VibekitsHarnessToolBridge.protocolVersion,
      'toolCall': VibekitsHarnessToolBridge.serialListPortsId,
      'result': result.toJson(),
      'activity': activity,
    };
    await File('${evidence.path}/harness-serial-probe.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    // Visible in CI/local acceptance output without exposing credentials.
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(report));
  });
}
