import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mihomo_profile_service.dart';

const String _yaml = '''
mixed-port: 17890
mode: rule
secret: local-test
external-controller: 127.0.0.1:19090
proxies:
  - name: Node-A
    type: socks5
    server: 127.0.0.1
    port: 1080
proxy-groups: []
rules:
  - MATCH,DIRECT
''';

void main() {
  late Directory sandbox;
  late Map<String, String> credentials;
  late MihomoProfileService service;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('vk_mihomo_profiles_');
    credentials = <String, String>{};
    service = MihomoProfileService(
      dataDirectory: sandbox.path,
      credentialReader: (String key) async => credentials[key],
      credentialWriter: (String key, String value) async {
        credentials[key] = value;
      },
      credentialDeleter: (String key) async {
        credentials.remove(key);
      },
    );
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('导入配置、选择状态和运行配置均持久化', () async {
    final File source = File('${sandbox.path}${Platform.pathSeparator}in.yaml')
      ..writeAsStringSync(_yaml);
    final MihomoProfile imported = await service.importConfig(
      sourcePath: source.path,
      displayName: '本地测试',
    );

    final MihomoProfileState state = await service.load();
    expect(state.activeId, imported.id);
    expect(state.profiles.single.name, '本地测试');
    expect(state.profiles.single.summary.proxyCount, 1);
    expect(state.profiles.single.summary.mixedPort, 17890);

    final MihomoManagedConfig managed = await service.prepareManagedConfig(
      state.profiles.single,
    );
    expect(File(managed.path).existsSync(), isTrue);
    expect(managed.summary.controller?.host, '127.0.0.1');
    expect(managed.summary.controller?.port, 19090);
  });

  test('订阅地址只进凭据库，清单不泄露 token，并支持更新', () async {
    int downloads = 0;
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> serving = () async {
      await for (final HttpRequest request in server) {
        downloads++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write(_yaml);
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final String url = 'http://127.0.0.1:${server.port}/sub?token=secret-token';
    final MihomoProfile profile = await service.addSubscription(
      name: '测试订阅',
      url: url,
    );
    expect(credentials[profile.credentialKey], url);
    final String manifest = File(
      '${sandbox.path}${Platform.pathSeparator}profiles.json',
    ).readAsStringSync();
    expect(manifest, isNot(contains('secret-token')));
    expect(manifest, contains('127.0.0.1'));

    final MihomoProfile updated = await service.update(profile);
    expect(updated.summary.proxyCount, 1);
    expect(downloads, 2);

    await service.delete(updated);
    expect(credentials, isEmpty);
    expect((await service.load()).profiles, isEmpty);
  });
}
