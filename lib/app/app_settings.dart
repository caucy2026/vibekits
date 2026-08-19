import 'dart:async';
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
    this.lastWorkspaceId = 'large-model',
    this.lastLargeModelView = 'agent',
    this.logLevel = AppLogLevel.info,
    this.cacheLimitMb = 512,
    this.modelDirectory = '',
    this.toolDownloadDirectory = '',
    this.archiveMaxEntries = 100000,
    this.archiveMaxFileMb = 2048,
    this.cleanupWhitelist = const <String>[],
    this.cleanupScanTargets = const <String>[],
    this.cleanupTargetCatalogVersion = 0,
    this.cleanupTotalReleasedBytes = 0,
    this.cleanupCompletedRuns = 0,
    this.recentDocumentPaths = const <String>[],
    this.remoteDatabaseProfiles = const <String>[],
    this.remoteSessionProfiles = const <String>[],
    this.serialPortSettings = '',
    this.deepSeekHarnessWorkspace = '',
    this.deepSeekHarnessDebugDirectory = '',
    this.rustDeskExecutable = '',
    this.rustDeskWebClientUrl = '',
  });

  final ThemeMode themeMode;
  final bool restoreLastTab;
  final int lastTab;
  final String lastWorkspaceId;
  final String lastLargeModelView;
  final AppLogLevel logLevel;
  final int cacheLimitMb;
  final String modelDirectory;
  final String toolDownloadDirectory;
  final int archiveMaxEntries;
  final int archiveMaxFileMb;
  final List<String> cleanupWhitelist;
  final List<String> cleanupScanTargets;
  final int cleanupTargetCatalogVersion;
  final int cleanupTotalReleasedBytes;
  final int cleanupCompletedRuns;
  final List<String> recentDocumentPaths;
  final List<String> remoteDatabaseProfiles;
  final List<String> remoteSessionProfiles;
  final String serialPortSettings;
  final String deepSeekHarnessWorkspace;
  final String deepSeekHarnessDebugDirectory;
  final String rustDeskExecutable;
  final String rustDeskWebClientUrl;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? restoreLastTab,
    int? lastTab,
    String? lastWorkspaceId,
    String? lastLargeModelView,
    AppLogLevel? logLevel,
    int? cacheLimitMb,
    String? modelDirectory,
    String? toolDownloadDirectory,
    int? archiveMaxEntries,
    int? archiveMaxFileMb,
    List<String>? cleanupWhitelist,
    List<String>? cleanupScanTargets,
    int? cleanupTargetCatalogVersion,
    int? cleanupTotalReleasedBytes,
    int? cleanupCompletedRuns,
    List<String>? recentDocumentPaths,
    List<String>? remoteDatabaseProfiles,
    List<String>? remoteSessionProfiles,
    String? serialPortSettings,
    String? deepSeekHarnessWorkspace,
    String? deepSeekHarnessDebugDirectory,
    String? rustDeskExecutable,
    String? rustDeskWebClientUrl,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    restoreLastTab: restoreLastTab ?? this.restoreLastTab,
    lastTab: lastTab ?? this.lastTab,
    lastWorkspaceId: lastWorkspaceId ?? this.lastWorkspaceId,
    lastLargeModelView: lastLargeModelView ?? this.lastLargeModelView,
    logLevel: logLevel ?? this.logLevel,
    cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
    modelDirectory: modelDirectory ?? this.modelDirectory,
    toolDownloadDirectory: toolDownloadDirectory ?? this.toolDownloadDirectory,
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
    remoteSessionProfiles: remoteSessionProfiles ?? this.remoteSessionProfiles,
    serialPortSettings: serialPortSettings ?? this.serialPortSettings,
    deepSeekHarnessWorkspace:
        deepSeekHarnessWorkspace ?? this.deepSeekHarnessWorkspace,
    deepSeekHarnessDebugDirectory:
        deepSeekHarnessDebugDirectory ?? this.deepSeekHarnessDebugDirectory,
    rustDeskExecutable: rustDeskExecutable ?? this.rustDeskExecutable,
    rustDeskWebClientUrl: rustDeskWebClientUrl ?? this.rustDeskWebClientUrl,
  );

  Map<String, Object> toJson() => <String, Object>{
    'themeMode': themeMode.name,
    'restoreLastTab': restoreLastTab,
    'lastTab': lastTab,
    'lastWorkspaceId': lastWorkspaceId,
    'lastLargeModelView': lastLargeModelView,
    'logLevel': logLevel.name,
    'cacheLimitMb': cacheLimitMb,
    'modelDirectory': modelDirectory,
    'toolDownloadDirectory': toolDownloadDirectory,
    'archiveMaxEntries': archiveMaxEntries,
    'archiveMaxFileMb': archiveMaxFileMb,
    'cleanupWhitelist': cleanupWhitelist,
    'cleanupScanTargets': cleanupScanTargets,
    'cleanupTargetCatalogVersion': cleanupTargetCatalogVersion,
    'cleanupTotalReleasedBytes': cleanupTotalReleasedBytes,
    'cleanupCompletedRuns': cleanupCompletedRuns,
    'recentDocumentPaths': recentDocumentPaths,
    'remoteDatabaseProfiles': remoteDatabaseProfiles,
    'remoteSessionProfiles': remoteSessionProfiles,
    'serialPortSettings': serialPortSettings,
    'deepSeekHarnessWorkspace': deepSeekHarnessWorkspace,
    'deepSeekHarnessDebugDirectory': deepSeekHarnessDebugDirectory,
    'rustDeskExecutable': rustDeskExecutable,
    'rustDeskWebClientUrl': rustDeskWebClientUrl,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((T value) => value.name == json[key]).firstOrNull ??
        fallback;
    int boundedInt(String key, int fallback, int min, int max) {
      final Object? value = json[key];
      return value is int && value >= min && value <= max ? value : fallback;
    }

    final int legacyLastTab = boundedInt('lastTab', 0, 0, 4);
    const List<String> legacyWorkspaceOrder = <String>[
      'archive',
      'cleaner',
      'documents',
      'dev-tools',
      'large-model',
    ];
    const Set<String> workspaceIds = <String>{
      'large-model',
      'archive',
      'cleaner',
      'documents',
      'dev-tools',
    };
    final String storedWorkspace = json['lastWorkspaceId'] is String
        ? json['lastWorkspaceId']! as String
        : '';
    final String lastWorkspaceId = workspaceIds.contains(storedWorkspace)
        ? storedWorkspace
        : legacyWorkspaceOrder[legacyLastTab];
    final String lastLargeModelView = json['lastLargeModelView'] == 'ocr'
        ? 'ocr'
        : 'agent';

    return AppSettings(
      themeMode: enumValue(ThemeMode.values, 'themeMode', ThemeMode.system),
      restoreLastTab: json['restoreLastTab'] is bool
          ? json['restoreLastTab']! as bool
          : true,
      lastTab: legacyLastTab,
      lastWorkspaceId: lastWorkspaceId,
      lastLargeModelView: lastLargeModelView,
      logLevel: enumValue(AppLogLevel.values, 'logLevel', AppLogLevel.info),
      cacheLimitMb: boundedInt('cacheLimitMb', 512, 64, 8192),
      modelDirectory: json['modelDirectory'] is String
          ? json['modelDirectory']! as String
          : '',
      toolDownloadDirectory:
          json['toolDownloadDirectory'] is String &&
              (json['toolDownloadDirectory']! as String).length <= 32768 &&
              !(json['toolDownloadDirectory']! as String).contains('\u0000')
          ? json['toolDownloadDirectory']! as String
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
      remoteSessionProfiles: json['remoteSessionProfiles'] is List<Object?>
          ? (json['remoteSessionProfiles']! as List<Object?>)
                .whereType<String>()
                .where(
                  (String profile) =>
                      profile.isNotEmpty &&
                      profile.length <= 4096 &&
                      !profile.contains('\u0000'),
                )
                .take(50)
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
      deepSeekHarnessDebugDirectory:
          json['deepSeekHarnessDebugDirectory'] is String &&
              (json['deepSeekHarnessDebugDirectory']! as String).length <=
                  32768 &&
              !(json['deepSeekHarnessDebugDirectory']! as String).contains(
                '\u0000',
              )
          ? json['deepSeekHarnessDebugDirectory']! as String
          : '',
      rustDeskExecutable:
          json['rustDeskExecutable'] is String &&
              (json['rustDeskExecutable']! as String).length <= 32768 &&
              !(json['rustDeskExecutable']! as String).contains('\u0000')
          ? json['rustDeskExecutable']! as String
          : '',
      rustDeskWebClientUrl:
          json['rustDeskWebClientUrl'] is String &&
              (json['rustDeskWebClientUrl']! as String).length <= 2048 &&
              !(json['rustDeskWebClientUrl']! as String).contains('\u0000')
          ? json['rustDeskWebClientUrl']! as String
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
    final List<File> candidates = <File>[
      _file,
      File(
        '${Directory.systemTemp.path}'
        '${Platform.pathSeparator}Vibekits${Platform.pathSeparator}settings.json',
      ),
    ];
    final String payload = jsonEncode(settings.toJson());
    Exception? lastError;

    for (final File target in candidates) {
      try {
        await target.parent.create(recursive: true);
        final File temporary = File('${target.path}.tmp');
        await temporary.writeAsString(payload, flush: true);
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
        return;
      } on Exception catch (error) {
        lastError = error;
      }
    }
    // Persisting settings is best-effort; avoid blocking startup if host
    // path permission is unavailable.
    if (lastError != null) {
      return;
    }
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({AppSettingsStore? store})
    : _store = store ?? AppSettingsStore();

  final AppSettingsStore _store;
  Timer? _backgroundSaveTimer;
  Future<void> _saveTail = Future<void>.value();
  AppSettings value = const AppSettings();

  Future<void> load() async {
    value = await _store.load();
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    _backgroundSaveTimer?.cancel();
    value = settings;
    notifyListeners();
    await _queueSave(settings);
  }

  /// Persists high-frequency workspace state without rebuilding the whole app.
  ///
  /// Navigation, recent-file and tool-local callbacks already update their own
  /// widgets. Notifying every root listener here used to rebuild the active
  /// workspace and race multiple atomic settings writes after a single click.
  Future<void> updateInBackground(AppSettings settings) {
    value = settings;
    _backgroundSaveTimer?.cancel();
    _backgroundSaveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_queueSave(value)),
    );
    return Future<void>.value();
  }

  Future<void> _queueSave(AppSettings settings) {
    final Completer<void> completed = Completer<void>();
    _saveTail = _saveTail
        .then((_) => _store.save(settings))
        .then(
          (_) {
            if (!completed.isCompleted) completed.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completed.isCompleted) {
              completed.completeError(error, stackTrace);
            }
          },
        );
    return completed.future;
  }

  @override
  void dispose() {
    final Timer? timer = _backgroundSaveTimer;
    if (timer?.isActive == true) {
      timer!.cancel();
      unawaited(_queueSave(value));
    }
    super.dispose();
  }
}
