import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_platform_policy.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/macos_cleanup_rule_catalog.dart';
import 'package:vibekits/features/cleaner/domain/windows_cleanup_rule_catalog.dart';

void main() {
  test('Windows 规则库 ID 唯一且包含系统与常用软件规则', () {
    final List<WindowsCleanupRule> rules = WindowsCleanupRuleCatalog.rules;
    expect(rules.length, greaterThanOrEqualTo(31));
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
        'system-drive-root-large-diagnostics',
        'est-encryption-old-logs',
      ]),
    );
  });

  test('系统盘根目录只发现超过阈值的旧诊断文件且不递归', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drive_root_logs_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory nested = Directory(
      '${sandbox.path}${Platform.pathSeparator}project',
    )..createSync();
    final Directory estlog = Directory(
      '${sandbox.path}${Platform.pathSeparator}estlog',
    )..createSync();
    final File largeLog = File(
      '${sandbox.path}${Platform.pathSeparator}est.log',
    );
    final RandomAccessFile largeWriter = largeLog.openSync(
      mode: FileMode.write,
    );
    largeWriter.setPositionSync(65 * 1024 * 1024);
    largeWriter.writeByteSync(0);
    largeWriter.closeSync();
    largeLog.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final File smallLog = File(
      '${sandbox.path}${Platform.pathSeparator}small.log',
    )..writeAsStringSync('small');
    smallLog.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final File nestedLog = File(
      '${nested.path}${Platform.pathSeparator}nested.log',
    );
    final RandomAccessFile nestedWriter = nestedLog.openSync(
      mode: FileMode.write,
    );
    nestedWriter.setPositionSync(65 * 1024 * 1024);
    nestedWriter.writeByteSync(0);
    nestedWriter.closeSync();
    nestedLog.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final File oldEstLog = File(
      '${estlog.path}${Platform.pathSeparator}encrypt-service.log',
    )..writeAsStringSync('old encrypted product log');
    oldEstLog.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final File newEstLog = File(
      '${estlog.path}${Platform.pathSeparator}current.log',
    )..writeAsStringSync('active log');

    final CleanupScanTarget target =
        CleanupTargetDiscovery.discover(
          environment: <String, String>{'SYSTEMDRIVE': sandbox.path},
          windowsBuild: 22621,
        ).singleWhere(
          (CleanupScanTarget item) =>
              item.id == 'system-drive-root-large-diagnostics',
        );
    expect(target.maxDepth, 0);
    expect(target.minimumSizeBytes, 64 * 1024 * 1024);
    expect(target.defaultEnabled, isFalse);

    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[target],
    );
    final Set<String> paths = result.candidates
        .map((CleanupCandidate item) => item.path)
        .toSet();
    expect(paths, contains(largeLog.path));
    expect(paths, isNot(contains(smallLog.path)));
    expect(paths, isNot(contains(nestedLog.path)));

    final CleanupScanTarget estTarget =
        CleanupTargetDiscovery.discover(
          environment: <String, String>{'SYSTEMDRIVE': sandbox.path},
          windowsBuild: 22621,
        ).singleWhere(
          (CleanupScanTarget item) => item.id == 'est-encryption-old-logs',
        );
    expect(estTarget.defaultEnabled, isTrue);
    expect(estTarget.minimumAgeHours, 24);
    expect(estTarget.includePatterns, <String>['*.log']);
    final CleanupScanResult estResult = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[estTarget],
    );
    expect(
      estResult.candidates.map((CleanupCandidate item) => item.path),
      contains(oldEstLog.path),
    );
    expect(
      estResult.candidates.map((CleanupCandidate item) => item.path),
      isNot(contains(newEstLog.path)),
    );
    // 加密软件日志虽然可清理，但可能仍用于排障；谨慎规则必须逐项确认。
    expect(estResult.candidates.single.defaultSelected, isFalse);
    expect(estResult.candidates.single.riskLevel, CleanupRiskLevel.cautious);
  });

  test('macOS 规则库覆盖开发链、应用、浏览器和日志且 ID 唯一', () {
    final List<MacosCleanupRule> rules = MacosCleanupRuleCatalog.rules;
    expect(rules.length, greaterThanOrEqualTo(26));
    expect(
      rules.map((MacosCleanupRule rule) => rule.id).toSet(),
      hasLength(rules.length),
    );
    expect(
      rules.map((MacosCleanupRule rule) => rule.id),
      containsAll(<String>[
        'mac-xcode-derived-data',
        'mac-core-simulator-cache',
        'mac-homebrew-cache',
        'mac-gradle-cache',
        'mac-vscode-cache',
        'mac-docker-old-logs',
        'mac-chrome-cache',
        'mac-diagnostic-reports',
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

  test('自动发现所有 Windows 用户配置中的未知日志目录且默认不选文件', () async {
    final Directory drive = Directory.systemTemp.createTempSync(
      'vk_profile_transient_',
    );
    addTearDown(() => drive.deleteSync(recursive: true));
    final Directory estlog = Directory(
      <String>[
        drive.path,
        'Users',
        'Default',
        'AppData',
        'Roaming',
        'ESTLOG',
      ].join(Platform.pathSeparator),
    )..createSync(recursive: true);
    final DateTime old = DateTime.now().subtract(const Duration(days: 10));
    final File oldLog = File(
      '${estlog.path}${Platform.pathSeparator}encrypt-service.log',
    )..writeAsStringSync('old log');
    oldLog.setLastModifiedSync(old);
    final File configuration = File(
      '${estlog.path}${Platform.pathSeparator}settings.json',
    )..writeAsStringSync('{}');
    configuration.setLastModifiedSync(old);
    final File currentLog = File(
      '${estlog.path}${Platform.pathSeparator}current.log',
    )..writeAsStringSync('active');

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: <String, String>{'SYSTEMDRIVE': drive.path},
      windowsBuild: 22621,
    );
    final CleanupScanTarget discovered = targets.singleWhere(
      (CleanupScanTarget target) => target.path == estlog.path,
    );
    expect(discovered.category, CleanupCategory.discoveredTransient);
    expect(discovered.defaultEnabled, isTrue);
    expect(discovered.minimumAgeHours, 168);
    expect(discovered.label, contains('Default'));

    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[discovered],
    );
    expect(
      result.candidates.map((CleanupCandidate item) => item.path),
      contains(oldLog.path),
    );
    expect(
      result.candidates.map((CleanupCandidate item) => item.path),
      isNot(contains(configuration.path)),
    );
    expect(
      result.candidates.map((CleanupCandidate item) => item.path),
      isNot(contains(currentLog.path)),
    );
    expect(result.candidates.single.defaultSelected, isFalse);
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

  test('macOS 规则只发现明确目录并按年龄过滤旧日志', () async {
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
    final String diagnosticReports = <String>[
      sandbox.path,
      'Library',
      'Logs',
      'DiagnosticReports',
    ].join(Platform.pathSeparator);
    final String chromeCache = <String>[
      sandbox.path,
      'Library',
      'Caches',
      'Google',
      'Chrome',
    ].join(Platform.pathSeparator);
    Directory(derivedData).createSync(recursive: true);
    Directory(downloads).createSync(recursive: true);
    Directory(diagnosticReports).createSync(recursive: true);
    Directory(chromeCache).createSync(recursive: true);
    final File oldCrash = File(
      '$diagnosticReports${Platform.pathSeparator}old.crash',
    )..writeAsStringSync('old crash');
    oldCrash.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 10)),
    );
    final File newCrash = File(
      '$diagnosticReports${Platform.pathSeparator}new.crash',
    )..writeAsStringSync('new crash');

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: <String, String>{'HOME': sandbox.path},
      platform: CleanupPlatform.macos,
    );

    expect(
      targets.map((target) => target.id),
      contains('mac-xcode-derived-data'),
    );
    expect(
      targets.map((target) => target.id),
      contains('mac-downloads-suggestions'),
    );
    expect(targets.map((target) => target.id), contains('mac-chrome-cache'));
    expect(
      targets
          .singleWhere((target) => target.id == 'mac-downloads-suggestions')
          .safetyNote,
      contains('永不默认勾选'),
    );
    final CleanupScanTarget reports = targets.singleWhere(
      (CleanupScanTarget target) => target.id == 'mac-diagnostic-reports',
    );
    expect(reports.minimumAgeHours, 168);
    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[reports],
    );
    expect(
      result.candidates.map((CleanupCandidate item) => item.path),
      contains(oldCrash.path),
    );
    expect(
      result.candidates.map((CleanupCandidate item) => item.path),
      isNot(contains(newCrash.path)),
    );
  });

  test('Harness 调试日志和截图超过 24 小时才进入清理候选', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_harness_cleanup',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory logs = Directory(
      '${sandbox.path}${Platform.pathSeparator}logs',
    )..createSync();
    final Directory screenshots = Directory(
      '${sandbox.path}${Platform.pathSeparator}screenshots',
    )..createSync();
    Directory('${sandbox.path}${Platform.pathSeparator}temp').createSync();
    final File oldLog = File('${logs.path}${Platform.pathSeparator}old.log')
      ..writeAsStringSync('old');
    final File newLog = File('${logs.path}${Platform.pathSeparator}new.log')
      ..writeAsStringSync('new');
    final File oldShot = File(
      '${screenshots.path}${Platform.pathSeparator}old.png',
    )..writeAsBytesSync(<int>[1, 2, 3]);
    final DateTime old = DateTime.now().subtract(const Duration(days: 2));
    oldLog.setLastModifiedSync(old);
    oldShot.setLastModifiedSync(old);

    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: const <String, String>{},
      harnessDebugDirectory: sandbox.path,
    );
    final List<CleanupScanTarget> harness = targets
        .where((CleanupScanTarget target) => target.id.startsWith('harness-'))
        .toList();
    expect(harness, hasLength(3));
    final CleanupScanResult result = await CleanupScanner.scanTargets(harness);
    final Set<String> paths = result.candidates
        .map((CleanupCandidate candidate) => candidate.path)
        .toSet();
    expect(paths, containsAll(<String>[oldLog.path, oldShot.path]));
    expect(paths, isNot(contains(newLog.path)));
    expect(result.candidates.every((item) => item.defaultSelected), isTrue);
  });

  test('系统盘任意旧 log 可发现但未知用途默认不选择', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_all_log_inventory',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory nested = Directory(
      '${sandbox.path}${Platform.pathSeparator}unknown-app',
    )..createSync();
    final File oldLog = File('${nested.path}${Platform.pathSeparator}app.log')
      ..writeAsStringSync('diagnostic');
    oldLog.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 8)),
    );

    final CleanupScanTarget target = CleanupTargetDiscovery.discover(
      environment: <String, String>{'SYSTEMDRIVE': sandbox.path},
    ).singleWhere((item) => item.id == 'system-drive-log-inventory');
    expect(target.maxEntries, 25000);
    expect(target.defaultEnabled, isFalse);
    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[target],
    );
    final CleanupCandidate candidate = result.candidates.singleWhere(
      (item) => item.path == oldLog.path,
    );
    expect(candidate.highRisk, isTrue);
    expect(candidate.defaultSelected, isFalse);
  });

  test('回收站与系统盘日志清单共用盘符但不会被去重', () {
    final List<CleanupScanTarget> targets = CleanupTargetDiscovery.discover(
      environment: const <String, String>{'SYSTEMDRIVE': r'C:'},
    );
    final CleanupScanTarget recycle = targets.singleWhere(
      (CleanupScanTarget item) => item.id == 'system-recycle-bin',
    );
    final CleanupScanTarget logs = targets.singleWhere(
      (CleanupScanTarget item) => item.id == 'system-drive-log-inventory',
    );
    expect(recycle.strategy, CleanupTargetStrategy.recycleBin);
    expect(logs.strategy, CleanupTargetStrategy.directoryContents);
    expect(recycle.path, logs.path);
  });

  test('过期子目录按会话聚合且目录名称过滤有效', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vk_stale_child_dirs',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory stale = Directory(
      '${sandbox.path}${Platform.pathSeparator}16.1.old',
    )..createSync();
    File('${stale.path}${Platform.pathSeparator}payload.bin')
        .writeAsBytesSync(List<int>.filled(4096, 7));
    final Directory current = Directory(
      '${sandbox.path}${Platform.pathSeparator}16.2.current',
    )..createSync();
    File('${current.path}${Platform.pathSeparator}payload.bin')
        .writeAsBytesSync(List<int>.filled(8192, 8));

    final CleanupScanResult result = await CleanupScanner.scanTargets(
      <CleanupScanTarget>[
        CleanupScanTarget(
          id: 'stale-folders',
          label: '旧版本目录',
          path: sandbox.path,
          category: CleanupCategory.pluginResidual,
          defaultEnabled: true,
          strategy: CleanupTargetStrategy.staleChildDirectories,
          includePatterns: const <String>['*.old'],
          riskLevel: CleanupRiskLevel.cautious,
        ),
      ],
    );

    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.path, stale.path);
    expect(result.candidates.single.size, 4096);
    expect(result.candidates.single.defaultSelected, isFalse);
  });
}
