import 'dart:convert';
import 'dart:io';

class HarnessContinuationRecord {
  const HarnessContinuationRecord({
    required this.id,
    required this.workspace,
    required this.sourceSessionId,
    required this.continuationSessionId,
    required this.sourceTitleSnapshot,
    this.continuationTitleSnapshot = '',
    required this.summary,
    required this.sourceMessageCursor,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });

  final String id;
  final String workspace;
  final String sourceSessionId;
  final String continuationSessionId;
  final String sourceTitleSnapshot;
  final String continuationTitleSnapshot;
  final String summary;
  final String sourceMessageCursor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'workspace': workspace,
    'sourceSessionId': sourceSessionId,
    'continuationSessionId': continuationSessionId,
    'sourceTitleSnapshot': sourceTitleSnapshot,
    'continuationTitleSnapshot': continuationTitleSnapshot,
    'summary': summary,
    'sourceMessageCursor': sourceMessageCursor,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is HarnessContinuationRecord &&
      other.id == id &&
      other.workspace == workspace &&
      other.sourceSessionId == sourceSessionId &&
      other.continuationSessionId == continuationSessionId &&
      other.sourceTitleSnapshot == sourceTitleSnapshot &&
      other.continuationTitleSnapshot == continuationTitleSnapshot &&
      other.summary == summary &&
      other.sourceMessageCursor == sourceMessageCursor &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    workspace,
    sourceSessionId,
    continuationSessionId,
    sourceTitleSnapshot,
    continuationTitleSnapshot,
    summary,
    sourceMessageCursor,
    createdAt,
    updatedAt,
    schemaVersion,
  );
}

class HarnessContinuationStore {
  HarnessContinuationStore({Directory? home}) : home = home ?? _defaultHome();

  static const int maxSummaryCharacters = 24000;
  static const int maxRecords = 500;
  static const int maxFileBytes = 16 * 1024 * 1024;

  final Directory home;

  File get _file =>
      File('${home.path}${Platform.pathSeparator}continuations.json');

