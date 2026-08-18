import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/serial_port_service.dart';

void main() {
  test('串口参数可持久化并保留完整帧格式', () {
    const SerialConnectionSettings settings = SerialConnectionSettings(
      portName: 'COM7',
      baudRate: 921600,
      dataBits: 7,
      parity: SerialParity.even,
      stopBits: 2,
      flowControl: SerialFlowControl.rtsCts,
    );
    final SerialConnectionSettings restored = SerialConnectionSettings.decode(
      settings.encode(),
    )!;
    expect(restored.portName, 'COM7');
    expect(restored.baudRate, 921600);
    expect(restored.dataBits, 7);
    expect(restored.parity, SerialParity.even);
    expect(restored.stopBits, 2);
    expect(restored.flowControl, SerialFlowControl.rtsCts);
    expect(restored.summary, contains('7-E-2'));
  });

  test('串口流控覆盖硬件和软件流控组合', () {
    expect(SerialFlowControl.dtrDsr.usesDtrDsr, isTrue);
    expect(SerialFlowControl.rtsCts.usesRtsCts, isTrue);
    expect(SerialFlowControl.xonXoff.usesXonXoff, isTrue);
    expect(SerialFlowControl.all.usesDtrDsr, isTrue);
    expect(SerialFlowControl.all.usesRtsCts, isTrue);
    expect(SerialFlowControl.all.usesXonXoff, isTrue);
    final String encoded = const SerialConnectionSettings(
      portName: 'COM31',
      flowControl: SerialFlowControl.all,
    ).encode();
    expect(
      SerialConnectionSettings.decode(encoded)?.flowControl,
      SerialFlowControl.all,
    );
  });

  test('文本与 HEX 发送编码支持常用行尾和明确错误', () {
    expect(
      SerialCodec.encode(
        'AT',
        SerialDataMode.text,
        lineEnding: SerialLineEnding.crlf,
      ),
      Uint8List.fromList(<int>[65, 84, 13, 10]),
    );
    expect(
      SerialCodec.encode('0x01 A0,ff', SerialDataMode.hex),
      Uint8List.fromList(<int>[1, 160, 255]),
    );
    expect(
      SerialCodec.decode(
        Uint8List.fromList(<int>[1, 160, 255]),
        SerialDataMode.hex,
      ),
      '01 A0 FF',
    );
    expect(
      () => SerialCodec.encode('ABC', SerialDataMode.hex),
      throwsFormatException,
    );
  });

  test('Windows 原生串口枚举在工作 Isolate 完成', () async {
    final List<SerialPortDescriptor> ports =
        await SerialPortService.listPorts();
    expect(ports, isA<List<SerialPortDescriptor>>());
    expect(
      ports.map((SerialPortDescriptor port) => port.name).toSet().length,
      ports.length,
    );
  });

  test('不存在的串口在后台失败且不阻塞事件循环', () async {
    bool timerRan = false;
    final Future<SerialPortSession> operation = SerialPortService.open(
      const SerialConnectionSettings(
        portName: 'VIBEKITS_PORT_THAT_DOES_NOT_EXIST',
      ),
    );
    // 先挂错误处理器，避免原生驱动在定时器触发前快速失败时被测试框架
    // 判定为未处理的异步错误。
    final Future<void> failure = expectLater(operation, throwsA(anything));
    await Future<void>.delayed(const Duration(milliseconds: 20), () {
      timerRan = true;
    });
    await failure;
    expect(timerRan, isTrue);
  });
}
