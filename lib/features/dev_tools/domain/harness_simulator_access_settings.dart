import 'dart:async';

import 'platform_credential_store.dart';

typedef HarnessSimulatorSecretReader = Future<String?> Function(String key);
typedef HarnessSimulatorSecretWriter =
    Future<void> Function(String key, String value);

/// Persistent, explicit gate for exposing this device as a simulator target.
///
/// This permission is intentionally separate from Harness remote assistance.
/// Both features share the same RustDesk routing identity, but neither one may
/// silently grant the other's capabilities.
final class HarnessSimulatorAccessSettings {
  HarnessSimulatorAccessSettings({
    HarnessSimulatorSecretReader? read,
    HarnessSimulatorSecretWriter? write,
  }) : _read = read ?? PlatformCredentialStore.read,
       _write = write ?? PlatformCredentialStore.write;

  static const String _enabledKey = 'harness-simulator-v1-enabled';
  static const String defaultActivationPassword = '2580';
  static const String _activationPasswordKey =
      'harness-simulator-v1-activation-password';
  static const String _relayFingerprintKey =
      'harness-simulator-v1-relay-fingerprint';
  static const String _relayExecutableKey =
      'harness-simulator-v1-relay-executable';
  static final StreamController<bool> _changes =
      StreamController<bool>.broadcast();
  static bool _enabled = false;

  final HarnessSimulatorSecretReader _read;
  final HarnessSimulatorSecretWriter _write;

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

  Future<bool> verifyActivationPassword(String? value) async {
    final saved = await _read(_activationPasswordKey);
    return value ==
        (saved?.isNotEmpty == true ? saved : defaultActivationPassword);
  }

  Future<String> loadRelayFingerprint() async =>
      (await _read(_relayFingerprintKey))?.trim().toLowerCase() ?? '';

  Future<void> saveRelayFingerprint(String value) =>
      _write(_relayFingerprintKey, value.trim().toLowerCase());

  Future<String> loadRelayExecutable() async =>
      (await _read(_relayExecutableKey))?.trim() ?? '';

  Future<void> saveRelayExecutable(String value) =>
      _write(_relayExecutableKey, value.trim());
}
