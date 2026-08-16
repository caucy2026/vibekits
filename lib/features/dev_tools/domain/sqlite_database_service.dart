import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

enum SqliteObjectKind { table, view }

class SqliteObjectInfo {
  const SqliteObjectInfo({
    required this.name,
    required this.kind,
    required this.sql,
  });

  final String name;
  final SqliteObjectKind kind;
  final String sql;
}

class SqliteResultPage {
  const SqliteResultPage({
    required this.columns,
    required this.rows,
    required this.offset,
    required this.hasMore,
    required this.label,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final int offset;
  final bool hasMore;
  final String label;
}

class SqliteDatabaseSnapshot {
  const SqliteDatabaseSnapshot({
    required this.path,
    required this.fileSize,
    required this.sqliteVersion,
    required this.objects,
    this.initialPage,
  });

  final String path;
  final int fileSize;
  final String sqliteVersion;
  final List<SqliteObjectInfo> objects;
  final SqliteResultPage? initialPage;
}

/// A bounded, read-only SQLite explorer.
///
/// Every request runs in a short-lived isolate and connection. This keeps FFI
/// work away from the UI isolate and lets a timed-out query terminate together
/// with its native connection.
abstract final class SqliteDatabaseService {
  static const int defaultPageSize = 100;
  static const int maxPageSize = 200;
  static const int maxQueryRows = 500;
  static const Duration taskTimeout = Duration(seconds: 8);

  static Future<SqliteDatabaseSnapshot> inspect(
    String path, {
    int pageSize = defaultPageSize,
  }) async {
    _validatePath(path);
    final int bounded = pageSize.clamp(1, maxPageSize);
    final Map<String, Object?> response = await _run(<String, Object?>{
      'action': 'inspect',
      'path': path,
      'limit': bounded,
    });
    return _snapshotFromMap(response);
  }

  static Future<SqliteResultPage> loadTable(
    String path,
    String objectName, {
    int offset = 0,
    int pageSize = defaultPageSize,
  }) async {
    _validatePath(path);
    if (objectName.isEmpty) throw const FormatException('请选择表或视图');
    final Map<String, Object?> response = await _run(<String, Object?>{
      'action': 'table',
      'path': path,
      'name': objectName,
      'offset': offset < 0 ? 0 : offset,
      'limit': pageSize.clamp(1, maxPageSize),
    });
    return _pageFromMap(response);
  }

  static Future<SqliteResultPage> query(
    String path,
    String sql, {
    int maxRows = maxQueryRows,
  }) async {
    _validatePath(path);
    final String source = sql.trim();
    if (source.isEmpty) throw const FormatException('请输入 SQL');
    if (source.length > 65536) throw const FormatException('SQL 超过 64 KiB');
    final Map<String, Object?> response = await _run(<String, Object?>{
      'action': 'query',
      'path': path,
      'sql': source,
      'limit': maxRows.clamp(1, maxQueryRows),
    });
    return _pageFromMap(response);
  }

  static void _validatePath(String path) {
    final File file = File(path);
    if (!file.existsSync()) throw const FileSystemException('数据库文件不存在');
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('只允许打开普通数据库文件');
    }
  }

  static Future<Map<String, Object?>> _run(Map<String, Object?> request) async {
    final ReceivePort port = ReceivePort();
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    late final StreamSubscription<Object?> subscription;
    subscription = port.listen((Object? message) {
      if (message is! Map) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('数据库工作进程返回了无效结果'));
        }
        return;
      }
      final Map<String, Object?> result = Map<String, Object?>.from(message);
      if (result['ok'] == true) {
        if (!completer.isCompleted) completer.complete(result);
      } else if (!completer.isCompleted) {
        completer.completeError(FormatException('${result['error']}'));
      }
    });
    final Isolate isolate = await Isolate.spawn<List<Object?>>(
      _sqliteWorker,
      <Object?>[port.sendPort, request],
      debugName: 'vibekits-sqlite-reader',
    );
    try {
      return await completer.future.timeout(
        taskTimeout,
        onTimeout: () => throw TimeoutException('数据库操作超过 8 秒，已停止'),
      );
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    }
  }

  static SqliteDatabaseSnapshot _snapshotFromMap(Map<String, Object?> map) {
    final List<Object?> rawObjects = List<Object?>.from(
      map['objects']! as List,
    );
    final List<SqliteObjectInfo> objects = rawObjects
        .map((Object? value) {
          final Map<String, Object?> item = Map<String, Object?>.from(
            value! as Map,
          );
          return SqliteObjectInfo(
            name: item['name']! as String,
            kind: item['kind'] == 'view'
                ? SqliteObjectKind.view
                : SqliteObjectKind.table,
            sql: item['sql']! as String,
          );
        })
        .toList(growable: false);
    return SqliteDatabaseSnapshot(
      path: map['path']! as String,
      fileSize: map['fileSize']! as int,
      sqliteVersion: map['sqliteVersion']! as String,
      objects: objects,
      initialPage: map['page'] == null
          ? null
          : _pageFromMap(Map<String, Object?>.from(map['page']! as Map)),
    );
  }

  static SqliteResultPage _pageFromMap(Map<String, Object?> map) {
    return SqliteResultPage(
      columns: List<String>.from(map['columns']! as List),
      rows: (map['rows']! as List)
          .map((Object? row) => List<String>.from(row! as List))
          .toList(growable: false),
      offset: map['offset']! as int,
      hasMore: map['hasMore']! as bool,
      label: map['label']! as String,
    );
  }
}

