import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/app_center/domain/app_center_service.dart';
import 'package:vibekits/features/app_center/presentation/app_center_tab.dart';

void main() {
  test('macOS 应用中心请求严格携带 os 并解析当前平台条目', () async {
    final List<Uri> requests = <Uri>[];
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      envelopeLoader: (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/api/store/categories')) {
          return <Object?>[
            <String, Object?>{'name': '探索', 'is_explore': true},
            <String, Object?>{'name': '开发工具', 'enabled': true},
          ];
        }
        return <String, Object?>{
          'total': 1,
          'list': <Object?>[_itemJson(os: 'macos')],
        };
      },
    );
    final AppCenterCatalog catalog = await service.load(
      category: '开发工具',
      keyword: 'Vibe',
    );
    final Uri listRequest = requests.singleWhere(
      (uri) => uri.path.endsWith('/api/store/apps'),
    );
    expect(listRequest.queryParameters['os'], 'macos');
    expect(listRequest.queryParameters['category'], '开发工具');
    expect(listRequest.queryParameters['keyword'], 'Vibe');
    expect(catalog.apps.single.name, 'Vibekits');
    expect(catalog.apps.single.hasVerifiedInstaller, isTrue);
    service.dispose();
  });

  test('缺少哈希的市场条目保持可见但禁止安装', () {
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'windows'),
      'apk_sha256': '',
    });
    expect(item.hasVerifiedInstaller, isFalse);
  });

  test('服务端即使返回错误平台条目，客户端仍会按 platforms 二次过滤', () async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      envelopeLoader: (uri) async {
        if (uri.path.endsWith('/api/store/categories')) return <Object?>[];
        return <String, Object?>{
          'total': 2,
          'list': <Object?>[
            <String, Object?>{..._itemJson(os: 'macos'), 'os_type': null},
            <String, Object?>{
              ..._itemJson(os: 'windows'),
              'app_id': 54,
              'os_type': null,
            },
          ],
        };
      },
    );
    addTearDown(service.dispose);

    final AppCenterCatalog catalog = await service.load();

    expect(catalog.apps.map((item) => item.appId), <int>[53]);
  });

  testWidgets('应用中心显示平台、分类、应用详情和安全安装状态', (tester) async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      loader: ({category, keyword = ''}) async => AppCenterCatalog(
        categories: const <AppCenterCategory>[
          AppCenterCategory(name: '探索', isExplore: true),
          AppCenterCategory(name: '开发工具'),
        ],
        apps: <AppCenterItem>[AppCenterItem.fromJson(_itemJson(os: 'macos'))],
        total: 1,
      ),
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppCenterTab(service: service)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('macOS 应用'), findsOneWidget);
    expect(find.text('开发工具'), findsWidgets);
    expect(find.text('Vibekits'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-center-item-53')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-center-details')), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('app-center-install')))
          .onPressed,
      isNotNull,
    );
  });
}

Map<String, Object?> _itemJson({required String os}) => <String, Object?>{
  'app_id': 53,
  'app_name': 'Vibekits',
  'package_name': 'com.caucy.vibekits',
  'version_name': '1.9.0-dev.153',
  'version_code': 2153,
  'category': '开发工具',
  'short_desc': '本地优先的智能体与工程工具箱',
  'long_desc': '详细介绍',
  'icon': '',
  'download_url': 'https://cdn.example.test/Vibekits.zip',
  'apk_sha256': List<String>.filled(64, 'a').join(),
  'file_size_bytes': 123,
  'rating': 5,
  'download_count': 10,
  'os_type': os,
  'platforms': <String>[os],
};
