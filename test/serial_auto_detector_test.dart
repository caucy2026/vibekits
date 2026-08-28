import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/serial_port_service.dart';

void main() {
  test('串口自动探测精确选择波特率、8-N-1 和 RTS/CTS', () async {
    final Map<String, Object?> result = await SerialAutoDetector.detect(
      portName: 'COM33',
      baudRates: const <int>[9600, 115200],
      listenDuration: const Duration(milliseconds: 1),
      open: (SerialConnectionSettings settings) async =>
          _ProbeSession(settings),
    );

    expect(result['passiveOnly'], isTrue);
    expect(result['requiresUserInput'], isFalse);
    final Map<String, Object?> selected = (result['selected'] as Map)
        .cast<String, Object?>();
    expect(selected, containsPair('baudRate', 115200));
    expect(selected, containsPair('dataBits', 8));
    expect(selected, containsPair('stopBits', 1));
    expect(selected, containsPair('parity', 'none'));
    expect(selected, containsPair('flowControl', 'rtsCts'));
    expect(result['receivedBytes'], greaterThan(0));
    expect(result['attempts'], isNotEmpty);
  });

  test('Harness 可精确查询串口工具参数和自动配置原则', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.describeToolId,
      arguments: const <String, Object?>{
        'toolId': VibekitsHarnessToolBridge.serialSessionOpenId,
      },
      approve: (_) async => false,
    );

    expect(result.ok, isTrue);
    final List<Map<String, Object?>> parameters =
        (result.data!['parameters'] as List)
            .map((dynamic value) => (value as Map).cast<String, Object?>())
            .toList(growable: false);
    Map<String, Object?> parameter(String name) => parameters.singleWhere(
      (Map<String, Object?> item) => item['name'] == name,
    );
    expect(parameter('baudRate')['default'], 115200);
    expect(parameter('dataBits')['enum'], <int>[5, 6, 7, 8]);
    expect(parameter('stopBits')['enum'], <int>[1, 2]);
    expect(
      parameter('parity')['enum'],
      containsAll(<String>['none', 'even', 'odd', 'mark', 'space']),
    );
    expect(parameter('flowControl')['enum'], hasLength(8));
    expect(result.data!['configurationPolicy'], isNotNull);
  });

  test('Harness 能精确列出每个公开工具的参数配置', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    for (final HarnessToolDefinition tool in bridge.executableCatalog) {
      final HarnessToolCallResult described = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.describeToolId,
        arguments: <String, Object?>{'toolId': tool.id},
        approve: (_) async => false,
      );
      expect(described.ok, isTrue, reason: tool.id);
      expect(described.data!['inputSchema'], tool.inputSchema, reason: tool.id);
      for (final dynamic raw in described.data!['parameters']! as List) {
        final Map<String, Object?> parameter = (raw as Map).cast<String, Object?>();
        expect(parameter['name'], isNotEmpty, reason: tool.id);
        expect(parameter['type'], isNotNull, reason: '${tool.id}.${parameter['name']}');
        expect(parameter['description'], isNotEmpty, reason: '${tool.id}.${parameter['name']}');
      }
    }
  });
}

class _ProbeSession implements SerialPortSession {
  _ProbeSession(this.settings) {
    _controller = StreamController<SerialPortEvent>(
      onListen: () {
        if (settings.baudRate == 115200 &&
            settings.dataBits == 8 &&
            settings.stopBits == 1 &&
            settings.parity == SerialParity.none &&
            settings.flowControl == SerialFlowControl.rtsCts) {
          scheduleMicrotask(() {
            if (!_controller.isClosed) {
              _controller.add(
                SerialPortEvent(
                  SerialPortEventType.received,
                  bytes: Uint8List.fromList('console:/ # boot ok\n'.codeUnits),
                ),
              );
            }
          });
        }
      },
    );
  }

  final SerialConnectionSettings settings;
  late final StreamController<SerialPortEvent> _controller;

  @override
  Stream<SerialPortEvent> get events => _controller.stream;

  @override
  bool get isOpen => !_controller.isClosed;

  @override
  Future<int> send(Uint8List bytes) async {
    fail('自动探测不得发送任何字节');
  }

  @override
  Future<void> close() => _controller.close();
}
