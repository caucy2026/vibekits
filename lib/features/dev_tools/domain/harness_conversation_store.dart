import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class HarnessConversationMessage {
  const HarnessConversationMessage({
    required this.text,
    required this.user,
    this.elapsedMs,
    this.exitCode,
    this.stopped = false,
    this.executionTrace = '',
  });

  final String text;
  final bool user;
  final int? elapsedMs;
  final int? exitCode;
  final bool stopped;
  final String executionTrace;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'user': user,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (exitCode != null) 'exitCode': exitCode,
    if (stopped) 'stopped': true,
    if (executionTrace.isNotEmpty) 'executionTrace': executionTrace,
  };

  static HarnessConversationMessage? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, Object?> item = Map<String, Object?>.from(value);
    final String text = item['text'] is String ? item['text']! as String : '';
    if (text.isEmpty ||
        text.length > HarnessConversationStore.maxMessageCharacters) {
      return null;
    }
    final String rawTrace = item['executionTrace'] is String
        ? item['executionTrace']! as String
        : '';
    final String executionTrace =
        rawTrace.length <= HarnessConversationStore.maxExecutionTraceCharacters
        ? rawTrace
        : rawTrace.substring(
            0,
            HarnessConversationStore.maxExecutionTraceCharacters,
          );
    return HarnessConversationMessage(
      text: text,
      user: item['user'] == true,
      elapsedMs: item['elapsedMs'] is int ? item['elapsedMs']! as int : null,
      exitCode: item['exitCode'] is int ? item['exitCode']! as int : null,
      stopped: item['stopped'] == true,
      executionTrace: executionTrace,
    );
  }
}

