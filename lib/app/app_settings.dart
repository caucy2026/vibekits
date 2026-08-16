import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

enum AppLogLevel { error, warning, info, debug }

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.restoreLastTab = true,
    this.lastTab = 0,
    this.logLevel = AppLogLevel.info,
    this.cacheLimitMb = 512,
    this.modelDirectory = '',
    this.archiveMaxEntries = 100000,
    this.archiveMaxFileMb = 2048,
    this.cleanupWhitelist = const <String>[],
    this.cleanupScanTargets = const <String>[],
    this.cleanupTargetCatalogVersion = 0,
    this.cleanupTotalReleasedBytes = 0,
    this.cleanupCompletedRuns = 0,
    this.recentDocumentPaths = const <String>[],
    this.remoteDatabaseProfiles = const <String>[],
    this.serialPortSettings = '',
    this.deepSeekHarnessWorkspace = '',
  });

  final ThemeMode themeMode;
  final bool restoreLastTab;
  final int lastTab;
  final AppLogLevel logLevel;
  final int cacheLimitMb;
  final String modelDirectory;
  final int archiveMaxEntries;
  final int archiveMaxFileMb;
  final List<String> cleanupWhitelist;
  final List<String> cleanupScanTargets;
  final int cleanupTargetCatalogVersion;
  final int cleanupTotalReleasedBytes;
  final int cleanupCompletedRuns;
  final List<String> recentDocumentPaths;
  final List<String> remoteDatabaseProfiles;
  final String serialPortSettings;
  final String deepSeekHarnessWorkspace;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? restoreLastTab,
    int? lastTab,
    AppLogLevel? logLevel,
    int? cacheLimitMb,
    String? modelDirectory,
    int? archiveMaxEntries,
    int? archiveMaxFileMb,
    List<String>? cleanupWhitelist,
    List<String>? cleanupScanTargets,
    int? cleanupTargetCatalogVersion,
    int? cleanupTotalReleasedBytes,
    int? cleanupCompletedRuns,
    List<String>? recentDocumentPaths,
    List<String>? remoteDatabaseProfiles,
    String? serialPortSettings,
    String? deepSeekHarnessWorkspace,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    restoreLastTab: restoreLastTab ?? this.restoreLastTab,
    lastTab: lastTab ?? this.lastTab,
    logLevel: logLevel ?? this.logLevel,
    cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
    modelDirectory: modelDirectory ?? this.modelDirectory,
    archiveMaxEntries: archiveMaxEntries ?? this.archiveMaxEntries,
    archiveMaxFileMb: archiveMaxFileMb ?? this.archiveMaxFileMb,
    cleanupWhitelist: cleanupWhitelist ?? this.cleanupWhitelist,
    cleanupScanTargets: cleanupScanTargets ?? this.cleanupScanTargets,
    cleanupTargetCatalogVersion:
        cleanupTargetCatalogVersion ?? this.cleanupTargetCatalogVersion,
    cleanupTotalReleasedBytes:
        cleanupTotalReleasedBytes ?? this.cleanupTotalReleasedBytes,
    cleanupCompletedRuns: cleanupCompletedRuns ?? this.cleanupCompletedRuns,
    recentDocumentPaths: recentDocumentPaths ?? this.recentDocumentPaths,
    remoteDatabaseProfiles:
        remoteDatabaseProfiles ?? this.remoteDatabaseProfiles,
    serialPortSettings: serialPortSettings ?? this.serialPortSettings,
    deepSeekHarnessWorkspace:
        deepSeekHarnessWorkspace ?? this.deepSeekHarnessWorkspace,
  );

  Map<String, Object> toJson() => <String, Object>{
    'themeMode': themeMode.name,
    'restoreLastTab': restoreLastTab,
    'lastTab': lastTab,
    'logLevel': logLevel.name,
    'cacheLimitMb': cacheLimitMb,
    'modelDirectory': modelDirectory,
    'archiveMaxEntries': archiveMaxEntries,
    'archiveMaxFileMb': archiveMaxFileMb,
    'cleanupWhitelist': cleanupWhitelist,
    'cleanupScanTargets': cleanupScanTargets,
    'cleanupTargetCatalogVersion': cleanupTargetCatalogVersion,
    'cleanupTotalReleasedBytes': cleanupTotalReleasedBytes,
    'cleanupCompletedRuns': cleanupCompletedRuns,
    'recentDocumentPaths': recentDocumentPaths,
    'remoteDatabaseProfiles': remoteDatabaseProfiles,
    'serialPortSettings': serialPortSettings,
    'deepSeekHarnessWorkspace': deepSeekHarnessWorkspace,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((T value) => value.name == json[key]).firstOrNull ??
        fallback;
    int boundedInt(String key, int fallback, int min, int max) {
      final Object? value = json[key];
      return value is int && value >= min && value <= max ? value : fallback;
    }

    return AppSettings(
      themeMode: enumValue(ThemeMode.values, 'themeMode', ThemeMode.system),
      restoreLastTab: json['restoreLastTab'] is bool
          ? json['restoreLastTab']! as bool
          : true,
      lastTab: boundedInt('lastTab', 0, 0, 4),
      logLevel: enumValue(AppLogLevel.values, 'logLevel', AppLogLevel.info),
      cacheLimitMb: boundedInt('cacheLimitMb', 512, 64, 8192),
      modelDirectory: json['modelDirectory'] is String
          ? json['modelDirectory']! as String
          : '',
      archiveMaxEntries: boundedInt('archiveMaxEntries', 100000, 1000, 1000000),
      archiveMaxFileMb: boundedInt('archiveMaxFileMb', 2048, 64, 102400),
      cleanupWhitelist: json['cleanupWhitelist'] is List<Object?>
          ? (json['cleanupWhitelist']! as List<Object?>)
                .whereType<String>()
                .where(
                  (String path) =>
                      path.length <= 1024 && !path.contains('\u0000'),
                )
                .take(100)
                .toList(growable: false)
          : const <String>[],
      cleanupScanTargets: json['cleanupScanTargets'] is List<Object?>
          ? (json['cleanupScanTargets']! as List<Object?>)
                .whereType<String>()
                .where(
                  (String id) => RegExp(r'^[a-z0-9.-]{1,100}$').hasMatch(id),
                )
                .toSet()
                .take(100)
                .toList(growable: false)
          : const <String>[],
      cleanupTargetCatalogVersion: boundedInt(
        'cleanupTargetCatalogVersion',
        0,
        0,
        100,
      ),
      cleanupTotalReleasedBytes: boundedInt(
        'cleanupTotalReleasedBytes',
        0,
        0,
        9000000000000000000,
      ),
      cleanupCompletedRuns: boundedInt(
        'cleanupCompletedRuns',
        0,
        0,
        1000000000,
      ),
      recentDocumentPaths: json['recentDocumentPaths'] is List<Object?>
          ? (json['recentDocumentPaths']! as List<Object?>)
                .whereType<String>()
                .where(
                  (String path) =>
                      path.isNotEmpty &&
                      path.length <= 32768 &&
                      !path.contains('\u0000'),
                )
                .toSet()
                .take(20)
                .toList(growable: false)
          : const <String>[],
      remoteDatabaseProfiles: json['remoteDatabaseProfiles'] is List<Object?>
          ? (json['remoteDatabaseProfiles']! as List<Object?>)
                .whereType<String>()
                .where(
                  (String profile) =>
                      profile.isNotEmpty && profile.length <= 4096,
                )
                .take(20)
                .toList(growable: false)
          : const <String>[],
      serialPortSettings:
          json['serialPortSettings'] is String &&
              (json['serialPortSettings']! as String).length <= 4096 &&
              !(json['serialPortSettings']! as String).contains('\u0000')
          ? json['serialPortSettings']! as String
          : '',
      deepSeekHarnessWorkspace:
          json['deepSeekHarnessWorkspace'] is String &&
              (json['deepSeekHarnessWorkspace']! as String).length <= 32768 &&
              !(json['deepSeekHarnessWorkspace']! as String).contains('\u0000')
          ? json['deepSeekHarnessWorkspace']! as String
          : '',
    );
  }
}

class AppSettingsStore {
  AppSettingsStore({File? file}) : _file = file ?? _defaultFile();

  final File _file;

  static File _defaultFile() {
    final String base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    return File(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}settings.json',
    );
  }

  Future<AppSettings> load() async {
    try {
      if (!await _file.exists()) return const AppSettings();
      final Object? decoded = jsonDecode(await _file.readAsString());
      return decoded is Map<String, Object?>
          ? AppSettings.fromJson(decoded)
          : const AppSettings();
    } on Object {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await _file.parent.create(recursive: true);
    final File temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({AppSettingsStore? store})
    : _store = store ?? AppSettingsStore();

  final AppSettingsStore _store;
  AppSettings value = const AppSettings();

  Future<void> load() async {
    value = await _store.load();
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    value = settings;
    notifyListeners();
    await _store.save(settings);
  }
}
