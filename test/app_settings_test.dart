import 'dart:convert';
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
      lastWorkspaceId: 'documents',
      lastLargeModelView: 'ocr',
      logLevel: AppLogLevel.debug,
      cacheLimitMb: 1024,
      modelDirectory: r'D:\Models',
      toolDownloadDirectory: r'D:\Vibekits\Downloads',
      archiveMaxEntries: 50000,
      archiveMaxFileMb: 4096,
      cleanupWhitelist: <String>[r'D:\Keep'],
      cleanupScanTargets: <String>['user-temp', 'crash-dumps'],
      cleanupTargetCatalogVersion: 2,
      cleanupTotalReleasedBytes: 123456789,
      cleanupCompletedRuns: 7,
      recentDocumentPaths: <String>[r'D:\Docs\one.md', r'D:\Docs\two.log'],
      remoteDatabaseProfiles: <String>['{"id":"postgres-1"}'],
      remoteSessionProfiles: <String>['{"id":"remote-1"}'],
      serialPortSettings: '{"portName":"COM7","baudRate":115200,"dataBits":8,"parity":"none","stopBits":1,"flowControl":"none"}',
      serialSendHistory: <String>['status', 'help'],
      adbRecentAddresses: <String>['192.168.3.63:5555', '192.168.3.62:5555'],
      adbCommandHistory: <String>[
        'shell getprop ro.product.model',
        'shell wm size',
      ],
      deepSeekHarnessWorkspace: r'D:\Work\demo',
      deepSeekHarnessDebugDirectory: r'D:\Vibekits\tmp',
      rustDeskExecutable: r'C:\Program Files\RustDesk\RustDesk.exe',
      rustDeskWebClientUrl: 'https://remote.example.com/web',
    );

    await store.save(expected);
    final AppSettings actual = await store.load();

    expect(actual.toJson(), expected.toJson());
  });

  test('旧版数字页签迁移为稳定页面 ID', () {
    final AppSettings settings = AppSettings.fromJson(<String, Object?>{
      'lastTab': 4,
    });

    expect(settings.lastWorkspaceId, 'large-model');
    expect(settings.lastLargeModelView, 'agent');
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

  test('平台存储位置变化时迁移旧设置而不丢历史', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'vibekits_settings_migration_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File legacy = File(
      '${directory.path}${Platform.pathSeparator}legacy.json',
    );
    final File current = File(
      '${directory.path}${Platform.pathSeparator}new'
      '${Platform.pathSeparator}settings.json',
    );
    await legacy.writeAsString(
      jsonEncode(
        const AppSettings(
          remoteSessionProfiles: <String>['{"id":"ssh-remembered"}'],
          adbRecentAddresses: <String>['192.168.3.63:5555'],
        ).toJson(),
      ),
    );
    final AppSettingsStore store = AppSettingsStore(
      file: current,
      legacyFiles: <File>[legacy],
    );

    final AppSettings migrated = await store.load();

    expect(migrated.remoteSessionProfiles.single, contains('ssh-remembered'));
    expect(migrated.adbRecentAddresses.single, '192.168.3.63:5555');
    expect(await current.exists(), isTrue);
    expect(
      AppSettings.fromJson(
        jsonDecode(await current.readAsString()) as Map<String, Object?>,
      ).adbRecentAddresses,
      <String>['192.168.3.63:5555'],
    );
  });
}
