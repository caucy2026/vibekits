import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/windows_cleanup_rule_catalog.dart';

void main() {
  test('Windows 规则库 ID 唯一且包含系统与常用软件规则', () {
    final List<WindowsCleanupRule> rules = WindowsCleanupRuleCatalog.rules;
    expect(rules.length, greaterThanOrEqualTo(29));
    expect(
      rules.map((WindowsCleanupRule rule) => rule.id).toSet(),
      hasLength(rules.length),
    );
    expect(
      rules.map((WindowsCleanupRule rule) => rule.id),
      containsAll(<String>[
        'windows-explorer-thumbnail-cache',
        'windows-wer-machine-archive',
        'delivery-optimization-cache',
        'vscode-logs',
        'docker-desktop-logs',
        'jetbrains-crash-heap-dumps',
        'wslg-rd-client-traces',
        'gradio-temp-files',
        'scoop-download-cache',
      ]),
    );
  });

  test('用户目录顶层规则不会递归误扫项目和个人目录', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_bounded_root_rules_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory nested = Directory(
      '${sandbox.path}${Platform.pathSeparator}projects',
    )..createSync();
    final DateTime old = DateTime.now().subtract(const Duration(days: 10));
    final File rootDump = File(
      '${sandbox.path}${Platform.pathSeparator}java_error_in_100.hprof',
    )..writeAsStringSync('root dump');
    rootDump.setLastModifiedSync(old);
    final File rootLog = File(
      '${sandbox.path}${Platform.pathSeparator}java_error_in_100.log',
    )..writeAsStringSync('root log');
    rootLog.setLastModifiedSync(old);
    final File nestedDump = File(
      '${nested.path}${Platform.pathSeparator}java_error_in_project.hprof',
    )..writeAsStringSync('must stay');
    nestedDump.setLastModifiedSync(old);

    final List<CleanupScanTarget> targets =
        CleanupTargetDiscovery.discover(
              environment: <String, String>{'USERPROFILE': sandbox.path},
              windowsBuild: 22621,
            )
            .where((CleanupScanTarget target) {
              return target.id == 'jetbrains-crash-heap-dumps' ||
                  target.id == 'jetbrains-crash-logs';
            })
            .toList(growable: false);

    expect(targets, hasLength(2));
    expect(
      targets.every((CleanupScanTarget target) => target.maxDepth == 0),
      isTrue,
    );
    final CleanupScanResult result = await CleanupScanner.scanTargets(targets);
    final Set<String> paths = result.candidates
        .map((CleanupCandidate candidate) => candidate.path)
        .toSet();
    expect(paths, containsAll(<String>[rootDump.path, rootLog.path]));
    expect(paths, isNot(contains(nestedDump.path)));
  });

  test('Windows 规则按版本、文件模式和时间阈值生成真实候选', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_windows_catalog_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String local = '${sandbox.path}${Platform.pathSeparator}Local';
    final String roaming = '${sandbox.path}${Platform.pathSeparator}Roaming';
    final String windows = '${sandbox.path}${Platform.pathSeparator}Windows';
    final String explorer = <String>[
      local,
      'Microsoft',
      'Windows',
      'Explorer',
    ].join(Platform.pathSeparator);
    final String codeLogs = <String>[
      roaming,
      'Code',
      'logs',
    ].join(Platform.pathSeparator);
    final String delivery = <String>[
      windows,
      'ServiceProfiles',
      'NetworkService',
      'AppData',
      'Local',
      'Microsoft',
      'Windows',
      'DeliveryOptimization',
      'Cache',
    ].join(Platform.pathSeparator);
    Directory(explorer).createSync(recursive: true);
    Directory(codeLogs).createSync(recursive: true);
    Directory(delivery).createSync(recursive: true);
    final DateTime old = DateTime.now().subtract(const Duration(days: 10));
    final File oldThumb = File(
      '$explorer${Platform.pathSeparator}thumbcache_256.db',
    )..writeAsStringSync('old thumbnail');
    oldThumb.setLastModifiedSync(old);
    final File unrelated = File(
      '$explorer${Platform.pathSeparator}settings.dat',
    )..writeAsStringSync('keep');
    unrelated.setLastModifiedSync(old);
    File('$explorer${Platform.pathSeparator}iconcache_32.db')
        .writeAsStringSync('new cache');
    final File oldLog = File('$codeLogs${Platform.pathSeparator}renderer.log')
      ..writeAsStringSync('old log');
    oldLog.setLastModifiedSync(old);
    File('$codeLogs${Platform.pathSeparator}current.log')
        .writeAsStringSync('new log');

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: <String, String>{
        'LOCALAPPDATA': local,
        'APPDATA': roaming,
        'WINDIR': windows,
      },
      windowsBuild: 22621,
    );
    final Set<String> ids = targets
        .map((CleanupScanTarget target) => target.id)
        .toSet();
    expect(
      ids,
      containsAll(<String>[
        'windows-explorer-thumbnail-cache',
        'delivery-optimization-cache',
        'vscode-logs',
      ]),
    );
    expect(
      targets
          .singleWhere(
            (CleanupScanTarget target) =>
                target.id == 'delivery-optimization-cache',
          )
          .defaultEnabled,
      isFalse,
    );

    final CleanupScanResult result = await CleanupScanner.scanTargets(
      targets
          .where(
            (CleanupScanTarget target) =>
                target.id == 'windows-explorer-thumbnail-cache' ||
                target.id == 'vscode-logs',
          )
          .toList(growable: false),
    );
    final Set<String> candidatePaths = result.candidates
        .map((CleanupCandidate candidate) => candidate.path)
        .toSet();
    expect(candidatePaths, contains(oldThumb.path));
    expect(candidatePaths, contains(oldLog.path));
    expect(candidatePaths, isNot(contains(unrelated.path)));
    expect(
      candidatePaths,
      isNot(contains('$explorer${Platform.pathSeparator}iconcache_32.db')),
    );

    final Set<String> legacyIds = CleanupTargetDiscovery.discover(
      environment: <String, String>{
        'LOCALAPPDATA': local,
        'APPDATA': roaming,
        'WINDIR': windows,
      },
      windowsBuild: 7601,
    ).map((CleanupScanTarget target) => target.id).toSet();
    expect(legacyIds, isNot(contains('delivery-optimization-cache')));
  });

  test('发现临时目录、浏览器缓存和崩溃转储扫描范围', () {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_targets');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String local = '${sandbox.path}${Platform.pathSeparator}Local';
    Directory(
      <String>[
        local,
        'Microsoft',
        'Edge',
        'User Data',
        'Default',
        'Cache',
      ].join(Platform.pathSeparator),
    ).createSync(recursive: true);
    Directory(
      <String>[
        local,
        'Google',
        'Chrome',
        'User Data',
        'Profile 1',
        'Cache',
      ].join(Platform.pathSeparator),
    ).createSync(recursive: true);
    Directory(
      <String>[
        local,
        'Mozilla',
        'Firefox',
        'Profiles',
        'abc.default',
        'cache2',
      ].join(Platform.pathSeparator),
    ).createSync(recursive: true);
    Directory(<String>[local, 'D3DSCache'].join(Platform.pathSeparator))
        .createSync(recursive: true);
    Directory(<String>[local, 'CrashDumps'].join(Platform.pathSeparator))
        .createSync(recursive: true);

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: <String, String>{
        'TEMP': '${sandbox.path}${Platform.pathSeparator}Temp',
        'WINDIR': '${sandbox.path}${Platform.pathSeparator}Windows',
        'LOCALAPPDATA': local,
      },
    );
    final Set<String> ids = targets
        .map((CleanupScanTarget target) => target.id)
        .toSet();

    expect(
      ids,
      containsAll(<String>{
        'user-temp',
        'windows-temp',
        'edge-default-cache',
        'chrome-profile-1-cache',
        'firefox-abc.default',
        'directx-shader-cache',
        'crash-dumps',
      }),
    );
    expect(
      targets
          .singleWhere(
            (CleanupScanTarget target) => target.id == 'windows-temp',
          )
          .defaultEnabled,
      isFalse,
    );
  });

  test('清理候选保留具体缓存来源供用户核对', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_source');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    File('${sandbox.path}${Platform.pathSeparator}cache.bin')
        .writeAsBytesSync(<int>[1, 2, 3]);
    final CleanupScanResult result =
        await CleanupScanner.scanDirectoryWithProgress(
          sandbox.path,
          CleanupCategory.applicationCache,
          sourceLabel: '测试应用 Code Cache',
        );

    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.reason, '测试应用 Code Cache');
    expect(result.candidates.single.sourceLabel, '测试应用 Code Cache');
    expect(result.candidates.single.defaultSelected, isTrue);
  });

  test('默认选择遵循类别风险与 24 小时规则', () {
    expect(
      const CleanupCandidate(
        path: 'cache',
        size: 1,
        category: CleanupCategory.browserCache,
        reason: '缓存',
      ).defaultSelected,
      isTrue,
    );
    expect(
      const CleanupCandidate(
        path: 'windows',
        size: 1,
        category: CleanupCategory.windowsTemp,
        reason: '临时文件',
      ).defaultSelected,
      isFalse,
    );
    expect(
      CleanupCandidate(
        path: 'old',
        size: 1,
        category: CleanupCategory.userTemp,
        reason: '临时文件',
        modified: DateTime.now().subtract(const Duration(days: 2)),
      ).defaultSelected,
      isTrue,
    );
  });

  test('发现包缓存、插件缓存、旧插件与下载建议入口', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_extended_targets',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String local = '${sandbox.path}${Platform.pathSeparator}Local';
    final String roaming = '${sandbox.path}${Platform.pathSeparator}Roaming';
    final String profile = '${sandbox.path}${Platform.pathSeparator}Profile';
    for (final String path in <String>[
      <String>[local, 'Pub', 'Cache'].join(Platform.pathSeparator),
      <String>[profile, '.nuget', 'packages'].join(Platform.pathSeparator),
      <String>[
        roaming,
        'Code',
        'CachedExtensionVSIXs',
      ].join(Platform.pathSeparator),
      <String>[profile, '.vscode', 'extensions'].join(Platform.pathSeparator),
      <String>[profile, 'Downloads'].join(Platform.pathSeparator),
    ]) {
      Directory(path).createSync(recursive: true);
    }

    final Set<String> ids = CleanupTargetDiscovery.discover(
      environment: <String, String>{
        'LOCALAPPDATA': local,
        'APPDATA': roaming,
        'USERPROFILE': profile,
      },
    ).map((CleanupScanTarget target) => target.id).toSet();

    expect(
      ids,
      containsAll(<String>{
        'pub-cache',
        'nuget-cache',
        'vscode-extension-download-cache',
        'vscode-stale-extensions',
        'downloads-suggestions',
      }),
    );
  });

  test('下载建议只列出残留下载和超过 30 天的安装包', () async {
    final Directory downloads = Directory.systemTemp.createTempSync(
      'vk_downloads',
    );
    addTearDown(() => downloads.deleteSync(recursive: true));
    final DateTime old = DateTime.now().subtract(const Duration(days: 45));
    final File partial =
        File(
            <String>[
              downloads.path,
              'broken.crdownload',
            ].join(Platform.pathSeparator),
          )
          ..writeAsStringSync('partial')
          ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(hours: 2)),
          );
    final File oldInstaller =
        File(<String>[downloads.path, 'setup.exe'].join(Platform.pathSeparator))
          ..writeAsStringSync('installer')
          ..setLastModifiedSync(old);
    File(<String>[downloads.path, 'new-setup.exe'].join(Platform.pathSeparator))
        .writeAsStringSync('new');
    File(<String>[downloads.path, 'notes.txt'].join(Platform.pathSeparator))
        .writeAsStringSync('keep');
    final CleanupScanTarget target = CleanupScanTarget(
      id: 'downloads-suggestions',
      label: '下载目录清理建议',
      path: downloads.path,
      category: CleanupCategory.downloads,
      defaultEnabled: true,
      strategy: CleanupTargetStrategy.downloadSuggestions,
    );

    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[target],
    );
    final Set<String> paths = result.candidates
        .map((CleanupCandidate candidate) => candidate.path)
        .toSet();

    expect(paths, <String>{partial.path, oldInstaller.path});
    expect(
      result.candidates.every((candidate) => !candidate.defaultSelected),
      isTrue,
    );
  });

  test('插件清理只列出同一 VS Code 插件的旧版本内容', () async {
    final Directory extensions = Directory.systemTemp.createTempSync(
      'vk_extensions',
    );
    addTearDown(() => extensions.deleteSync(recursive: true));
    final Directory old = Directory(
      <String>[
        extensions.path,
        'publisher.tool-1.2.0',
      ].join(Platform.pathSeparator),
    )..createSync();
    final Directory current = Directory(
      <String>[
        extensions.path,
        'publisher.tool-1.10.0',
      ].join(Platform.pathSeparator),
    )..createSync();
    final File oldFile = File(
      <String>[old.path, 'extension.js'].join(Platform.pathSeparator),
    )..writeAsStringSync('old');
    final File currentFile = File(
      <String>[current.path, 'extension.js'].join(Platform.pathSeparator),
    )..writeAsStringSync('current');
    final CleanupScanTarget target = CleanupScanTarget(
      id: 'vscode-stale-extensions',
      label: 'VS Code 旧版本插件',
      path: extensions.path,
      category: CleanupCategory.pluginResidual,
      defaultEnabled: true,
      strategy: CleanupTargetStrategy.staleVsCodeExtensions,
    );

    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[target],
    );

    expect(
      result.candidates.map((CleanupCandidate candidate) => candidate.path),
      contains(oldFile.path),
    );
    expect(
      result.candidates.map((CleanupCandidate candidate) => candidate.path),
      isNot(contains(currentFile.path)),
    );
    expect(
      result.candidates.every((candidate) => !candidate.defaultSelected),
      isTrue,
    );
  });

  test('开发工具缓存范围精确且不会把 pnpm 根目录当缓存', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_smart_dev_targets',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String local = '${sandbox.path}${Platform.pathSeparator}Local';
    final String profile = '${sandbox.path}${Platform.pathSeparator}Profile';
    final String pnpmRoot = <String>[
      local,
      'pnpm',
    ].join(Platform.pathSeparator);
    final String pnpmStore = <String>[
      pnpmRoot,
      'store',
    ].join(Platform.pathSeparator);
    final String visualStudioCache = <String>[
      local,
      'Microsoft',
      'VisualStudio',
      '17.0_test',
      'ComponentModelCache',
    ].join(Platform.pathSeparator);
    final String jetBrainsCache = <String>[
      local,
      'JetBrains',
      'IntelliJIdea2026.1',
      'caches',
    ].join(Platform.pathSeparator);
    final String cursorExtensions = <String>[
      profile,
      '.cursor',
      'extensions',
    ].join(Platform.pathSeparator);
    for (final String path in <String>[
      pnpmStore,
      visualStudioCache,
      jetBrainsCache,
      cursorExtensions,
    ]) {
      Directory(path).createSync(recursive: true);
    }

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: <String, String>{
        'LOCALAPPDATA': local,
        'USERPROFILE': profile,
      },
    );

    expect(
      targets.singleWhere((target) => target.id == 'pnpm-cache').path,
      pnpmStore,
    );
    expect(
      targets.map((target) => target.id),
      contains('cursor-stale-extensions'),
    );
    expect(
      targets.map((target) => target.path),
      containsAll(<String>[visualStudioCache, jetBrainsCache]),
    );
    expect(
      targets.every(
        (target) => target.path != pnpmRoot || target.id != 'pnpm-cache',
      ),
      isTrue,
    );
  });

  test('macOS 开发缓存与下载建议只发现已存在的明确目录', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_mac_targets',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String derivedData = <String>[
      sandbox.path,
      'Library',
      'Developer',
      'Xcode',
      'DerivedData',
    ].join(Platform.pathSeparator);
    final String downloads = <String>[
      sandbox.path,
      'Downloads',
    ].join(Platform.pathSeparator);
    Directory(derivedData).createSync(recursive: true);
    Directory(downloads).createSync(recursive: true);

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: <String, String>{'HOME': sandbox.path},
    );

    expect(
      targets.map((target) => target.id),
      contains('mac-xcode-derived-data'),
    );
    expect(
      targets.map((target) => target.id),
      contains('mac-downloads-suggestions'),
    );
    expect(
      targets
          .singleWhere((target) => target.id == 'mac-downloads-suggestions')
          .safetyNote,
      contains('永不默认勾选'),
    );
  });
}
