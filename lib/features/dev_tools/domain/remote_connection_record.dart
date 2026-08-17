import 'dart:convert';

import 'remote_session.dart';

class RemoteConnectionRecord {
  const RemoteConnectionRecord({
    required this.id,
    required this.name,
    required this.mode,
    required this.host,
    required this.user,
    required this.port,
    this.identityFile,
    this.favorite = false,
    this.lastUsedEpochMs = 0,
    this.hostKeyType,
    this.hostKeyFingerprint,
  });

  final String id;
  final String name;
  final RemoteSessionMode mode;
  final String host;
  final String user;
  final int port;
  final String? identityFile;
  final bool favorite;
  final int lastUsedEpochMs;
  final String? hostKeyType;
  final String? hostKeyFingerprint;

  String get credentialKey => 'vibekits.remote-session.$id';

  RemoteConnectionProfile get connection => RemoteConnectionProfile(
    host: host,
    user: user,
    port: port,
    identityFile: identityFile,
  );

  RemoteConnectionRecord copyWith({
    String? name,
    RemoteSessionMode? mode,
    String? host,
    String? user,
    int? port,
    String? identityFile,
    bool clearIdentityFile = false,
    bool? favorite,
    int? lastUsedEpochMs,
    String? hostKeyType,
    String? hostKeyFingerprint,
    bool clearHostKey = false,
  }) => RemoteConnectionRecord(
    id: id,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    host: host ?? this.host,
    user: user ?? this.user,
    port: port ?? this.port,
    identityFile: clearIdentityFile ? null : identityFile ?? this.identityFile,
    favorite: favorite ?? this.favorite,
    lastUsedEpochMs: lastUsedEpochMs ?? this.lastUsedEpochMs,
    hostKeyType: clearHostKey ? null : hostKeyType ?? this.hostKeyType,
    hostKeyFingerprint: clearHostKey
        ? null
        : hostKeyFingerprint ?? this.hostKeyFingerprint,
  );

  String encode() => jsonEncode(<String, Object?>{
    'version': 1,
    'id': id,
    'name': name,
    'mode': mode.name,
    'host': host,
    'user': user,
    'port': port,
    'identityFile': identityFile,
    'favorite': favorite,
    'lastUsedEpochMs': lastUsedEpochMs,
    'hostKeyType': hostKeyType,
    'hostKeyFingerprint': hostKeyFingerprint,
  });

  static RemoteConnectionRecord? decode(String source) {
    try {
      final Object? raw = jsonDecode(source);
      if (raw is! Map<String, Object?>) return null;
      final String id = '${raw['id'] ?? ''}'.trim();
      final String name = '${raw['name'] ?? ''}'.trim();
      final String host = '${raw['host'] ?? ''}'.trim();
      final String user = '${raw['user'] ?? ''}'.trim();
      final int? port = raw['port'] is int ? raw['port']! as int : null;
      final RemoteSessionMode? mode = RemoteSessionMode.values
          .where((RemoteSessionMode value) => value.name == raw['mode'])
          .firstOrNull;
      if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id) ||
          name.isEmpty ||
          name.length > 100 ||
          host.isEmpty ||
          host.length > 253 ||
          user.isEmpty && mode != RemoteSessionMode.remoteDesktop ||
          user.length > 128 ||
          port == null ||
          port < 1 ||
          port > 65535 ||
          mode == null) {
        return null;
      }
      final String? identity = raw['identityFile'] is String
          ? (raw['identityFile']! as String).trim()
          : null;
      final String? hostKeyType = raw['hostKeyType'] is String
          ? (raw['hostKeyType']! as String).trim()
          : null;
      final String? hostKeyFingerprint = raw['hostKeyFingerprint'] is String
          ? (raw['hostKeyFingerprint']! as String).trim()
          : null;
      final bool validHostKey =
          hostKeyType == null && hostKeyFingerprint == null ||
          hostKeyType != null &&
              hostKeyType.length <= 80 &&
              hostKeyFingerprint != null &&
              RegExp(r'^SHA256:[A-Za-z0-9+/]+$').hasMatch(hostKeyFingerprint);
      if (!validHostKey) return null;
      return RemoteConnectionRecord(
        id: id,
        name: name,
        mode: mode,
        host: host,
        user: user,
        port: port,
        identityFile: identity == null || identity.isEmpty ? null : identity,
        favorite: raw['favorite'] == true,
        lastUsedEpochMs:
            raw['lastUsedEpochMs'] is int &&
                (raw['lastUsedEpochMs']! as int) >= 0
            ? raw['lastUsedEpochMs']! as int
            : 0,
        hostKeyType: hostKeyType,
        hostKeyFingerprint: hostKeyFingerprint,
      );
    } on Object {
      return null;
    }
  }

  static List<RemoteConnectionRecord> decodeMany(Iterable<String> values) {
    final Map<String, RemoteConnectionRecord> unique =
        <String, RemoteConnectionRecord>{};
    for (final String value in values) {
      final RemoteConnectionRecord? record = decode(value);
      if (record != null) unique[record.id] = record;
    }
    final List<RemoteConnectionRecord> result = unique.values.toList()
      ..sort((RemoteConnectionRecord a, RemoteConnectionRecord b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return b.lastUsedEpochMs.compareTo(a.lastUsedEpochMs);
      });
    return result;
  }
}
