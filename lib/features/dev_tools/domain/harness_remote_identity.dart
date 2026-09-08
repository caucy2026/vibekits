import 'dart:convert';
import 'dart:io';

import 'lmcp_exposure_server.dart';
import 'platform_credential_store.dart';

/// Dedicated Harness identity, never the LMCP or RustDesk desktop identity.
/// The ID is a certificate-derived label, not by itself a routable address or
/// proof of authorization. Pairing always pins the full certificate digest.
class HarnessRemoteIdentity {
  HarnessRemoteIdentity._(this._certificate);
  final LmcpInstanceCertificate _certificate;
  String get fingerprint => _certificate.fingerprint.substring(7);
  String get deviceId => 'VH-${fingerprint.substring(0, 32).toUpperCase()}';
  String get certificatePem => _certificate.certificatePem;

  SecurityContext context({Iterable<String> trustedCertificates = const []}) {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(_certificate.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(_certificate.privateKeyPem));
    for (final certificate in trustedCertificates) {
      context.setTrustedCertificatesBytes(utf8.encode(certificate));
    }
    return context;
  }
}

class HarnessRemoteIdentityStore {
  HarnessRemoteIdentityStore({
    LmcpCredentialReader? read,
    LmcpCredentialWriter? write,
  }) : _read = read ?? PlatformCredentialStore.read,
       _write = write ?? PlatformCredentialStore.write;

  static final instance = HarnessRemoteIdentityStore();
  static const credentialKey = 'harness-remote-v1-identity';
  final LmcpCredentialReader _read;
  final LmcpCredentialWriter _write;
  Future<HarnessRemoteIdentity>? _loading;

  Future<HarnessRemoteIdentity> loadOrCreate() => _loading ??= _load();

  Future<HarnessRemoteIdentity> _load() async {
    try {
      final encoded = await _read(credentialKey);
      final existing = encoded != null && encoded.isNotEmpty;
      final Map<String, String> values;
      if (existing) {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map ||
            decoded.length != 2 ||
            decoded.values.any((v) => v is! String || v.isEmpty)) {
          throw StateError('REMOTE_IDENTITY_CORRUPT');
        }
        values = Map<String, String>.from(decoded);
      } else {
        values = {};
      }
      final certificate = await LmcpCertificateStore(
        readCredential: (key) async => values[key],
        writeCredential: (key, value) async {
          // Unlike ephemeral discovery identity, remote paired identity must
          // never silently rotate when secure storage is partial/corrupt.
          if (existing) throw StateError('REMOTE_IDENTITY_CORRUPT');
          values[key] = value;
        },
      ).loadOrCreate(commonName: 'VibeKits Harness Remote');
      if (!existing) {
        await _write(credentialKey, jsonEncode(values));
      }
      return HarnessRemoteIdentity._(certificate);
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }
}
