import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_settings.dart';

void main() {
  test('设置可持久化并恢复', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'vibekits_settings_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final AppSettingsStore store = AppSettingsStore(
      file: File('${directory.path}${Platform.pathSeparator}settings.json'),
    );
    const AppSettings expected = AppSettings(
      themeMode: ThemeMode.dark,
      restoreLastTab: true,
      lastTab: 3,
      logLevel: AppLogLevel.debug,
      cacheLimitMb: 1024,
      modelDirectory: r'D:\Models',
      archiveMaxEntries: 50000,
      archiveMaxFileMb: 4096,
      cleanupWhitelist: <String>[r'D:\Keep'],
      cleanupScanTargets: <String>['user-temp', 'crash-dumps'],
      cleanupTargetCatalogVersion: 2,
    );

    await store.save(expected);
    final AppSettings actual = await store.load();

    expect(actual.toJson(), expected.toJson());
  });

  test('设置文件损坏时安全恢复默认值', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'vibekits_settings_bad_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File file = File(
      '${directory.path}${Platform.pathSeparator}settings.json',
    );
    await file.writeAsString('{bad json');

    final AppSettings actual = await AppSettingsStore(file: file).load();

    expect(actual.themeMode, ThemeMode.system);
    expect(actual.cacheLimitMb, 512);
  });
}
