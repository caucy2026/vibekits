import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mysql_dart/mysql_dart.dart';
import 'package:postgres/postgres.dart';

import 'platform_credential_store.dart';
import 'sqlite_database_service.dart';

enum RemoteDatabaseEngine { postgresql, mysql, mariaDb }

extension RemoteDatabaseEngineInfo on RemoteDatabaseEngine {
  String get storageName => switch (this) {
    RemoteDatabaseEngine.postgresql => 'postgresql',
    RemoteDatabaseEngine.mysql => 'mysql',
    RemoteDatabaseEngine.mariaDb => 'mariadb',
  };

  String get label => switch (this) {
    RemoteDatabaseEngine.postgresql => 'PostgreSQL',
    RemoteDatabaseEngine.mysql => 'MySQL',
    RemoteDatabaseEngine.mariaDb => 'MariaDB',
  };

  int get defaultPort => switch (this) {
    RemoteDatabaseEngine.postgresql => 5432,
    RemoteDatabaseEngine.mysql || RemoteDatabaseEngine.mariaDb => 3306,
  };

  String get defaultDatabase => switch (this) {
    RemoteDatabaseEngine.postgresql => 'postgres',
    RemoteDatabaseEngine.mysql || RemoteDatabaseEngine.mariaDb => 'mysql',
  };

  String get defaultUsername => switch (this) {
    RemoteDatabaseEngine.postgresql => 'postgres',
    RemoteDatabaseEngine.mysql || RemoteDatabaseEngine.mariaDb => 'root',
  };

  static RemoteDatabaseEngine parse(Object? value) => switch (value) {
    'mysql' => RemoteDatabaseEngine.mysql,
    'mariadb' => RemoteDatabaseEngine.mariaDb,
    _ => RemoteDatabaseEngine.postgresql,
  };
}

class RemoteDatabaseProfile {
  const RemoteDatabaseProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.useTls,
    this.engine = RemoteDatabaseEngine.postgresql,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String database;
  final String username;
  final bool useTls;
  final RemoteDatabaseEngine engine;

  String get endpointLabel => '$username@$host:$port/$database';

  Map<String, Object> toMap() => <String, Object>{
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'useTls': useTls,
    'engine': engine.storageName,
  };

  String encode() => jsonEncode(toMap());

  static RemoteDatabaseProfile? decode(String source) {
    try {
      final Object? raw = jsonDecode(source);
      return raw is Map ? fromMap(Map<String, Object?>.from(raw)) : null;
    } on Object {
      return null;
    }
  }

  static RemoteDatabaseProfile? fromMap(Map<String, Object?> raw) {
    final String id = raw['id'] is String ? raw['id']! as String : '';
    final String host = raw['host'] is String ? raw['host']! as String : '';
    final String database = raw['database'] is String
        ? raw['database']! as String
        : '';
    final String username = raw['username'] is String
        ? raw['username']! as String
        : '';
    final RemoteDatabaseEngine engine = RemoteDatabaseEngineInfo.parse(
      raw['engine'],
    );
    final int port = raw['port'] is int
        ? raw['port']! as int
        : engine.defaultPort;
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
      engine: engine,
    );
  }

  static String createId({
    required String host,
    required int port,
    required String database,
    required String username,
    RemoteDatabaseEngine engine = RemoteDatabaseEngine.postgresql,
  }) {
    final String source =
        '${engine.storageName}:$username@$host:$port/$database'.toLowerCase();
    int hash = 0x811c9dc5;
    for (final int byte in utf8.encode(source)) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    final String prefix = switch (engine) {
      RemoteDatabaseEngine.postgresql => 'postgres',
      RemoteDatabaseEngine.mysql => 'mysql',
      RemoteDatabaseEngine.mariaDb => 'mariadb',
    };
    return '$prefix-$hash';
  }
}

class RemoteDatabaseObject {
  const RemoteDatabaseObject({required this.schema, required this.name});

