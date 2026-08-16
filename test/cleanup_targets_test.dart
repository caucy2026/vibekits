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
}
