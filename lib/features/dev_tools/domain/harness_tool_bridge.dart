import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../app/app_settings.dart';
import '../../cleaner/domain/cleanup_task.dart';
import '../../cleaner/domain/system_drive_analysis_runner.dart';
import '../../cleaner/domain/system_drive_analyzer.dart';
import '../../cleaner/domain/system_drive_insights.dart';
import 'adb_service.dart';
import 'api_request_service.dart';
import 'duplicate_file_background_runner.dart';
import 'duplicate_file_scanner.dart';
import 'file_hash_background_runner.dart';
import 'file_hash_service.dart';
import 'file_diff_service.dart';
import 'file_search_service.dart';
import 'git_repository_service.dart';
import 'github_diagnostics.dart';
import 'harness_tool_activity_store.dart';
import 'programmer_calculator.dart';
import 'platform_credential_store.dart';
import 'remote_connection_record.dart';
import 'remote_database_service.dart';
import 'remote_session.dart';
import 'serial_port_service.dart';
import 'sftp_service.dart';
import 'sqlite_database_service.dart';
import 'tool_registry.dart';
import 'tool_result.dart';

enum HarnessToolRisk { readOnly, writesData, controlsDevice, destructive }

class HarnessToolDefinition {
  const HarnessToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.risk,
    required this.inputSchema,
    required this.available,
  });

  final String id;
  final String name;
  final String description;
  final HarnessToolRisk risk;
  final Map<String, Object?> inputSchema;
  final bool available;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'risk': risk.name,
    'inputSchema': inputSchema,
    'available': available,
  };
}

class HarnessToolApprovalRequest {
  const HarnessToolApprovalRequest({
    required this.tool,
    required this.arguments,
    required this.target,
  });

  final HarnessToolDefinition tool;
  final Map<String, Object?> arguments;
  final String target;
}

class HarnessToolCallResult {
  const HarnessToolCallResult._({
    required this.ok,
    required this.cancelled,
    this.data,
    this.error,
  });

  const HarnessToolCallResult.success(Map<String, Object?> data)
    : this._(ok: true, cancelled: false, data: data);

  const HarnessToolCallResult.failure(String error)
    : this._(ok: false, cancelled: false, error: error);

  const HarnessToolCallResult.cancelled()
    : this._(ok: false, cancelled: true, error: '用户未批准此操作');

  final bool ok;
  final bool cancelled;
  final Map<String, Object?>? data;
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    'cancelled': cancelled,
    if (data != null) 'data': data,
    if (error != null) 'error': error,
  };
}

typedef HarnessToolApproval = Future<bool> Function(
  HarnessToolApprovalRequest request,
);
typedef HarnessToolHandler = Future<Map<String, Object?>> Function(
  Map<String, Object?> arguments,
);
typedef HarnessRemoteProfileLoader =
    Future<List<RemoteConnectionRecord>> Function();
typedef HarnessCredentialReader = Future<String?> Function(String key);
typedef HarnessRemoteCommandRunner = Future<RemoteCommandResult> Function(
  RemoteConnectionProfile profile,
  String command,
  String? secret,
  RemoteHostKeyVerifier verifyHostKey,
);
typedef HarnessRemoteFileConnector = Future<RemoteFileClient> Function(
  RemoteConnectionProfile profile,
  String? secret,
  RemoteHostKeyVerifier verifyHostKey,
);
typedef HarnessRemoteDatabaseProfileLoader =
    Future<List<RemoteDatabaseProfile>> Function();
typedef HarnessRemoteDatabaseInspector =
    Future<RemoteDatabaseSnapshot> Function(
      RemoteDatabaseProfile profile,
      String password,
    );
typedef HarnessRemoteDatabaseQuerier = Future<SqliteResultPage> Function(
  RemoteDatabaseProfile profile,
  String password,
  String sql,
);
typedef HarnessRemoteWorkspaceLauncher = Future<void> Function(
  RemoteWorkspaceIntent intent,
);
typedef HarnessScreenshotOcrRunner = Future<Map<String, Object?>> Function();

/// Harness 只能通过此桥接调用 Vibekits 能力。
///
/// 目录与手工界面共用 [ToolSpec] 和领域服务。未接处理器的独立工作区会
/// 出现在完整能力目录中，但不会进入可执行目录，避免向模型宣传假能力。
class VibekitsHarnessToolBridge {
  factory VibekitsHarnessToolBridge({
    Map<String, HarnessToolHandler> handlers =
        const <String, HarnessToolHandler>{},
    AdbCommandRunner? adbRunner,
    String? adbExecutable,
    HarnessToolActivityRecorder? activityRecorder,
    HarnessRemoteProfileLoader? remoteProfileLoader,
    HarnessCredentialReader? credentialReader,
    HarnessRemoteCommandRunner? remoteCommandRunner,
    HarnessRemoteFileConnector? remoteFileConnector,
    HarnessRemoteDatabaseProfileLoader? remoteDatabaseProfileLoader,
    HarnessRemoteDatabaseInspector? remoteDatabaseInspector,
    HarnessRemoteDatabaseQuerier? remoteDatabaseQuerier,
    HarnessRemoteWorkspaceLauncher? remoteWorkspaceLauncher,
    HarnessScreenshotOcrRunner? screenshotOcrRunner,
  }) => VibekitsHarnessToolBridge._(
    handlers,
    adbRunner,
    adbExecutable,
    activityRecorder,
    remoteProfileLoader,
    credentialReader,
    remoteCommandRunner,
    remoteFileConnector,
    remoteDatabaseProfileLoader,
    remoteDatabaseInspector,
    remoteDatabaseQuerier,
    remoteWorkspaceLauncher,
    screenshotOcrRunner,
  );

  VibekitsHarnessToolBridge._(
    this._customHandlers,
    this._adbRunner,
    this._adbExecutable,
    this._activityRecorder,
    this._remoteProfileLoader,
    this._credentialReader,
    this._remoteCommandRunner,
    this._remoteFileConnector,
    this._remoteDatabaseProfileLoader,
    this._remoteDatabaseInspector,
    this._remoteDatabaseQuerier,
    this._remoteWorkspaceLauncher,
    this._screenshotOcrRunner,
  );

  static const String protocolVersion = 'vibekits.tools.v1';
  static const String adbListDevicesId = 'vibekits.adb.list_devices';
  static const String adbConnectId = 'vibekits.adb.connect';
  static const String adbCommandId = 'vibekits.adb.command';
  static const String serialListPortsId = 'vibekits.serial.list_ports';
  static const String serialTransactId = 'vibekits.serial.transact';
  static const String sqliteInspectId = 'vibekits.sqlite.inspect';
  static const String sqliteQueryId = 'vibekits.sqlite.query';
  static const String gitInspectId = 'vibekits.git.inspect';
  static const String gitCompareRefsId = 'vibekits.git.compare_refs';
  static const String gitCreateLocalBranchId =
      'vibekits.git.create_local_branch';
  static const String fileSearchId = 'vibekits.files.search';
  static const String apiRequestId = 'vibekits.http.request';
  static const String githubDiagnosticsId = 'vibekits.github.diagnose';
  static const String programmerCalculatorId = 'vibekits.calculator.programmer';
  static const String remoteListProfilesId = 'vibekits.remote.list_profiles';
  static const String remoteSshExecId = 'vibekits.remote.ssh_exec';
  static const String remoteSftpListId = 'vibekits.remote.sftp_list';
  static const String remoteSftpUploadId = 'vibekits.remote.sftp_upload';
  static const String remoteSftpDownloadId = 'vibekits.remote.sftp_download';
  static const String remoteOpenInteractiveId =
      'vibekits.remote.open_interactive';
  static const String remoteDatabaseListProfilesId =
      'vibekits.database.remote_list_profiles';
  static const String remoteDatabaseInspectId =
      'vibekits.database.remote_inspect';
  static const String remoteDatabaseQueryId = 'vibekits.database.remote_query';
  static const String duplicateScanId = 'vibekits.files.duplicate_scan';
  static const String fileDiffId = 'vibekits.file_diff';
  static const String systemDriveAnalyzeId = 'vibekits.cleaner.analyze_drive';
  static const String screenshotOcrId = 'vibekits.ocr.capture_screen';

