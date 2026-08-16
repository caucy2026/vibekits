import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_database_service.dart';

void main() {
  test('连接资料兼容旧 PostgreSQL 记录并区分三种数据库引擎', () {
    final RemoteDatabaseProfile legacy = RemoteDatabaseProfile.decode(
      '{"id":"postgres-old","name":"旧连接","host":"db.local","port":5432,"database":"app","username":"dev","useTls":true}',
    )!;
    expect(legacy.engine, RemoteDatabaseEngine.postgresql);

    const RemoteDatabaseProfile maria = RemoteDatabaseProfile(
      id: 'mariadb-1',
      name: 'MariaDB',
      host: 'maria.local',
      port: 3306,
      database: 'app',
      username: 'dev',
      useTls: true,
      engine: RemoteDatabaseEngine.mariaDb,
    );
    expect(
      RemoteDatabaseProfile.decode(maria.encode())?.engine,
      RemoteDatabaseEngine.mariaDb,
    );
    expect(
      RemoteDatabaseProfile.createId(
        host: 'db.local',
        port: 3306,
        database: 'app',
        username: 'dev',
        engine: RemoteDatabaseEngine.mysql,
      ),
      startsWith('mysql-'),
    );
  });

  test('只读 SQL 检查拒绝写语句、多语句和 WITH 写入', () {
    expect(
      RemoteDatabaseService.validateReadOnlySql(
        "SELECT 'delete is text' AS value;",
        RemoteDatabaseEngine.mysql,
      ),
      contains('SELECT'),
    );
    expect(
      () => RemoteDatabaseService.validateReadOnlySql(
        'SELECT 1; DROP TABLE users',
        RemoteDatabaseEngine.mysql,
      ),
      throwsFormatException,
    );
    expect(
      () => RemoteDatabaseService.validateReadOnlySql(
        'WITH changed AS (DELETE FROM users RETURNING *) SELECT * FROM changed',
        RemoteDatabaseEngine.postgresql,
      ),
      throwsFormatException,
    );
    expect(
      RemoteDatabaseService.validateReadOnlySql(
        'DESCRIBE users',
        RemoteDatabaseEngine.mariaDb,
      ),
      'DESCRIBE users',
    );
    expect(
      () => RemoteDatabaseService.validateReadOnlySql(
        'DESCRIBE users',
        RemoteDatabaseEngine.postgresql,
      ),
      throwsFormatException,
    );
  });

  test('MySQL 握手等待位于工作 Isolate 且可立即取消', () async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<Socket> clients = <Socket>[];
    final Completer<void> accepted = Completer<void>();
    final StreamSubscription<Socket> subscription = server.listen((
      Socket socket,
    ) {
      clients.add(socket);
      if (!accepted.isCompleted) accepted.complete();
    });
    addTearDown(() async {
      for (final Socket socket in clients) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    });

    final RemoteDatabaseCancellation cancellation =
        RemoteDatabaseCancellation();
    final Future<RemoteDatabaseSnapshot> operation =
        RemoteDatabaseService.inspect(
          RemoteDatabaseProfile(
            id: 'mysql-cancel',
            name: 'cancel',
            host: InternetAddress.loopbackIPv4.address,
            port: server.port,
            database: 'mysql',
            username: 'root',
            useTls: false,
            engine: RemoteDatabaseEngine.mysql,
          ),
          '',
          cancellation: cancellation,
        );

    await accepted.future.timeout(const Duration(seconds: 5));
    bool uiTimerRan = false;
    await Future<void>.delayed(const Duration(milliseconds: 20), () {
      uiTimerRan = true;
    });
    cancellation.cancel();

    await expectLater(
      operation,
      throwsA(isA<RemoteDatabaseCancelledException>()),
    );
    expect(uiTimerRan, isTrue);
  });
}