void _sqliteWorker(List<Object?> message) {
  final SendPort sendPort = message[0]! as SendPort;
  final Map<String, Object?> request = Map<String, Object?>.from(
    message[1]! as Map,
  );
  Database? database;
  try {
    final String path = request['path']! as String;
    database = sqlite3.open(path, mode: OpenMode.readOnly);
    database.config.doubleQuotedStringLiterals = false;
    database.execute('PRAGMA query_only = ON');
    database.execute('PRAGMA trusted_schema = OFF');
    database.execute('PRAGMA busy_timeout = 2000');

    final String action = request['action']! as String;
    final Map<String, Object?> payload = switch (action) {
      'inspect' => _inspect(database, path, request['limit']! as int),
      'table' => _tablePage(
        database,
        request['name']! as String,
        request['offset']! as int,
        request['limit']! as int,
      ),
      'query' => _queryPage(
        database,
        request['sql']! as String,
        request['limit']! as int,
      ),
      _ => throw const FormatException('未知数据库操作'),
    };
    sendPort.send(<String, Object?>{'ok': true, ...payload});
  } catch (error) {
    sendPort.send(<String, Object?>{
      'ok': false,
      'error': _friendlySqliteError(error),
    });
  } finally {
    database?.close();
  }
}

Map<String, Object?> _inspect(Database db, String path, int limit) {
  final ResultSet schema = db.select('''
SELECT name, type, COALESCE(sql, '') AS sql
FROM sqlite_schema
WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, lower(name)
LIMIT 5001
''');
  if (schema.length > 5000) {
    throw const FormatException('数据库对象超过 5000 个，已停止加载');
  }
  final List<Map<String, Object?>> objects = schema
      .map((Row row) {
        final String sql = row['sql']! as String;
        return <String, Object?>{
          'name': row['name']! as String,
          'kind': row['type']! as String,
          'sql': sql.length > 20000 ? '${sql.substring(0, 20000)}…' : sql,
        };
      })
      .toList(growable: false);
  final Map<String, Object?>? page = objects.isEmpty
      ? null
      : _tablePage(db, objects.first['name']! as String, 0, limit);
  return <String, Object?>{
    'path': path,
    'fileSize': File(path).lengthSync(),
    'sqliteVersion': sqlite3.version.libVersion,
    'objects': objects,
    'page': page,
  };
}

Map<String, Object?> _tablePage(
  Database db,
  String name,
  int offset,
  int limit,
) {
  final ResultSet known = db.select(
    "SELECT type FROM sqlite_schema WHERE name = ? AND type IN ('table', 'view')",
    <Object?>[name],
  );
  if (known.isEmpty) throw const FormatException('表或视图已经不存在');
  final String identifier = '"${name.replaceAll('"', '""')}"';
  final ResultSet result = db.select(
    'SELECT * FROM $identifier LIMIT ? OFFSET ?',
    <Object?>[limit + 1, offset],
  );
  return _resultMap(
    result.columnNames,
    result.rows,
    limit: limit,
    offset: offset,
    label: name,
  );
}

Map<String, Object?> _queryPage(Database db, String sql, int limit) {
  final PreparedStatement statement = db.prepare(sql, checkNoTail: true);
  try {
    if (!statement.isReadOnly) {
      throw const FormatException('当前工作区默认只读，写入 SQL 未执行');
    }
    if (statement.parameterCount != 0) {
      throw const FormatException('当前查询暂不支持未绑定参数');
    }
    final IteratingCursor cursor = statement.selectCursor();
    final List<List<Object?>> rows = <List<Object?>>[];
    while (rows.length <= limit && cursor.moveNext()) {
      rows.add(cursor.current.values.toList(growable: false));
    }
    return _resultMap(
      cursor.columnNames,
      rows,
      limit: limit,
      offset: 0,
      label: 'SQL 查询',
    );
  } finally {
    statement.close();
  }
}

Map<String, Object?> _resultMap(
  List<String> columns,
  List<List<Object?>> rawRows, {
  required int limit,
  required int offset,
  required String label,
}) {
  final bool hasMore = rawRows.length > limit;
  final List<List<String>> rows = rawRows
      .take(limit)
      .map(
        (List<Object?> row) =>
            row.map(_displaySqliteValue).toList(growable: false),
      )
      .toList(growable: false);
  return <String, Object?>{
    'columns': List<String>.from(columns),
    'rows': rows,
    'offset': offset,
    'hasMore': hasMore,
    'label': label,
  };
}

String _displaySqliteValue(Object? value) {
  if (value == null) return 'NULL';
  if (value is Uint8List) return '<BLOB · ${value.length} bytes>';
  final String text = value.toString().replaceAll('\u0000', '␀');
  return text.length > 1000 ? '${text.substring(0, 1000)}…' : text;
}

String _friendlySqliteError(Object error) {
  if (error is SqliteException) {
    return 'SQLite ${error.extendedResultCode}：${error.message}';
  }
  if (error is FormatException) return error.message;
  if (error is FileSystemException) return error.message;
  return '无法读取数据库：$error';
}
