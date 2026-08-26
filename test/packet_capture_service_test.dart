import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/packet_capture_service.dart';

void main() {
  test('读取并分析 LINKTYPE_RAW PCAP，Harness 使用同一解析结果', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'vibekits-pcap-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}${Platform.pathSeparator}dns.pcap');
    await file.writeAsBytes(<int>[
      0xd4,
      0xc3,
      0xb2,
      0xa1,
      2,
      0,
      4,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0xff,
      0xff,
      0,
      0,
      101,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      32,
      0,
      0,
      0,
      32,
      0,
      0,
      0,
      0x45,
      0,
      0,
      0x20,
      0,
      1,
      0,
      0,
      0x40,
      0x11,
      0,
      0,
      127,
      0,
      0,
      1,
      8,
      8,
      8,
      8,
      0xc3,
      0x50,
      0,
      0x35,
      0,
      0x0c,
      0,
      0,
      0x56,
      0x49,
      0x42,
      0x45,
    ]);

    final PacketCaptureSummary summary = await PacketCaptureService().read(
      file.path,
    );
    expect(summary.packets, hasLength(1));
    expect(summary.packets.single.protocol, 'DNS');
    expect(summary.packets.single.source, '127.0.0.1:50000');
    expect(summary.packets.single.destination, '8.8.8.8:53');

    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.captureAnalyzeId,
      arguments: <String, Object?>{'path': file.path},
      approve: (_) async => true,
    );
    expect(result.ok, isTrue);
    expect(result.data?['packetCount'], 1);
    expect(result.data?['protocolCounts'], <String, int>{'DNS': 1});
    expect(result.data?.containsKey('packets'), isFalse);
  });

  test('拒绝非 PCAP 内容', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'vibekits-pcap-bad-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}${Platform.pathSeparator}bad.pcap');
    await file.writeAsString('not a capture');
    expect(() => PacketCaptureService().read(file.path), throwsFormatException);
  });

  test('Release 真抓 PCAP 可由 Harness 读取（本机产物存在时）', () async {
    final File capture = File(
      'build/windows/x64/runner/Release/tmp/network-capture/live-admin-test.pcap',
    );
    if (!await capture.exists()) return;
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.captureReadId,
          arguments: <String, Object?>{
            'path': capture.absolute.path,
            'maxPackets': 100,
          },
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect((result.data?['packetCount'] as int?) ?? 0, greaterThanOrEqualTo(5));
    expect(result.data?['packets'], isNotEmpty);
  });
}
