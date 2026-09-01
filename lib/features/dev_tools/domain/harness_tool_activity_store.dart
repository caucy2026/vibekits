import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'semantic_workflow_service.dart';

enum HarnessToolActivityStatus { succeeded, failed, denied }

class HarnessToolActivity {
  const HarnessToolActivity({
    required this.id,
    required this.toolId,
    required this.toolName,
    required this.target,
    required this.argumentsSummary,
    required this.resultSummary,
    required this.status,
    required this.startedAt,
    required this.elapsedMs,
  });

  final String id;
  final String toolId;
  final String toolName;
  final String target;
  final String argumentsSummary;
  final String resultSummary;
  final HarnessToolActivityStatus status;
  final DateTime startedAt;
  final int elapsedMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'toolId': toolId,
    'toolName': toolName,
    'target': target,
    'argumentsSummary': argumentsSummary,
    'resultSummary': resultSummary,
    'status': status.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'elapsedMs': elapsedMs,
  };

  static HarnessToolActivity? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, Object?> item = Map<String, Object?>.from(value);
    final DateTime? startedAt = DateTime.tryParse('${item['startedAt'] ?? ''}');
    final HarnessToolActivityStatus? status = HarnessToolActivityStatus.values
        .where(
          (HarnessToolActivityStatus value) => value.name == item['status'],
        )
        .firstOrNull;
    if (startedAt == null || status == null) return null;
    String text(String key, {int max = 1024}) {
      final String result = item[key] is String ? item[key]! as String : '';
      return result.length <= max ? result : result.substring(0, max);
    }

    final String id = text('id', max: 100);
    final String toolId = text('toolId', max: 200);
    if (id.isEmpty || toolId.isEmpty) return null;
    return HarnessToolActivity(
      id: id,
      toolId: toolId,
      toolName: text('toolName', max: 200),
      target: text('target', max: 1024),
      argumentsSummary: text('argumentsSummary'),
      resultSummary: text('resultSummary'),
      status: status,
      startedAt: startedAt.toLocal(),
      elapsedMs: item['elapsedMs'] is int
          ? (item['elapsedMs']! as int).clamp(0, 86400000)
          : 0,
    );
  }
}

typedef HarnessToolActivityLoader =
    Future<List<HarnessToolActivity>> Function(Set<String> toolIds);
typedef HarnessToolActivityDeleter = Future<void> Function(String id);
typedef HarnessToolActivityClearer = Future<void> Function(Set<String> toolIds);
typedef HarnessToolActivityRecorder =
    Future<void> Function({
      required String toolId,
      required String toolName,
      required String target,
      required Map<String, Object?> arguments,
      required Object? result,
      required HarnessToolActivityStatus status,
      required DateTime startedAt,
    });

class HarnessToolLoggingPolicy {
  const HarnessToolLoggingPolicy({
    this.globalEnabled = true,
    this.disabledToolIds = const <String>{},
  });

  final bool globalEnabled;
  final Set<String> disabledToolIds;

  bool enabledFor(Set<String> toolIds) =>
      globalEnabled &&
      (toolIds.isEmpty ||
          toolIds.every((String toolId) => !disabledToolIds.contains(toolId)));

  HarnessToolLoggingPolicy setEnabled(
    bool enabled, {
    Set<String> toolIds = const <String>{},
  }) {
    if (toolIds.isEmpty) {
      return HarnessToolLoggingPolicy(
        globalEnabled: enabled,
        disabledToolIds: disabledToolIds,
      );
    }
    final Set<String> disabled = disabledToolIds.toSet();
    if (enabled) {
      disabled.removeAll(toolIds);
    } else {
      disabled.addAll(
        toolIds.where((String value) => value.startsWith('vibekits.')),
      );
    }
    return HarnessToolLoggingPolicy(
      globalEnabled: globalEnabled,
      disabledToolIds: Set<String>.unmodifiable(disabled),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 2,
    'enabled': globalEnabled,
    'disabledToolIds': disabledToolIds.toList()..sort(),
  };

  factory HarnessToolLoggingPolicy.fromJson(Object? decoded) {
    final bool enabled = decoded is Map && decoded['enabled'] is bool
        ? decoded['enabled']! as bool
        : true;
    final Set<String> disabled =
        decoded is Map && decoded['disabledToolIds'] is List
        ? (decoded['disabledToolIds']! as List)
              .map((Object? value) => '$value')
              .where((String value) => value.startsWith('vibekits.'))
              .take(1000)
              .toSet()
        : <String>{};
    return HarnessToolLoggingPolicy(
      globalEnabled: enabled,
      disabledToolIds: Set<String>.unmodifiable(disabled),
    );
  }
}

abstract final class HarnessToolActivityStore {
  static const int maxEntries = 200;
  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int targetFileBytes = 512 * 1024;
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static Future<void> _writeTail = Future<void>.value();
  static HarnessToolLoggingPolicy? _loggingPolicy;

  static Stream<void> get changes => _changes.stream;

  static Future<bool> loadLoggingEnabled([
    Set<String> toolIds = const <String>{},
  ]) async {
    await _loadLoggingSettings();
    return _loggingPolicy!.enabledFor(toolIds);
  }

  static Future<void> _loadLoggingSettings() async {
    if (_loggingPolicy != null) return;
    try {
      final File file = _settingsFile();
      if (!await file.exists()) {
        _loggingPolicy = const HarnessToolLoggingPolicy();
        return;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      _loggingPolicy = HarnessToolLoggingPolicy.fromJson(decoded);
    } on Object {
      _loggingPolicy = const HarnessToolLoggingPolicy();
    }
  }

  static Future<void> setLoggingEnabled(
    bool enabled, {
    Set<String> toolIds = const <String>{},
  }) async {
    await _loadLoggingSettings();
    _loggingPolicy = _loggingPolicy!.setEnabled(enabled, toolIds: toolIds);
    final File file = _settingsFile();
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(_loggingPolicy!.toJson()));
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    if (!_changes.isClosed) _changes.add(null);
  }