  final String schema;
  final String name;

  String get label => schema == 'public' ? name : '$schema.$name';

  Map<String, Object> toMap() => <String, Object>{
    'schema': schema,
    'name': name,
  };

  static RemoteDatabaseObject fromMap(Map<String, Object?> map) =>
      RemoteDatabaseObject(schema: '${map['schema']}', name: '${map['name']}');
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

class RemoteDatabaseCancellation {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final void Function() listener in _listeners.toList()) {
      listener();
    }
  }

  void addCancelListener(void Function() listener) => _listeners.add(listener);

  void removeCancelListener(void Function() listener) =>
      _listeners.remove(listener);
}

class RemoteDatabaseCancelledException implements Exception {
  const RemoteDatabaseCancelledException();

  @override
  String toString() => '数据库操作已取消';
}

abstract final class RemoteDatabaseCredentials {
  static Future<String?> read(String profileId) =>
      PlatformCredentialStore.read(profileId);

  static Future<void> write(String profileId, String password) =>
      PlatformCredentialStore.write(profileId, password);

  static Future<void> delete(String profileId) =>
      PlatformCredentialStore.delete(profileId);
}

/// Bounded read-only PostgreSQL/MySQL/MariaDB explorer.
///
/// Every request owns a short-lived worker isolate and database connection.
/// Cancelling or timing out kills the isolate, which also closes its socket, so
/// a slow remote host never blocks the Flutter UI isolate or window message pump.
abstract final class RemoteDatabaseService {
  static const int maxRows = 500;
  static const Duration taskTimeout = Duration(seconds: 15);

  static Future<RemoteDatabaseSnapshot> inspect(
    RemoteDatabaseProfile profile,
    String password, {
    RemoteDatabaseCancellation? cancellation,
  }) async {
    final Map<String, Object?> response = await _run(<String, Object?>{
      'action': 'inspect',
      'profile': profile.toMap(),
      'password': password,
    }, cancellation: cancellation);
    return _snapshotFromMap(response);
  }

  static Future<SqliteResultPage> loadTable(
    RemoteDatabaseProfile profile,
    String password,
    RemoteDatabaseObject object, {
    int offset = 0,
    RemoteDatabaseCancellation? cancellation,
  }) async {
    final Map<String, Object?> response = await _run(<String, Object?>{
      'action': 'table',
      'profile': profile.toMap(),
      'password': password,
      'object': object.toMap(),
      'offset': offset < 0 ? 0 : offset,
    }, cancellation: cancellation);
    return _pageFromMap(response);
  }

  static Future<SqliteResultPage> query(
    RemoteDatabaseProfile profile,
    String password,
    String sql, {
    RemoteDatabaseCancellation? cancellation,
  }) async {
    final String source = validateReadOnlySql(sql, profile.engine);
    final Map<String, Object?> response = await _run(<String, Object?>{
      'action': 'query',
      'profile': profile.toMap(),
      'password': password,
      'sql': source,
    }, cancellation: cancellation);
    return _pageFromMap(response);
  }

  static String validateReadOnlySql(String sql, RemoteDatabaseEngine engine) {
    final String source = sql.trim();
    if (source.isEmpty) throw const FormatException('请输入 SQL');
    if (source.length > 65536) throw const FormatException('SQL 超过 64 KiB');
    final List<String> tokens = _sqlTokens(source);
    if (tokens.isEmpty) throw const FormatException('请输入有效的 SQL');
    const Set<String> writeKeywords = <String>{
      'ALTER',
      'CALL',
      'COPY',
      'CREATE',
      'DELETE',
      'DO',
      'DROP',
      'GRANT',
      'INSERT',
      'LOAD',
      'LOCK',
      'MERGE',
      'REPLACE',
      'REVOKE',
      'SET',
      'TRUNCATE',
      'UNLOCK',
      'UPDATE',
    };
    if (tokens.any(writeKeywords.contains)) {
      throw const FormatException('当前远程工作区只读，检测到写入或管理语句，未执行');
    }
    final Set<String> allowed = <String>{
      'SELECT',
      'WITH',
      'SHOW',
      'EXPLAIN',
      'VALUES',
      if (engine != RemoteDatabaseEngine.postgresql) ...<String>{
        'DESCRIBE',
        'DESC',
      },
    };
    if (!allowed.contains(tokens.first)) {
      throw const FormatException('当前远程工作区只读，仅支持查询、说明和执行计划');
    }
    return source;
  }

