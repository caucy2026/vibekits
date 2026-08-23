import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef LanAddressLister = Future<List<NetworkInterface>> Function();

/// Receives one Harness API Key from a short-lived page on the trusted LAN.
///
/// The QR contains only a private-network URL and a random one-time token. The
/// Key is accepted once, never logged, and the listener is closed immediately.
final class LanHarnessKeyReceiver {
  LanHarnessKeyReceiver._(
    this._server,
    this.pageUri,
    this.expiresAt,
    this._token,
  ) {
    _subscription = _server.listen(_handleRequest);
    _expiryTimer = Timer(expiresAt.difference(DateTime.now()), () {
      if (!_keyCompleter.isCompleted) {
        _keyCompleter.completeError(TimeoutException('二维码已过期，请重新生成'));
      }
      unawaited(close());
    });
  }

  final HttpServer _server;
  final Uri pageUri;
  final DateTime expiresAt;
  final String _token;
  final Completer<String> _keyCompleter = Completer<String>();
  late final StreamSubscription<HttpRequest> _subscription;
  late final Timer _expiryTimer;
  bool _closed = false;

  Future<String> get keyReceived => _keyCompleter.future;

  static Future<LanHarnessKeyReceiver> start({
    Duration lifetime = const Duration(minutes: 5),
    LanAddressLister? listInterfaces,
    InternetAddress? bindAddress,
    InternetAddress? advertisedAddress,
  }) async {
    final InternetAddress advertised =
        advertisedAddress ?? await _findPrivateAddress(listInterfaces);
    final HttpServer server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
      shared: false,
    );
    final String token = _randomToken();
    final Uri uri = Uri(
      scheme: 'http',
      host: advertised.address,
      port: server.port,
      path: '/harness-key',
      queryParameters: <String, String>{'token': token},
    );
    return LanHarnessKeyReceiver._(
      server,
      uri,
      DateTime.now().add(lifetime),
      token,
    );
  }

  static Future<InternetAddress> _findPrivateAddress(
    LanAddressLister? listInterfaces,
  ) async {
    final List<NetworkInterface> interfaces = listInterfaces == null
        ? await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
            includeLinkLocal: false,
          )
        : await listInterfaces();
    final List<(bool, InternetAddress)> candidates =
        <(bool, InternetAddress)>[];
    for (final NetworkInterface interface in interfaces) {
      for (final InternetAddress address in interface.addresses) {
        if (_isPrivateIpv4(address.address)) {
          final String name = interface.name.toLowerCase();
          candidates.add((
            name.contains('wlan') || name.contains('wifi'),
            address,
          ));
        }
      }
    }
    if (candidates.isEmpty) {
      throw StateError('没有找到可用的局域网 IPv4，请先连接 Wi-Fi');
    }
    candidates.sort((
      (bool, InternetAddress) left,
      (bool, InternetAddress) right,
    ) {
      return (right.$1 ? 1 : 0).compareTo(left.$1 ? 1 : 0);
    });
    return candidates.first.$2;
  }

  static bool _isPrivateIpv4(String value) {
    final List<int>? parts = _ipv4Parts(value);
    if (parts == null) return false;
    return parts[0] == 10 ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
        (parts[0] == 192 && parts[1] == 168);
  }

  static List<int>? _ipv4Parts(String value) {
    final List<String> raw = value.split('.');
    if (raw.length != 4) return null;
    final List<int> parts = <int>[];
    for (final String item in raw) {
      final int? number = int.tryParse(item);
      if (number == null || number < 0 || number > 255) return null;
      parts.add(number);
    }
    return parts;
  }

  static String _randomToken() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final HttpResponse response = request.response;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'",
      );
    if (_closed ||
        request.uri.path != '/harness-key' ||
        request.uri.queryParameters['token'] != _token) {
      await _reply(
        response,
        HttpStatus.notFound,
        'text/plain; charset=utf-8',
        '链接无效或已过期',
      );
      return;
    }
    if (request.method == 'GET') {
      await _reply(
        response,
        HttpStatus.ok,
        'text/html; charset=utf-8',
        _page(),
      );
      return;
    }
    if (request.method != 'POST') {
      response.headers.set(HttpHeaders.allowHeader, 'GET, POST');
      await _reply(
        response,
        HttpStatus.methodNotAllowed,
        'text/plain; charset=utf-8',
        '不支持此操作',
      );
      return;
    }
    try {
      final String body = await _readBounded(request, 8192);
      final Map<String, String> fields = Uri.splitQueryString(
        body,
        encoding: utf8,
      );
      final String key = (fields['apiKey'] ?? '').trim();
      if (key.length < 8 ||
          key.length > 4096 ||
          key.contains(RegExp(r'[\r\n]'))) {
        await _reply(
          response,
          HttpStatus.badRequest,
          'text/html; charset=utf-8',
          _resultPage('Key 格式无效，请返回重试', success: false),
        );
        return;
      }
      await _reply(
        response,
        HttpStatus.ok,
        'text/html; charset=utf-8',
        _resultPage('已安全发送到 Vibekits，可以关闭此页面', success: true),
      );
      if (!_keyCompleter.isCompleted) _keyCompleter.complete(key);
      unawaited(close());
    } on FormatException catch (error) {
      await _reply(
        response,
        HttpStatus.badRequest,
        'text/plain; charset=utf-8',
        error.message,
      );
    }
  }

  static Future<String> _readBounded(
    HttpRequest request,
    int maximumBytes,
  ) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    int length = 0;
    await for (final List<int> chunk in request) {
      length += chunk.length;
      if (length > maximumBytes) throw const FormatException('提交内容过大');
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  static Future<void> _reply(
    HttpResponse response,
    int status,
    String contentType,
    String body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.parse(contentType);
    response.write(body);
    await response.close();
  }

  String _page() =>
      '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vibekits Harness 登录</title><style>
body{font-family:system-ui,sans-serif;background:#f5f5f3;margin:0;padding:24px;color:#20211f}.card{max-width:460px;margin:8vh auto;background:white;border:1px solid #ddd;border-radius:18px;padding:26px;box-shadow:0 10px 40px #0001}h1{font-size:24px;margin:0 0 8px}p{color:#666;line-height:1.6}label{display:block;font-weight:650;margin:22px 0 8px}input{box-sizing:border-box;width:100%;font-size:17px;padding:14px;border:1px solid #bbb;border-radius:12px}button{width:100%;margin-top:16px;padding:14px;border:0;border-radius:12px;background:#20211f;color:white;font-size:17px;font-weight:650}.tip{font-size:13px;color:#777}</style></head>
<body><main class="card"><h1>连接 Harness</h1><p>在这里粘贴 DeepSeek API Key，确认后会写入当前安卓设备。</p>
<form method="post" action="${pageUri.path}?token=$_token"><label for="key">API Key</label><input id="key" name="apiKey" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" required autofocus><button type="submit">确认并发送</button></form>
<p class="tip">仅限可信局域网使用。二维码不包含 Key，页面 5 分钟后自动失效。</p></main></body></html>''';

  static String _resultPage(String message, {required bool success}) =>
      '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Vibekits</title><style>body{font-family:system-ui;background:#f5f5f3;padding:24px;color:#20211f}.card{max-width:460px;margin:14vh auto;background:#fff;border-radius:18px;padding:30px;text-align:center}.icon{font-size:46px;color:${success ? '#198754' : '#c0392b'}}</style></head><body><main class="card"><div class="icon">${success ? '✓' : '!'}</div><h2>${success ? '登录信息已发送' : '发送失败'}</h2><p>$message</p></main></body></html>''';

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiryTimer.cancel();
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
