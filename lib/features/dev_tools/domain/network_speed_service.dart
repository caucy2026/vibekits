import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

enum NetworkSpeedPhase { latency, download, upload, complete }

class NetworkSpeedProgress {
  const NetworkSpeedProgress({
    required this.phase,
    required this.completedUnits,
    required this.totalUnits,
    required this.currentMbps,
    required this.detail,
  });

  final NetworkSpeedPhase phase;
  final int completedUnits;
  final int totalUnits;
  final double currentMbps;
  final String detail;

  double get fraction =>
      totalUnits == 0 ? 0 : (completedUnits / totalUnits).clamp(0.0, 1.0);
}

class NetworkSpeedResult {
  const NetworkSpeedResult({
    required this.server,
    required this.latencyMs,
    required this.jitterMs,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.elapsed,
  });

  final Uri server;
  final double latencyMs;
  final double jitterMs;
  final double downloadMbps;
  final double uploadMbps;
  final int downloadBytes;
  final int uploadBytes;
  final Duration elapsed;

  Map<String, Object?> toJson() => <String, Object?>{
    'server': server.origin,
    'latencyMs': double.parse(latencyMs.toStringAsFixed(2)),
    'jitterMs': double.parse(jitterMs.toStringAsFixed(2)),
    'downloadMbps': double.parse(downloadMbps.toStringAsFixed(2)),
    'uploadMbps': double.parse(uploadMbps.toStringAsFixed(2)),
    'downloadBytes': downloadBytes,
    'uploadBytes': uploadBytes,
    'elapsedMs': elapsed.inMilliseconds,
    'method': 'progressive-p90',
  };
}

class NetworkSpeedCancellation {
  bool _cancelled = false;
  void Function()? _abort;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _abort?.call();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const NetworkSpeedCancelled();
  }
}

class NetworkSpeedCancelled implements Exception {
  const NetworkSpeedCancelled();
  @override
  String toString() => '测速已停止';
}

/// Measures Internet-path latency, downstream and upstream throughput.
///
/// The default endpoint follows Cloudflare's public speed-test contract. Small
/// samples warm the route before progressively larger samples. The reported
/// throughput is p90 rather than a single transient peak.
class NetworkSpeedService {
  NetworkSpeedService({
    Uri? server,
    this.latencySamples = 5,
    this.downloadSizes = const <int>[100000, 1000000, 5000000],
    this.uploadSizes = const <int>[100000, 500000, 2000000],
    this.timeout = const Duration(seconds: 20),
  }) : server = server ?? Uri.https('speed.cloudflare.com', '');

  final Uri server;
  final int latencySamples;
  final List<int> downloadSizes;
  final List<int> uploadSizes;
  final Duration timeout;

  Future<NetworkSpeedResult> run({
    NetworkSpeedCancellation? cancellation,
    void Function(NetworkSpeedProgress progress)? onProgress,
  }) async {
    if (server.scheme != 'https' && server.scheme != 'http') {
      throw const FormatException('测速服务器必须使用 HTTP 或 HTTPS');
    }
    if (latencySamples < 2 || downloadSizes.isEmpty || uploadSizes.isEmpty) {
      throw const FormatException('测速采样配置不完整');
    }
    final NetworkSpeedCancellation token =
        cancellation ?? NetworkSpeedCancellation();
    final HttpClient client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'VibeKits Network Speed Test/1';
    token._abort = () => client.close(force: true);
    final Stopwatch total = Stopwatch()..start();
    try {
      final List<double> latencies = <double>[];
      for (int index = 0; index < latencySamples; index++) {
        token.throwIfCancelled();
        final Stopwatch watch = Stopwatch()..start();
        final Uri uri = _downloadUri(0, index);
        final HttpClientResponse response = await (await client.getUrl(
          uri,
        )).close().timeout(timeout);
        await response.drain<void>().timeout(timeout);
        _requireSuccess(response, uri);
        watch.stop();
        latencies.add(watch.elapsedMicroseconds / 1000);
        onProgress?.call(
          NetworkSpeedProgress(
            phase: NetworkSpeedPhase.latency,
            completedUnits: index + 1,
            totalUnits: latencySamples,
            currentMbps: 0,
            detail: '延迟采样 ${index + 1}/$latencySamples',
          ),
        );
      }

      final _TransferSummary down = await _measureDownload(
        client,
        token,
        onProgress,
      );
      final _TransferSummary up = await _measureUpload(
        client,
        token,
        onProgress,
      );
      total.stop();
      onProgress?.call(
        const NetworkSpeedProgress(
          phase: NetworkSpeedPhase.complete,
          completedUnits: 1,
          totalUnits: 1,
          currentMbps: 0,
          detail: '测速完成',
        ),
      );
      final double median = _percentile(latencies, 0.5);
      final List<double> deviations = latencies
          .map((double value) => (value - median).abs())
          .toList();
      return NetworkSpeedResult(
        server: server,
        latencyMs: median,
        jitterMs: _percentile(deviations, 0.5),
        downloadMbps: _percentile(down.mbps, 0.9),
        uploadMbps: _percentile(up.mbps, 0.9),
        downloadBytes: down.bytes,
        uploadBytes: up.bytes,
        elapsed: total.elapsed,
      );
    } on NetworkSpeedCancelled {
      rethrow;
    } on Object {
      token.throwIfCancelled();
      rethrow;
    } finally {
      token._abort = null;
      client.close(force: true);
    }
  }