  final Map<String, HarnessToolHandler> _customHandlers;
  final AdbCommandRunner? _adbRunner;
  final String? _adbExecutable;
  final HarnessToolActivityRecorder? _activityRecorder;
  final HarnessRemoteProfileLoader? _remoteProfileLoader;
  final HarnessCredentialReader? _credentialReader;
  final HarnessRemoteCommandRunner? _remoteCommandRunner;
  final HarnessRemoteFileConnector? _remoteFileConnector;
  final HarnessRemoteDatabaseProfileLoader? _remoteDatabaseProfileLoader;
  final HarnessRemoteDatabaseInspector? _remoteDatabaseInspector;
  final HarnessRemoteDatabaseQuerier? _remoteDatabaseQuerier;
  final HarnessRemoteWorkspaceLauncher? _remoteWorkspaceLauncher;
  final HarnessScreenshotOcrRunner? _screenshotOcrRunner;

  late final Map<String, HarnessToolDefinition> _definitions =
      <String, HarnessToolDefinition>{
        for (final ToolSpec spec in allDevToolRegistry)
          'vibekits.${spec.id}': _fromToolSpec(spec),
        adbListDevicesId: const HarnessToolDefinition(
          id: adbListDevicesId,
          name: '列出 ADB 设备',
          description: '读取已连接的 Android USB/无线调试设备及授权状态。',
          risk: HarnessToolRisk.readOnly,
          inputSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          available: true,
        ),
        adbConnectId: const HarnessToolDefinition(
          id: adbConnectId,
          name: '连接 ADB 设备',
          description: '连接用户明确指定的 Android 无线调试地址。',
          risk: HarnessToolRisk.controlsDevice,
          inputSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'address': <String, Object?>{
                'type': 'string',
                'description': 'IP 或 IP:端口，例如 192.168.3.63:5555',
              },
            },
            'required': <String>['address'],
            'additionalProperties': false,
          },
          available: true,
        ),
        adbCommandId: _definition(
          id: adbCommandId,
          name: '执行 ADB 命令',
          description: '对明确设备执行受限 ADB 参数；禁止 start-server、kill-server 和任意本机程序。',
          risk: HarnessToolRisk.controlsDevice,
          properties: <String, Object?>{
            'serial': _string('设备序列号或 IP:端口'),
            'arguments': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
              'minItems': 1,
              'maxItems': 32,
            },
          },
          required: <String>['serial', 'arguments'],
        ),
        serialListPortsId: _definition(
          id: serialListPortsId,
          name: '列出串口',
          description: '在后台线程读取 Windows/macOS 可用串口及 USB 描述。',
          properties: const <String, Object?>{},
        ),
        serialTransactId: _definition(
          id: serialTransactId,
          name: '串口一次收发',
          description: '后台打开串口、发送文本或 HEX、短暂接收后自动关闭。',
          risk: HarnessToolRisk.controlsDevice,
          properties: <String, Object?>{
            'port': _string('串口名，例如 COM3'),
            'baudRate': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 12000000,
            },
            'data': _string('待发送文本或 HEX 字节'),
            'mode': <String, Object?>{
              'type': 'string',
              'enum': <String>['text', 'hex'],
            },
            'waitMs': <String, Object?>{
              'type': 'integer',
              'minimum': 50,
              'maximum': 5000,
            },
          },
          required: <String>['port', 'data'],
        ),
        sqliteInspectId: _definition(
          id: sqliteInspectId,
          name: '检查 SQLite 数据库',
          description: '只读列出本地 SQLite 数据库中的表、视图和建表语句。',
          properties: <String, Object?>{'path': _string('数据库绝对路径')},
          required: <String>['path'],
        ),
        sqliteQueryId: _definition(
          id: sqliteQueryId,
          name: '查询 SQLite 数据库',
          description: '在隔离线程执行单条只读 SQL，最多返回 500 行。',
          properties: <String, Object?>{
            'path': _string('数据库绝对路径'),
            'sql': _string('单条只读 SQL'),
            'maxRows': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 500,
            },
          },
          required: <String>['path', 'sql'],
        ),
        gitInspectId: _definition(
          id: gitInspectId,
          name: '检查 Git 工作区',
          description: '只读返回分支、状态、diff 和最近提交。',
          properties: <String, Object?>{'path': _string('仓库或其子目录')},
          required: <String>['path'],
        ),
        gitCompareRefsId: _definition(
          id: gitCompareRefsId,
          name: '对比 Git 两个版本',
          description: '只读校验两个提交、标签或分支，并返回文件列表、统计和文本差异。',
          properties: <String, Object?>{
            'path': _string('仓库或其子目录'),
            'baseRef': _string('基准提交、标签或分支'),
            'targetRef': _string('目标提交、标签或分支'),
          },
          required: <String>['path', 'baseRef', 'targetRef'],
        ),
        gitCreateLocalBranchId: _definition(
          id: gitCreateLocalBranchId,
          name: '创建 Git 本地安全分支',
          description: '从指定版本创建本地分支但不切换工作区；需要按当前权限模式批准。',
          risk: HarnessToolRisk.writesData,
          properties: <String, Object?>{
            'path': _string('仓库或其子目录'),
            'name': _string('新本地分支名称'),
            'startPoint': _string('起点提交、标签或分支，默认 HEAD'),
          },
          required: <String>['path', 'name'],
        ),
        fileSearchId: _definition(
          id: fileSearchId,
          name: '搜索文件',
          description: '按文件名或文本内容进行有界搜索，不跟随符号链接。',
          properties: <String, Object?>{
            'root': _string('搜索根目录'),
            'query': _string('关键词'),
            'mode': <String, Object?>{
              'type': 'string',
              'enum': <String>['name', 'content'],
            },
            'maxResults': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 500,
            },
          },
          required: <String>['root', 'query'],
        ),
        apiRequestId: _definition(
          id: apiRequestId,
          name: '发送 HTTP 请求',
          description: '发送有界 HTTP 请求并返回状态、响应头和正文；所有请求均需确认目标。',
          risk: HarnessToolRisk.controlsDevice,
          properties: <String, Object?>{
            'method': <String, Object?>{
              'type': 'string',
              'enum': <String>[
                'GET',
                'POST',
                'PUT',
                'PATCH',
                'DELETE',
                'HEAD',
                'OPTIONS',
              ],
            },
            'url': _string('完整 HTTP/HTTPS URL'),
            'headers': <String, Object?>{
              'type': 'object',
              'additionalProperties': <String, Object?>{'type': 'string'},
            },
            'body': <String, Object?>{'type': 'string'},
          },
          required: <String>['method', 'url'],
        ),
        githubDiagnosticsId: _definition(
          id: githubDiagnosticsId,
          name: 'GitHub 网络诊断',
          description: '并行检查 DNS、TLS、HTTPS、SSH 端口、代理和 hosts，只读不改系统。',
          properties: const <String, Object?>{},
        ),
        remoteListProfilesId: _definition(
          id: remoteListProfilesId,
          name: '列出远程会话',
          description: '列出已保存且已确认主机指纹的 SSH/SFTP 会话；不返回密码或私钥内容。',
          properties: const <String, Object?>{},
        ),
        remoteOpenInteractiveId: HarnessToolDefinition(
          id: remoteOpenInteractiveId,
          name: '打开 SSH 与 SFTP 工作流',
          description:
              '在 Vibekits 中打开指定主机的 SSH 登录界面；用户认证一次后自动复用该连接展示 SFTP 双栏文件。',
          risk: HarnessToolRisk.readOnly,
          inputSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'host': <String, Object?>{
                'type': 'string',
                'description': 'IP 地址或主机名',
              },
              'user': <String, Object?>{
                'type': 'string',
                'description': 'SSH 用户名；未知时可留空让用户填写',
              },
              'port': <String, Object?>{
                'type': 'integer',
                'minimum': 1,
                'maximum': 65535,
              },
              'openSftp': <String, Object?>{'type': 'boolean'},
            },
            'required': <String>['host'],
            'additionalProperties': false,
          },
          available: _remoteWorkspaceLauncher != null,
        ),
        remoteSshExecId: _definition(
          id: remoteSshExecId,
          name: '执行 SSH 命令',
          description: '使用已保存会话和系统凭据执行一条有界远程命令，严格校验已绑定主机指纹。',
          risk: HarnessToolRisk.controlsDevice,
          properties: <String, Object?>{
            'profileId': _string('远程工作台保存的会话 ID'),
            'command': _string('要在远端执行的单条命令'),
          },
          required: <String>['profileId', 'command'],
        ),
        remoteSftpListId: _definition(
          id: remoteSftpListId,
          name: '列出 SFTP 目录',
          description: '复用已保存 SSH 会话的凭据和主机指纹，只读列出远端目录。',
          properties: <String, Object?>{
            'profileId': _string('远程工作台保存的会话 ID'),
            'remotePath': _string('远端目录，默认当前用户主目录'),
          },
          required: <String>['profileId'],
        ),
        remoteSftpUploadId: _definition(
          id: remoteSftpUploadId,
          name: 'SFTP 上传文件',
          description: '通过已保存 SSH 会话上传一个本地文件；覆盖已有文件必须明确指定。',
          risk: HarnessToolRisk.writesData,
          properties: <String, Object?>{
            'profileId': _string('远程工作台保存的会话 ID'),
            'localPath': _string('本地文件绝对路径'),
            'remotePath': _string('远端目标绝对路径'),
            'overwrite': <String, Object?>{'type': 'boolean'},
          },
          required: <String>['profileId', 'localPath', 'remotePath'],
        ),
        remoteSftpDownloadId: _definition(
          id: remoteSftpDownloadId,
          name: 'SFTP 下载文件',
          description: '通过已保存 SSH 会话下载一个远端文件；覆盖本地文件必须明确指定。',
          risk: HarnessToolRisk.writesData,
          properties: <String, Object?>{
            'profileId': _string('远程工作台保存的会话 ID'),
            'remotePath': _string('远端文件绝对路径'),
            'localPath': _string('本地目标绝对路径'),
            'overwrite': <String, Object?>{'type': 'boolean'},
          },
          required: <String>['profileId', 'remotePath', 'localPath'],
        ),
        remoteDatabaseListProfilesId: _definition(
          id: remoteDatabaseListProfilesId,
          name: '列出远程数据库会话',
          description: '列出已保存的 PostgreSQL、MySQL 和 MariaDB 会话；不返回密码。',
          properties: const <String, Object?>{},
        ),
        remoteDatabaseInspectId: _definition(
          id: remoteDatabaseInspectId,
          name: '检查远程数据库',
          description: '使用系统凭据在后台线程连接已保存的远程数据库，并只读列出对象。',
          risk: HarnessToolRisk.controlsDevice,
          properties: <String, Object?>{'profileId': _string('数据库工作区保存的会话 ID')},
          required: <String>['profileId'],
        ),
        remoteDatabaseQueryId: _definition(
          id: remoteDatabaseQueryId,
          name: '查询远程数据库',
          description: '使用已保存会话执行一条有界只读 SQL，最多返回 500 行。',
          risk: HarnessToolRisk.controlsDevice,
          properties: <String, Object?>{
            'profileId': _string('数据库工作区保存的会话 ID'),
            'sql': _string('只读 SQL'),
          },
          required: <String>['profileId', 'sql'],
        ),
        duplicateScanId: _definition(
          id: duplicateScanId,
          name: '扫描重复文件',
          description: '在独立后台线程按大小和完整 SHA-256 扫描重复文件；只返回建议，不自动删除。',
          properties: <String, Object?>{
            'root': _string('扫描根目录'),
            'recursive': <String, Object?>{'type': 'boolean'},
            'minimumSize': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 1099511627776,
            },
          },
          required: <String>['root'],
        ),
        fileDiffId: _definition(
          id: fileDiffId,
          name: '比较两个文件',
          description: '在独立后台线程读取两个有界文本或源码文件，自动识别编码并返回行级差异；不修改文件。',
          properties: <String, Object?>{
            'leftPath': _string('左侧原文件路径'),
            'rightPath': _string('右侧新文件路径'),
            'ignoreWhitespace': <String, Object?>{'type': 'boolean'},
            'ignoreCase': <String, Object?>{'type': 'boolean'},
          },
          required: <String>['leftPath', 'rightPath'],
        ),
        systemDriveAnalyzeId: _definition(
          id: systemDriveAnalyzeId,
          name: '分析磁盘占用',
          description: '在独立后台线程分析指定磁盘根目录，按系统、软件和用户数据解释占用是否合理并给出安全建议；不删除任何文件。',
          properties: <String, Object?>{'root': _string('磁盘或待分析目录')},
          required: <String>['root'],
        ),
        screenshotOcrId: HarnessToolDefinition(
          id: screenshotOcrId,
          name: '截图并 OCR 分析',
          description: '让用户框选屏幕区域，使用 App 内置 PP-OCRv6 tiny 在本机识别，并把文字返回智能体。',
          risk: HarnessToolRisk.controlsDevice,
          inputSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          available: _screenshotOcrRunner != null,
        ),
        programmerCalculatorId: _definition(
          id: programmerCalculatorId,
          name: '程序员计算器',
          description: '计算整数、进制和位运算表达式，并返回固定位宽的二/八/十/十六进制结果。',
          properties: <String, Object?>{
            'expression': _string('整数表达式，例如 (0xFF << 2) | 3'),
            'width': <String, Object?>{
              'type': 'integer',
              'enum': <int>[8, 16, 32, 64, 128],
            },
            'inputRadix': <String, Object?>{
              'type': 'integer',
              'enum': <int>[2, 8, 10, 16],
            },
          },
          required: <String>['expression'],
        ),
      };

  List<HarnessToolDefinition> get fullCatalog =>
      List<HarnessToolDefinition>.unmodifiable(_definitions.values);

  List<HarnessToolDefinition> get executableCatalog =>
      List<HarnessToolDefinition>.unmodifiable(
        _definitions.values.where((HarnessToolDefinition tool) {
          return tool.available || _customHandlers.containsKey(tool.id);
        }),
      );

  Map<String, Object?> exportCatalog() => <String, Object?>{
    'protocol': protocolVersion,
    'tools': <Map<String, Object?>>[
      for (final HarnessToolDefinition tool in executableCatalog) tool.toJson(),
    ],
  };

  Future<HarnessToolCallResult> invoke({
    required String toolId,
    required Map<String, Object?> arguments,
    required HarnessToolApproval approve,
  }) async {
    final DateTime startedAt = DateTime.now();
    final HarnessToolDefinition? definition = _definitions[toolId];
    if (definition == null) {
      return HarnessToolCallResult.failure('未知 Vibekits 工具：$toolId');
    }
    final HarnessToolHandler? handler = _handlerFor(toolId);
    if (handler == null) {
      return HarnessToolCallResult.failure('工具尚未接入 Harness 执行器：$toolId');
    }
    final String target = _targetSummary(toolId, arguments);
    if (definition.risk != HarnessToolRisk.readOnly) {
      final bool allowed = await approve(
        HarnessToolApprovalRequest(
          tool: definition,
          arguments: Map<String, Object?>.unmodifiable(arguments),
          target: target,
        ),
      );
      if (!allowed) {
        await _recordActivity(
          toolId: toolId,
          toolName: definition.name,
          target: target,
          arguments: arguments,
          result: '用户拒绝',
          status: HarnessToolActivityStatus.denied,
          startedAt: startedAt,
        );
        return const HarnessToolCallResult.cancelled();
      }
    }
    try {
      final Map<String, Object?> data = await handler(arguments);
      if (!_adbExecutionIsAuditedByService(toolId)) {
        await _recordActivity(
          toolId: toolId,
          toolName: definition.name,
          target: target,
          arguments: arguments,
          result: _activityResult(toolId, data),
          status: HarnessToolActivityStatus.succeeded,
          startedAt: startedAt,
        );
      }
      return HarnessToolCallResult.success(data);
    } on Object catch (error) {
      if (!_adbExecutionIsAuditedByService(toolId)) {
        await _recordActivity(
          toolId: toolId,
          toolName: definition.name,
          target: target,
          arguments: arguments,
          result: '$error',
          status: HarnessToolActivityStatus.failed,
          startedAt: startedAt,
        );
      }
      return HarnessToolCallResult.failure('$error');
    }
  }

  bool _adbExecutionIsAuditedByService(String toolId) =>
      _adbRunner == null &&
      (toolId == adbListDevicesId ||
          toolId == adbConnectId ||
          toolId == adbCommandId);

  Future<void> _recordActivity({
    required String toolId,
    required String toolName,
    required String target,
    required Map<String, Object?> arguments,
    required Object? result,
    required HarnessToolActivityStatus status,
    required DateTime startedAt,
  }) async {
    if (_activityRecorder == null &&
        Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }
    try {
      await (_activityRecorder ?? HarnessToolActivityStore.record)(
        toolId: toolId,
        toolName: toolName,
        target: target,
        arguments: arguments,
        result: result,
        status: status,
        startedAt: startedAt,
      );
    } on Object {
      // An audit storage failure must not turn a completed tool call into a
      // model-visible tool failure. The UI will still show the storage error
      // when it attempts to load the activity file.
    }
  }

  HarnessToolDefinition _fromToolSpec(ToolSpec spec) {
    final String id = 'vibekits.${spec.id}';
    return HarnessToolDefinition(
      id: id,
      name: spec.name,
      description: spec.description,
      risk: _riskFor(spec.id),
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'input': <String, Object?>{'type': 'string'},
          'params': <String, Object?>{'type': 'string'},
        },
        'required': <String>['input'],
        'additionalProperties': false,
      },
      available:
          spec.run != null ||
          spec.runAsync != null ||
          _customHandlers.containsKey(id),
    );
  }

  HarnessToolHandler? _handlerFor(String toolId) {
    final HarnessToolHandler? custom = _customHandlers[toolId];
    if (custom != null) return custom;
    if (toolId == adbListDevicesId) return _listAdbDevices;
    if (toolId == adbConnectId) return _connectAdb;
    if (toolId == adbCommandId) return _runAdbCommand;
    if (toolId == serialListPortsId) return _listSerialPorts;
    if (toolId == serialTransactId) return _serialTransact;
    if (toolId == sqliteInspectId) return _inspectSqlite;
    if (toolId == sqliteQueryId) return _querySqlite;
    if (toolId == gitInspectId) return _inspectGit;
    if (toolId == gitCompareRefsId) return _compareGitRefs;
    if (toolId == gitCreateLocalBranchId) return _createGitLocalBranch;
    if (toolId == fileSearchId) return _searchFiles;
    if (toolId == apiRequestId) return _requestHttp;
    if (toolId == githubDiagnosticsId) return _diagnoseGithub;
    if (toolId == remoteListProfilesId) return _listRemoteProfiles;
    if (toolId == remoteOpenInteractiveId) return _openInteractiveRemote;
    if (toolId == remoteSshExecId) return _runRemoteSshCommand;
    if (toolId == remoteSftpListId) return _listRemoteSftp;
    if (toolId == remoteSftpUploadId) return _uploadRemoteSftp;
    if (toolId == remoteSftpDownloadId) return _downloadRemoteSftp;
    if (toolId == remoteDatabaseListProfilesId) {
      return _listRemoteDatabaseProfiles;
    }
    if (toolId == remoteDatabaseInspectId) return _inspectRemoteDatabase;
    if (toolId == remoteDatabaseQueryId) return _queryRemoteDatabase;
    if (toolId == duplicateScanId) return _scanDuplicateFiles;
    if (toolId == fileDiffId) return _diffFiles;
    if (toolId == systemDriveAnalyzeId) return _analyzeSystemDrive;
    if (toolId == screenshotOcrId) return _captureScreenAndOcr;
    if (toolId == 'vibekits.file_hash') return _hashFileInBackground;
    if (toolId == programmerCalculatorId) return _calculate;
    final String specId = toolId.startsWith('vibekits.')
        ? toolId.substring('vibekits.'.length)
        : '';
    final ToolSpec? spec = allDevToolRegistry
        .where((ToolSpec value) => value.id == specId)
        .firstOrNull;
    if (spec == null || (spec.run == null && spec.runAsync == null)) {
      return null;
    }
    return (Map<String, Object?> arguments) async {
      final String input = (arguments['input'] ?? '').toString();
      final String params = (arguments['params'] ?? '').toString();
      final ToolResult result = spec.runAsync != null
          ? await spec.runAsync!(input, params)
          : spec.run!(input, params);
      return switch (result) {
        ToolSuccess(:final String output) => <String, Object?>{
          'output': output,
        },
        ToolFailure(:final String message, :final int? position) =>
          throw FormatException(message, null, position),
      };
    };
  }

  Future<Map<String, Object?>> _listAdbDevices(
    Map<String, Object?> arguments,
  ) async {
    final AdbSnapshot snapshot = await AdbService.discoverAndList(
      preferredExecutable: _adbExecutable ?? AdbService.bundledExecutablePath(),
      runner: _adbRunner,
      listAudit: AdbCommandAudit(
        toolId: adbListDevicesId,
        toolName: '列出 ADB 设备',
        target: '',
        recorder: _activityRecorder,
      ),
    );
    return <String, Object?>{
      'adbVersion': snapshot.installation.version,
      'devices': <Map<String, Object?>>[
        for (final AdbDevice device in snapshot.devices)
          <String, Object?>{
            'serial': device.serial,
            'state': device.state.name,
            if (device.model != null) 'model': device.model,
            if (device.product != null) 'product': device.product,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _connectAdb(
    Map<String, Object?> arguments,
  ) async {
    final String address = (arguments['address'] ?? '').toString().trim();
    if (address.isEmpty) throw const FormatException('缺少 ADB 设备地址');
    final String executable =
        _adbExecutable ?? AdbService.bundledExecutablePath();
    final String output = await AdbService.connect(
      executable,
      address,
      runner: _adbRunner,
      audit: AdbCommandAudit(
        toolId: adbConnectId,
        toolName: '连接 ADB 设备',
        target: AdbService.normalizeWirelessAddress(address),
        recorder: _activityRecorder,
      ),
    );
    return <String, Object?>{
      'address': AdbService.normalizeWirelessAddress(address),
      'output': output,
    };
  }

  Future<Map<String, Object?>> _runAdbCommand(
    Map<String, Object?> arguments,
  ) async {
    final String serial = (arguments['serial'] ?? '').toString().trim();
    final List<String> command = _stringList(arguments['arguments']);
    if (serial.isEmpty || command.isEmpty) {
      throw const FormatException('缺少设备或 ADB 参数');
    }
    const Set<String> forbidden = <String>{
      'start-server',
      'kill-server',
      'server',
      'connect',
      'disconnect',
    };
    if (forbidden.contains(command.first.toLowerCase())) {
      throw const FormatException('该 ADB 管理命令未开放，请使用专用工具');
    }
    final String executable =
        _adbExecutable ?? AdbService.bundledExecutablePath();
    final List<String> adbArguments = <String>['-s', serial, ...command];
    final AdbCommandResult result = _adbRunner == null
        ? await AdbService.runCommand(
            executable,
            adbArguments,
            audit: AdbCommandAudit(
              toolId: adbCommandId,
              toolName: '执行 ADB 命令',
              target: serial,
              recorder: _activityRecorder,
            ),
          )
        : await _adbRunner(executable, adbArguments);
    if (result.exitCode != 0) {
      throw StateError(
        result.stderr.trim().isEmpty
            ? 'ADB 命令失败（exit ${result.exitCode}）'
            : result.stderr.trim(),
      );
    }
    return <String, Object?>{
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
    };
  }

  Future<Map<String, Object?>> _listSerialPorts(
    Map<String, Object?> arguments,
  ) async {
    final List<SerialPortDescriptor> ports =
        await SerialPortService.listPorts();
    return <String, Object?>{
      'ports': <Map<String, Object?>>[
        for (final SerialPortDescriptor port in ports)
          <String, Object?>{
            'name': port.name,
            'description': port.description,
            'transport': port.transport,
            if (port.vendorId != null) 'vendorId': port.vendorId,
            if (port.productId != null) 'productId': port.productId,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _serialTransact(
    Map<String, Object?> arguments,
  ) async {
    final SerialConnectionSettings settings = SerialConnectionSettings(
      portName: (arguments['port'] ?? '').toString(),
      baudRate: _integer(arguments['baudRate'], 115200),
    );
    final SerialDataMode mode = arguments['mode'] == 'hex'
        ? SerialDataMode.hex
        : SerialDataMode.text;
    final int waitMs = _integer(arguments['waitMs'], 350).clamp(50, 5000);
    final SerialPortSession session = await SerialPortService.open(settings);
    final BytesBuilder received = BytesBuilder(copy: false);
    final StreamSubscription<SerialPortEvent> subscription = session.events
        .listen((SerialPortEvent event) {
          if (event.type == SerialPortEventType.received &&
              event.bytes != null) {
            received.add(event.bytes!);
          }
        });
    try {
      final Uint8List output = SerialCodec.encode(
        (arguments['data'] ?? '').toString(),
        mode,
      );
      final int sent = await session.send(output);
      await Future<void>.delayed(Duration(milliseconds: waitMs));
      final Uint8List input = received.takeBytes();
      return <String, Object?>{
        'sentBytes': sent,
        'receivedBytes': input.length,
        'received': SerialCodec.decode(input, mode),
      };
    } finally {
      await session.close();
      await subscription.cancel();
    }
  }

  Future<Map<String, Object?>> _inspectSqlite(
    Map<String, Object?> arguments,
  ) async {
    final SqliteDatabaseSnapshot snapshot = await SqliteDatabaseService.inspect(
      (arguments['path'] ?? '').toString(),
    );
    return <String, Object?>{
      'path': snapshot.path,
      'fileSize': snapshot.fileSize,
      'sqliteVersion': snapshot.sqliteVersion,
      'objects': <Map<String, Object?>>[
        for (final SqliteObjectInfo object in snapshot.objects)
          <String, Object?>{
            'name': object.name,
            'kind': object.kind.name,
            'sql': object.sql,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _querySqlite(
    Map<String, Object?> arguments,
  ) async => _pageJson(
    await SqliteDatabaseService.query(
      (arguments['path'] ?? '').toString(),
      (arguments['sql'] ?? '').toString(),
      maxRows: _integer(arguments['maxRows'], 100).clamp(1, 500),
    ),
  );

  Future<Map<String, Object?>> _inspectGit(
    Map<String, Object?> arguments,
  ) async {
    final GitRepositorySnapshot snapshot = await GitRepositoryService.inspect(
      (arguments['path'] ?? '').toString(),
    );
    return <String, Object?>{
      'root': snapshot.root,
      'branch': snapshot.branch,
      'status': snapshot.status,
      'diff': snapshot.diff,
      'log': snapshot.log,
    };
  }

  Future<Map<String, Object?>> _compareGitRefs(
    Map<String, Object?> arguments,
  ) async {
    final GitReferenceComparison comparison =
        await GitRepositoryService.compareRefs(
          (arguments['path'] ?? '').toString(),
          baseRef: (arguments['baseRef'] ?? '').toString(),
          targetRef: (arguments['targetRef'] ?? '').toString(),
        );
    return <String, Object?>{
      'root': comparison.root,
      'baseRef': comparison.baseRef,
      'targetRef': comparison.targetRef,
      'baseCommit': comparison.baseCommit,
      'targetCommit': comparison.targetCommit,
      'summary': comparison.summary,
      'changedFiles': comparison.changedFiles,
      'diff': comparison.diff,
    };
  }

  Future<Map<String, Object?>> _createGitLocalBranch(
    Map<String, Object?> arguments,
  ) async {
    final String branch = await GitRepositoryService.createLocalBranch(
      (arguments['path'] ?? '').toString(),
      name: (arguments['name'] ?? '').toString(),
      startPoint: (arguments['startPoint'] ?? 'HEAD').toString(),
    );
    return <String, Object?>{
      'branch': branch,
      'switched': false,
      'message': '本地分支已创建，当前工作区未切换',
    };
  }

  Future<Map<String, Object?>> _searchFiles(
    Map<String, Object?> arguments,
  ) async {
    final FileSearchResult result = await FileSearchService.search(
      FileSearchRequest(
        root: (arguments['root'] ?? '').toString(),
        query: (arguments['query'] ?? '').toString(),
        mode: arguments['mode'] == 'content'
            ? FileSearchMode.content
            : FileSearchMode.name,
        maxResults: _integer(arguments['maxResults'], 100).clamp(1, 500),
      ),
    );
    return <String, Object?>{
      'visitedFiles': result.visitedFiles,
      'skippedFiles': result.skippedFiles,
      'truncated': result.truncated,
      'elapsedMs': result.elapsed.inMilliseconds,
      'matches': <Map<String, Object?>>[
        for (final FileSearchMatch match in result.matches)
          <String, Object?>{
            'path': match.path,
            'name': match.name,
            'size': match.size,
            'modified': match.modified.toIso8601String(),
            if (match.lineNumber != null) 'lineNumber': match.lineNumber,
            if (match.snippet != null) 'snippet': match.snippet,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _requestHttp(
    Map<String, Object?> arguments,
  ) async {
    final Map<String, String> headers = arguments['headers'] is Map
        ? Map<String, String>.from(arguments['headers']! as Map)
        : const <String, String>{};
    final ApiResponseData response = await ApiRequestService.execute(
      ApiRequestSpec(
        method: (arguments['method'] ?? 'GET').toString().toUpperCase(),
        url: (arguments['url'] ?? '').toString(),
        headers: headers,
        body: (arguments['body'] ?? '').toString(),
      ),
    );
    return <String, Object?>{
      'statusCode': response.statusCode,
      'reason': response.reasonPhrase,
      'headers': response.headers,
      'body': response.body,
      'bodyBytes': response.bodyBytes,
      'elapsedMs': response.elapsed.inMilliseconds,
      'finalUrl': response.finalUrl.toString(),
    };
  }

  Future<Map<String, Object?>> _diagnoseGithub(
    Map<String, Object?> arguments,
  ) async {
    final GithubDiagnosticsReport report = await GithubDiagnosticsService.run();
    return <String, Object?>{
      'checks': <Map<String, Object?>>[
        for (final DiagnosticCheck check in report.checks)
          <String, Object?>{
            'id': check.id,
            'label': check.label,
            'status': check.status.name,
            'detail': check.detail,
            if (check.elapsed != null)
              'elapsedMs': check.elapsed!.inMilliseconds,
          },
      ],
      'recommendation': report.recommendation,
    };
  }

  Future<List<RemoteConnectionRecord>> _loadRemoteProfiles() async {
    final HarnessRemoteProfileLoader? loader = _remoteProfileLoader;
    return loader != null
        ? loader()
        : RemoteConnectionRecord.decodeMany(
            (await AppSettingsStore().load()).remoteSessionProfiles,
          );
  }

  Future<RemoteConnectionRecord> _remoteProfile(Object? rawId) async {
    final String id = '$rawId'.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('远程会话 ID 无效');
    }
    final RemoteConnectionRecord? profile = (await _loadRemoteProfiles())
        .where((RemoteConnectionRecord value) => value.id == id)
        .firstOrNull;
    if (profile == null || profile.mode == RemoteSessionMode.remoteDesktop) {
      throw StateError('没有找到可用的 SSH/SFTP 会话：$id');
    }
    if (profile.hostKeyType == null || profile.hostKeyFingerprint == null) {
      throw StateError('请先在远程工作台手动连接一次并确认主机指纹');
    }
    return profile;
  }

  Future<String?> _remoteSecret(RemoteConnectionRecord profile) async {
    final HarnessCredentialReader? reader = _credentialReader;
    final String? secret = await (reader != null
        ? reader(profile.credentialKey)
        : PlatformCredentialStore.read(profile.credentialKey));
    if (secret?.isNotEmpty != true &&
        profile.identityFile?.trim().isNotEmpty != true) {
      throw StateError('该远程会话没有可复用的系统凭据或私钥');
    }
    return secret;
  }

  RemoteHostKeyVerifier _pinnedVerifier(RemoteConnectionRecord profile) =>
      (String type, String fingerprint) async =>
          type == profile.hostKeyType &&
          fingerprint == profile.hostKeyFingerprint;

  Future<RemoteFileClient> _connectRemoteFiles(
    RemoteConnectionRecord profile,
  ) async {
    final String? secret = await _remoteSecret(profile);
    final RemoteHostKeyVerifier verifier = _pinnedVerifier(profile);
    final HarnessRemoteFileConnector? connector = _remoteFileConnector;
    return connector != null
        ? connector(profile.connection, secret, verifier)
        : RemoteFileService.connect(
            profile.connection,
            secret: secret,
            verifyHostKey: verifier,
          );
  }

  Future<Map<String, Object?>> _listRemoteProfiles(
    Map<String, Object?> arguments,
  ) async {
    final List<RemoteConnectionRecord> profiles = await _loadRemoteProfiles();
    return <String, Object?>{
      'profiles': <Map<String, Object?>>[
        for (final RemoteConnectionRecord profile in profiles)
          if (profile.mode != RemoteSessionMode.remoteDesktop)
            <String, Object?>{
              'id': profile.id,
              'name': profile.name,
              'mode': profile.mode.name,
              'host': profile.host,
              'port': profile.port,
              'user': profile.user,
              'hostKeyPinned': profile.hostKeyFingerprint != null,
              'hasIdentityFile': profile.identityFile != null,
            },
      ],
    };
  }

  Future<Map<String, Object?>> _openInteractiveRemote(
    Map<String, Object?> arguments,
  ) async {
    final HarnessRemoteWorkspaceLauncher? launcher = _remoteWorkspaceLauncher;
    if (launcher == null) {
      throw StateError('当前界面没有连接远程工作区导航器');
    }
    final RemoteWorkspaceIntent intent = RemoteWorkspaceIntent(
      host: (arguments['host'] ?? '').toString().trim(),
      user: (arguments['user'] ?? '').toString().trim(),
      port: _integer(arguments['port'], 22),
      openSftpAfterConnect: arguments['openSftp'] != false,
    );
    intent.validate();
    await launcher(intent);
    return <String, Object?>{
      'opened': true,
      'host': intent.host,
      'user': intent.user,
      'port': intent.port,
      'state': 'awaiting_user_authentication',
      'sftpAfterAuthentication': intent.openSftpAfterConnect,
      'message': intent.user.isEmpty
          ? '已打开 SSH 工作区，请填写用户名和密码；认证成功后将复用连接打开 SFTP。'
          : '已打开 SSH 工作区，请输入密码；认证成功后将复用连接打开 SFTP。',
    };
  }

  Future<Map<String, Object?>> _runRemoteSshCommand(
    Map<String, Object?> arguments,
  ) async {
    final RemoteConnectionRecord profile = await _remoteProfile(
      arguments['profileId'],
    );
    final String? secret = await _remoteSecret(profile);
    final RemoteHostKeyVerifier verifier = _pinnedVerifier(profile);
    final HarnessRemoteCommandRunner? runner = _remoteCommandRunner;
    final RemoteCommandResult result = runner != null
        ? await runner(
            profile.connection,
            (arguments['command'] ?? '').toString(),
            secret,
            verifier,
          )
        : await RemoteSshConnector.runCommand(
            profile.connection,
            (arguments['command'] ?? '').toString(),
            secret: secret,
            verifyHostKey: verifier,
          );
    if (result.exitCode != 0) {
      throw StateError(
        result.stderr.trim().isEmpty
            ? '远程命令失败（exit ${result.exitCode}）'
            : result.stderr.trim(),
      );
    }
    return <String, Object?>{
      'profileId': profile.id,
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
    };
  }

  Future<Map<String, Object?>> _listRemoteSftp(
    Map<String, Object?> arguments,
  ) async {
    final RemoteConnectionRecord profile = await _remoteProfile(
      arguments['profileId'],
    );
    final RemoteFileClient client = await _connectRemoteFiles(profile);
    try {
      final String path = (arguments['remotePath'] ?? '.').toString().trim();
      final List<RemoteFileEntry> entries = await client.listDirectory(
        path.isEmpty ? '.' : path,
      );
      return <String, Object?>{
        'profileId': profile.id,
        'path': await client.absolute(path.isEmpty ? '.' : path),
        'entries': <Map<String, Object?>>[
          for (final RemoteFileEntry entry in entries)
            <String, Object?>{
              'name': entry.name,
              'path': entry.path,
              'directory': entry.isDirectory,
              'size': entry.size,
              if (entry.modifiedEpochSeconds != null)
                'modifiedEpochSeconds': entry.modifiedEpochSeconds,
            },
        ],
      };
    } finally {
      await client.close();
    }
  }

  Future<Map<String, Object?>> _uploadRemoteSftp(
    Map<String, Object?> arguments,
  ) async {
    final RemoteConnectionRecord profile = await _remoteProfile(
      arguments['profileId'],
    );
    final String localPath = (arguments['localPath'] ?? '').toString();
    final String remotePath = (arguments['remotePath'] ?? '').toString();
    final File local = File(localPath).absolute;
    if (localPath.isEmpty || !await local.exists()) {
      throw StateError('本地上传文件不存在');
    }
    final RemoteFileClient client = await _connectRemoteFiles(profile);
    int transferred = 0;
    try {
      await client.upload(
        local.path,
        remotePath,
        overwrite: arguments['overwrite'] == true,
        cancellation: SftpCancellationToken(),
        onProgress: (int bytes, int total) => transferred = bytes,
      );
      return <String, Object?>{
        'profileId': profile.id,
        'localPath': local.path,
        'remotePath': remotePath,
        'bytes': transferred,
      };
    } finally {
      await client.close();
    }
  }

  Future<Map<String, Object?>> _downloadRemoteSftp(
    Map<String, Object?> arguments,
  ) async {
    final RemoteConnectionRecord profile = await _remoteProfile(
      arguments['profileId'],
    );
    final String remotePath = (arguments['remotePath'] ?? '').toString();
    final File local = File((arguments['localPath'] ?? '').toString()).absolute;
    final RemoteFileClient client = await _connectRemoteFiles(profile);
    int transferred = 0;
    try {
      final String normalized = remotePath.replaceAll('\\', '/');
      final int separator = normalized.lastIndexOf('/');
      final String parent = separator <= 0
          ? '/'
          : normalized.substring(0, separator);
      final String name = normalized.substring(separator + 1);
      final RemoteFileEntry? source = (await client.listDirectory(parent))
          .where(
            (RemoteFileEntry entry) => entry.name == name && !entry.isDirectory,
          )
          .firstOrNull;
      if (source == null) throw StateError('远端文件不存在或不是普通文件');
      await client.download(
        source.path,
        local.path,
        total: source.size,
        overwrite: arguments['overwrite'] == true,
        cancellation: SftpCancellationToken(),
        onProgress: (int bytes, int total) => transferred = bytes,
      );
      return <String, Object?>{
        'profileId': profile.id,
        'remotePath': source.path,
        'localPath': local.path,
        'bytes': transferred,
      };
    } finally {
      await client.close();
    }
  }

  Future<List<RemoteDatabaseProfile>> _loadRemoteDatabaseProfiles() async {
    final HarnessRemoteDatabaseProfileLoader? loader =
        _remoteDatabaseProfileLoader;
    if (loader != null) return loader();
    final List<String> encoded =
        (await AppSettingsStore().load()).remoteDatabaseProfiles;
    return encoded
        .map(RemoteDatabaseProfile.decode)
        .whereType<RemoteDatabaseProfile>()
        .toList(growable: false);
  }

  Future<RemoteDatabaseProfile> _remoteDatabaseProfile(Object? rawId) async {
    final String id = '$rawId'.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('远程数据库会话 ID 无效');
    }
    final RemoteDatabaseProfile? profile = (await _loadRemoteDatabaseProfiles())
        .where((RemoteDatabaseProfile value) => value.id == id)
        .firstOrNull;
    if (profile == null) throw StateError('没有找到远程数据库会话：$id');
    return profile;
  }

  Future<String> _remoteDatabasePassword(RemoteDatabaseProfile profile) async {
    final HarnessCredentialReader? reader = _credentialReader;
    final String? password = await (reader != null
        ? reader(profile.id)
        : RemoteDatabaseCredentials.read(profile.id));
    if (password == null) throw StateError('该数据库会话没有可复用的系统凭据');
    return password;
  }

  Future<Map<String, Object?>> _listRemoteDatabaseProfiles(
    Map<String, Object?> arguments,
  ) async {
    final List<RemoteDatabaseProfile> profiles =
        await _loadRemoteDatabaseProfiles();
    return <String, Object?>{
      'profiles': <Map<String, Object?>>[
        for (final RemoteDatabaseProfile profile in profiles)
          <String, Object?>{
            'id': profile.id,
            'name': profile.name,
            'engine': profile.engine.storageName,
            'host': profile.host,
            'port': profile.port,
            'database': profile.database,
            'username': profile.username,
            'tls': profile.useTls,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _inspectRemoteDatabase(
    Map<String, Object?> arguments,
  ) async {
    final RemoteDatabaseProfile profile = await _remoteDatabaseProfile(
      arguments['profileId'],
    );
    final String password = await _remoteDatabasePassword(profile);
    final HarnessRemoteDatabaseInspector? inspector = _remoteDatabaseInspector;
    final RemoteDatabaseSnapshot snapshot = inspector != null
        ? await inspector(profile, password)
        : await RemoteDatabaseService.inspect(profile, password);
    return <String, Object?>{
      'profileId': profile.id,
      'serverVersion': snapshot.serverVersion,
      'objects': <Map<String, Object?>>[
        for (final RemoteDatabaseObject object in snapshot.objects)
          object.toMap(),
      ],
      if (snapshot.initialPage != null)
        'initialPage': _pageJson(snapshot.initialPage!),
    };
  }

  Future<Map<String, Object?>> _queryRemoteDatabase(
    Map<String, Object?> arguments,
  ) async {
    final RemoteDatabaseProfile profile = await _remoteDatabaseProfile(
      arguments['profileId'],
    );
    final String password = await _remoteDatabasePassword(profile);
    final String sql = (arguments['sql'] ?? '').toString();
    final HarnessRemoteDatabaseQuerier? querier = _remoteDatabaseQuerier;
    final SqliteResultPage page = querier != null
        ? await querier(profile, password, sql)
        : await RemoteDatabaseService.query(profile, password, sql);
    return <String, Object?>{'profileId': profile.id, ..._pageJson(page)};
  }

  Future<Map<String, Object?>> _scanDuplicateFiles(
    Map<String, Object?> arguments,
  ) async {
    final String root = (arguments['root'] ?? '').toString().trim();
    final int minimumSize = _integer(
      arguments['minimumSize'],
      1024 * 1024,
    ).clamp(1, 1 << 40);
    final DuplicateScanResult result = await DuplicateFileBackgroundRunner.scan(
      root,
      recursive: arguments['recursive'] != false,
      minimumSize: minimumSize,
      cancellationToken: CleanupCancellationToken(),
      onProgress: (_) {},
    );
    return <String, Object?>{
      'root': Directory(root).absolute.path,
      'cancelled': result.cancelled,
      'visitedFiles': result.visitedFiles,
      'hashedFiles': result.hashedFiles,
      'unreadablePaths': result.unreadablePaths,
      'duplicateFiles': result.duplicateFiles,
      'reclaimableBytes': result.reclaimableBytes,
      'truncated': result.groups.length > 100,
      'groups': <Map<String, Object?>>[
        for (final DuplicateFileGroup group in result.groups.take(100))
          <String, Object?>{
            'sha256': group.sha256,
            'size': group.size,
            'reclaimableBytes': group.reclaimableBytes,
            'suggestedKeep': group.suggestedKeep.path,
            'files': group.files
                .take(50)
                .map((DuplicateFileEntry file) => file.path)
                .toList(growable: false),
          },
      ],
    };
  }

  Future<Map<String, Object?>> _hashFileInBackground(
    Map<String, Object?> arguments,
  ) async {
    final String algorithmName = (arguments['params'] ?? 'sha256')
        .toString()
        .trim()
        .toLowerCase();
    final FileHashAlgorithm algorithm = switch (algorithmName) {
      'md5' => FileHashAlgorithm.md5,
      'sha1' || 'sha-1' => FileHashAlgorithm.sha1,
      'sha256' || 'sha-256' || '' => FileHashAlgorithm.sha256,
      'sha512' || 'sha-512' => FileHashAlgorithm.sha512,
      _ => throw const FormatException('算法仅支持 md5/sha1/sha256/sha512'),
    };
    final FileHashResult result = await FileHashBackgroundRunner.calculate(
      (arguments['input'] ?? '').toString(),
      algorithm,
      cancellation: FileHashCancellation(),
      onProgress: (_, _) {},
    );
    if (!result.succeeded) {
      throw StateError(
        result.cancelled ? '文件哈希已取消' : (result.error ?? '文件哈希失败'),
      );
    }
    return <String, Object?>{
      'path': File(result.path).absolute.path,
      'algorithm': result.algorithm.name,
      'bytes': result.totalBytes,
      'digest': result.digest,
    };
  }

  Future<Map<String, Object?>> _analyzeSystemDrive(
    Map<String, Object?> arguments,
  ) async {
    final String root = (arguments['root'] ?? '').toString().trim();
    final SystemDriveAnalysis analysis =
        await SystemDriveAnalysisRunner.analyze(
          root,
          cancellationToken: CleanupCancellationToken(),
          onProgress: (_) {},
        );
    final SystemDriveInsights insights = SystemDriveInsights.from(analysis);
    Map<String, Object?> entry(SystemDriveUsageEntry value) =>
        <String, Object?>{
          'path': value.path,
          'name': value.name,
          'sizeBytes': value.sizeBytes,
          'kind': value.kind.name,
          'kindLabel': value.kind.label,
          'owner': value.ownerLabel,
          'assessment': value.needsReview ? 'review' : 'expected',
          'canDeleteAfterConfirmation': value.canDelete,
          'reason': value.reason,
          'measurementComplete': value.complete,
        };
    return <String, Object?>{
      'root': analysis.rootPath,
      'cancelled': analysis.cancelled,
      'totalBytes': analysis.totalBytes,
      'usedBytes': analysis.usedBytes,
      'freeBytes': analysis.freeBytes,
      'availableBytes': analysis.availableBytes,
      'logicalMeasuredBytes': analysis.logicalMeasuredBytes,
      'unaccountedBytes': analysis.unaccountedBytes,
      'logicalOvercountBytes': analysis.logicalOvercountBytes,
      'visitedEntries': analysis.visitedEntries,
      'unreadablePaths': analysis.unreadablePaths,
      'storagePressure': <String, Object?>{
        'level': insights.storagePressure.name,
        'label': insights.storagePressure.label,
        'summary': insights.storagePressureSummary,
      },
      'systemBaseline': insights.systemBaseline,
      'categoryTotals': <String, int>{
        for (final MapEntry<SystemDriveEntryKind, int> item
            in insights.categoryTotals.entries)
          item.key.name: item.value,
      },
      'priorities': insights.priorities
          .take(100)
          .map((SystemDriveEntryAssessment item) => item.toJson())
          .toList(growable: false),
      'softwareOwners': insights.softwareOwners
          .take(100)
          .map((SystemDriveEntryAssessment item) => item.toJson())
          .toList(growable: false),
      'entries': analysis.entries.take(500).map(entry).toList(growable: false),
      'breakdownEntries': analysis.breakdownEntries
          .take(500)
          .map(entry)
          .toList(growable: false),
      'truncated':
          analysis.entries.length > 500 ||
          analysis.breakdownEntries.length > 500,
    };
  }

  Future<Map<String, Object?>> _diffFiles(
    Map<String, Object?> arguments,
  ) async {
    final FileDiffResult result = await FileDiffService.compare(
      leftPath: (arguments['leftPath'] ?? '').toString(),
      rightPath: (arguments['rightPath'] ?? '').toString(),
      ignoreWhitespace: arguments['ignoreWhitespace'] == true,
      ignoreCase: arguments['ignoreCase'] == true,
    );
    final Map<String, Object?> data = result.toJson();
    final String unified = result.unifiedText;
    data['unifiedDiff'] = unified.length <= 200000
        ? unified
        : '${unified.substring(0, 200000)}\n…差异输出已截断';
    return data;
  }

  Future<Map<String, Object?>> _captureScreenAndOcr(
    Map<String, Object?> arguments,
  ) async {
    final HarnessScreenshotOcrRunner? runner = _screenshotOcrRunner;
    if (runner == null) throw StateError('当前界面没有连接截图 OCR 工作流');
    return runner();
  }

  Future<Map<String, Object?>> _calculate(
    Map<String, Object?> arguments,
  ) async {
    final ProgrammerCalculation result = ProgrammerCalculator.calculate(
      (arguments['expression'] ?? '').toString(),
      width: _integer(arguments['width'], 64),
      inputRadix: _integer(arguments['inputRadix'], 10),
    );
    return <String, Object?>{
      'decimal': result.decimal,
      'hexadecimal': result.hexadecimal,
      'octal': result.octal,
      'binary': result.binary,
      'width': result.width,
    };
  }

  static Map<String, Object?> _pageJson(SqliteResultPage page) =>
      <String, Object?>{
        'columns': page.columns,
        'rows': page.rows,
        'offset': page.offset,
        'hasMore': page.hasMore,
        'label': page.label,
      };

  static int _integer(Object? value, int fallback) =>
      value is int ? value : int.tryParse('$value') ?? fallback;
  static List<String> _stringList(Object? value) => value is List
      ? value.map((Object? item) => '$item').toList(growable: false)
      : const <String>[];

  static Object? _activityResult(String toolId, Map<String, Object?> result) {
    if (toolId != fileDiffId) return result;
    return <String, Object?>{
      'leftPath': result['leftPath'],
      'rightPath': result['rightPath'],
      'identical': result['identical'],
      'addedLines': result['addedLines'],
      'removedLines': result['removedLines'],
      'unchangedLines': result['unchangedLines'],
      'truncated': result['truncated'],
    };
  }

  static Map<String, Object?> _string(String description) => <String, Object?>{
    'type': 'string',
    'description': description,
  };
  static HarnessToolDefinition _definition({
    required String id,
    required String name,
    required String description,
    HarnessToolRisk risk = HarnessToolRisk.readOnly,
    required Map<String, Object?> properties,
    List<String> required = const <String>[],
  }) => HarnessToolDefinition(
    id: id,
    name: name,
    description: description,
    risk: risk,
    inputSchema: <String, Object?>{
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': false,
    },
    available: true,
  );

  static HarnessToolRisk _riskFor(String id) => switch (id) {
    'batch_rename' || 'duplicate_files' => HarnessToolRisk.writesData,
    'serial_port' ||
    'adb_workspace' ||
    'remote_workspace' => HarnessToolRisk.controlsDevice,
    _ => HarnessToolRisk.readOnly,
  };

  static String _targetSummary(String toolId, Map<String, Object?> arguments) {
    if (toolId == adbConnectId) {
      return AdbService.normalizeWirelessAddress(
        (arguments['address'] ?? '').toString(),
      );
    }
    if (toolId == adbCommandId) return (arguments['serial'] ?? '').toString();
    if (toolId == serialTransactId) return (arguments['port'] ?? '').toString();
    if (toolId == apiRequestId) return (arguments['url'] ?? '').toString();
    if (toolId == remoteOpenInteractiveId) {
      return (arguments['host'] ?? '').toString();
    }
    if (toolId == duplicateScanId || toolId == systemDriveAnalyzeId) {
      return (arguments['root'] ?? '').toString();
    }
    if (toolId == fileDiffId) {
      return '${arguments['leftPath'] ?? ''} ↔ '
          '${arguments['rightPath'] ?? ''}';
    }
    if (toolId == remoteSshExecId ||
        toolId == remoteSftpListId ||
        toolId == remoteSftpUploadId ||
        toolId == remoteSftpDownloadId) {
      final String profile = (arguments['profileId'] ?? '').toString();
      final String path = (arguments['remotePath'] ?? '').toString();
      return path.isEmpty ? profile : '$profile · $path';
    }
    if (toolId == remoteDatabaseInspectId || toolId == remoteDatabaseQueryId) {
      return (arguments['profileId'] ?? '').toString();
    }
    if (toolId == gitInspectId ||
        toolId == gitCompareRefsId ||
        toolId == gitCreateLocalBranchId) {
      return (arguments['path'] ?? '').toString();
    }
    return (arguments['input'] ?? toolId).toString();
  }
}