  static Future<List<HarnessToolActivity>> load(Set<String> toolIds) async {
    final List<HarnessToolActivity> entries = await _readAll();
    return entries
        .where(
          (HarnessToolActivity entry) =>
              toolIds.isEmpty || toolIds.contains(entry.toolId),
        )
        .toList(growable: false);
  }

  static Future<void> record({
    required String toolId,
    required String toolName,
    required String target,
    required Map<String, Object?> arguments,
    required Object? result,
    required HarnessToolActivityStatus status,
    required DateTime startedAt,
  }) async {
    await SemanticWorkflowService.instance.capture(
      toolId: toolId,
      toolName: toolName,
      target: target,
      arguments: Map<String, Object?>.from(_redact(arguments)! as Map),
      result: _redact(result),
      status: status.name,
      startedAt: startedAt,
    );
    if (!await loadLoggingEnabled(<String>{toolId})) return;
    return _enqueue(() async {
      final List<HarnessToolActivity> entries = await _readAll();
      entries.insert(
        0,
        HarnessToolActivity(
          id: '${startedAt.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
          toolId: toolId,
          toolName: toolName,
          target: _bounded(target, 1024),
          argumentsSummary: _summarize(arguments),
          resultSummary: _summarize(result),
          status: status,
          startedAt: startedAt,
          elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        ),
      );
      await _write(entries.take(maxEntries).toList(growable: false));
    });
  }

  /// Produces the same bounded, credential-redacted representation used by
  /// the persistent audit log. The Harness execution timeline uses this so
  /// visible tool details never expose raw tokens, passwords, or cookies.
  static String summarizeForDisplay(Object? value) => _summarize(value);

  static Future<void> delete(String id) => _enqueue(() async {
    final List<HarnessToolActivity> entries = await _readAll();
    entries.removeWhere((HarnessToolActivity entry) => entry.id == id);
    await _write(entries);
  });

  static Future<void> clear(Set<String> toolIds) => _enqueue(() async {
    final List<HarnessToolActivity> entries = await _readAll();
    entries.removeWhere(
      (HarnessToolActivity entry) =>
          toolIds.isEmpty || toolIds.contains(entry.toolId),
    );
    await _write(entries);
  });

  static Future<void> _enqueue(Future<void> Function() operation) {
    final Completer<void> completer = Completer<void>();
    _writeTail = _writeTail
        .catchError((Object _) {
          // A previous write failure must not permanently poison the queue.
        })
        .then((_) => operation())
        .then(
          (_) {
            if (!_changes.isClosed) _changes.add(null);
            completer.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        );
    return completer.future;
  }

  static Future<List<HarnessToolActivity>> _readAll() async {
    final File file = _file();
    try {
      if (!await file.exists()) {
        return <HarnessToolActivity>[];
      }
      final int originalBytes = await file.length();
      if (originalBytes > maxFileBytes) return <HarnessToolActivity>[];
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) {
        return <HarnessToolActivity>[];
      }
      final List<HarnessToolActivity> entries = <HarnessToolActivity>[];
      for (final Object? item in decoded['entries']! as List) {
        final HarnessToolActivity? entry = HarnessToolActivity.fromJson(item);
        if (entry != null) entries.add(entry);
      }
      entries.sort(
        (HarnessToolActivity a, HarnessToolActivity b) =>
            b.startedAt.compareTo(a.startedAt),
      );
      final List<HarnessToolActivity> bounded = entries
          .take(maxEntries)
          .toList(growable: true);
      if (originalBytes > targetFileBytes || entries.length > maxEntries) {
        await _write(bounded);
      }
      return bounded;
    } on Object {
      return <HarnessToolActivity>[];
    }
  }

  static Future<void> _write(List<HarnessToolActivity> entries) async {
    final File file = _file();
    await file.parent.create(recursive: true);
    final List<HarnessToolActivity> bounded = entries
        .take(maxEntries)
        .toList(growable: true);
    String payload = _encode(bounded);
    while (utf8.encode(payload).length > targetFileBytes &&
        bounded.isNotEmpty) {
      bounded.removeLast();
      payload = _encode(bounded);
    }
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static File _file() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return File(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
      '${Platform.pathSeparator}tool_activity.json',
    );
  }

  static File _settingsFile() => File(
    '${_file().parent.path}${Platform.pathSeparator}tool_activity_settings.json',
  );

  static String _summarize(Object? value) {
    final Object? redacted = _redact(value);
    final String encoded = redacted is String ? redacted : jsonEncode(redacted);
    return _bounded(encoded, 1024);
  }

  static String _encode(List<HarnessToolActivity> entries) =>
      jsonEncode(<String, Object?>{
        'version': 1,
        'entries': <Map<String, Object?>>[
          for (final HarnessToolActivity entry in entries) entry.toJson(),
        ],
      });

  static Object? _redact(Object? value, [String key = '']) {
    final String normalized = key.toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    if (RegExp(
      r'(password|secret|token|apikey|authorization|cookie|pairingcode)',
    ).hasMatch(normalized)) {
      return '<已隐藏>';
    }
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> item in value.entries)
          '${item.key}': _redact(item.value, '${item.key}'),
      };
    }
    if (value is Iterable) {
      return <Object?>[for (final Object? item in value) _redact(item)];
    }
    return value;
  }

  static String _bounded(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
