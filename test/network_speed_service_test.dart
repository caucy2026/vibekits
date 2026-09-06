import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/network_speed_service.dart';

void main() {
  late HttpServer server;
  late Uri endpoint;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://${server.address.address}:${server.port}');
    server.listen((HttpRequest request) async {
      if (request.uri.path == '/__down') {
        final int bytes = int.parse(request.uri.queryParameters['bytes']!);
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = bytes;
        const List<int> block = <int>[0, 1, 2, 3, 4, 5, 6, 7];
        int written = 0;
        while (written < bytes) {
          final int remaining = bytes - written;
          final int length = remaining < block.length
              ? remaining
              : block.length;
          request.response.add(block.take(length).toList());
          written += length;
        }
        await request.response.close();
        return;
      }
      if (request.uri.path == '/__up') {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test(
    'measures latency, download and upload against a compatible server',
    () async {
      final List<NetworkSpeedPhase> phases = <NetworkSpeedPhase>[];
      final NetworkSpeedResult result = await NetworkSpeedService(
        server: endpoint,
        latencySamples: 3,
        downloadSizes: const <int>[1024, 4096],
        uploadSizes: const <int>[1024, 4096],
        timeout: const Duration(seconds: 5),
      ).run(onProgress: (progress) => phases.add(progress.phase));

      expect(result.downloadBytes, 5120);
      expect(result.uploadBytes, 5120);
      expect(result.latencyMs, greaterThanOrEqualTo(0));
      expect(result.downloadMbps, greaterThan(0));
      expect(result.uploadMbps, greaterThan(0));
      expect(phases, containsAll(NetworkSpeedPhase.values));
      expect(result.toJson()['method'], 'progressive-p90');
    },
  );

  test('cancellation closes an in-progress test', () async {
    final NetworkSpeedCancellation cancellation = NetworkSpeedCancellation();
    final Future<NetworkSpeedResult> future =
        NetworkSpeedService(
          server: endpoint,
          latencySamples: 3,
          downloadSizes: const <int>[1024],
          uploadSizes: const <int>[1024],
        ).run(
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.phase == NetworkSpeedPhase.latency) {
              cancellation.cancel();
            }
          },
        );

    await expectLater(future, throwsA(isA<NetworkSpeedCancelled>()));
  });
}
