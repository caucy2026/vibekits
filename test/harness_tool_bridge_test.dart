import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/domain/remote_connection_record.dart';
import 'package:vibekits/features/dev_tools/domain/remote_database_service.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';
import 'package:vibekits/features/dev_tools/domain/sftp_service.dart';
import 'package:vibekits/features/dev_tools/domain/sqlite_database_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

void main() {
  test('导出版本化可执行工具目录且不暴露未接工具', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Map<String, Object?> catalog = bridge.exportCatalog();
    expect(catalog['protocol'], VibekitsHarnessToolBridge.protocolVersion);
    final List<dynamic> tools = catalog['tools']! as List<dynamic>;
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.sha256'),
      isTrue,
    );
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.database_manager'),
      isFalse,
    );
    expect(
      tools.any(
        (dynamic tool) =>
            tool['id'] == VibekitsHarnessToolBridge.adbListDevicesId,
      ),
      isTrue,
    );
    for (final String id in <String>[
      VibekitsHarnessToolBridge.adbCommandId,
      VibekitsHarnessToolBridge.serialListPortsId,
      VibekitsHarnessToolBridge.serialTransactId,
      VibekitsHarnessToolBridge.sqliteInspectId,
      VibekitsHarnessToolBridge.sqliteQueryId,
      VibekitsHarnessToolBridge.gitInspectId,
      VibekitsHarnessToolBridge.gitCompareRefsId,
      VibekitsHarnessToolBridge.gitCreateLocalBranchId,
      VibekitsHarnessToolBridge.fileSearchId,
      VibekitsHarnessToolBridge.apiRequestId,
      VibekitsHarnessToolBridge.githubDiagnosticsId,
      VibekitsHarnessToolBridge.programmerCalculatorId,
      VibekitsHarnessToolBridge.remoteListProfilesId,
      VibekitsHarnessToolBridge.remoteSshExecId,
      VibekitsHarnessToolBridge.remoteSftpListId,
      VibekitsHarnessToolBridge.remoteSftpUploadId,
      VibekitsHarnessToolBridge.remoteSftpDownloadId,
      VibekitsHarnessToolBridge.remoteDatabaseListProfilesId,
      VibekitsHarnessToolBridge.remoteDatabaseInspectId,
      VibekitsHarnessToolBridge.remoteDatabaseQueryId,
      VibekitsHarnessToolBridge.duplicateScanId,
      VibekitsHarnessToolBridge.systemDriveAnalyzeId,
    ]) {
      expect(tools.any((dynamic tool) => tool['id'] == id), isTrue, reason: id);
    }
  });

  test('开发工具左侧每个入口都有至少一个 Harness 可执行适配器', () {
    final Set<String> executable = VibekitsHarnessToolBridge().executableCatalog
        .map((HarnessToolDefinition tool) => tool.id)
        .toSet();
    final Map<String, Set<String>> adapters = <String, Set<String>>{
      'programmer_calculator': <String>{
        VibekitsHarnessToolBridge.programmerCalculatorId,
      },
      'database_manager': <String>{
        VibekitsHarnessToolBridge.sqliteInspectId,
        VibekitsHarnessToolBridge.sqliteQueryId,
        VibekitsHarnessToolBridge.remoteDatabaseInspectId,
        VibekitsHarnessToolBridge.remoteDatabaseQueryId,
      },
      'remote_workspace': <String>{
        VibekitsHarnessToolBridge.remoteSshExecId,
        VibekitsHarnessToolBridge.remoteSftpListId,
        VibekitsHarnessToolBridge.remoteSftpUploadId,
        VibekitsHarnessToolBridge.remoteSftpDownloadId,
      },
      'serial_port': <String>{VibekitsHarnessToolBridge.serialTransactId},
      'adb_workspace': <String>{VibekitsHarnessToolBridge.adbCommandId},
      'api_workspace': <String>{VibekitsHarnessToolBridge.apiRequestId},
      'git_workspace': <String>{VibekitsHarnessToolBridge.gitInspectId},
      'github_diagnostics': <String>{
        VibekitsHarnessToolBridge.githubDiagnosticsId,
      },
      'file_hash': <String>{'vibekits.file_hash'},
      'file_search': <String>{VibekitsHarnessToolBridge.fileSearchId},
      'batch_rename': <String>{'vibekits.batch_rename'},
      'duplicate_files': <String>{VibekitsHarnessToolBridge.duplicateScanId},
      'utility_collection': <String>{
        for (final ToolSpec tool in utilityToolRegistry) 'vibekits.${tool.id}',
      },
    };

    for (final ToolSpec workspace in devToolRegistry) {
      final Set<String>? toolIds = adapters[workspace.id];
      expect(toolIds, isNotNull, reason: '未声明 ${workspace.id} 的 Harness 适配器');
      expect(
        toolIds!.any(executable.contains),
        isTrue,
        reason: '${workspace.id} 没有进入 Harness 可执行目录',
      );
    }
  });

  test('只读文本工具无需审批并返回结构化结果', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.sha256',
      arguments: <String, Object?>{'input': 'abc'},
      approve: (_) async {
        approvals++;
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(approvals, 0);
    expect(
      result.data?['output'],
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('Harness 工具完成后写入对应工具审计记录', () async {
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      activityRecorder:
          ({
            required String toolId,
            required String toolName,
            required String target,
            required Map<String, Object?> arguments,
            required Object? result,
            required HarnessToolActivityStatus status,
            required DateTime startedAt,
          }) async {
            records.add(<String, Object?>{
              'toolId': toolId,
              'toolName': toolName,
              'arguments': arguments,
              'result': result,
              'status': status,
            });
          },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.sha256',
      arguments: <String, Object?>{'input': 'abc'},
      approve: (_) async => true,
    );

    expect(result.ok, isTrue);
    expect(records, hasLength(1));
    expect(records.single['toolId'], 'vibekits.sha256');
    expect(records.single['status'], HarnessToolActivityStatus.succeeded);
  });

  test('ADB 连接先展示规范化目标并取得一次性批准', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: 'C:\\tools\\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'connected to 192.168.3.63:5555',
          stderr: '',
        );
      },
    );
    HarnessToolApprovalRequest? approval;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbConnectId,
      arguments: <String, Object?>{'address': '192.168.3.63'},
      approve: (HarnessToolApprovalRequest request) async {
        approval = request;
        return true;
      },
    );
    expect(approval?.tool.risk, HarnessToolRisk.controlsDevice);
    expect(approval?.target, '192.168.3.63:5555');
    expect(calls.single, <String>['connect', '192.168.3.63:5555']);
    expect(result.ok, isTrue);
  });

  test('拒绝高风险工具后不执行处理器', () async {
    int calls = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        'vibekits.batch_rename': (_) async {
          calls++;
          return <String, Object?>{};
        },
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.batch_rename',
      arguments: <String, Object?>{'input': 'D:\\project'},
      approve: (_) async => false,
    );
    expect(result.cancelled, isTrue);
    expect(calls, 0);
  });

  test('ADB 命令经过设备审批并使用固定可执行文件', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: r'C:\tools\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'Pixel_8',
          stderr: '',
        );
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbCommandId,
      arguments: <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
      },
      approve: (HarnessToolApprovalRequest request) async {
        expect(request.target, '192.168.3.63:5555');
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(calls.single, <String>[
      '-s',
      '192.168.3.63:5555',
      'shell',
      'getprop',
      'ro.product.model',
    ]);
  });

  test('SQLite 检查和查询通过桥接完成闭环', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_sqlite_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final String path = '${sandbox.path}${Platform.pathSeparator}sample.db';
    final Database database = sqlite3.open(path);
    database.execute('CREATE TABLE users(id INTEGER, name TEXT)');
    database.execute("INSERT INTO users VALUES (1, 'Ada')");
    database.close();
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();

    final HarnessToolCallResult inspect = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.sqliteInspectId,
      arguments: <String, Object?>{'path': path},
      approve: (_) async => true,
    );
    final HarnessToolCallResult query = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.sqliteQueryId,
      arguments: <String, Object?>{
        'path': path,
        'sql': 'SELECT name FROM users',
      },
      approve: (_) async => true,
    );

    expect(inspect.ok, isTrue);
    expect(inspect.data?['objects'].toString(), contains('users'));
    expect(query.ok, isTrue);
    expect(query.data?['rows'], <List<String>>[
      <String>['Ada'],
    ]);
  });

  test('文件搜索通过桥接返回结构化匹配', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_search_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    await File('${sandbox.path}${Platform.pathSeparator}hello.dart')
        .writeAsString('void main() {}');
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.fileSearchId,
          arguments: <String, Object?>{'root': sandbox.path, 'query': 'hello'},
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect(result.data?['matches'].toString(), contains('hello.dart'));
  });

  test('HTTP 工具经审批访问本地服务并回传响应', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"bridge":"ok"}');
      await request.response.close();
    });
    final Uri target = Uri.parse('http://127.0.0.1:${server.port}/health');
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.apiRequestId,
          arguments: <String, Object?>{
            'method': 'GET',
            'url': target.toString(),
          },
          approve: (HarnessToolApprovalRequest request) async {
            expect(request.target, target.toString());
            return true;
          },
        );
    expect(result.ok, isTrue);
    expect(result.data?['statusCode'], 200);
    expect(result.data?['body'], '{"bridge":"ok"}');
  });

  test('程序员计算器通过桥接返回多进制结果', () async {
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.programmerCalculatorId,
          arguments: <String, Object?>{
            'expression': '(0xFF << 2) | 3',
            'width': 16,
          },
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect(result.data?['hexadecimal'], '0x03FF');
    expect(result.data?['decimal'], '1023');
  });

  test('Harness 通过已保存会话闭环调用 SSH 与 SFTP 且不暴露凭据', () async {
    const RemoteConnectionRecord profile = RemoteConnectionRecord(
      id: 'server_1',
      name: '测试服务器',
      mode: RemoteSessionMode.ssh,
      host: 'server.example.com',
      user: 'dev',
      port: 22,
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: 'SHA256:TrustedHostKey0123456789+/',
    );
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_remote_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final File upload = await File(
      '${sandbox.path}${Platform.pathSeparator}upload.txt',
    ).writeAsString('UPLOAD_OK');
    final String download =
        '${sandbox.path}${Platform.pathSeparator}download.txt';
    final List<String> transfers = <String>[];
    final List<Map<String, Object?>> activities = <Map<String, Object?>>[];
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      activityRecorder:
          ({
            required String toolId,
            required String toolName,
            required String target,
            required Map<String, Object?> arguments,
            required Object? result,
            required HarnessToolActivityStatus status,
            required DateTime startedAt,
          }) async {
            activities.add(<String, Object?>{
              'toolId': toolId,
              'target': target,
              'arguments': arguments,
              'result': result,
              'status': status.name,
            });
          },
      remoteProfileLoader: () async => const <RemoteConnectionRecord>[profile],
      credentialReader: (String key) async {
        expect(key, profile.credentialKey);
        return 'vault-secret';
      },
      remoteCommandRunner:
          (
            RemoteConnectionProfile connection,
            String command,
            String? secret,
            RemoteHostKeyVerifier verifier,
          ) async {
            expect(connection.host, profile.host);
            expect(secret, 'vault-secret');
            expect(command, 'printf HARNESS_SSH_OK');
            expect(
              await verifier(profile.hostKeyType!, profile.hostKeyFingerprint!),
              isTrue,
            );
            return const RemoteCommandResult(
              exitCode: 0,
              stdout: 'HARNESS_SSH_OK',
              stderr: '',
            );
          },
      remoteFileConnector: (
        RemoteConnectionProfile connection,
        String? secret,
        RemoteHostKeyVerifier verifier,
      ) async => _FakeHarnessRemoteFileClient(transfers),
    );

    Future<bool> approve(HarnessToolApprovalRequest request) async {
      approvals += 1;
      expect(request.target, contains('server_1'));
      return true;
    }

    final HarnessToolCallResult profiles = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteListProfilesId,
      arguments: const <String, Object?>{},
      approve: approve,
    );
    final HarnessToolCallResult command = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSshExecId,
      arguments: const <String, Object?>{
        'profileId': 'server_1',
        'command': 'printf HARNESS_SSH_OK',
      },
      approve: approve,
    );
    final HarnessToolCallResult listing = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSftpListId,
      arguments: const <String, Object?>{
        'profileId': 'server_1',
        'remotePath': '/tmp',
      },
      approve: approve,
    );
    final HarnessToolCallResult uploaded = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSftpUploadId,
      arguments: <String, Object?>{
        'profileId': 'server_1',
        'localPath': upload.path,
        'remotePath': '/tmp/upload.txt',
      },
      approve: approve,
    );
    final HarnessToolCallResult downloaded = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSftpDownloadId,
      arguments: <String, Object?>{
        'profileId': 'server_1',
        'remotePath': '/tmp/remote.txt',
        'localPath': download,
      },
      approve: approve,
    );

    expect(profiles.ok, isTrue);
    expect(profiles.data.toString(), isNot(contains('vault-secret')));
    expect(command.data?['stdout'], 'HARNESS_SSH_OK');
    expect(listing.data.toString(), contains('remote.txt'));
    expect(uploaded.ok, isTrue);
    expect(downloaded.ok, isTrue);
    expect(await File(download).readAsString(), 'REMOTE_OK');
    expect(transfers, <String>['upload:/tmp/upload.txt', 'download:$download']);
    expect(approvals, 3);
    expect(activities, hasLength(5));
    expect(
      activities.map((Map<String, Object?> item) => item['toolId']),
      containsAll(<String>[
        VibekitsHarnessToolBridge.remoteSshExecId,
        VibekitsHarnessToolBridge.remoteSftpListId,
        VibekitsHarnessToolBridge.remoteSftpUploadId,
        VibekitsHarnessToolBridge.remoteSftpDownloadId,
      ]),
    );
    expect(activities.toString(), isNot(contains('vault-secret')));
  });

  test('Harness 可打开一次认证后自动联动 SFTP 的交互工作流', () async {
    RemoteWorkspaceIntent? opened;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      remoteWorkspaceLauncher: (RemoteWorkspaceIntent intent) async {
        opened = intent;
      },
    );
    expect(
      bridge.executableCatalog.any(
        (HarnessToolDefinition tool) =>
            tool.id == VibekitsHarnessToolBridge.remoteOpenInteractiveId,
      ),
      isTrue,
    );
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteOpenInteractiveId,
      arguments: const <String, Object?>{
        'host': '192.168.3.20',
        'user': 'root',
        'openSftp': true,
      },
      approve: (_) async {
        approvals += 1;
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.data?['state'], 'awaiting_user_authentication');
    expect(opened?.host, '192.168.3.20');
    expect(opened?.user, 'root');
    expect(opened?.openSftpAfterConnect, isTrue);
    expect(approvals, 0);
  });

  test('Harness 截图 OCR 通过界面工作流返回本机识别结果', () async {
    int runs = 0;
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      screenshotOcrRunner: () async {
        runs += 1;
        return <String, Object?>{
          'text': 'Build succeeded',
          'lineCount': 1,
          'runtime': 'PP-OCRv6 tiny',
        };
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.screenshotOcrId,
      arguments: const <String, Object?>{},
      approve: (_) async {
        approvals += 1;
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.data?['text'], 'Build succeeded');
    expect(runs, 1);
    expect(approvals, 1);
  });

  test('Harness 通过已保存会话只读检查和查询远程数据库', () async {
    const RemoteDatabaseProfile profile = RemoteDatabaseProfile(
      id: 'postgres-42',
      name: '开发库',
      host: 'db.example.com',
      port: 5432,
      database: 'app',
      username: 'developer',
      useTls: true,
    );
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      remoteDatabaseProfileLoader: () async => <RemoteDatabaseProfile>[profile],
      credentialReader: (String key) async {
        expect(key, profile.id);
        return 'database-secret';
      },
      remoteDatabaseInspector:
          (RemoteDatabaseProfile value, String password) async {
            expect(value.id, profile.id);
            expect(password, 'database-secret');
            return const RemoteDatabaseSnapshot(
              profile: profile,
              serverVersion: 'PostgreSQL 17',
              objects: <RemoteDatabaseObject>[
                RemoteDatabaseObject(schema: 'public', name: 'users'),
              ],
            );
          },
      remoteDatabaseQuerier:
          (RemoteDatabaseProfile value, String password, String sql) async {
            expect(password, 'database-secret');
            expect(
              RemoteDatabaseService.validateReadOnlySql(sql, value.engine),
              'SELECT 1',
            );
            return const SqliteResultPage(
              columns: <String>['value'],
              rows: <List<String>>[
                <String>['1'],
              ],
              offset: 0,
              hasMore: false,
              label: '远程 SQL 查询',
            );
          },
    );

    Future<bool> approve(HarnessToolApprovalRequest request) async {
      approvals += 1;
      expect(request.target, profile.id);
      return true;
    }

    final HarnessToolCallResult profiles = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteDatabaseListProfilesId,
      arguments: const <String, Object?>{},
      approve: approve,
    );
    final HarnessToolCallResult inspected = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteDatabaseInspectId,
      arguments: const <String, Object?>{'profileId': 'postgres-42'},
      approve: approve,
    );
    final HarnessToolCallResult queried = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteDatabaseQueryId,
      arguments: const <String, Object?>{
        'profileId': 'postgres-42',
        'sql': 'SELECT 1',
      },
      approve: approve,
    );

    expect(profiles.data.toString(), contains('db.example.com'));
    expect(profiles.data.toString(), isNot(contains('database-secret')));
    expect(inspected.data.toString(), contains('users'));
    expect(queried.data?['rows'], <List<String>>[
      <String>['1'],
    ]);
    expect(approvals, 2);
  });

  test('Harness 在后台线程完成文件哈希和重复文件扫描', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_files_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final File first = await File(
      '${sandbox.path}${Platform.pathSeparator}first.bin',
    ).writeAsString('same-content');
    await File('${sandbox.path}${Platform.pathSeparator}second.bin')
        .writeAsString('same-content');
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;
    Future<bool> approve(HarnessToolApprovalRequest request) async {
      approvals += 1;
      return true;
    }

    final HarnessToolCallResult hash = await bridge.invoke(
      toolId: 'vibekits.file_hash',
      arguments: <String, Object?>{'input': first.path, 'params': 'sha256'},
      approve: approve,
    );
    final HarnessToolCallResult duplicates = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.duplicateScanId,
      arguments: <String, Object?>{'root': sandbox.path, 'minimumSize': 1},
      approve: approve,
    );
    final HarnessToolCallResult drive = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.systemDriveAnalyzeId,
      arguments: <String, Object?>{'root': sandbox.path},
      approve: approve,
    );

    expect(hash.ok, isTrue);
    expect(hash.data?['digest'], hasLength(64));
    expect(duplicates.data?['duplicateFiles'], 1);
    expect(duplicates.data?['reclaimableBytes'], 12);
    expect(drive.ok, isTrue);
    expect(drive.data?['totalBytes'], greaterThan(0));
    expect(drive.data?['entries'].toString(), contains('first.bin'));
    expect(approvals, 0);
  });
}

class _FakeHarnessRemoteFileClient implements RemoteFileClient {
  _FakeHarnessRemoteFileClient(this.transfers);

  final List<String> transfers;

  @override
  Future<String> absolute(String path) async => path;

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async =>
      const <RemoteFileEntry>[
        RemoteFileEntry(
          name: 'remote.txt',
          path: '/tmp/remote.txt',
          isDirectory: false,
          size: 9,
        ),
      ];

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    final int size = await File(localPath).length();
    transfers.add('upload:$remotePath');
    onProgress(size, size);
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    required int total,
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    transfers.add('download:$localPath');
    await File(localPath).writeAsString('REMOTE_OK');
    onProgress(total, total);
  }

  @override
  Future<void> close() async {}
}
