import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_connection_sessions.dart';
import 'package:vibekits/features/dev_tools/domain/serial_port_service.dart';

void main() {
  test('串口长连接可跨多次调用收发并在关闭时释放句柄', () async {
    final _FakeSerialSession serial = _FakeSerialSession();
    final HarnessConnectionSessions sessions = HarnessConnectionSessions(
      openSerial: (_) async => serial,
    );

    final Map<String, Object?> opened = await sessions.openSerial(
      const SerialConnectionSettings(portName: 'COM33'),
    );
    final String id = opened['sessionId']! as String;
    serial.receive(<int>[0x41, 0x42]);
    await Future<void>.delayed(Duration.zero);

    final Map<String, Object?> first = sessions.readSerial(id, clear: false);
    final Map<String, Object?> second = sessions.readSerial(id);
    expect(first['data'], 'AB');
    expect(second['data'], 'AB');
    expect(
      await sessions.writeSerial(id, 'OK\n'),
      containsPair('sentBytes', 3),
    );
    expect(serial.writes.single, <int>[79, 75, 10]);

    await sessions.closeSerial(id);
    expect(serial.closed, isTrue);
    expect(() => sessions.serialStatus(id), throwsStateError);
  });

  test('ADB 长连接状态刷新复用会话并执行真实健康检查语义', () async {
    int checks = 0;
    final HarnessConnectionSessions sessions = HarnessConnectionSessions(
      checkAdb: (_) async {
        checks += 1;
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'device\n',
          stderr: '',
        );
      },
    );
    final Map<String, Object?> opened = await sessions.openAdb(
      '192.168.3.62:5555',
      heartbeatSeconds: 60,
    );
    final String id = opened['sessionId']! as String;
    final Map<String, Object?> refreshed = await sessions.refreshAdb(id);

    expect(refreshed['connected'], isTrue);
    expect(refreshed['healthChecks'], 2);
    expect(checks, 2);
    expect(sessions.closeAdb(id), containsPair('closed', true));
  });
}

class _FakeSerialSession implements SerialPortSession {
  final StreamController<SerialPortEvent> _events =
      StreamController<SerialPortEvent>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  bool closed = false;

  @override
  Stream<SerialPortEvent> get events => _events.stream;

  @override
  bool get isOpen => !closed;

  void receive(List<int> bytes) => _events.add(
    SerialPortEvent(
      SerialPortEventType.received,
      bytes: Uint8List.fromList(bytes),
    ),
  );

  @override
  Future<int> send(Uint8List bytes) async {
    writes.add(bytes.toList(growable: false));
    return bytes.length;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}
