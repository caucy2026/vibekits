import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mihomo_controller_service.dart';

void main() {
  test('控制器读取实时状态并切换模式和节点', () async {
    final List<String> mutations = <String>[];
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> serving = () async {
      await for (final HttpRequest request in server) {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer key',
        );
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/configs') {
          request.response.write(jsonEncode(<String, Object>{'mode': 'rule'}));
        } else if (request.method == 'GET' && request.uri.path == '/proxies') {
          request.response.write(
            jsonEncode(<String, Object>{
              'proxies': <String, Object>{
                '自动选择': <String, Object>{
                  'type': 'Selector',
                  'now': '节点 A',
                  'all': <String>['节点 A', '节点 B'],
                },
              },
            }),
          );
        } else if (request.method == 'GET' &&
            request.uri.path.endsWith('/delay')) {
          expect(request.uri.queryParameters['timeout'], '5000');
          expect(
            request.uri.queryParameters['url'],
            'https://www.gstatic.com/generate_204',
          );
          request.response.write(jsonEncode(<String, Object>{'delay': 86}));
        } else if (request.method == 'GET' &&
            request.uri.path == '/connections') {
          request.response.write(
            jsonEncode(<String, Object>{
              'connections': <Object>[
                <String, Object>{'id': '1'},
              ],
              'downloadTotal': 1024,
              'uploadTotal': 512,
            }),
          );
        } else if (request.method == 'PATCH' || request.method == 'PUT') {
          mutations.add(
            '${request.method} ${request.uri.path} ${await utf8.decoder.bind(request).join()}',
          );
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final MihomoControllerService controller = MihomoControllerService(
      Uri.parse('http://127.0.0.1:${server.port}'),
      secret: 'key',
    );
    final MihomoControllerSnapshot snapshot = await controller.snapshot();
    expect(snapshot.mode, 'rule');
    expect(snapshot.connectionCount, 1);
    expect(snapshot.downloadTotal, 1024);
    expect(snapshot.groups.single.selected, '节点 A');
    expect(await controller.testDelay('节点 A'), 86);

    await controller.setMode('global');
    await controller.selectNode('自动选择', '节点 B');
    expect(mutations[0], contains('PATCH /configs'));
    expect(mutations[0], contains('global'));
    expect(mutations[1], contains('PUT /proxies/'));
    expect(mutations[1], contains('节点 B'));
  });
}
