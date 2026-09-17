import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows release requires a source-built self-contained relay',
    () async {
      final String prepare = await File(
        'tool/prepare_rustdesk_harness_relay_windows.ps1',
      ).readAsString();
      final String cmake = await File('windows/CMakeLists.txt').readAsString();
      final String verify = await File(
        'tool/verify_windows_bundle.ps1',
      ).readAsString();

      expect(prepare, contains("'D:\\KEMI-Test\\tools'"));
      expect(prepare, contains('Assert-DDrivePath'));
      expect(prepare, contains('System.Diagnostics.ProcessStartInfo'));
      expect(prepare, contains(r'RedirectStandardOutput = $true'));
      expect(prepare, contains(r'RedirectStandardError = $true'));
      expect(prepare, contains('cargo test --locked'));
      expect(prepare, contains("--lib 'vibekits_harness_relay::tests'"));
      expect(prepare, contains('--features flutter'));
      expect(prepare, contains('cargo build --locked --release'));
      expect(prepare, contains('--target x86_64-pc-windows-msvc'));
      expect(prepare, contains('transport_connected'));
      expect(prepare, contains('transport_connect_timeout'));
      expect(prepare, contains('stdin_eof_v1'));
      expect(prepare, contains('vibekits-harness-remote-assistance-access'));
      expect(prepare, contains('RUSTDESK-AGPL-3.0.txt'));
      expect(prepare, contains('Get-FileHash'));
      expect(prepare, contains('snapshot-sha256:'));
      expect(prepare, contains('src\\vibekits_harness_relay.rs'));
      expect(cmake, contains('vibekits-harness-relay.json'));
      expect(cmake, contains('RUSTDESK-AGPL-3.0.txt'));
      expect(cmake, contains('VIBEKITS_NUGET_EXECUTABLE'));
      expect(cmake, contains('v6.5.0/nuget.exe'));
      expect(
        cmake,
        contains(
          'd5fce5185de92b7356ea9264b997a620e35c6f6c3c061e471e0dc3a84b3d74fd',
        ),
      );
      expect(cmake, contains('message(FATAL_ERROR'));
      expect(verify, contains("'vibekits-harness-relay.exe'"));
      expect(verify, contains(r'$relayManifest.sha256 -ne $relayHash'));
    },
  );
}
