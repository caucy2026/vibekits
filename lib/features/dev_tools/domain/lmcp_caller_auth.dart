import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

class LmcpCallerAuthException implements Exception {
  const LmcpCallerAuthException(this.code);

  final String code;
}

class LmcpVerifiedCaller {
  const LmcpVerifiedCaller({
    required this.appId,
    required this.instanceId,
    required this.fingerprint,
  });

  final String appId;
  final String instanceId;
  final String fingerprint;
}

/// Verifies the LMCP/2 signed caller headers defined by the single integration
/// standard. Private-network source addresses remain a transport boundary,
/// never an authorization identity.
class LmcpCallerRequestVerifier {
  LmcpCallerRequestVerifier({
    DateTime Function()? clock,
    this.allowedClockSkew = const Duration(seconds: 120),
    this.replayWindow = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration allowedClockSkew;
  final Duration replayWindow;
  final Map<String, DateTime> _seenNonces = <String, DateTime>{};

  LmcpVerifiedCaller verify({
    required HttpHeaders headers,
    required Uri uri,
    required List<int> body,
  }) {
    String requiredHeader(String name) {
      final String value = (headers.value(name) ?? '').trim();
      if (value.isEmpty) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_REQUIRED');
      }
      return value;
    }

    try {
      final String instanceId = requiredHeader('LMCP-Caller-Instance-Id');
      final String appId = requiredHeader('LMCP-Caller-App-Id');
      final String certificateValue = requiredHeader('LMCP-Caller-Certificate');
      final String fingerprint = requiredHeader('LMCP-Caller-Fingerprint')
          .toLowerCase();
      final String timestampValue = requiredHeader('LMCP-Caller-Timestamp');
      final String nonce = requiredHeader('LMCP-Caller-Nonce');
      final String signature = requiredHeader('LMCP-Caller-Signature');
      if (!RegExp(r'^[A-Za-z0-9.-]{3,120}$').hasMatch(appId) ||
          !instanceId.startsWith('$appId:') ||
          instanceId.length > 200 ||
          !RegExp(r'^[A-Za-z0-9_-]{22,43}$').hasMatch(nonce) ||
          !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(fingerprint)) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      final int timestamp = int.parse(timestampValue);
      final DateTime occurredAt = DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      );
      final DateTime now = _clock().toUtc();
      if (now.difference(occurredAt).abs() > allowedClockSkew) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      _prune(now);
      final String replayKey = '$fingerprint:$nonce';
      if (_seenNonces.containsKey(replayKey)) {
        throw const LmcpCallerAuthException('CALLER_REPLAYED');
      }
      final Uint8List certificateDer = base64.decode(certificateValue);
      if (certificateDer.isEmpty || certificateDer.length > 8192) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      final String actualFingerprint =
          'sha256:${sha256.convert(certificateDer)}';
      if (!_constantTimeEquals(actualFingerprint, fingerprint)) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      final String certificatePem = _certificatePem(certificateDer);
      if (!X509Utils.checkX509Signature(certificatePem)) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      final certificate = X509Utils.x509CertificateFromPem(certificatePem);
      final String? publicKeyHex =
          certificate.tbsCertificate?.subjectPublicKeyInfo.bytes;
      if (publicKeyHex == null || publicKeyHex.isEmpty) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      final Uint8List publicKeyDer = _hexBytes(publicKeyHex);
      final publicKey = CryptoUtils.ecPublicKeyFromDerBytes(publicKeyDer);
      final String canonical = <String>[
        'LMCP/2',
        'POST',
        uri.path,
        instanceId,
        timestampValue,
        nonce,
        'sha256:${sha256.convert(body)}',
      ].join('\n');
      if (!CryptoUtils.ecVerifyBase64(
        publicKey,
        Uint8List.fromList(utf8.encode(canonical)),
        signature,
        algorithm: 'SHA-256/ECDSA',
      )) {
        throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
      }
      _seenNonces[replayKey] = now;
      return LmcpVerifiedCaller(
        appId: appId,
        instanceId: instanceId,
        fingerprint: fingerprint,
      );
    } on LmcpCallerAuthException {
      rethrow;
    } on Object {
      throw const LmcpCallerAuthException('CALLER_IDENTITY_INVALID');
    }
  }

  void _prune(DateTime now) {
    _seenNonces.removeWhere(
      (_, DateTime seenAt) => now.difference(seenAt) > replayWindow,
    );
  }

  static String _certificatePem(List<int> der) {
    final String encoded = base64.encode(der);
    final Iterable<String> lines = Iterable<String>.generate(
      (encoded.length + 63) ~/ 64,
      (int index) {
        final int start = index * 64;
        final int end = (start + 64).clamp(0, encoded.length);
        return encoded.substring(start, end);
      },
    );
    return '${X509Utils.BEGIN_CERT}\n${lines.join('\n')}\n${X509Utils.END_CERT}';
  }

  static Uint8List _hexBytes(String value) {
    if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      throw const FormatException('invalid public key');
    }
    return Uint8List.fromList(<int>[
      for (int offset = 0; offset < value.length; offset += 2)
        int.parse(value.substring(offset, offset + 2), radix: 16),
    ]);
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    int difference = 0;
    for (int index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
