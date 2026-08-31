import 'dart:convert';
import 'dart:typed_data';

const String harnessStatusProtocol = 'vibekits.harness.status';
const int harnessStatusProtocolVersion = 1;
const int harnessStatusMaxFrameBytes = 32 * 1024;
const Duration harnessStatusBusyHeartbeat = Duration(seconds: 2);
const Duration harnessStatusIdleHeartbeat = Duration(seconds: 15);

const Set<String> harnessStatusErrorCodes = <String>{
  'invalid_frame',
  'frame_too_large',
  'invalid_handshake',
  'unsupported_version',
  'unauthorized_peer',
  'not_subscribed',
  'subscription_busy',
  'internal_error',
};

class HarnessStatusFrameException implements Exception {
  const HarnessStatusFrameException(this.code);

  final String code;
}

abstract final class HarnessStatusFrameCodec {
  static Uint8List encode(
    Map<String, Object?> message, {
    int maxFrameBytes = harnessStatusMaxFrameBytes,
  }) {
    final Uint8List payload = Uint8List.fromList(
      utf8.encode(jsonEncode(message)),
    );
    if (payload.isEmpty) {
      throw const HarnessStatusFrameException('invalid_frame');
    }
    if (payload.length > maxFrameBytes) {
      throw const HarnessStatusFrameException('frame_too_large');
    }
    final Uint8List frame = Uint8List(payload.length + 4);
    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);
    frame.setRange(4, frame.length, payload);
    return frame;
  }
}

class HarnessStatusFrameDecoder {
  HarnessStatusFrameDecoder({this.maxFrameBytes = harnessStatusMaxFrameBytes});

  int maxFrameBytes;
  final List<int> _buffer = <int>[];
  int? _payloadLength;

  List<Map<String, Object?>> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
    while (true) {
      if (_payloadLength == null) {
        if (_buffer.length < 4) break;
        final int length = ByteData.sublistView(
          Uint8List.fromList(_buffer.sublist(0, 4)),
        ).getUint32(0, Endian.big);
        _buffer.removeRange(0, 4);
        if (length == 0) {
          throw const HarnessStatusFrameException('invalid_frame');
        }
        if (length > maxFrameBytes) {
          throw const HarnessStatusFrameException('frame_too_large');
        }
        _payloadLength = length;
      }
      final int length = _payloadLength!;
      if (_buffer.length < length) break;
      final Uint8List payload = Uint8List.fromList(_buffer.sublist(0, length));
      _buffer.removeRange(0, length);
      _payloadLength = null;
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(payload, allowMalformed: false));
      } on Object {
        throw const HarnessStatusFrameException('invalid_frame');
      }
      if (decoded is! Map) {
        throw const HarnessStatusFrameException('invalid_frame');
      }
      final Map<String, Object?> frame = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in decoded.entries) {
        if (entry.key is! String) {
          throw const HarnessStatusFrameException('invalid_frame');
        }
        frame[entry.key! as String] = entry.value;
      }
      frames.add(frame);
    }
    return frames;
  }
}
