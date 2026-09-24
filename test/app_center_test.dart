import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/app_center/domain/app_center_service.dart';
import 'package:vibekits/features/app_center/presentation/app_center_tab.dart';
import 'package:vibekits/features/dev_tools/domain/pad_builder_component_service.dart';

void main() {
  test('PAD 编译组件已安装时离线读取本地版本，不依赖市场', () async {
    final market = AppCenterService(
      platformOverride: 'android',
      versionLookup: (_) async => const AppCenterLocalVersion.installed(3),
      loader: ({category, keyword = ''}) async => throw StateError('不应访问市场'),
    );
    final component = PadBuilderComponentService(market: market);
    addTearDown(market.dispose);
    final status = await component.check();
    expect(status.state, PadBuilderComponentState.installed);
    expect(status.versionCode, 3);
    expect(status.item, isNull);
  });

  test('PAD 编译组件缺失时只接受完整且可信的商城记录', () async {
    AppCenterItem builder(String url) => AppCenterItem.fromJson({
      ..._itemJson(os: 'android'),
      'package_name': PadBuilderComponentService.packageName,
      'download_url': url,
      'version_code': 1,
    });
    final valid = builder('https://cdn.example.test/builder.apk');
    var listed = valid;
    final market = AppCenterService(
      platformOverride: 'android',
      versionLookup: (_) async => const AppCenterLocalVersion.uninstalled(),
      loader: ({category, keyword = ''}) async =>
          AppCenterCatalog(categories: const [], apps: [listed], total: 1),
    );
    addTearDown(market.dispose);
    final component = PadBuilderComponentService(market: market);
    final available = await component.check();
    expect(available.state, PadBuilderComponentState.availableInMarket);
    expect(available.item, same(valid));

    listed = builder('http://cdn.example.test/builder.apk');
    final unsafe = await component.check();
    expect(unsafe.state, PadBuilderComponentState.incompleteMarketRecord);
    expect(() => component.requestInstall(unsafe), throwsStateError);
  });

  test('PAD 编译组件按独立包名查询重启后版本并拒绝伪装条目', () async {
    final queried = <String>[];
    final service = AppCenterService(
      platformOverride: 'android',
      versionLookup: (packageName) async {
        queried.add(packageName);
        return const AppCenterLocalVersion.installed(7);
      },
    );
    addTearDown(service.dispose);
    final item = AppCenterItem.fromJson({
      ..._itemJson(os: 'android'),
      'package_name': 'com.vibekits.vibekits.component.builder',
      'download_url': 'https://cdn.example.test/builder.apk',
      'version_code': 8,
    });
    expect(item.isTrustedAndroidHostComponent, isTrue);
    expect(item.componentId, 'android_builder');
    expect(item.hostPackageName, 'com.vibekits.vibekits');
    final local = await service.localVersion(item);
    expect(queried, ['com.vibekits.vibekits.component.builder']);
    expect(local.versionCode, 7);
    expect(service.updateStatus(item, local), AppCenterUpdateStatus.update);

    final spoofed = AppCenterItem.fromJson({
      ..._itemJson(os: 'android'),
      'package_name': 'com.vibekits.vibekits.component.builder',
      'android_package_name': 'com.attacker.builder',
      'download_url': 'https://cdn.example.test/builder.apk',
    });
    expect(spoofed.isTrustedAndroidHostComponent, isFalse);
    await expectLater(service.installComponent(spoofed), throwsFormatException);
    expect((await service.localVersion(spoofed)).installed, isNull);
    expect(queried, hasLength(1));
  });

  test('Android 模型组件归属实际 PAD 包名且不能伪装宿主', () async {
    final service = AppCenterService(platformOverride: 'android');
    addTearDown(service.dispose);
    final item = AppCenterItem.fromJson({
      ..._itemJson(os: 'android'),
      'package_name': 'com.vibekits.vibekits.component.models',
    });
    expect(item.isComponent, isTrue);
    expect(item.componentId, 'android_models');
    expect(item.hostPackageName, 'com.vibekits.vibekits');
    final wrongHost = AppCenterItem.fromJson({
      ..._itemJson(os: 'android'),
      'package_name': 'com.vibekits.vibekits.component.models',
      'host_package_name': 'com.caucy.vibekits',
    });
    await expectLater(
      service.installComponent(wrongHost),
      throwsFormatException,
    );
  });

  test('Android 网络代理组件按签名宿主和精确市场记录安装', () async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'android',
      versionLookup: (String packageName) async {
        expect(packageName, 'com.caucy.vibekits.component.network_proxy');
        return const AppCenterLocalVersion.uninstalled();
      },
    );
    addTearDown(service.dispose);
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'android'),
      'package_name': 'com.caucy.vibekits.component.network_proxy',
      'download_url': 'https://cdn.example.test/network-proxy.apk',
      'version_code': 1,
    });
    expect(item.isComponent, isTrue);
    expect(item.componentId, 'network_proxy');
    expect(item.hostPackageName, 'com.vibekits.vibekits');
    expect(
      await service.localVersion(item),
      isA<AppCenterLocalVersion>().having(
        (value) => value.installed,
        'installed',
        false,
      ),
    );
    expect(
      service.canDownload(item, const AppCenterLocalVersion.uninstalled()),
      isTrue,
    );
    final AppCenterItem wrongHost = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'android'),
      'package_name': 'com.caucy.vibekits.component.network_proxy',
      'host_package_name': 'com.caucy.vibekits',
      'download_url': 'https://cdn.example.test/network-proxy.apk',
    });
    await expectLater(
      service.installComponent(wrongHost),
      throwsFormatException,
    );
  });

  test('旧商城接口按精确包名识别两个 Windows 组件', () {
    for (final id in ['virtual_machine', 'network_proxy']) {
      final item = AppCenterItem.fromJson({
        ..._itemJson(os: 'windows'),
        'package_name': 'com.caucy.vibekits.component.$id',
      });
      expect(item.isComponent, isTrue);
      expect(item.standalone, isFalse);
      expect(item.componentId, id);
      expect(item.hostPackageName, 'com.caucy.vibekits');
    }
    final unrelated = AppCenterItem.fromJson({
      ..._itemJson(os: 'windows'),
      'package_name': 'com.caucy.vibekits.component.untrusted',
    });
    expect(unrelated.isComponent, isFalse);
  });

  test('组件标记不能通过 standalone=true 绕过宿主安装入口', () async {
    final service = AppCenterService(platformOverride: 'windows');
    addTearDown(service.dispose);
    final item = AppCenterItem.fromJson({
      ..._itemJson(os: 'windows'),
      'artifact_type': 'component',
      'standalone': true,
      'host_package_name': 'com.caucy.vibekits',
      'component_id': 'network_proxy',
    });
    expect(item.isComponent, isTrue);
    await expectLater(service.downloadAndOpen(item), throwsStateError);
    await expectLater(service.installComponent(item), throwsFormatException);
  });

  test('宿主组件不能作为独立应用打开或下载安装器', () async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'windows',
    );
    addTearDown(service.dispose);
    final AppCenterItem item = AppCenterItem.fromJson({
      ..._itemJson(os: 'windows'),
      'artifact_type': 'component',
      'standalone': false,
      'host_package_name': 'com.caucy.vibekits',
      'component_id': 'network_proxy',
    });
    expect(item.isComponent, isTrue);
    expect(await service.openApplication(item), isFalse);
    expect(await service.isApplicationInstalled(item), isFalse);
    await expectLater(service.downloadAndOpen(item), throwsStateError);
  });

  test('未知组件和错误宿主在下载前拒绝', () async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'windows',
    );
    addTearDown(service.dispose);
    for (final String component in ['../escape', 'unknown']) {
      final AppCenterItem item = AppCenterItem.fromJson({
        ..._itemJson(os: 'windows'),
        'artifact_type': 'component',
        'standalone': false,
        'host_package_name': 'com.caucy.vibekits',
        'component_id': component,
      });
      await expectLater(service.installComponent(item), throwsFormatException);
    }
  });

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
    expect(item.androidInstallPackageName, 'com.vibekits.vibekits');
    final AppCenterItem legacy = AppCenterItem.fromJson(
      _itemJson(os: 'android'),
    );
    expect(legacy.androidInstallPackageName, 'com.vibekits.vibekits');
  });

  test('Android 兼容市场的 all 与 PAD2 平台标识', () {
    final AppCenterItem all = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'android'),
      'os_type': null,
      'platforms': <String>['all'],
    });
    final AppCenterItem pad = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'android'),
      'os_type': null,
      'platforms': <String>['pad2'],
    });
    final AppCenterItem windows = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'windows'),
      'os_type': null,
      'platforms': <String>['windows'],
    });

    expect(all.supportsPlatform('android'), isTrue);
    expect(pad.supportsPlatform('android'), isTrue);
    expect(windows.supportsPlatform('android'), isFalse);
  });

  test('平台字段冲突的商品不展示也不能下载', () {
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'macos'),
      'platforms': <String>['windows'],
    });
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
    );
    addTearDown(service.dispose);
    expect(item.supportsPlatform('macos'), isFalse);
    expect(
      service.canDownload(item, const AppCenterLocalVersion.uninstalled()),
      isFalse,
    );
  });

  test('Android 当前包使用真实 applicationId 并禁止重复下载', () async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'android',
      versionLookup: (packageName) async {
        expect(packageName, 'com.vibekits.vibekits');
        return const AppCenterLocalVersion.installed(2169);
      },
    );
    addTearDown(service.dispose);
    final AppCenterItem current = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'android'),
      'package_name': 'com.vibekits.vibekits',
      'version_code': 2169,
    });

    final AppCenterLocalVersion local = await service.localVersion(current);
    expect(service.updateStatus(current, local), AppCenterUpdateStatus.current);
    expect(service.canDownload(current, local), isFalse);
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
      versionLookup: (_) async => const AppCenterLocalVersion.uninstalled(),
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
    expect(find.text('探索'), findsOneWidget);
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
      versionLookup: (_) async => const AppCenterLocalVersion.installed(1),
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
      versionLookup: (_) async => const AppCenterLocalVersion.uninstalled(),
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
      versionLookup: (_) async => const AppCenterLocalVersion.uninstalled(),
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
        versionLookup: (_) async => const AppCenterLocalVersion.installed(2159),
        installedLookup: (_) async => false,
        loader: ({category, keyword = ''}) async => AppCenterCatalog(
          categories: const <AppCenterCategory>[],
          apps: <AppCenterItem>[
            AppCenterItem.fromJson(<String, Object?>{
              ..._itemJson(os: os),
              if (os == 'android') 'package_name': 'com.vibekits.vibekits',
              'version_code': 2159,
              'file_size_bytes': 0,
              'file_size': '大小未知',
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
      expect(find.text('该条目缺少完整的 HTTPS、文件大小或 SHA-256 信息，已禁止安装。'), findsNothing);
      expect(find.text('已是最新版'), findsWidgets);
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
      versionLookup: (_) async => const AppCenterLocalVersion.installed(2159),
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

  test('其他已安装应用逐包比较版本，同版和降级在下载前被阻止', () async {
    final List<String> queried = <String>[];
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      versionLookup: (packageName) async {
        queried.add(packageName);
        return const AppCenterLocalVersion.installed(300);
      },
    );
    addTearDown(service.dispose);
    final AppCenterItem same = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'macos'),
      'package_name': 'com.kemi.other',
      'version_code': 300,
    });
    final AppCenterItem older = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'macos'),
      'package_name': 'com.kemi.other',
      'version_code': 299,
    });
    final AppCenterItem newer = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'macos'),
      'package_name': 'com.kemi.other',
      'version_code': 301,
    });
    expect(
      service.updateStatus(same, await service.localVersion(same)),
      AppCenterUpdateStatus.current,
    );
    expect(
      service.updateStatus(older, await service.localVersion(older)),
      AppCenterUpdateStatus.downgrade,
    );
    expect(
      service.canDownload(newer, await service.localVersion(newer)),
      isTrue,
    );
    await expectLater(
      service.downloadAndOpen(same),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.downloadAndOpen(older),
      throwsA(isA<StateError>()),
    );
    expect(queried, everyElement('com.kemi.other'));
  });

  test('无法读取版本、已安装但码未知和云端码缺失均禁止下载', () async {
    final AppCenterItem item = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'windows'),
      'package_name': 'com.kemi.other',
    });
    for (final AppCenterLocalVersion local in <AppCenterLocalVersion>[
      const AppCenterLocalVersion.unknown(),
      const AppCenterLocalVersion.installed(null),
      const AppCenterLocalVersion.installed(0),
    ]) {
      final AppCenterService service = AppCenterService(
        platformOverride: 'windows',
        versionLookup: (_) async => local,
      );
      expect(
        service.canDownload(item, await service.localVersion(item)),
        isFalse,
      );
      await expectLater(
        service.downloadAndOpen(item),
        throwsA(isA<StateError>()),
      );
      service.dispose();
    }
    final AppCenterService service = AppCenterService(
      platformOverride: 'windows',
      versionLookup: (_) async => const AppCenterLocalVersion.uninstalled(),
    );
    addTearDown(service.dispose);
    final AppCenterItem missing = AppCenterItem.fromJson(<String, Object?>{
      ..._itemJson(os: 'windows'),
      'version_code': 0,
    });
    expect(
      service.canDownload(missing, await service.localVersion(missing)),
      isFalse,
    );
  });

  testWidgets('其他应用同版时详情按钮禁用并显示最新版', (tester) async {
    final AppCenterService service = AppCenterService(
      platformOverride: 'macos',
      installedLookup: (_) async => true,
      versionLookup: (_) async => const AppCenterLocalVersion.installed(2153),
      loader: ({category, keyword = ''}) async => AppCenterCatalog(
        categories: const <AppCenterCategory>[],
        apps: <AppCenterItem>[
          AppCenterItem.fromJson(<String, Object?>{
            ..._itemJson(os: 'macos'),
            'package_name': 'com.kemi.other',
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
    expect(find.text('已是最新版'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('app-center-install')))
          .onPressed,
      isNull,
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
