import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_os_profile.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_platform_policy.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

void main() {
  test('macOS unknown or future version never implies latest supported', () {
    expect(CleanupOsProfile.parseMacosMajor('Version 12.7.6 (Build 21H1320)'), 12);
    expect(CleanupOsProfile.parseMacosMajor('macOS 26.0'), 26);
    expect(CleanupOsProfile.parseMacosMajor('Darwin unknown'), null);
    expect(const CleanupOsProfile(macosMajor: 99).knownMacos, false);
  });
  test('Android storage generations all keep app-only scope', () {
    expect(const CleanupOsProfile(androidSdk: 28).androidStoragePolicy, contains('旧存储'));
    expect(const CleanupOsProfile(androidSdk: 29).androidStoragePolicy, contains('过渡'));
    expect(const CleanupOsProfile(androidSdk: 32).androidStoragePolicy, contains('私有缓存'));
    expect(const CleanupOsProfile(androidSdk: 99).knownAndroid, false);
  });
  test('unknown Android cache is not preselected and requires review', () {
    final root = Directory.systemTemp.createTempSync('cleanup-version-test-');
    addTearDown(() => root.deleteSync(recursive: true));
    final target = CleanupTargetDiscovery.discover(platform: CleanupPlatform.android,
      appCacheDirectory: root.path).single;
    expect(target.defaultEnabled, false);
    expect(target.minimumAgeHours, 168);
    expect(target.riskLevel, CleanupRiskLevel.cautious);
    final known = CleanupTargetDiscovery.discover(platform: CleanupPlatform.android,
      androidSdk: 32, appCacheDirectory: root.path).single;
    expect(known.defaultEnabled, true);
    expect(known.minimumAgeHours, 24);
    expect(known.ruleSource, contains('SDK 32'));
  });
}
