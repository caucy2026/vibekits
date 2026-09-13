import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS release rejects a relay without the assistance gate', () async {
    final String prepare = await File(
      'tool/prepare_rustdesk_harness_relay_macos.sh',
    ).readAsString();
    final String package = await File(
      'tool/package_harness_runtime_macos.sh',
    ).readAsString();

    for (final String script in <String>[prepare, package]) {
      expect(script, contains('transport_connected'));
      expect(script, contains('transport_connect_timeout'));
      expect(script, contains('stdin_eof_v1'));
      expect(
        script,
        contains('vibekits-harness-remote-assistance-access'),
      );
    }
    expect(prepare, contains(r'lipo "$SOURCE" -verify_arch "$ARCH"'));
    expect(
      package,
      contains(r'lipo "$RELAY_SOURCE" -verify_arch "$RELAY_ARCH"'),
    );
  });
}