class HarnessConversationSession {
  const HarnessConversationSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<HarnessConversationMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  HarnessConversationSession copyWith({
    String? title,
    List<HarnessConversationMessage>? messages,
    DateTime? updatedAt,
  }) => HarnessConversationSession(
    id: id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class HarnessConversationProject {
  const HarnessConversationProject({
    required this.workspace,
    required this.sessions,
    required this.activeSessionId,
    required this.updatedAt,
  });

  final String workspace;
  final List<HarnessConversationSession> sessions;
  final String? activeSessionId;
  final DateTime updatedAt;
}

typedef HarnessConversationLoader =
    Future<HarnessConversationProject?> Function(String workspace);
typedef HarnessConversationSaver = Future<void> Function(
  HarnessConversationProject project,
);
typedef HarnessWorkspaceCatalogLoader = Future<List<String>> Function();
typedef HarnessWorkspaceCatalogSaver = Future<void> Function(
  List<String> workspaces,
);

abstract final class HarnessConversationStore {
  static const int maxSessions = 40;
  static const int maxMessages = 80;
  static const int maxMessageCharacters = 65536;
  static const int maxExecutionTraceCharacters = 32768;
  static const int maxFileBytes = 8 * 1024 * 1024;
  static const int maxWorkspaces = 40;
  static final Map<String, Future<void>> _saveQueues = <String, Future<void>>{};

  static Future<List<String>> loadWorkspaceCatalog() async {
    final File file = _catalogFile();
    if (!await file.exists()) return const <String>[];
    try {
      if (await file.length() > 64 * 1024) return const <String>[];
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['workspaces'] is! List) {
        return const <String>[];
      }
      return List<String>.unmodifiable(
        _normalizeWorkspaceList(
          (decoded['workspaces']! as List).whereType<String>(),
        ),
      );
    } on Object {
      return const <String>[];
    }
  }

  static Future<void> saveWorkspaceCatalog(List<String> workspaces) async {
    final List<String> normalized = _normalizeWorkspaceList(workspaces);
    final File file = _catalogFile();
    final Map<String, String> names = await loadWorkspaceNames();
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 2,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'workspaces': normalized,
        'names': <String, String>{
          for (final String workspace in normalized)
            if (names[workspace]?.isNotEmpty == true)
              workspace: names[workspace]!,
        },
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static Future<Map<String, String>> loadWorkspaceNames() async {
    final File file = _catalogFile();
    if (!await file.exists()) return const <String, String>{};
    try {
      if (await file.length() > 64 * 1024) return const <String, String>{};
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['names'] is! Map) {
        return const <String, String>{};
      }
      final Map<String, String> result = <String, String>{};
      for (final MapEntry<Object?, Object?> entry
          in (decoded['names']! as Map).entries) {
        if (entry.key is! String || entry.value is! String) continue;
        final String workspace = _normalizeWorkspace(entry.key! as String);
        final String name = (entry.value! as String).trim();
        if (workspace.isNotEmpty && name.isNotEmpty && name.length <= 80) {
          result[workspace] = name;
        }
      }
      return Map<String, String>.unmodifiable(result);
    } on Object {
      return const <String, String>{};
    }
  }

  static Future<void> saveWorkspaceName(String workspace, String? name) async {
    final String normalized = _normalizeWorkspace(workspace);
    if (normalized.isEmpty) return;
    final List<String> workspaces = await loadWorkspaceCatalog();
    final Map<String, String> names = Map<String, String>.of(
      await loadWorkspaceNames(),
    );
    final String value = name?.trim() ?? '';
    if (value.isEmpty) {
      names.remove(normalized);
    } else {
      names[normalized] = value.length <= 80 ? value : value.substring(0, 80);
    }
    final File file = _catalogFile();
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 2,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'workspaces': workspaces,
        'names': names,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static Future<HarnessConversationProject?> load(String workspace) async {
    final String normalized = _normalizeWorkspace(workspace);
    if (normalized.isEmpty) return null;
    final File file = _fileFor(normalized);
    if (!await file.exists()) return null;
    try {
      if (await file.length() > maxFileBytes) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['workspace'] != normalized) return null;
      final DateTime fileUpdatedAt =
          DateTime.tryParse('${decoded['updatedAt'] ?? ''}') ??
          (await file.stat()).modified;
      if (decoded['sessions'] is List) {
        final List<HarnessConversationSession> sessions =
            <HarnessConversationSession>[];
        for (final Object? raw in (decoded['sessions']! as List).take(
          maxSessions,
        )) {
          final HarnessConversationSession? session = _sessionFromJson(raw);
          if (session != null) sessions.add(session);
        }
        sessions.sort(
          (HarnessConversationSession left, HarnessConversationSession right) =>
              right.updatedAt.compareTo(left.updatedAt),
        );
        final String requestedActive = '${decoded['activeSessionId'] ?? ''}';
        final String? active =
            sessions.any(
              (HarnessConversationSession session) =>
                  session.id == requestedActive,
            )
            ? requestedActive
            : sessions.firstOrNull?.id;
        return HarnessConversationProject(
          workspace: normalized,
          sessions: List<HarnessConversationSession>.unmodifiable(sessions),
          activeSessionId: active,
          updatedAt: fileUpdatedAt,
        );
      }
      final List<HarnessConversationMessage> messages = _messagesFromJson(
        decoded['messages'],
      );
      if (messages.isEmpty) return null;
      final HarnessConversationSession migrated = HarnessConversationSession(
        id: 'legacy-${fileUpdatedAt.microsecondsSinceEpoch}',
        title: _titleFor(messages),
        messages: messages,
        createdAt: fileUpdatedAt,
        updatedAt: fileUpdatedAt,
      );
      return HarnessConversationProject(
        workspace: normalized,
        sessions: <HarnessConversationSession>[migrated],
        activeSessionId: migrated.id,
        updatedAt: fileUpdatedAt,
      );
    } on Object {
      return null;
    }
  }

  static Future<void> save(HarnessConversationProject project) async {
    final String normalized = _normalizeWorkspace(project.workspace);
    if (normalized.isEmpty) return;
    final Future<void> previous =
        _saveQueues[normalized] ?? Future<void>.value();
    final Future<void> operation = previous
        .catchError((Object _) {})
        .then((_) => _saveProject(normalized, project));
    _saveQueues[normalized] = operation;
    try {
      await operation;
    } finally {
      if (identical(_saveQueues[normalized], operation)) {
        _saveQueues.remove(normalized);
      }
    }
  }

  static Future<void> _saveProject(
    String normalized,
    HarnessConversationProject project,
  ) async {
    final List<HarnessConversationSession> sessions =
        project.sessions
            .where(
              (HarnessConversationSession session) => session.id.isNotEmpty,
            )
            .map(_boundedSession)
            .toList(growable: false)
          ..sort(
            (
              HarnessConversationSession left,
              HarnessConversationSession right,
            ) => right.updatedAt.compareTo(left.updatedAt),
          );
    final List<HarnessConversationSession> bounded = sessions
        .take(maxSessions)
        .toList(growable: false);
    final String? active =
        bounded.any(
          (HarnessConversationSession session) =>
              session.id == project.activeSessionId,
        )
        ? project.activeSessionId
        : bounded.firstOrNull?.id;
    final String payload = jsonEncode(<String, Object?>{
      'version': 2,
      'workspace': normalized,
      'activeSessionId': active,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'sessions': <Map<String, Object?>>[
        for (final HarnessConversationSession session in bounded)
          <String, Object?>{
            'id': session.id,
            'title': session.title,
            'createdAt': session.createdAt.toUtc().toIso8601String(),
            'updatedAt': session.updatedAt.toUtc().toIso8601String(),
            'messages': <Map<String, Object?>>[
              for (final HarnessConversationMessage message in session.messages)
                message.toJson(),
            ],
          },
      ],
    });
    if (utf8.encode(payload).length > maxFileBytes) {
      throw const FileSystemException('Harness 项目会话记录超过 8 MiB');
    }
    final File file = _fileFor(normalized);
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static HarnessConversationSession? _sessionFromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, Object?> item = Map<String, Object?>.from(value);
    final String id = '${item['id'] ?? ''}'.trim();
    final DateTime? createdAt = DateTime.tryParse('${item['createdAt'] ?? ''}');
    final DateTime? updatedAt = DateTime.tryParse('${item['updatedAt'] ?? ''}');
    if (id.isEmpty || createdAt == null || updatedAt == null) return null;
    final List<HarnessConversationMessage> messages = _messagesFromJson(
      item['messages'],
    );
    return HarnessConversationSession(
      id: id.length <= 100 ? id : id.substring(0, 100),
      title: _boundedTitle('${item['title'] ?? ''}', messages),
      messages: messages,
      createdAt: createdAt.toLocal(),
      updatedAt: updatedAt.toLocal(),
    );
  }

  static List<HarnessConversationMessage> _messagesFromJson(Object? value) {
    if (value is! List) return const <HarnessConversationMessage>[];
    final List<HarnessConversationMessage> messages =
        <HarnessConversationMessage>[];
    for (final Object? raw in value.take(maxMessages)) {
      final HarnessConversationMessage? message =
          HarnessConversationMessage.fromJson(raw);
      if (message != null) messages.add(message);
    }
    return List<HarnessConversationMessage>.unmodifiable(messages);
  }

  static HarnessConversationSession _boundedSession(
    HarnessConversationSession session,
  ) {
    final List<HarnessConversationMessage> messages = session.messages
        .where((HarnessConversationMessage message) => message.text.isNotEmpty)
        .map(
          (HarnessConversationMessage message) => HarnessConversationMessage(
            text: message.text.length <= maxMessageCharacters
                ? message.text
                : message.text.substring(
                    message.text.length - maxMessageCharacters,
                  ),
            user: message.user,
            elapsedMs: message.elapsedMs,
            exitCode: message.exitCode,
            stopped: message.stopped,
            executionTrace: message.executionTrace,
          ),
        )
        .toList(growable: false);
    final List<HarnessConversationMessage> tail = messages.length <= maxMessages
        ? messages
        : messages.sublist(messages.length - maxMessages);
    return session.copyWith(
      title: _boundedTitle(session.title, tail),
      messages: List<HarnessConversationMessage>.unmodifiable(tail),
    );
  }

  static String _titleFor(List<HarnessConversationMessage> messages) =>
      _boundedTitle(
        messages
                .where((HarnessConversationMessage message) => message.user)
                .firstOrNull
                ?.text ??
            '新会话',
        messages,
      );

  static String _boundedTitle(
    String value,
    List<HarnessConversationMessage> messages,
  ) {
    final String normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    final String fallback = normalized.isEmpty
        ? _titleForFallback(messages)
        : normalized;
    return fallback.length <= 48 ? fallback : '${fallback.substring(0, 48)}…';
  }

  static String _titleForFallback(List<HarnessConversationMessage> messages) {
    final String text =
        messages
            .where((HarnessConversationMessage message) => message.user)
            .firstOrNull
            ?.text
            .trim() ??
        '';
    return text.isEmpty ? '新会话' : text;
  }

  static File _fileFor(String workspace) {
    final String id = sha256.convert(utf8.encode(workspace)).toString();
    return File(
      '${_harnessStoreDirectory().path}${Platform.pathSeparator}conversations'
      '${Platform.pathSeparator}$id.json',
    );
  }

  static File _catalogFile() => File(
    '${_harnessStoreDirectory().path}${Platform.pathSeparator}workspace-catalog.json',
  );

  static Directory _harnessStoreDirectory() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return Directory(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness',
    );
  }

  static List<String> _normalizeWorkspaceList(Iterable<String> values) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String raw in values) {
      final String workspace = _normalizeWorkspace(raw);
      if (workspace.isEmpty || !Directory(workspace).isAbsolute) continue;
      final String identity = Platform.isWindows
          ? workspace.toLowerCase()
          : workspace;
      if (!seen.add(identity)) continue;
      result.add(workspace);
      if (result.length == maxWorkspaces) break;
    }
    return result;
  }

  static String _normalizeWorkspace(String value) {
    final String normalized = value.trim().replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
