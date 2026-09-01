// This test requires shared array buffers. We can use a CLI flag for Chrome to
// make them available without custom headers, but we can't run this test on
// Firefox.
@TestOn('!firefox')
@Tags(['wasm'])
library;

import 'package:sqlite3/src/wasm/js_interop.dart';
import 'package:sqlite3/src/wasm/vfs/async_opfs/sync_channel.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips file offsets and sizes beyond 2 GiB', () {
    // Regression test for https://github.com/simolus3/sqlite3.dart/pull/403
    final serializer = MessageSerializer(
      SharedArrayBuffer(MessageSerializer.totalSize),
    );

    const values = [
      -1,
      0,
      0x7fffffff,
      0x80000000,
      0x100000000,
      0xffff_fffe_0000,
    ];

    for (final value in values) {
      {
        serializer.write(Flags(value, value, value));

        final decoded = MessageSerializer.readFlags(serializer);

        expect(decoded.flag0, value);
        expect(decoded.flag1, value);
        expect(decoded.flag2, value);
      }

      {
        serializer.write(
          NameAndIntFlags('/some/database/path.sqlite', value, value, value),
        );

        final decoded = MessageSerializer.readNameAndFlags(serializer);

        expect(decoded.name, '/some/database/path.sqlite');
        expect(decoded.flag0, value);
        expect(decoded.flag1, value);
        expect(decoded.flag2, value);
      }
    }
  });
}
