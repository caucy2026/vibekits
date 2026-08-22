import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/platform_credential_store.dart';

void main() {
  test('数据库密码写入系统安全凭据后可读取和删除', () async {
    final String key = 'test-${DateTime.now().microsecondsSinceEpoch}';
    const String password = 'Vibekits-密码-123!';
    try {
      await PlatformCredentialStore.write(key, password);
      expect(await PlatformCredentialStore.read(key), password);
      await PlatformCredentialStore.delete(key);
      expect(await PlatformCredentialStore.read(key), isNull);
    } finally {
      await PlatformCredentialStore.delete(key);
    }
  }, skip: !Platform.isWindows && !Platform.isMacOS);

  test('长订阅凭据可安全写入读取和删除', () async {
    final String key = 'test-long-${DateTime.now().microsecondsSinceEpoch}';
    final String value =
        'https://example.com/sub?token=${List<String>.filled(600, 'x').join()}';
    try {
      await PlatformCredentialStore.write(key, value);
      expect(await PlatformCredentialStore.read(key), value);
      await PlatformCredentialStore.delete(key);
      expect(await PlatformCredentialStore.read(key), isNull);
    } finally {
      await PlatformCredentialStore.delete(key);
    }
  }, skip: !Platform.isWindows && !Platform.isMacOS);
}
