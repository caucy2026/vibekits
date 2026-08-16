import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ApiRequestSpec {
  const ApiRequestSpec({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body = '',
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 5 * 1024 * 1024,
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;
  final Duration timeout;
  final int maxResponseBytes;

  Uri validate() {
    const Set<String> methods = <String>{
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'HEAD',
      'OPTIONS',
    };
    if (!methods.contains(method.toUpperCase())) {
      throw const FormatException('不支持的 HTTP 方法');
    }
    final Uri uri = Uri.tryParse(url.trim()) ?? Uri();
    if (!uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('URL 必须是完整的 http:// 或 https:// 地址');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('请不要把账号或密码写在 URL 中');
    }
    if (timeout < const Duration(seconds: 1) ||
        timeout > const Duration(minutes: 2)) {
      throw const FormatException('超时必须在 1 到 120 秒之间');
    }
    if (maxResponseBytes < 1024 || maxResponseBytes > 50 * 1024 * 1024) {
      throw const FormatException('响应上限必须在 1 KiB 到 50 MiB 之间');
    }
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.trim().isEmpty ||
          header.key.codeUnits.any(_isControl) ||
          header.value.codeUnits.any(_isControlExceptTab)) {
        throw FormatException('请求头 ${header.key} 含非法控制字符');
      }
    }
    return uri;
  }

  static bool _isControl(int unit) => unit <= 0x20 || unit == 0x7f;
  static bool _isControlExceptTab(int unit) =>
      (unit < 0x20 && unit != 0x09) || unit == 0x7f;
}

class ApiResponseData {
  const ApiResponseData({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    required this.bodyBytes,
    required this.elapsed,
    required this.finalUrl,
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;
  final String body;
  final int bodyBytes;
  final Duration elapsed;
  final Uri finalUrl;
}

class ApiRequestCancellation {
  bool _cancelled = false;
  HttpClient? _client;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}

abstract final class ApiRequestService {
  static Future<ApiResponseData> execute(
    ApiRequestSpec spec, {
    ApiRequestCancellation? cancellation,
  }) async {
    final Uri uri = spec.validate();
    if (cancellation?.isCancelled == true) {
      throw const ApiRequestCancelled();
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = spec.timeout
      ..idleTimeout = spec.timeout;
    cancellation?._client = client;
    try {
      final HttpClientRequest request = await client
          .openUrl(spec.method.toUpperCase(), uri)
          .timeout(spec.timeout);
      request
        ..followRedirects = true
        ..maxRedirects = 5;
      for (final MapEntry<String, String> header in spec.headers.entries) {
        request.headers.set(header.key, header.value, preserveHeaderCase: true);
      }
      if (spec.body.isNotEmpty && spec.method.toUpperCase() != 'GET') {
        final List<int> encoded = utf8.encode(spec.body);
        request.contentLength = encoded.length;
        request.add(encoded);
      }
      final HttpClientResponse response = await request.close().timeout(
        spec.timeout,
      );
      final BytesBuilder bytes = BytesBuilder(copy: false);
      int received = 0;
      await for (final List<int> chunk in response.timeout(spec.timeout)) {
        if (cancellation?.isCancelled == true) {
          throw const ApiRequestCancelled();
        }
        received += chunk.length;
        if (received > spec.maxResponseBytes) {
          throw FormatException('响应超过 ${spec.maxResponseBytes} 字节上限，已停止读取');
        }
        bytes.add(chunk);
      }
      final Uint8List raw = bytes.takeBytes();
      final Map<String, List<String>> headers = <String, List<String>>{};
      response.headers.forEach((String name, List<String> values) {
        headers[name] = List<String>.unmodifiable(values);
      });
      stopwatch.stop();
      return ApiResponseData(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: Map<String, List<String>>.unmodifiable(headers),
        body: _decodeBody(raw, response.headers.contentType),
        bodyBytes: raw.length,
        elapsed: stopwatch.elapsed,
        finalUrl: response.redirects.isEmpty
            ? uri
            : response.redirects.last.location,
      );
    } on SocketException catch (error) {
      if (cancellation?.isCancelled == true) {
        throw const ApiRequestCancelled();
      }
      throw FormatException('网络连接失败：${error.message}');
    } on TimeoutException {
      throw FormatException('请求超过 ${spec.timeout.inSeconds} 秒，已停止');
    } finally {
      cancellation?._client = null;
      client.close(force: true);
    }
  }

  static String _decodeBody(Uint8List bytes, ContentType? contentType) {
    final String? charset = contentType?.charset?.toLowerCase();
    if (charset == 'latin1' || charset == 'iso-8859-1') {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class ApiRequestCancelled implements Exception {
  const ApiRequestCancelled();

  @override
  String toString() => '请求已取消';
}
