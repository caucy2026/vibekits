import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/serial_port_service.dart';
import 'package:vibekits/features/dev_tools/presentation/serial_port_workspace.dart';

void main() {
  testWidgets('自动选择端口后打开、收发并关闭', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeSerialSession session = _FakeSerialSession();
    SerialConnectionSettings? openedSettings;
    String? savedSettings;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SerialPortWorkspace(
            listPorts: () async => const <SerialPortDescriptor>[
              SerialPortDescriptor(name: 'COM7', description: 'USB Serial'),
            ],
            openSession: (SerialConnectionSettings settings) async {
              openedSettings = settings;
              return session;
            },
            onSettingsChanged: (String settings) async {
              savedSettings = settings;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('serial-port-name')))
          .controller
          ?.text,
      'COM7',
    );
    await tester.enterText(find.byKey(const Key('serial-baud-rate')), '9600');
    await tester.tap(find.byKey(const Key('serial-open')));
    await tester.pumpAndSettle();

    expect(openedSettings?.portName, 'COM7');
    expect(openedSettings?.baudRate, 9600);
    expect(SerialConnectionSettings.decode(savedSettings)?.baudRate, 9600);
    expect(find.byKey(const Key('serial-close')), findsOneWidget);

    session.receive(<int>[65, 66]);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('AB'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('serial-send-input')), 'PING');
    await tester.tap(find.byKey(const Key('serial-send')));
    await tester.pumpAndSettle();
    expect(session.sent.single, <int>[80, 73, 78, 71, 13, 10]);

    await tester.tap(find.byKey(const Key('serial-close')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(session.closed, isTrue);
    expect(find.text('未连接'), findsOneWidget);
  });

  testWidgets('HEX 输入错误保留内容且高级参数在 1024 窗口不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeSerialSession session = _FakeSerialSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SerialPortWorkspace(
            listPorts: () async => const <SerialPortDescriptor>[
              SerialPortDescriptor(name: 'COM9'),
            ],
            openSession: (_) async => session,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('serial-advanced-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('serial-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('serial-send-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HEX').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('serial-send-input')), 'ABC');
    await tester.tap(find.byKey(const Key('serial-send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('成对十六进制'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('serial-send-input')))
          .controller
          ?.text,
      'ABC',
    );
    expect(session.sent, isEmpty);
  });

  testWidgets('销毁工作区会立即请求关闭后台串口会话', (WidgetTester tester) async {
    final _FakeSerialSession session = _FakeSerialSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SerialPortWorkspace(
            listPorts: () async => const <SerialPortDescriptor>[
              SerialPortDescriptor(name: 'COM5'),
            ],
            openSession: (_) async => session,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('serial-open')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(session.closed, isTrue);
  });
}

class _FakeSerialSession implements SerialPortSession {
  final StreamController<SerialPortEvent> _events =
      StreamController<SerialPortEvent>.broadcast();
  final List<List<int>> sent = <List<int>>[];
  bool closed = false;

  @override
  Stream<SerialPortEvent> get events => _events.stream;

  @override
  bool get isOpen => !closed;

  void receive(List<int> bytes) {
    _events.add(
      SerialPortEvent(
        SerialPortEventType.received,
        bytes: Uint8List.fromList(bytes),
      ),
    );
  }

  @override
  Future<int> send(Uint8List bytes) async {
    sent.add(bytes.toList(growable: false));
    _events.add(SerialPortEvent(SerialPortEventType.sent, bytes: bytes));
    return bytes.length;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _events.close();
  }
}
