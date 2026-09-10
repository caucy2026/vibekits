import 'dart:async';

import 'platform_credential_store.dart';

typedef HarnessRemoteSecretReader = Future<String?> Function(String key);
typedef HarnessRemoteSecretWriter =
    Future<void> Function(String key, String value);

/// Persistent remote-assistance gate plus the locally protected pairing
/// password. A user's explicit choice survives an application restart; actual
/// access still requires the remembered certificate and scoped peer grant.
final class HarnessRemoteAccessSettings {
  HarnessRemoteAccessSettings({
    HarnessRemoteSecretReader? read,
    HarnessRemoteSecretWriter? write,
  }) : _read = read ?? PlatformCredentialStore.read,
       _write = write ?? PlatformCredentialStore.write;

  static const String defaultPassword = '12345678';
  static const String _passwordKey = 'harness-remote-v1-password';
  static const String _enabledKey = 'harness-remote-v1-enabled';
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

  Future<bool> loadEnabled() async {
    final value = (await _read(_enabledKey))?.trim().toLowerCase();
    final enabled = value == 'true';
    setEnabled(enabled);
    return enabled;
  }

  Future<void> saveEnabled(bool value) async {
    await _write(_enabledKey, value ? 'true' : 'false');
    setEnabled(value);
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
