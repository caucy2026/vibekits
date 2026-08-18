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
  });

  final String text;
  final bool user;
  final int? elapsedMs;
  final int? exitCode;
  final bool stopped;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'user': user,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (exitCode != null) 'exitCode': exitCode,
    if (stopped) 'stopped': true,
  };
}

class HarnessConversationSnapshot {
  const HarnessConversationSnapshot({
    required this.workspace,
    required this.messages,
    required this.updatedAt,
  });

  final String workspace;
  final List<HarnessConversationMessage> messages;
  final DateTime updatedAt;
}

typedef HarnessConversationLoader =
    Future<HarnessConversationSnapshot?> Function(String workspace);
typedef HarnessConversationSaver = Future<void> Function(
  String workspace,
  List<HarnessConversationMessage> messages,
);

abstract final class HarnessConversationStore {
  static const int maxMessages = 80;
  static const int maxMessageCharacters = 65536;
  static const int maxFileBytes = 2 * 1024 * 1024;

  static Future<HarnessConversationSnapshot?> load(String workspace) async {
    final String normalized = _normalizeWorkspace(workspace);
    if (normalized.isEmpty) return null;
    final File file = _fileFor(normalized);
    if (!await file.exists()) return null;
    try {
      if (await file.length() > maxFileBytes) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['workspace'] != normalized) return null;
      final List<Object?> raw = decoded['messages'] is List
          ? List<Object?>.from(decoded['messages']! as List)
          : const <Object?>[];
      final List<HarnessConversationMessage> messages =
          <HarnessConversationMessage>[];
      for (final Object? value in raw.take(maxMessages)) {
        if (value is! Map) continue;
        final Map<String, Object?> item = Map<String, Object?>.from(value);
        final String text = item['text'] is String
            ? item['text']! as String
            : '';
        if (text.isEmpty || text.length > maxMessageCharacters) continue;
        messages.add(
          HarnessConversationMessage(
            text: text,
            user: item['user'] == true,
            elapsedMs: item['elapsedMs'] is int
                ? item['elapsedMs']! as int
                : null,
            exitCode: item['exitCode'] is int ? item['exitCode']! as int : null,
            stopped: item['stopped'] == true,
          ),
        );
      }
      return HarnessConversationSnapshot(
        workspace: normalized,
        messages: List<HarnessConversationMessage>.unmodifiable(messages),
        updatedAt:
            DateTime.tryParse('${decoded['updatedAt'] ?? ''}') ??
            (await file.stat()).modified,
      );
    } on Object {
      return null;
    }
  }

  static Future<void> save(
    String workspace,
    List<HarnessConversationMessage> messages,
  ) async {
    final String normalized = _normalizeWorkspace(workspace);
    if (normalized.isEmpty) return;
    final File file = _fileFor(normalized);
    await file.parent.create(recursive: true);
    final List<HarnessConversationMessage> bounded = messages
        .where((HarnessConversationMessage item) => item.text.isNotEmpty)
        .map(
          (HarnessConversationMessage item) => HarnessConversationMessage(
            text: item.text.length <= maxMessageCharacters
                ? item.text
                : item.text.substring(item.text.length - maxMessageCharacters),
            user: item.user,
            elapsedMs: item.elapsedMs,
            exitCode: item.exitCode,
            stopped: item.stopped,
          ),
        )
        .toList(growable: false);
    final List<HarnessConversationMessage> tail = bounded.length <= maxMessages
        ? bounded
        : bounded.sublist(bounded.length - maxMessages);
    final String payload = jsonEncode(<String, Object?>{
      'version': 1,
      'workspace': normalized,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'messages': <Map<String, Object?>>[
        for (final HarnessConversationMessage message in tail) message.toJson(),
      ],
    });
    if (utf8.encode(payload).length > maxFileBytes) {
      throw const FileSystemException('Harness 会话记录超过 2 MiB');
    }
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static File _fileFor(String workspace) {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    final String id = sha256.convert(utf8.encode(workspace)).toString();
    return File(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
      '${Platform.pathSeparator}conversations${Platform.pathSeparator}$id.json',
    );
  }

  static String _normalizeWorkspace(String value) {
    final String normalized = value.trim().replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
