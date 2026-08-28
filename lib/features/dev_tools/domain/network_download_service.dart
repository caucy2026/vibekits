import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

class NetworkDownloadRequest {
  const NetworkDownloadRequest({
    required this.url,
    required this.outputDirectory,
    this.fileName = '',
    this.overwrite = false,
    this.expectedSha256 = '',
    this.timeout = const Duration(minutes: 5),
    this.maxBytes = 2 * 1024 * 1024 * 1024,
  });

  final Uri url;
  final String outputDirectory;
  final String fileName;
  final bool overwrite;
  final String expectedSha256;
  final Duration timeout;
  final int maxBytes;
}

class NetworkDownloadResult {
  const NetworkDownloadResult({
    required this.sourceUrl,
    required this.finalUrl,
    required this.outputPath,
    required this.fileName,
    required this.statusCode,
    required this.bytes,
    required this.sha256,
    required this.elapsed,
    required this.contentType,
    required this.artifactType,
  });

  final String sourceUrl;
  final String finalUrl;
  final String outputPath;
  final String fileName;
  final int statusCode;
  final int bytes;
  final String sha256;
  final Duration elapsed;
  final String contentType;
  final String artifactType;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceUrl': sourceUrl,
    'finalUrl': finalUrl,
    'outputPath': outputPath,
    'fileName': fileName,
    'statusCode': statusCode,
    'bytes': bytes,
    'sha256': sha256,
    'contentType': contentType,
    'artifactType': artifactType,
    'elapsedMs': elapsed.inMilliseconds,
    'evidenceSource': 'http-stream+sha256',
  };
}

/// Streams an HTTP(S) artifact into a writable download directory.
///
/// A partial file is never exposed as the destination. APK downloads must
/// have a ZIP signature so an HTML error page cannot be handed to ADB.
class NetworkDownloadService {
  const NetworkDownloadService();

  Future<NetworkDownloadResult> download(NetworkDownloadRequest request) async {
    if (!request.url.hasScheme ||
        !<String>{'http', 'https'}.contains(request.url.scheme.toLowerCase()) ||
        request.url.host.trim().isEmpty) {
      throw const FormatException('只允许带主机名的 HTTP/HTTPS URL');
    }
    if (request.maxBytes <= 0) throw const FormatException('maxBytes 必须大于 0');

    final Directory directory = Directory(request.outputDirectory).absolute;
    await directory.create(recursive: true);
    final String fileName = _safeFileName(request.fileName, request.url);
    final File destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    if (await destination.exists() && !request.overwrite) {
      throw FileSystemException(
        '目标文件已存在；如需替换请设置 overwrite=true',
        destination.path,
      );
    }

    final File partial = File(
      '${destination.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    final HttpClient client = HttpClient()
      ..connectionTimeout = Duration(
        seconds: request.timeout.inSeconds.clamp(5, 30),
      )
      ..userAgent = 'Vibekits Harness Downloader';
    final Stopwatch stopwatch = Stopwatch()..start();
    IOSink? sink;
    try {
      final HttpClientRequest httpRequest = await client
          .getUrl(request.url)
          .timeout(request.timeout);
      httpRequest.followRedirects = true;
      httpRequest.maxRedirects = 5;
      final HttpClientResponse response = await httpRequest.close().timeout(
        request.timeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '下载失败：HTTP ${response.statusCode}',
          uri: request.url,
        );
      }
      if (response.contentLength > request.maxBytes) {
        throw StateError(
          '文件大小 ${response.contentLength} 超过上限 ${request.maxBytes}',
        );
      }

      sink = partial.openWrite(mode: FileMode.writeOnly);
      int received = 0;
      await for (final List<int> chunk in response.timeout(request.timeout)) {
        received += chunk.length;
        if (received > request.maxBytes) {
          throw StateError('下载内容超过上限 ${request.maxBytes} 字节');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received == 0) throw const FormatException('服务器返回了空文件');
      final String digest = (await crypto.sha256.bind(partial.openRead()).first)
          .toString();
      final String expected = request.expectedSha256.trim().toLowerCase();
      if (expected.isNotEmpty &&
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
        throw const FormatException('expectedSha256 必须是 64 位十六进制');
      }
      if (expected.isNotEmpty && digest != expected) {
        throw StateError('SHA-256 校验失败：期望 $expected，实际 $digest');
      }

      String artifactType = 'binary';
      if (fileName.toLowerCase().endsWith('.apk')) {
        final List<int> signature = await partial
            .openRead(0, 4)
            .fold<List<int>>(
              <int>[],
              (List<int> value, List<int> chunk) => value..addAll(chunk),
            );
        if (signature.length < 4 ||
            signature[0] != 0x50 ||
            signature[1] != 0x4b ||
            signature[2] != 0x03 ||
            signature[3] != 0x04) {
          throw const FormatException('APK 校验失败：文件不是有效的 ZIP/APK 容器');
        }
        artifactType = 'android-apk';
      }

      if (await destination.exists()) await destination.delete();
      final File completed = await partial.rename(destination.path);
      stopwatch.stop();
      final Uri finalUrl = response.redirects.isEmpty
          ? request.url
          : response.redirects.last.location;
      return NetworkDownloadResult(
        sourceUrl: request.url.toString(),
        finalUrl: finalUrl.toString(),
        outputPath: completed.absolute.path,
        fileName: fileName,
        statusCode: response.statusCode,
        bytes: received,
        sha256: digest,
        elapsed: stopwatch.elapsed,
        contentType: response.headers.contentType?.mimeType ?? '',
        artifactType: artifactType,
      );
    } finally {
      client.close(force: true);
      if (sink != null) await sink.close();
      if (await partial.exists()) await partial.delete();
    }
  }

  static String _safeFileName(String requested, Uri url) {
    String value = requested.trim();
    if (value.isEmpty) {
      value = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
      try {
        value = Uri.decodeComponent(value);
      } on Object {
        // Keep the encoded path segment when it cannot be decoded.
      }
    }
    value = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
    value = value.replaceAll(RegExp(r'[. ]+$'), '');
    if (value.isEmpty || value == '.' || value == '..') {
      value = 'download-${DateTime.now().millisecondsSinceEpoch}.bin';
    }
    if (value.length > 180) value = value.substring(value.length - 180);
    return value;
  }
}
