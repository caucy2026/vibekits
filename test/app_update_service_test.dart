import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_update_service.dart';

void main() {
  for (final String os in <String>['macos', 'windows']) {
    test('$os 启动自动更新已关闭且不会请求更新接口', () async {
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

      expect(requestCount, 0);
      expect(service.snapshot.value.phase, AppUpdatePhase.idle);
      service.dispose();
      await server.close(force: true);
    });
  }

  test('macOS 检查更新携带包名、整数版本和系统隔离参数', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    late final Uri requestUri;
    server.listen((HttpRequest request) async {
      requestUri = request.uri;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'status': 200,
          'msg': 'success',
          'data': <String, Object?>{
            'has_update': false,
            'package_name': AppUpdateService.packageName,
            'os_type': 'macos',
          },
        }),
      );
      await request.response.close();
    });
    final AppUpdateService service = AppUpdateService(
      apiRoot: 'http://${server.address.host}:${server.port}',
      platformOverride: 'macos',
    );
    await service.check();
    expect(requestUri.path, '/api/store/update/check');
    expect(
      requestUri.queryParameters['package_name'],
      AppUpdateService.packageName,
    );
    expect(requestUri.queryParameters['version_code'], '2161');
    expect(requestUri.queryParameters['os'], 'macos');
    expect(service.snapshot.value.phase, AppUpdatePhase.current);
    service.dispose();
    await server.close(force: true);
  });

  test('拒绝非 HTTPS 的更新安装包', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'status': 200,
          'msg': 'success',
          'data': <String, Object?>{
            'has_update': true,
            'package_name': AppUpdateService.packageName,
            'os_type': 'windows',
            'version_name': '9.9.9',
            'version_code': 9999,
            'download_url': 'http://example.test/update.exe',
            'sha256': List<String>.filled(64, 'a').join(),
            'file_size_bytes': 12,
          },
        }),
      );
      await request.response.close();
    });
    final AppUpdateService service = AppUpdateService(
      apiRoot: 'http://${server.address.host}:${server.port}',
      platformOverride: 'windows',
    );
    await service.check();
    expect(service.snapshot.value.phase, AppUpdatePhase.failed);
    expect(service.snapshot.value.message, '暂时无法检查更新，请稍后重试');
    expect(service.snapshot.value.message, isNot(contains('FormatException')));
    service.dispose();
    await server.close(force: true);
  });

  test('服务端错误不会把内部异常文本暴露给界面', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'status': 400,
          'msg': "Unknown column 'a.names' in 'field list'",
          'data': null,
        }),
      );
      await request.response.close();
    });
    final AppUpdateService service = AppUpdateService(
      apiRoot: 'http://${server.address.host}:${server.port}',
      platformOverride: 'windows',
    );
    await service.check();
    expect(service.snapshot.value.phase, AppUpdatePhase.failed);
    expect(service.snapshot.value.message, '暂时无法检查更新，请稍后重试');
    expect(service.snapshot.value.message, isNot(contains('Unknown column')));
    service.dispose();
    await server.close(force: true);
  });

  for (final String os in <String>['macos', 'windows']) {
    test('$os 服务端误报同版本有更新时仍判定为最新版', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'status': 200,
            'data': <String, Object?>{
              'has_update': true,
              'package_name': AppUpdateService.packageName,
              'os_type': os,
              'version_name': '1.9.0-dev.161',
              'version_code': 2161,
              'download_url': os == 'macos'
                  ? 'https://example.test/Vibekits.zip'
                  : 'https://example.test/Vibekits.exe',
              'sha256': List<String>.filled(64, 'a').join(),
              'file_size_bytes': 12,
            },
          }),
        );
        await request.response.close();
      });
      final AppUpdateService service = AppUpdateService(
        apiRoot: 'http://${server.address.host}:${server.port}',
        platformOverride: os,
      );
      await service.check();

      expect(service.snapshot.value.phase, AppUpdatePhase.current);
      expect(service.snapshot.value.message, '当前已是最新版本');
      service.dispose();
      await server.close(force: true);
    });
  }
}
