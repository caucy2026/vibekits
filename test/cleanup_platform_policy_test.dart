import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_decision_engine.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_platform_policy.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_rule_database.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';

void main() {
  test('Windows、macOS、Android 目标发现互不串用', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_platform_targets_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Map<String, String> environment = <String, String>{
      'TEMP': '${sandbox.path}${Platform.pathSeparator}win-temp',
      'WINDIR': '${sandbox.path}${Platform.pathSeparator}Windows',
      'SYSTEMDRIVE': sandbox.path,
      'HOME': sandbox.path,
      'VIBEKITS_APP_CACHE': '${sandbox.path}${Platform.pathSeparator}app-cache',
    };
    Directory(environment['TEMP']!).createSync(recursive: true);
    Directory(environment['VIBEKITS_APP_CACHE']!).createSync(recursive: true);
    Directory(
      <String>[
        sandbox.path,
        'Library',
        'Developer',
        'Xcode',
        'DerivedData',
      ].join(Platform.pathSeparator),
    ).createSync(recursive: true);

    final List<CleanupScanTarget> windows = CleanupTargetDiscovery.discover(
      environment: environment,
      platform: CleanupPlatform.windows,
    );
    final List<CleanupScanTarget> macos = CleanupTargetDiscovery.discover(
      environment: environment,
      platform: CleanupPlatform.macos,
    );
    final List<CleanupScanTarget> android = CleanupTargetDiscovery.discover(
      environment: environment,
      platform: CleanupPlatform.android,
    );

    expect(
      windows.map((CleanupScanTarget item) => item.id),
      contains('user-temp'),
    );
    expect(
      windows.any((CleanupScanTarget item) => item.id.startsWith('mac-')),
      isFalse,
    );
    expect(
      macos.map((CleanupScanTarget item) => item.id),
      contains('mac-xcode-derived-data'),
    );
    expect(
      macos.any((CleanupScanTarget item) => item.id == 'user-temp'),
      isFalse,
    );
    expect(
      android.map((CleanupScanTarget item) => item.id),
      contains('android-vibekits-app-cache'),
    );
    expect(
      android.any((CleanupScanTarget item) => item.id.startsWith('mac-')),
      isFalse,
    );
    expect(
      android.any((CleanupScanTarget item) => item.id == 'user-temp'),
      isFalse,
    );
  });

  test('规则数据库只加载当前平台规则', () {
    final String source = jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'catalogVersion': 1,
      'rules': <Object?>[
        <String, Object?>{
          'id': 'windows-test-rule',
          'label': 'Windows 测试规则',
          'platform': 'windows',
          'pathTemplate': r'%TEMP%',
          'category': 'applicationCache',
          'risk': 'safe',
          'defaultEnabled': true,
          'cleanupAction': 'recycle',
          'impact': '测试缓存',
        },
      ],
    });
    final Map<String, String> env = <String, String>{
      'TEMP': Directory.systemTemp.path,
    };
    expect(
      CleanupRuleDatabase.parse(
        source,
        environment: env,
        platform: 'windows',
      ).targets,
      hasLength(1),
    );
    expect(
      CleanupRuleDatabase.parse(
        source,
        environment: env,
        platform: 'android',
      ).targets,
      isEmpty,
    );
  });

  test('Windows Gradle 缓存按完整旧版本目录复核且默认不选', () {
    final Directory home = Directory.systemTemp.createTempSync(
      'vk_gradle_policy_',
    );
    addTearDown(() => home.deleteSync(recursive: true));
    Directory(
      '${home.path}${Platform.pathSeparator}.gradle${Platform.pathSeparator}caches',
    ).createSync(recursive: true);
    final CleanupScanTarget target = CleanupTargetDiscovery.discover(
      environment: <String, String>{'USERPROFILE': home.path},
      platform: CleanupPlatform.windows,
    ).singleWhere((CleanupScanTarget item) => item.id == 'gradle-cache');

    expect(target.strategy, CleanupTargetStrategy.staleChildDirectories);
    expect(target.minimumAgeHours, 24 * 30);
    expect(target.defaultEnabled, isFalse);
    expect(target.riskLevel, CleanupRiskLevel.cautious);
  });

  test('Android 删除器只允许应用私有缓存，越界文件保持不变', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_android_delete_',
    );
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
    final Directory cache = Directory(
      '${sandbox.path}${Platform.pathSeparator}cache',
    )..createSync();
    final File inside = File('${cache.path}${Platform.pathSeparator}inside.tmp')
      ..writeAsStringSync('cache');
    final File outside = File(
      '${sandbox.path}${Platform.pathSeparator}outside.txt',
    )..writeAsStringSync('user data');
    CleanupCandidate candidate(File file) => CleanupCandidate(
      path: file.path,
      size: file.lengthSync(),
      modified: file.lastModifiedSync(),
      category: CleanupCategory.applicationCache,
      reason: '测试',
    );

    final CleanupDeleteResult result = await CleanupDeleter.deleteCandidates(
      <CleanupCandidate>[candidate(inside), candidate(outside)],
      platform: CleanupPlatform.android,
      environment: <String, String>{'VIBEKITS_APP_CACHE': cache.path},
    );

    expect(inside.existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
    expect(result.succeeded, 1);
    expect(result.skipped, 1);
  });

  test('Android 决策层把共享存储候选标记为受保护', () {
    const CleanupCandidate candidate = CleanupCandidate(
      path: '/storage/emulated/0/Download/project.zip',
      size: 1024,
      category: CleanupCategory.downloads,
      reason: '未知下载文件',
    );
    final CleanupDecision decision = CleanupDecisionEngine.buildPlan(
      const <CleanupCandidate>[candidate],
      platform: CleanupPlatform.android,
      environment: const <String, String>{
        'VIBEKITS_APP_CACHE': '/data/user/0/com.vibekits/cache',
      },
    ).decisions.single;
    expect(decision.tier, CleanupDecisionTier.protected);
    expect(decision.explanation, contains('安全边界'));
  });
}
