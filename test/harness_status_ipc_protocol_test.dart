import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_status_ipc_protocol.dart';

void main() {
  test('length-prefixed JSON decoder accepts fragmented and joined frames', () {
    final Uint8List first = HarnessStatusFrameCodec.encode(<String, Object?>{
      'type': 'hello',
      'nonce': 'n-1',
    });
    final Uint8List second = HarnessStatusFrameCodec.encode(<String, Object?>{
      'type': 'getSnapshot',
    });
    final HarnessStatusFrameDecoder decoder = HarnessStatusFrameDecoder();

    expect(decoder.add(first.sublist(0, 2)), isEmpty);
    final List<int> remainder = <int>[...first.sublist(2), ...second];
    final List<Map<String, Object?>> decoded = decoder.add(remainder);

    expect(decoded, hasLength(2));
    expect(decoded[0]['nonce'], 'n-1');
    expect(decoded[1]['type'], 'getSnapshot');
  });

  test('zero, oversized and non-object frames fail closed', () {
    final HarnessStatusFrameDecoder zeroDecoder = HarnessStatusFrameDecoder();
    expect(
      () => zeroDecoder.add(<int>[0, 0, 0, 0]),
      throwsA(
        isA<HarnessStatusFrameException>().having(
          (HarnessStatusFrameException error) => error.code,
          'code',
          'invalid_frame',
        ),
      ),
    );

    final HarnessStatusFrameDecoder oversized = HarnessStatusFrameDecoder(
      maxFrameBytes: 16,
    );
    expect(
      () => oversized.add(<int>[0, 0, 0, 17]),
      throwsA(
        isA<HarnessStatusFrameException>().having(
          (HarnessStatusFrameException error) => error.code,
          'code',
          'frame_too_large',
        ),
      ),
    );

    final HarnessStatusFrameDecoder arrayDecoder = HarnessStatusFrameDecoder();
    final Uint8List arrayFrame = Uint8List.fromList(<int>[0, 0, 0, 2, 91, 93]);
    expect(
      () => arrayDecoder.add(arrayFrame),
      throwsA(isA<HarnessStatusFrameException>()),
    );
  });

  test('protocol constants retain the RustDesk contract', () {
    expect(harnessStatusProtocol, 'vibekits.harness.status');
    expect(harnessStatusProtocolVersion, 1);
    expect(harnessStatusMaxFrameBytes, 32768);
    expect(harnessStatusBusyHeartbeat, const Duration(seconds: 2));
    expect(harnessStatusIdleHeartbeat, const Duration(seconds: 15));
  });
}
