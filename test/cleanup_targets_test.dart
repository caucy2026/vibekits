import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';

void main() {
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
}
