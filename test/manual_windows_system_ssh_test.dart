import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_system_ssh_service.dart';

void main() {
  final bool enabled =
      Platform.isWindows &&
      Platform.environment['VIBEKITS_REAL_WINDOWS_SYSTEM_SSH'] == '1';

  test(
    'real Windows SSH identity and restricted key lifecycle',
    () async {
      final String rawHome =
          Platform.environment['VIBEKITS_WINDOWS_SSH_TEST_HOME'] ?? '';
      expect(rawHome, startsWith(r'D:\KEMI-Test\'));
      final Directory home = Directory(rawHome);
      if (await home.exists()) await home.delete(recursive: true);
      await home.create(recursive: true);
      addTearDown(() async {
        if (await home.exists()) await home.delete(recursive: true);
      });

      final Map<String, Object?> identity =
          await HarnessSystemSshService.identity();
      expect(identity['enabled'], isTrue);
      expect('${identity['username']}', isNotEmpty);
      expect('${identity['hostKeyFingerprint']}', startsWith('SHA256:'));

      final String key = base64Encode(
        List<int>.generate(48, (int index) => index + 1),
      );
      final String publicKey = 'ssh-ed25519 $key windows-acceptance';
      final Map<String, Object?> authorized =
          await HarnessSystemSshService.authorizePublicKey(
            peerId: '4456560334',
            publicKey: publicKey,
            homeDirectory: home,
          );
      expect(authorized['authorized'], isTrue);
      expect(
        (await HarnessSystemSshService.publicKeyStatus(
          peerId: '4456560334',
          publicKey: publicKey,
          homeDirectory: home,
        ))['authorized'],
        isTrue,
      );
      final File authorizedKeys = File('${home.path}\\.ssh\\authorized_keys');
      expect(await authorizedKeys.exists(), isTrue);
      expect(await authorizedKeys.readAsString(), contains('from="127.0.0.1"'));

      final Map<String, Object?> revoked =
          await HarnessSystemSshService.revokePublicKeys(
            peerId: '4456560334',
            homeDirectory: home,
          );
      expect(revoked['removed'], 1);
      expect(await authorizedKeys.readAsString(), isEmpty);

      // Counts only: do not print account names, fingerprints or key text.
      // ignore: avoid_print
      print('WINDOWS_SYSTEM_SSH_REAL identity=true authorize=1 revoke=1');
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_WINDOWS_SYSTEM_SSH=1',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
