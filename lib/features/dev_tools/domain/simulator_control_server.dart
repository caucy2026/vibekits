import 'dart:convert';
import 'dart:io';

import 'harness_system_ssh_service.dart';

typedef SimulatorCallerAuthorizer = Future<bool> Function(String callerId);
typedef SimulatorSshIdentityLoader = Future<Map<String, Object?>> Function();
typedef SimulatorSshKeyStatusLoader =
    Future<Map<String, Object?>> Function({
      required String peerId,
      required String publicKey,
    });
typedef SimulatorSshKeyAuthorizer =
    Future<Map<String, Object?>> Function({
      required String peerId,
      required String publicKey,
    });

/// Loopback-only control plane owned by remote simulation.
///
/// It deliberately has no Harness or MCP dependency. The native carrier is
/// the authentication boundary and forwards this endpoint only after the
/// target owner enables remote simulation.
final class SimulatorControlServer {
  SimulatorControlServer._(
    this._server,
    this._authorizeCaller,
    this._loadIdentity,
    this._loadKeyStatus,
    this._authorizeKey,
  );

  static const int portNumber = 32148;
  static const String sshBootstrapPath = '/simulator/ssh-bootstrap';
  static const int _maxRequestBytes = 1024 * 1024;

  final HttpServer _server;
  final SimulatorCallerAuthorizer _authorizeCaller;
  final SimulatorSshIdentityLoader _loadIdentity;
  final SimulatorSshKeyStatusLoader _loadKeyStatus;
  final SimulatorSshKeyAuthorizer _authorizeKey;

  int get port => _server.port;

  static Future<SimulatorControlServer> start({
    required SimulatorCallerAuthorizer authorizeCaller,
    SimulatorSshIdentityLoader? loadIdentity,
    SimulatorSshKeyStatusLoader? loadKeyStatus,
    SimulatorSshKeyAuthorizer? authorizeKey,
    InternetAddress? bindAddress,
    int port = portNumber,
  }) async {
    final server = await HttpServer.bind(
      bindAddress ?? InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    final result = SimulatorControlServer._(
      server,
      authorizeCaller,
      loadIdentity ?? HarnessSystemSshService.identity,
      loadKeyStatus ?? HarnessSystemSshService.publicKeyStatus,
      authorizeKey ?? HarnessSystemSshService.authorizePublicKey,
    );
    server.listen(result._handle, onError: (_) {});
    return result;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    final remoteAddress = request.connectionInfo?.remoteAddress.address ?? '';
    if (remoteAddress != '127.0.0.1' ||
        request.method != 'POST' ||
        request.uri.path != sshBootstrapPath) {
      await _json(request.response, HttpStatus.notFound, const {
        'ok': false,
        'error': 'not_found',
      });
      return;
    }
    try {
      final payload = await _readObject(request);
      final callerId = '${payload['callerId'] ?? ''}'.trim();
      final headerCallerId =
          request.headers.value('x-vibekits-caller-id')?.trim() ?? '';
      final publicKey = '${payload['publicKey'] ?? ''}'.trim();
      if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(callerId) ||
          headerCallerId != callerId) {
        throw const FormatException('控制端设备 ID 无效');
      }
      if (!await _authorizeCaller(callerId)) {
        await _json(request.response, HttpStatus.forbidden, const {
          'ok': false,
          'error': 'simulator_peer_not_authenticated',
        });
        return;
      }
      // Android exposes the authenticated MCP endpoint but has no system SSH.
      // Tell the desktop controller explicitly so it opens the MCP tunnel
      // without treating a missing SSH daemon as a transport failure.
      if (Platform.isAndroid) {
        await _json(request.response, HttpStatus.ok, {
          'ok': true,
          'data': {
            'platform': 'android',
            'sshSupported': false,
            'authorized': true,
            'peerId': callerId,
          },
        });
        return;
      }
      var status = await _loadKeyStatus(peerId: callerId, publicKey: publicKey);
      if (status['authorized'] != true) {
        await _authorizeKey(peerId: callerId, publicKey: publicKey);
        status = await _loadKeyStatus(peerId: callerId, publicKey: publicKey);
      }
      if (status['authorized'] != true) {
        throw StateError('SSH 公钥授权未持久化');
      }
      final identity = await _loadIdentity();
      await _json(request.response, HttpStatus.ok, {
        'ok': true,
        'data': {...identity, 'authorized': true, 'peerId': callerId},
      });
    } on FormatException catch (error) {
      await _json(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': '$error',
      });
    } on Object catch (error) {
      await _json(request.response, HttpStatus.internalServerError, {
        'ok': false,
        'error': '$error',
      });
    }
  }

  static Future<Map<String, Object?>> _readObject(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > _maxRequestBytes) {
        throw const FormatException('控制请求超过 1 MiB');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('控制请求不是对象');
    return Map<String, Object?>.from(decoded);
  }

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> value,
  ) async {
    response.statusCode = status;
    response.write(jsonEncode(value));
    await response.close();
  }
}