  Future<_TransferSummary> _measureDownload(
    HttpClient client,
    NetworkSpeedCancellation token,
    void Function(NetworkSpeedProgress progress)? onProgress,
  ) async {
    final List<double> rates = <double>[];
    int totalBytes = 0;
    for (int index = 0; index < downloadSizes.length; index++) {
      token.throwIfCancelled();
      final int expected = downloadSizes[index];
      final Uri uri = _downloadUri(expected, latencySamples + index);
      final Stopwatch watch = Stopwatch()..start();
      final HttpClientResponse response = await (await client.getUrl(
        uri,
      )).close().timeout(timeout);
      _requireSuccess(response, uri);
      int bytes = 0;
      await for (final List<int> chunk in response.timeout(timeout)) {
        token.throwIfCancelled();
        bytes += chunk.length;
        final double mbps = _mbps(bytes, watch.elapsedMicroseconds);
        onProgress?.call(
          NetworkSpeedProgress(
            phase: NetworkSpeedPhase.download,
            completedUnits: index,
            totalUnits: downloadSizes.length,
            currentMbps: mbps,
            detail: '下载采样 ${index + 1}/${downloadSizes.length}',
          ),
        );
      }
      watch.stop();
      if (bytes <= 0) throw StateError('测速服务器返回空下载数据');
      totalBytes += bytes;
      rates.add(_mbps(bytes, watch.elapsedMicroseconds));
      onProgress?.call(
        NetworkSpeedProgress(
          phase: NetworkSpeedPhase.download,
          completedUnits: index + 1,
          totalUnits: downloadSizes.length,
          currentMbps: rates.last,
          detail: '下载采样 ${index + 1}/${downloadSizes.length}',
        ),
      );
    }
    return _TransferSummary(rates, totalBytes);
  }

  Future<_TransferSummary> _measureUpload(
    HttpClient client,
    NetworkSpeedCancellation token,
    void Function(NetworkSpeedProgress progress)? onProgress,
  ) async {
    final List<double> rates = <double>[];
    int totalBytes = 0;
    final Uint8List block = Uint8List(64 * 1024);
    for (int index = 0; index < uploadSizes.length; index++) {
      token.throwIfCancelled();
      final int size = uploadSizes[index];
      final Uri uri = server.resolve('/__up');
      final Stopwatch watch = Stopwatch()..start();
      final HttpClientRequest request = await client.postUrl(uri);
      request.headers.contentType = ContentType.binary;
      request.contentLength = size;
      int sent = 0;
      while (sent < size) {
        token.throwIfCancelled();
        final int length = math.min(block.length, size - sent);
        request.add(length == block.length ? block : block.sublist(0, length));
        sent += length;
        onProgress?.call(
          NetworkSpeedProgress(
            phase: NetworkSpeedPhase.upload,
            completedUnits: index,
            totalUnits: uploadSizes.length,
            currentMbps: _mbps(sent, watch.elapsedMicroseconds),
            detail: '上传采样 ${index + 1}/${uploadSizes.length}',
          ),
        );
      }
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      await response.drain<void>().timeout(timeout);
      _requireSuccess(response, uri);
      watch.stop();
      totalBytes += sent;
      rates.add(_mbps(sent, watch.elapsedMicroseconds));
      onProgress?.call(
        NetworkSpeedProgress(
          phase: NetworkSpeedPhase.upload,
          completedUnits: index + 1,
          totalUnits: uploadSizes.length,
          currentMbps: rates.last,
          detail: '上传采样 ${index + 1}/${uploadSizes.length}',
        ),
      );
    }
    return _TransferSummary(rates, totalBytes);
  }

  Uri _downloadUri(int bytes, int nonce) => server
      .resolve('/__down')
      .replace(
        queryParameters: <String, String>{
          'bytes': '$bytes',
          'v': '${DateTime.now().microsecondsSinceEpoch}-$nonce',
        },
      );

  static void _requireSuccess(HttpClientResponse response, Uri uri) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('测速请求失败：HTTP ${response.statusCode}', uri: uri);
    }
  }

  static double _mbps(int bytes, int microseconds) {
    if (microseconds <= 0) return 0;
    return bytes * 8 / microseconds;
  }

  static double _percentile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    final List<double> sorted = List<double>.of(values)..sort();
    final double position = (sorted.length - 1) * percentile;
    final int lower = position.floor();
    final int upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }
}

class _TransferSummary {
  const _TransferSummary(this.mbps, this.bytes);
  final List<double> mbps;
  final int bytes;
}
