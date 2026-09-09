import 'dart:async';

import 'platform_credential_store.dart';

typedef HarnessRemoteSecretReader = Future<String?> Function(String key);
typedef HarnessRemoteSecretWriter =
    Future<void> Function(String key, String value);

/// Process-lifetime remote-assistance gate plus the locally protected pairing
/// password. The gate deliberately starts disabled after every application
/// launch; showing the registered routing ID does not grant protocol access.
final class HarnessRemoteAccessSettings {
  HarnessRemoteAccessSettings({
    HarnessRemoteSecretReader? read,
    HarnessRemoteSecretWriter? write,
  }) : _read = read ?? PlatformCredentialStore.read,
       _write = write ?? PlatformCredentialStore.write;

  static const String defaultPassword = '12345678';
  static const String _passwordKey = 'harness-remote-v1-password';
  static final StreamController<bool> _changes =
      StreamController<bool>.broadcast();
  static bool _enabled = false;

  final HarnessRemoteSecretReader _read;
  final HarnessRemoteSecretWriter _write;

  static bool get enabled => _enabled;
  static Stream<bool> get changes => _changes.stream;

  static void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _changes.add(value);
  }

  Future<String> loadPassword() async {
    final String value = (await _read(_passwordKey))?.trim() ?? '';
    return value.isEmpty ? defaultPassword : value;
  }

  Future<void> savePassword(String value) async {
    final String password = value.trim();
    if (password.length < 8 || password.length > 64) {
      throw const FormatException('远程协助密码必须为 8～64 个字符');
    }
    await _write(_passwordKey, password);
  }
}
