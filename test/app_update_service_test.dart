import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_update_service.dart';

void main() {
  for (final String os in <String>['macos', 'windows']) {
    test('$os 主程序不会检查、提示、下载或安装自身更新', () async {
      var requestCount = 0;
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((HttpRequest request) async {
        requestCount++;
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      final AppUpdateService service = AppUpdateService(
        apiRoot: 'http://${server.address.host}:${server.port}',
        platformOverride: os,
      );

      await service.start();
      await service.check();
      await service.downloadAndInstall();

      expect(requestCount, 0);
      expect(service.snapshot.value.phase, AppUpdatePhase.idle);
      service.dispose();
      await server.close(force: true);
    });
  }
}
