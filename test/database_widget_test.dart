import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/sqlite_database_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('拖入数据库后直接显示第一张表并可运行只读 SQL', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final SqliteResultPage initialPage = SqliteResultPage(
      columns: const <String>['id', 'name'],
      rows: const <List<String>>[
        <String>['1', 'Alice'],
      ],
      offset: 0,
      hasMore: false,
      label: 'users',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            initialDatabasePath: r'C:\data\sample.sqlite',
            databaseInspect: (String path) async => SqliteDatabaseSnapshot(
              path: path,
              fileSize: 4096,
              sqliteVersion: '3.test',
              objects: const <SqliteObjectInfo>[
                SqliteObjectInfo(
                  name: 'users',
                  kind: SqliteObjectKind.table,
                  sql: 'CREATE TABLE users (id INTEGER, name TEXT)',
                ),
              ],
              initialPage: initialPage,
            ),
            databaseRunQuery: (String path, String sql) async =>
                const SqliteResultPage(
                  columns: <String>['count'],
                  rows: <List<String>>[
                    <String>['1'],
                  ],
                  offset: 0,
                  hasMore: false,
                  label: 'SQL 查询',
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('数据库管理器'), findsNWidgets(2));
    expect(find.text('SQLite · 只读'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('SQL'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('database-query-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('database-run-query')));
    await tester.pumpAndSettle();
    expect(find.text('count'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });
}