  static Future<Map<String, Object?>> _run(
    Map<String, Object?> request, {
    RemoteDatabaseCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      throw const RemoteDatabaseCancelledException();
    }
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    Isolate? isolate;
    bool reportedResult = false;

    void cancel() {
      isolate?.kill(priority: Isolate.immediate);
      if (!completer.isCompleted) {
        completer.completeError(const RemoteDatabaseCancelledException());
      }
    }

    cancellation?.addCancelListener(cancel);
    late final StreamSubscription<Object?> resultSubscription;
    late final StreamSubscription<Object?> errorSubscription;
    late final StreamSubscription<Object?> exitSubscription;
    resultSubscription = resultPort.listen((Object? message) {
      if (message is! Map) return;
      reportedResult = true;
      final Map<String, Object?> result = Map<String, Object?>.from(message);
      if (result['ok'] == true) {
        if (!completer.isCompleted) completer.complete(result);
      } else if (!completer.isCompleted) {
        completer.completeError(FormatException('${result['error']}'));
      }
    });
    errorSubscription = errorPort.listen((Object? error) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('远程数据库后台线程异常：$error'));
      }
    });
    exitSubscription = exitPort.listen((Object? _) {
      scheduleMicrotask(() {
        if (!reportedResult &&
            cancellation?.isCancelled != true &&
            !completer.isCompleted) {
          completer.completeError(StateError('远程数据库后台线程意外退出'));
        }
      });
    });
    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(
        _remoteDatabaseWorker,
        <String, Object?>{...request, 'replyPort': resultPort.sendPort},
        debugName: 'vibekits-remote-database',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      if (cancellation?.isCancelled == true) cancel();
      return await completer.future.timeout(
        taskTimeout,
        onTimeout: () => throw TimeoutException('远程数据库操作超过 15 秒，已停止'),
      );
    } finally {
      cancellation?.removeCancelListener(cancel);
      isolate?.kill(priority: Isolate.immediate);
      await resultSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      resultPort.close();
      errorPort.close();
      exitPort.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _remoteDatabaseWorker(Map<String, Object?> request) async {
  final SendPort replyPort = request['replyPort']! as SendPort;
  try {
    final RemoteDatabaseProfile? profile = RemoteDatabaseProfile.fromMap(
      Map<String, Object?>.from(request['profile']! as Map),
    );
    if (profile == null) throw const FormatException('远程数据库连接资料无效');
    final String password = '${request['password'] ?? ''}';
    final String action = '${request['action']}';
    final Map<String, Object?> result = switch (profile.engine) {
      RemoteDatabaseEngine.postgresql => await _runPostgres(
        action,
        profile,
        password,
        request,
      ),
      RemoteDatabaseEngine.mysql || RemoteDatabaseEngine.mariaDb =>
        await _runMySql(action, profile, password, request),
    };
    replyPort.send(<String, Object?>{'ok': true, ...result});
  } catch (error) {
    replyPort.send(<String, Object?>{'ok': false, 'error': '$error'});
  }
}

Future<Map<String, Object?>> _runPostgres(
  String action,
  RemoteDatabaseProfile profile,
  String password,
  Map<String, Object?> request,
) async {
  final Connection connection = await Connection.open(
    Endpoint(
      host: profile.host,
      port: profile.port,
      database: profile.database,
      username: profile.username,
      password: password,
    ),
    settings: ConnectionSettings(
      applicationName: 'Vibekits',
      connectTimeout: const Duration(seconds: 10),
      queryTimeout: const Duration(seconds: 10),
      sslMode: profile.useTls ? SslMode.require : SslMode.disable,
    ),
  );
  try {
    await connection.execute('BEGIN READ ONLY');
    return switch (action) {
      'inspect' => await _inspectPostgres(connection, profile),
      'table' => _pageToMap(
        await _loadPostgresTable(
          connection,
          RemoteDatabaseObject.fromMap(
            Map<String, Object?>.from(request['object']! as Map),
          ),
          offset: request['offset']! as int,
        ),
      ),
      'query' => _pageToMap(
        _postgresPageFromResult(
          await connection.execute('${request['sql']}'),
          label: '远程 SQL 查询',
          rowLimit: RemoteDatabaseService.maxRows,
        ),
      ),
      _ => throw const FormatException('未知远程数据库操作'),
    };
  } finally {
    await connection.close();
  }
}

Future<Map<String, Object?>> _inspectPostgres(
  Connection connection,
  RemoteDatabaseProfile profile,
) async {
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
      : await _loadPostgresTable(connection, objects.first, offset: 0);
  return _snapshotToMap(
    profile,
    version.isEmpty ? 'PostgreSQL' : '${version.first[0]}',
    objects,
    initialPage,
  );
}

Future<SqliteResultPage> _loadPostgresTable(
  Connection connection,
  RemoteDatabaseObject object, {
  required int offset,
}) async {
  final String schema = _quotePostgresIdentifier(object.schema);
  final String table = _quotePostgresIdentifier(object.name);
  final Result result = await connection.execute(
    'SELECT * FROM $schema.$table LIMIT ${SqliteDatabaseService.defaultPageSize + 1} OFFSET ${offset.clamp(0, 1 << 62)}',
  );
  return _postgresPageFromResult(
    result,
    label: object.label,
    offset: offset,
    rowLimit: SqliteDatabaseService.defaultPageSize,
  );
}

Future<Map<String, Object?>> _runMySql(
  String action,
  RemoteDatabaseProfile profile,
  String password,
  Map<String, Object?> request,
) async {
  final MySQLConnection connection = await MySQLConnection.createConnection(
    host: profile.host,
    port: profile.port,
    userName: profile.username,
    password: password,
    databaseName: profile.database,
    secure: profile.useTls,
  );
  try {
    await connection.connect(timeoutMs: 10000);
    await connection.execute('START TRANSACTION READ ONLY');
    return switch (action) {
      'inspect' => await _inspectMySql(connection, profile),
      'table' => _pageToMap(
        await _loadMySqlTable(
          connection,
          RemoteDatabaseObject.fromMap(
            Map<String, Object?>.from(request['object']! as Map),
          ),
          offset: request['offset']! as int,
        ),
      ),
      'query' => _pageToMap(await _queryMySql(connection, '${request['sql']}')),
      _ => throw const FormatException('未知远程数据库操作'),
    };
  } finally {
    await connection.close();
  }
}

Future<Map<String, Object?>> _inspectMySql(
  MySQLConnection connection,
  RemoteDatabaseProfile profile,
) async {
  final IResultSet version = await connection.execute(
    'SELECT VERSION() AS version',
  );
  final IResultSet tables = await connection.execute('''
SELECT TABLE_SCHEMA, TABLE_NAME
FROM information_schema.tables
WHERE TABLE_TYPE IN ('BASE TABLE', 'VIEW')
  AND TABLE_SCHEMA = DATABASE()
ORDER BY TABLE_SCHEMA, TABLE_NAME
LIMIT 5001
''');
  if (tables.numOfRows > 5000) {
    throw const FormatException('远程数据库对象超过 5000 个，已停止加载');
  }
  final List<RemoteDatabaseObject> objects = tables.rows
      .map(
        (ResultSetRow row) => RemoteDatabaseObject(
          schema: '${row.colAt(0)}',
          name: '${row.colAt(1)}',
        ),
      )
      .toList(growable: false);
  final SqliteResultPage? initialPage = objects.isEmpty
      ? null
      : await _loadMySqlTable(connection, objects.first, offset: 0);
  final Object? versionValue = version.rows.isEmpty
      ? profile.engine.label
      : version.rows.first.colAt(0);
  return _snapshotToMap(profile, '$versionValue', objects, initialPage);
}

Future<SqliteResultPage> _loadMySqlTable(
  MySQLConnection connection,
  RemoteDatabaseObject object, {
  required int offset,
}) async {
  final String schema = _quoteMySqlIdentifier(object.schema);
  final String table = _quoteMySqlIdentifier(object.name);
  final IResultSet result = await connection.execute(
    'SELECT * FROM $schema.$table LIMIT ${SqliteDatabaseService.defaultPageSize + 1} OFFSET ${offset.clamp(0, 1 << 62)}',
  );
  return _mysqlPageFromResult(
    result,
    label: object.label,
    offset: offset,
    rowLimit: SqliteDatabaseService.defaultPageSize,
  );
}

Future<SqliteResultPage> _queryMySql(
  MySQLConnection connection,
  String sql,
) async {
  final IResultSet result = await connection.execute(sql, null, true);
  final List<ResultSetRow> rows = await result.rowsStream
      .take(RemoteDatabaseService.maxRows + 1)
      .toList();
  return _mysqlPageFromRows(
    result,
    rows,
    label: '远程 SQL 查询',
    rowLimit: RemoteDatabaseService.maxRows,
  );
}

SqliteResultPage _postgresPageFromResult(
  Result result, {
  required String label,
  int offset = 0,
  required int rowLimit,
}) {
  final bool hasMore = result.length > rowLimit;
  return SqliteResultPage(
    columns: result.schema.columns
        .map((ResultSchemaColumn column) => column.columnName ?? '')
        .toList(growable: false),
    rows: result
        .take(rowLimit)
        .map((ResultRow row) => row.map(_displayValue).toList(growable: false))
        .toList(growable: false),
    offset: offset,
    hasMore: hasMore,
    label: label,
  );
}

SqliteResultPage _mysqlPageFromResult(
  IResultSet result, {
  required String label,
  int offset = 0,
  required int rowLimit,
}) => _mysqlPageFromRows(
  result,
  result.rows.toList(growable: false),
  label: label,
  offset: offset,
  rowLimit: rowLimit,
);

SqliteResultPage _mysqlPageFromRows(
  IResultSet result,
  List<ResultSetRow> sourceRows, {
  required String label,
  int offset = 0,
  required int rowLimit,
}) {
  return SqliteResultPage(
    columns: result.cols
        .map((ResultSetColumn column) => column.name)
        .toList(growable: false),
    rows: sourceRows
        .take(rowLimit)
        .map(
          (ResultSetRow row) => List<String>.generate(
            row.numOfColumns,
            (int index) => _displayValue(row.colAt(index)),
            growable: false,
          ),
        )
        .toList(growable: false),
    offset: offset,
    hasMore: sourceRows.length > rowLimit,
    label: label,
  );
}

Map<String, Object?> _snapshotToMap(
  RemoteDatabaseProfile profile,
  String serverVersion,
  List<RemoteDatabaseObject> objects,
  SqliteResultPage? initialPage,
) => <String, Object?>{
  'profile': profile.toMap(),
  'serverVersion': serverVersion,
  'objects': objects
      .map((RemoteDatabaseObject object) => object.toMap())
      .toList(growable: false),
  'initialPage': initialPage == null ? null : _pageToMap(initialPage),
};

RemoteDatabaseSnapshot _snapshotFromMap(Map<String, Object?> map) {
  final RemoteDatabaseProfile? profile = RemoteDatabaseProfile.fromMap(
    Map<String, Object?>.from(map['profile']! as Map),
  );
  if (profile == null) throw const FormatException('远程数据库返回的连接资料无效');
  return RemoteDatabaseSnapshot(
    profile: profile,
    serverVersion: '${map['serverVersion']}',
    objects: (map['objects']! as List<Object?>)
        .map(
          (Object? item) => RemoteDatabaseObject.fromMap(
            Map<String, Object?>.from(item! as Map),
          ),
        )
        .toList(growable: false),
    initialPage: map['initialPage'] == null
        ? null
        : _pageFromMap(Map<String, Object?>.from(map['initialPage']! as Map)),
  );
}

Map<String, Object?> _pageToMap(SqliteResultPage page) => <String, Object?>{
  'columns': page.columns,
  'rows': page.rows,
  'offset': page.offset,
  'hasMore': page.hasMore,
  'label': page.label,
};

SqliteResultPage _pageFromMap(Map<String, Object?> map) => SqliteResultPage(
  columns: List<String>.from(map['columns']! as List),
  rows: (map['rows']! as List<Object?>)
      .map((Object? row) => List<String>.from(row! as List))
      .toList(growable: false),
  offset: map['offset']! as int,
  hasMore: map['hasMore']! as bool,
  label: '${map['label']}',
);

String _quotePostgresIdentifier(String value) =>
    '"${value.replaceAll('"', '""')}"';

String _quoteMySqlIdentifier(String value) =>
    '`${value.replaceAll('`', '``')}`';

String _displayValue(Object? value) {
  if (value == null) return 'NULL';
  if (value is Uint8List) return '<BINARY · ${value.length} bytes>';
  final String text = '$value'.replaceAll('\u0000', '␀');
  return text.length > 1000 ? '${text.substring(0, 1000)}…' : text;
}

List<String> _sqlTokens(String source) {
  final List<String> tokens = <String>[];
  int index = 0;
  while (index < source.length) {
    final int code = source.codeUnitAt(index);
    if (_isWhitespace(code)) {
      index++;
      continue;
    }
    if (code == 45 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 45) {
      index += 2;
      while (index < source.length && source.codeUnitAt(index) != 10) {
        index++;
      }
      continue;
    }
    if (code == 47 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 42) {
      final int end = source.indexOf('*/', index + 2);
      if (end < 0) throw const FormatException('SQL 块注释未结束');
      index = end + 2;
      continue;
    }
    if (code == 39 || code == 34 || code == 96) {
      final int quote = code;
      index++;
      bool closed = false;
      while (index < source.length) {
        if (source.codeUnitAt(index) == quote) {
          if (index + 1 < source.length &&
              source.codeUnitAt(index + 1) == quote) {
            index += 2;
            continue;
          }
          index++;
          closed = true;
          break;
        }
        if (source.codeUnitAt(index) == 92 && index + 1 < source.length) {
          index += 2;
        } else {
          index++;
        }
      }
      if (!closed) throw const FormatException('SQL 引号未结束');
      continue;
    }
    if (code == 59) {
      index++;
      while (index < source.length && _isWhitespace(source.codeUnitAt(index))) {
        index++;
      }
      if (index < source.length) {
        throw const FormatException('一次只能执行一条只读 SQL');
      }
      continue;
    }
    if (_isAsciiLetter(code) || code == 95) {
      final int start = index++;
      while (index < source.length) {
        final int next = source.codeUnitAt(index);
        if (!_isAsciiLetter(next) && !_isAsciiDigit(next) && next != 95) break;
        index++;
      }
      tokens.add(source.substring(start, index).toUpperCase());
      continue;
    }
    index++;
  }
  return tokens;
}

bool _isWhitespace(int code) =>
    code == 9 || code == 10 || code == 13 || code == 32;
bool _isAsciiLetter(int code) =>
    (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
bool _isAsciiDigit(int code) => code >= 48 && code <= 57;
