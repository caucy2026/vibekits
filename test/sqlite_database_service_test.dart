import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vibekits/features/dev_tools/domain/sqlite_database_service.dart';

void main() {
  late Directory sandbox;
  late File databaseFile;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('vk_sqlite_');
    databaseFile = File(
      '${sandbox.path}${Platform.pathSeparator}sample.sqlite',
    );
    final Database database = sqlite3.open(databaseFile.path);
    try {
      database.execute('''
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  note TEXT,
  payload BLOB
)
''');
      final PreparedStatement insert = database.prepare(
        'INSERT INTO users (name, note, payload) VALUES (?, ?, ?)',
      );
      try {
        for (int index = 0; index < 205; index++) {
          insert.execute(<Object?>[
            index == 0 ? '你好' : 'user-$index',
            index.isEven ? null : 'note-$index',
            index == 0 ? <int>[1, 2, 3] : null,
          ]);
        }
      } finally {
        insert.close();
      }
      database.execute(
        'CREATE VIEW named_users AS SELECT id, name FROM users WHERE id <= 3',
      );
    } finally {
      database.close();
    }
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test('只读检查列出表和视图并自动加载首屏', () async {
    final SqliteDatabaseSnapshot snapshot = await SqliteDatabaseService.inspect(
      databaseFile.path,
    );

    expect(snapshot.sqliteVersion, isNotEmpty);
    expect(snapshot.fileSize, greaterThan(0));
    expect(snapshot.objects.map((SqliteObjectInfo item) => item.name), <String>[
      'users',
      'named_users',
    ]);
    expect(snapshot.initialPage?.columns, <String>[
      'id',
      'name',
      'note',
      'payload',
    ]);
    expect(snapshot.initialPage?.rows, hasLength(100));
    expect(snapshot.initialPage?.rows.first, <String>[
      '1',
      '你好',
      'NULL',
      '<BLOB · 3 bytes>',
    ]);
    expect(snapshot.initialPage?.hasMore, isTrue);
  });

  test('表格分页有上限且不会整体读取数据库', () async {
    final SqliteResultPage last = await SqliteDatabaseService.loadTable(
      databaseFile.path,
      'users',
      offset: 200,
    );
    expect(last.offset, 200);
    expect(last.rows, hasLength(5));
    expect(last.hasMore, isFalse);
  });

  test('SQL 查询限制结果行数并拒绝写操作', () async {
    final SqliteResultPage page = await SqliteDatabaseService.query(
      databaseFile.path,
      'SELECT name FROM users ORDER BY id',
      maxRows: 3,
    );
    expect(page.rows, <List<String>>[
      <String>['你好'],
      <String>['user-1'],
      <String>['user-2'],
    ]);
    expect(page.hasMore, isTrue);

    await expectLater(
      SqliteDatabaseService.query(databaseFile.path, 'DELETE FROM users'),
      throwsA(isA<FormatException>()),
    );
    final Database verify = sqlite3.open(
      databaseFile.path,
      mode: OpenMode.readOnly,
    );
    try {
      expect(verify.select('SELECT count(*) AS c FROM users').first['c'], 205);
    } finally {
      verify.close();
    }
  });

  test('损坏数据库返回可控错误', () async {
    final File corrupt = File('${sandbox.path}${Platform.pathSeparator}bad.db')
      ..writeAsStringSync('not sqlite');
    await expectLater(
      SqliteDatabaseService.inspect(corrupt.path),
      throwsA(isA<FormatException>()),
    );
  });
}
