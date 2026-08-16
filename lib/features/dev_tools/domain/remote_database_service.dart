import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import 'platform_credential_store.dart';
import 'sqlite_database_service.dart';

class RemoteDatabaseProfile {
  const RemoteDatabaseProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.useTls,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String database;
  final String username;
  final bool useTls;

  String get endpointLabel => '$username@$host:$port/$database';

  String encode() => jsonEncode(<String, Object>{
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'useTls': useTls,
  });

  static RemoteDatabaseProfile? decode(String source) {
    try {
      final Object? raw = jsonDecode(source);
      if (raw is! Map<String, Object?>) return null;
      final String id = raw['id'] is String ? raw['id']! as String : '';
      final String host = raw['host'] is String ? raw['host']! as String : '';
      final String database = raw['database'] is String
          ? raw['database']! as String
          : '';
      final String username = raw['username'] is String
          ? raw['username']! as String
          : '';
      final int port = raw['port'] is int ? raw['port']! as int : 5432;
      if (id.isEmpty ||
          host.isEmpty ||
          database.isEmpty ||
          username.isEmpty ||
          port < 1 ||
          port > 65535) {
        return null;
      }
      return RemoteDatabaseProfile(
        id: id,
        name: raw['name'] is String && (raw['name']! as String).isNotEmpty
            ? raw['name']! as String
            : '$host/$database',
        host: host,
        port: port,
        database: database,
        username: username,
        useTls: raw['useTls'] != false,
      );
    } on Object {
      return null;
    }
  }

  static String createId({
    required String host,
    required int port,
    required String database,
    required String username,
  }) {
    final String source = '$username@$host:$port/$database'.toLowerCase();
    int hash = 0x811c9dc5;
    for (final int byte in utf8.encode(source)) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return 'postgres-$hash';
  }
}

class RemoteDatabaseObject {
  const RemoteDatabaseObject({required this.schema, required this.name});

  final String schema;
  final String name;

  String get label => schema == 'public' ? name : '$schema.$name';
}

class RemoteDatabaseSnapshot {
  const RemoteDatabaseSnapshot({
    required this.profile,
    required this.serverVersion,
    required this.objects,
    this.initialPage,
  });

  final RemoteDatabaseProfile profile;
  final String serverVersion;
  final List<RemoteDatabaseObject> objects;
  final SqliteResultPage? initialPage;
}

abstract final class RemoteDatabaseCredentials {
  static Future<String?> read(String profileId) =>
      PlatformCredentialStore.read(profileId);

  static Future<void> write(String profileId, String password) =>
      PlatformCredentialStore.write(profileId, password);

  static Future<void> delete(String profileId) =>
      PlatformCredentialStore.delete(profileId);
}

/// Bounded read-only PostgreSQL explorer for remote development databases.
abstract final class RemoteDatabaseService {
  static const int maxRows = 500;
  static const Duration timeout = Duration(seconds: 10);

  static Future<RemoteDatabaseSnapshot> inspect(
    RemoteDatabaseProfile profile,
    String password,
  ) async {
    final Connection connection = await _open(profile, password);
    try {
      final Result version = await connection.execute('SHOW server_version');
      final Result tables = await connection.execute('''
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_type IN ('BASE TABLE', 'VIEW')
  AND table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name
LIMIT 5001
''');
      if (tables.length > 5000) {
        throw const FormatException('远程数据库对象超过 5000 个，已停止加载');
      }
      final List<RemoteDatabaseObject> objects = tables
          .map(
            (ResultRow row) =>
                RemoteDatabaseObject(schema: '${row[0]}', name: '${row[1]}'),
          )
          .toList(growable: false);
      final SqliteResultPage? initialPage = objects.isEmpty
          ? null
          : await _loadTable(connection, objects.first, offset: 0);
      return RemoteDatabaseSnapshot(
        profile: profile,
        serverVersion: version.isEmpty ? 'PostgreSQL' : '${version.first[0]}',
        objects: objects,
        initialPage: initialPage,
      );
    } finally {
      await connection.close();
    }
  }

  static Future<SqliteResultPage> loadTable(
    RemoteDatabaseProfile profile,
    String password,
    RemoteDatabaseObject object, {
    int offset = 0,
  }) async {
    final Connection connection = await _open(profile, password);
    try {
      return await _loadTable(connection, object, offset: offset);
    } finally {
      await connection.close();
    }
  }

  static Future<SqliteResultPage> query(
    RemoteDatabaseProfile profile,
    String password,
    String sql,
  ) async {
    final String source = sql.trim();
    if (source.isEmpty) throw const FormatException('请输入 SQL');
    if (source.length > 65536) throw const FormatException('SQL 超过 64 KiB');
    final String firstWord =
        RegExp(
          r'^[a-z]+',
          caseSensitive: false,
        ).firstMatch(source)?.group(0)?.toUpperCase() ??
        '';
    if (!const <String>{
      'SELECT',
      'WITH',
      'SHOW',
      'EXPLAIN',
      'VALUES',
    }.contains(firstWord)) {
      throw const FormatException('当前远程工作区默认只读，写入 SQL 未执行');
    }
    final Connection connection = await _open(profile, password);
    try {
      final Result result = await connection.execute(source);
      return _pageFromResult(result, label: '远程 SQL 查询', rowLimit: maxRows);
    } finally {
      await connection.close();
    }
  }

  static Future<Connection> _open(
    RemoteDatabaseProfile profile,
    String password,
  ) {
    return Connection.open(
      Endpoint(
        host: profile.host,
        port: profile.port,
        database: profile.database,
        username: profile.username,
        password: password,
      ),
      settings: ConnectionSettings(
        applicationName: 'Vibekits',
        connectTimeout: timeout,
        queryTimeout: timeout,
        sslMode: profile.useTls ? SslMode.require : SslMode.disable,
      ),
    );
  }

  static Future<SqliteResultPage> _loadTable(
    Connection connection,
    RemoteDatabaseObject object, {
    required int offset,
  }) async {
    final String schema = _quoteIdentifier(object.schema);
    final String table = _quoteIdentifier(object.name);
    final Result result = await connection.execute(
      'SELECT * FROM $schema.$table LIMIT ${SqliteDatabaseService.defaultPageSize + 1} OFFSET ${offset.clamp(0, 1 << 62)}',
    );
    return _pageFromResult(
      result,
      label: object.label,
      offset: offset,
      rowLimit: SqliteDatabaseService.defaultPageSize,
    );
  }

  static SqliteResultPage _pageFromResult(
    Result result, {
    required String label,
    int offset = 0,
    required int rowLimit,
  }) {
    final bool hasMore = result.length > rowLimit;
    final List<String> columns = result.schema.columns
        .map((ResultSchemaColumn column) => column.columnName ?? '')
        .toList(growable: false);
    final List<List<String>> rows = result
        .take(rowLimit)
        .map(
          (ResultRow row) => row
              .map((Object? value) => _displayValue(value))
              .toList(growable: false),
        )
        .toList(growable: false);
    return SqliteResultPage(
      columns: columns,
      rows: rows,
      offset: offset,
      hasMore: hasMore,
      label: label,
    );
  }

  static String _quoteIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  static String _displayValue(Object? value) {
    if (value == null) return 'NULL';
    if (value is Uint8List) return '<BYTEA · ${value.length} bytes>';
    final String text = '$value'.replaceAll('\u0000', '␀');
    return text.length > 1000 ? '${text.substring(0, 1000)}…' : text;
  }
}