  Future<List<HarnessContinuationRecord>> load() async {
    final File file = _file;
    if (!await file.exists() || await file.length() > maxFileBytes) {
      return const <HarnessContinuationRecord>[];
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['records'] is! List) {
        return const <HarnessContinuationRecord>[];
      }
      return List<HarnessContinuationRecord>.unmodifiable(
        (decoded['records']! as List)
            .take(maxRecords)
            .map(_fromJson)
            .whereType<HarnessContinuationRecord>(),
      );
    } on Object {
      return const <HarnessContinuationRecord>[];
    }
  }

  Future<void> upsert(HarnessContinuationRecord record) async {
    final HarnessContinuationRecord normalized = _normalize(record);
    final List<HarnessContinuationRecord> records = List.of(await load())
      ..removeWhere(
        (item) =>
            item.id == normalized.id ||
            item.continuationSessionId == normalized.continuationSessionId,
      )
      ..add(normalized);
    records.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    if (records.length > maxRecords) {
      records.removeRange(0, records.length - maxRecords);
    }
    await _save(records);
  }

  Future<HarnessContinuationRecord?> sourceFor(
    String workspace,
    String continuationSessionId,
  ) async {
    final String key = _normalizeWorkspace(workspace);
    for (final HarnessContinuationRecord record in await load()) {
      if (record.workspace == key &&
          record.continuationSessionId == continuationSessionId) {
        return record;
      }
    }
    return null;
  }

  Future<List<HarnessContinuationRecord>> childrenFor(
    String workspace,
    String sourceSessionId,
  ) async {
    final String key = _normalizeWorkspace(workspace);
    return List<HarnessContinuationRecord>.unmodifiable(
      (await load()).where(
        (record) =>
            record.workspace == key &&
            record.sourceSessionId == sourceSessionId,
      ),
    );
  }

  Future<List<HarnessContinuationRecord>> recordsForWorkspace(
    String workspace,
  ) async {
    final String key = _normalizeWorkspace(workspace);
    return List<HarnessContinuationRecord>.unmodifiable(
      (await load()).where((record) => record.workspace == key),
    );
  }

  Future<void> removeWorkspace(String workspace) async {
    final String key = _normalizeWorkspace(workspace);
    await _save(
      (await load()).where((record) => record.workspace != key).toList(),
    );
  }

  /// Removes metadata owned by a deleted derived session. Relations whose
  /// source was deleted remain so the derived session can explicitly report
  /// that its source is no longer available.
  Future<void> removeContinuationSession(String sessionId) async {
    final String key = sessionId.trim();
    if (key.isEmpty) return;
    await _save(
      (await load())
          .where((record) => record.continuationSessionId != key)
          .toList(),
    );
  }

  /// Keep sidebar labels in sync with names persisted by the official Harness.
  Future<void> updateContinuationTitles(Map<String, String> titles) async {
    if (titles.isEmpty) return;
    bool changed = false;
    final records = <HarnessContinuationRecord>[];
    for (final record in await load()) {
      final title = titles[record.continuationSessionId]?.trim() ?? '';
      if (title.isEmpty || title == record.continuationTitleSnapshot) {
        records.add(record);
        continue;
      }
      changed = true;
      records.add(
        HarnessContinuationRecord(
          id: record.id,
          workspace: record.workspace,
          sourceSessionId: record.sourceSessionId,
          continuationSessionId: record.continuationSessionId,
          sourceTitleSnapshot: record.sourceTitleSnapshot,
          continuationTitleSnapshot: title,
          summary: record.summary,
          sourceMessageCursor: record.sourceMessageCursor,
          createdAt: record.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (changed) await _save(records);
  }

  Future<void> _save(List<HarnessContinuationRecord> records) async {
    await home.create(recursive: true);
    final File temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'records': records.map((record) => record.toJson()).toList(),
      }),
      flush: true,
    );
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }

  static HarnessContinuationRecord _normalize(
    HarnessContinuationRecord record,
  ) {
    if (record.schemaVersion != 1 ||
        record.id.trim().isEmpty ||
        record.sourceSessionId.trim().isEmpty ||
        record.continuationSessionId.trim().isEmpty ||
        record.summary.isEmpty ||
        record.summary.length > maxSummaryCharacters) {
      throw const FormatException('Harness 继续会话关系无效');
    }
    return HarnessContinuationRecord(
      id: record.id.trim(),
      workspace: _normalizeWorkspace(record.workspace),
      sourceSessionId: record.sourceSessionId.trim(),
      continuationSessionId: record.continuationSessionId.trim(),
      sourceTitleSnapshot: record.sourceTitleSnapshot.trim(),
      continuationTitleSnapshot: record.continuationTitleSnapshot.trim(),
      summary: record.summary,
      sourceMessageCursor: record.sourceMessageCursor.trim(),
      createdAt: record.createdAt.toUtc(),
      updatedAt: record.updatedAt.toUtc(),
    );
  }

  static HarnessContinuationRecord? _fromJson(Object? value) {
    if (value is! Map || value['schemaVersion'] != 1) return null;
    final DateTime? createdAt = DateTime.tryParse(
      '${value['createdAt'] ?? ''}',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      '${value['updatedAt'] ?? ''}',
    );
    if (createdAt == null || updatedAt == null) return null;
    try {
      return _normalize(
        HarnessContinuationRecord(
          id: '${value['id'] ?? ''}',
          workspace: '${value['workspace'] ?? ''}',
          sourceSessionId: '${value['sourceSessionId'] ?? ''}',
          continuationSessionId: '${value['continuationSessionId'] ?? ''}',
          sourceTitleSnapshot: '${value['sourceTitleSnapshot'] ?? ''}',
          continuationTitleSnapshot:
              '${value['continuationTitleSnapshot'] ?? ''}',
          summary: '${value['summary'] ?? ''}',
          sourceMessageCursor: '${value['sourceMessageCursor'] ?? ''}',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    } on FormatException {
      return null;
    }
  }

  static String _normalizeWorkspace(String workspace) {
    final String value = workspace.trim();
    if (value.isEmpty) return '';
    // Official Harness workspace ids are UUIDs, not filesystem paths. An
    // earlier build resolved bare ids against the app's working directory;
    // accept those persisted records while writing a stable id key now.
    final RegExpMatch? workspaceId = RegExp(
      r'(?:^|[/\\])([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})[/\\]?$',
    ).firstMatch(value);
    if (workspaceId != null) {
      return '/${workspaceId.group(1)!.toLowerCase()}/';
    }
    return Directory(value).absolute.uri.normalizePath().toFilePath();
  }

  static Directory _defaultHome() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return Directory(
      Platform.isWindows
          ? '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
          : '$base${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness',
    );
  }
}
