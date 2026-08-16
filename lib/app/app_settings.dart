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
