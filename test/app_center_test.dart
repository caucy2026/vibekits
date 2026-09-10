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
    expect(listRequest.queryParameters['pageSize'], '30');
    expect(catalog.apps.single.name, 'Vibekits');
    expect(catalog.apps.single.hasVerifiedInstaller, isTrue);
    service.dispose();
  });

  test('应用中心逐页读取并去重，新增商品不会被首屏容量截断', () async {
    final List<int> requestedPages = <int>[];
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      envelopeLoader: (uri) async {
        if (uri.path.endsWith('/api/store/categories')) return <Object?>[];
        final int page = int.parse(uri.queryParameters['page']!);
        requestedPages.add(page);
        if (page == 1) {
          return <String, Object?>{
            'total': 31,
            'list': List<Object?>.generate(
              30,
              (int index) => <String, Object?>{
                ..._itemJson(os: 'macos'),
                'app_id': index + 1,
                'package_name': 'com.kemi.app.${index + 1}',
              },
            ),
          };
        }
        return <String, Object?>{
          'total': 31,
          'list': <Object?>[
            <String, Object?>{
              ..._itemJson(os: 'macos'),
              'app_id': 30,
              'package_name': 'com.kemi.app.30',
            },
            <String, Object?>{
              ..._itemJson(os: 'macos'),
              'app_id': 31,
              'package_name': 'com.kemi.app.31',
            },
          ],
        };
      },
    );
    addTearDown(service.dispose);

    final AppCenterCatalog catalog = await service.load();

    expect(requestedPages, <int>[1, 2]);
    expect(catalog.apps, hasLength(31));
    expect(catalog.total, 31);
  });

  test('缺少哈希的市场条目保持可见但禁止安装', () {
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'windows'),
      'apk_sha256': '',
    });
    expect(item.hasVerifiedInstaller, isFalse);
  });

  test('Android 原生包名与跨平台商品标识分别解析', () {
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'android'),
      'android_package_name': 'com.vibekits.vibekits',
    });

    expect(item.packageName, 'com.caucy.vibekits');
    expect(item.androidPackageName, 'com.vibekits.vibekits');
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
      currentVersionCode: 1,
      installedLookup: (_) async => false,
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

  testWidgets('macOS 已安装应用显示可用的打开按钮并调用稳定包名', (tester) async {
    String? openedPackage;
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      currentVersionCode: 1,
      installedLookup: (String packageName) async =>
          packageName == 'com.caucy.vibekits',
      applicationOpener: (String packageName) async {
        openedPackage = packageName;
        return true;
      },
      loader: ({category, keyword = ''}) async => AppCenterCatalog(
        categories: const <AppCenterCategory>[],
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-center-item-53')));
    await tester.pumpAndSettle();

    final Finder openButton = find.byKey(const Key('app-center-open'));
    expect(openButton, findsOneWidget);
    expect(tester.widget<TextButton>(openButton).onPressed, isNotNull);
    await tester.tap(openButton);
    await tester.pumpAndSettle();

    expect(openedPackage, 'com.caucy.vibekits');
    expect(find.text('已打开应用'), findsOneWidget);
  });

  testWidgets('Windows 未安装应用的打开按钮禁用', (tester) async {
    final AppCenterService windowsService = AppCenterService(
      platformOverride: 'windows',
      installedLookup: (_) async => false,
      loader: ({category, keyword = ''}) async => AppCenterCatalog(
        categories: const <AppCenterCategory>[],
        apps: <AppCenterItem>[AppCenterItem.fromJson(_itemJson(os: 'windows'))],
        total: 1,
      ),
    );
    addTearDown(windowsService.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppCenterTab(service: windowsService)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-center-item-53')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('app-center-open')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Android 不显示桌面打开操作', (tester) async {
    final AppCenterService androidService = AppCenterService(
      platformOverride: 'android',
      loader: ({category, keyword = ''}) async => AppCenterCatalog(
        categories: const <AppCenterCategory>[],
        apps: <AppCenterItem>[AppCenterItem.fromJson(_itemJson(os: 'android'))],
        total: 1,
      ),
    );
    addTearDown(androidService.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppCenterTab(service: androidService)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-center-item-53')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-center-open')), findsNothing);
  });

  test('非法包名不会传给桌面原生打开通道', () async {
    bool called = false;
    final AppCenterService service = AppCenterService(
      platformOverride: 'windows',
      installedLookup: (_) async {
        called = true;
        return true;
      },
      applicationOpener: (_) async {
        called = true;
        return true;
      },
    );
    addTearDown(service.dispose);
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'windows'),
      'package_name': r'..\\bad package',
    });

    expect(await service.isApplicationInstalled(item), isFalse);
    expect(await service.openApplication(item), isFalse);
    expect(called, isFalse);
  });

  for (final String os in <String>['macos', 'windows', 'android']) {
    testWidgets('$os 当前版本显示最新版且下载按钮不可点击', (tester) async {
      final AppCenterService service = AppCenterService(
        platformOverride: os,
        currentVersionCode: 2159,
        installedLookup: (_) async => false,
        loader: ({category, keyword = ''}) async => AppCenterCatalog(
          categories: const <AppCenterCategory>[],
          apps: <AppCenterItem>[
            AppCenterItem.fromJson(<String, Object?>{
              ..._itemJson(os: os),
              'version_code': 2159,
            }),
          ],
          total: 1,
        ),
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppCenterTab(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('app-center-item-53')));
      await tester.pumpAndSettle();

      expect(find.text('当前已是最新版本，无需重复下载。'), findsOneWidget);
      expect(find.text('已是最新版'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('app-center-install')))
            .onPressed,
        isNull,
      );
    });
  }

  test('服务层拒绝重复下载当前版本', () async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      currentVersionCode: 2159,
    );
    addTearDown(service.dispose);
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'macos'),
      'version_code': 2159,
    });

    await expectLater(
      service.downloadAndOpen(item),
      throwsA(isA<StateError>()),
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
