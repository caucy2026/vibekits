import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_database_service.dart';
import 'package:vibekits/features/dev_tools/domain/sqlite_database_service.dart';
import 'package:vibekits/features/dev_tools/presentation/database_workspace.dart';
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
    expect(find.text('SQLite · 本地只读'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('SQL'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('database-query-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('database-run-query')));
    await tester.pumpAndSettle();
    expect(find.text('count'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('远程 PostgreSQL 连接成功后保存记录与凭据', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<String> savedProfiles = <String>[];
    String? savedPassword;

    Future<RemoteDatabaseSnapshot> inspect(
      RemoteDatabaseProfile profile,
      String password,
    ) async => RemoteDatabaseSnapshot(
      profile: profile,
      serverVersion: '17.test',
      objects: const <RemoteDatabaseObject>[
        RemoteDatabaseObject(schema: 'public', name: 'users'),
      ],
      initialPage: const SqliteResultPage(
        columns: <String>['id'],
        rows: <List<String>>[
          <String>['42'],
        ],
        offset: 0,
        hasMore: false,
        label: 'users',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseWorkspace(
            remoteInspect: inspect,
            passwordReader: (String id) async => savedPassword,
            passwordWriter: (String id, String password) async {
              savedPassword = password;
            },
            onRemoteProfilesChanged: (List<String> profiles) async {
              savedProfiles = profiles;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('database-connect-remote')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('remote-database-host')),
      'db.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('remote-database-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('remote-database-submit')));
    await tester.pumpAndSettle();

    expect(find.text('PostgreSQL · 远程只读'), findsOneWidget);
    expect(
      find.textContaining('postgres@db.example.com:5432/postgres'),
      findsOneWidget,
    );
    expect(find.text('42'), findsOneWidget);
    expect(savedPassword, 'secret');
    expect(savedProfiles, hasLength(1));
    expect(
      RemoteDatabaseProfile.decode(savedProfiles.single)?.host,
      'db.example.com',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseWorkspace(
            key: const ValueKey<String>('restored-database'),
            initialRemoteProfiles: savedProfiles,
            passwordReader: (String id) async => savedPassword,
            remoteInspect: inspect,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('database-connect-remote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote-database-history')), findsOneWidget);
    final TextField passwordField = tester.widget<TextField>(
      find.byKey(const Key('remote-database-password')),
    );
    expect(passwordField.controller?.text, 'secret');
  });
}
