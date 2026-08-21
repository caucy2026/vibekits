import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../app/app_settings.dart';
import '../../cleaner/domain/cleanup_task.dart';
import '../../cleaner/domain/installed_application_service.dart';
import '../../cleaner/domain/software_storage_analyzer.dart';
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
import 'github_proxy_service.dart';
import 'harness_tool_activity_store.dart';
import 'harness_work_status.dart';
import 'network_virtualization_service.dart';
import 'system_proxy_service.dart';
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
import 'windows_test_node_service.dart';
import 'windows_node_device_service.dart';
import 'windows_node_helper_protocol.dart';

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
    GithubProxyService? githubProxyService,
    WindowsTestNodeService? windowsTestNodeService,
    WindowsNodeDeviceService? windowsNodeDeviceService,
    String? runtimeToolRoot,
    Future<void> Function(int processId)? runtimeBindProcessTree,
    Future<void> Function(int processId)? runtimeReleaseProcessTree,
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
    githubProxyService ?? GithubProxyService(),
    windowsTestNodeService ?? WindowsTestNodeService(),
    windowsNodeDeviceService ?? WindowsNodeDeviceService(),
    runtimeToolRoot,
    runtimeBindProcessTree,
    runtimeReleaseProcessTree,
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
    this._githubProxyService,
    this._windowsTestNodeService,
    this._windowsNodeDeviceService,
    this._runtimeToolRoot,
    this._runtimeBindProcessTree,
    this._runtimeReleaseProcessTree,
  );

  static const String protocolVersion = 'vibekits.tools.v1';
  static const String adbListDevicesId = 'vibekits.adb.list_devices';
  static const String adbConnectId = 'vibekits.adb.connect';
  static const String adbCommandId = 'vibekits.adb.command';
  static const String adbShellId = 'vibekits.adb.shell';
  static const String adbLogcatId = 'vibekits.adb.logcat';
  static const String adbInstallApkId = 'vibekits.adb.install_apk';
  static const String adbPushFileId = 'vibekits.adb.push_file';
  static const String adbPullFileId = 'vibekits.adb.pull_file';
  static const String adbScreenshotId = 'vibekits.adb.screenshot';
  static const String serialListPortsId = 'vibekits.serial.list_ports';
  static const String serialTransactId = 'vibekits.serial.transact';
  static const String sqliteInspectId = 'vibekits.sqlite.inspect';
  static const String sqliteQueryId = 'vibekits.sqlite.query';
  static const String gitInspectId = 'vibekits.git.inspect';
  static const String gitCompareRefsId = 'vibekits.git.compare_refs';
  static const String gitCreateLocalBranchId =
      'vibekits.git.create_local_branch';
  static const String gitBackupPreviewId = 'vibekits.git.backup_preview';
  static const String gitBackupCommitId = 'vibekits.git.backup_commit';
  static const String gitBackupPushId = 'vibekits.git.backup_push';
  static const String gitVerifyRemoteRefId = 'vibekits.git.verify_remote_ref';
  static const String fileSearchId = 'vibekits.files.search';
  static const String apiRequestId = 'vibekits.http.request';
  static const String githubDiagnosticsId = 'vibekits.github.diagnose';
  static const String githubProxyCandidatesId =
      'vibekits.github.proxy_candidates';
  static const String githubProxyPlanId = 'vibekits.github.proxy_plan';
  static const String githubProxyApplyId = 'vibekits.github.proxy_apply';
  static const String githubProxyRollbackId = 'vibekits.github.proxy_rollback';
  static const String windowsNodeInspectId = 'vibekits.windows_node.inspect';
  static const String windowsNodeHelperStatusId =
      'vibekits.windows_node.helper_status';
  static const String windowsNodePlanId = 'vibekits.windows_node.plan';
  static const String windowsNodeApplyId = 'vibekits.windows_node.apply';
  static const String windowsNodeVerifyId = 'vibekits.windows_node.verify';
  static const String windowsNodeListDevicesId =
      'vibekits.windows_node.list_devices';
  static const String windowsNodeEnrollDeviceId =
      'vibekits.windows_node.enroll_device';
  static const String windowsNodeRevokeDeviceId =
      'vibekits.windows_node.revoke_device';
  static const String windowsNodeExportOnboardingId =
      'vibekits.windows_node.export_onboarding';
  static const String windowsNodeRollbackId = 'vibekits.windows_node.rollback';
  static const String windowsNodeEnsureClientIdentityId =
      'vibekits.windows_node.ensure_client_identity';
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
  static const String runtimeInspectId = 'vibekits.runtime.inspect';
  static const String runtimeStatusId = 'vibekits.runtime.status';
  static const String proxyStartId = 'vibekits.proxy.start';
  static const String proxyStopId = 'vibekits.proxy.stop';
  static const String proxySystemApplyId = 'vibekits.proxy.system_apply';
  static const String proxySystemRestoreId = 'vibekits.proxy.system_restore';
  static const String vmStartId = 'vibekits.vm.start';
  static const String vmStopId = 'vibekits.vm.stop';
  static const String vmCreateDiskId = 'vibekits.vm.create_disk';

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
  final GithubProxyService _githubProxyService;
  final WindowsTestNodeService _windowsTestNodeService;
  final WindowsNodeDeviceService _windowsNodeDeviceService;
  final String? _runtimeToolRoot;
  final Future<void> Function(int processId)? _runtimeBindProcessTree;
  final Future<void> Function(int processId)? _runtimeReleaseProcessTree;

  String? get _mihomoRuntimeExecutable => _runtimeToolRoot == null
      ? null
      : '${Directory(_runtimeToolRoot).absolute.path}${Platform.pathSeparator}'
            'mihomo${Platform.pathSeparator}${Platform.isWindows ? 'mihomo.exe' : 'mihomo'}';
  String? get _qemuRuntimeExecutable => _runtimeToolRoot == null
      ? null
      : '${Directory(_runtimeToolRoot).absolute.path}${Platform.pathSeparator}'
            'qemu${Platform.pathSeparator}${Platform.isWindows ? 'qemu-system-x86_64.exe' : 'qemu-system-x86_64'}';
  String? get _qemuImgRuntimeExecutable => _runtimeToolRoot == null
      ? null
      : '${Directory(_runtimeToolRoot).absolute.path}${Platform.pathSeparator}'
            'qemu${Platform.pathSeparator}${Platform.isWindows ? 'qemu-img.exe' : 'qemu-img'}';

  late final Map<String, HarnessToolDefinition>
  _definitions = <String, HarnessToolDefinition>{
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
    adbShellId: _definition(
      id: adbShellId,
      name: '执行 Android Shell',
      description: '对选定设备执行参数化 Android shell 命令；不经过本机 cmd 或 sh。',
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
    adbLogcatId: _definition(
      id: adbLogcatId,
      name: '读取 Android Logcat',
      description: '读取选定设备最近的有界 Logcat；可按 tag 过滤，不启动无限流。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'lines': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 2000,
        },
        'tag': _string('可选 Android 日志 tag'),
      },
      required: <String>['serial'],
    ),
    adbInstallApkId: _definition(
      id: adbInstallApkId,
      name: '安装 APK',
      description: '把明确的本地 APK 安装到选定设备；覆盖安装必须显式指定。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'apkPath': _string('本地 APK 绝对路径'),
        'replace': <String, Object?>{'type': 'boolean'},
      },
      required: <String>['serial', 'apkPath'],
    ),
    adbPushFileId: _definition(
      id: adbPushFileId,
      name: '推送文件到 Android',
      description: '把一个真实本地文件推送到选定设备的绝对路径。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'localPath': _string('本地文件绝对路径'),
        'remotePath': _string('设备端绝对路径'),
      },
      required: <String>['serial', 'localPath', 'remotePath'],
    ),
    adbPullFileId: _definition(
      id: adbPullFileId,
      name: '从 Android 拉取文件',
      description: '从选定设备拉取一个文件；覆盖本地文件必须显式指定。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'remotePath': _string('设备端绝对路径'),
        'localPath': _string('本地目标绝对路径'),
        'overwrite': <String, Object?>{'type': 'boolean'},
      },
      required: <String>['serial', 'remotePath', 'localPath'],
    ),
    adbScreenshotId: _definition(
      id: adbScreenshotId,
      name: '保存 Android 截图',
      description: '从选定设备实时截图并保存为本地 PNG，不读取剪贴板。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'localPath': _string('本地 PNG 绝对路径'),
        'overwrite': <String, Object?>{'type': 'boolean'},
      },
      required: <String>['serial', 'localPath'],
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
    gitBackupPreviewId: _definition(
      id: gitBackupPreviewId,
      name: '预览 GitHub 备份',
      description: '只读检查已打开仓库的变更、已有 remote、大文件、构建产物和秘密阻断项，生成短期备份计划。',
      properties: <String, Object?>{
        'path': _string('已打开的本地 Git 仓库或其子目录'),
        'remoteId': _string('仓库中已经存在的 remote 名称，不接受 URL'),
        'deviceLabel': _string('可选设备标签，用于 backup/ 分支'),
      },
      required: <String>['path', 'remoteId'],
    ),
    gitBackupCommitId: _definition(
      id: gitBackupCommitId,
      name: '提交 Git 备份',
      description: '只暂存 preview 允许且用户确认的文件并创建本地提交；不会自动 push。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'previewId': _string('短期备份 preview ID'),
        'includedPaths': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
          'minItems': 1,
          'maxItems': 2000,
        },
        'message': _string('1～200 字符提交说明'),
      },
      required: <String>['previewId', 'includedPaths', 'message'],
    ),
    gitBackupPushId: _definition(
      id: gitBackupPushId,
      name: '推送 Git 备份',
      description:
          '独立审批后把 preview 生成的 commit 推送到 backup/ 分支，并读取远端 ref 核对 SHA；禁止 force。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'previewId': _string('已经完成本地 commit 的 preview ID'),
        'commitSha': _string('该 preview 返回的 commit SHA'),
      },
      required: <String>['previewId', 'commitSha'],
    ),
    gitVerifyRemoteRefId: _definition(
      id: gitVerifyRemoteRefId,
      name: '核验远端备份 SHA',
      description: '只读查询已有 remote 的 backup/ 分支并返回远端 commit SHA。',
      properties: <String, Object?>{
        'path': _string('本地仓库'),
        'remoteId': _string('已有 remote 名称'),
        'targetBranch': _string('backup/ 开头的目标分支'),
      },
      required: <String>['path', 'remoteId', 'targetBranch'],
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
    githubProxyCandidatesId: _definition(
      id: githubProxyCandidatesId,
      name: '发现 GitHub 代理候选',
      description: '只读发现 Mihomo/Clash 的真实回环监听端口，不读取订阅、节点或配置正文。',
      properties: const <String, Object?>{},
    ),
    githubProxyPlanId: _definition(
      id: githubProxyPlanId,
      name: '预览 GitHub 专用代理',
      description: '读取现有 host-scoped Git 配置，生成带旧值、摘要、到期时间和回滚动作的短期计划。',
      properties: <String, Object?>{'candidateId': _string('代理候选 ID')},
      required: <String>['candidateId'],
    ),
    githubProxyApplyId: _definition(
      id: githubProxyApplyId,
      name: '应用 GitHub 专用代理',
      description: '只修改 http.https://github.com.proxy；随后真实 ls-remote，失败自动恢复旧值。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'planId': _string('代理计划 ID'),
        'digest': _string('代理计划摘要'),
      },
      required: <String>['planId', 'digest'],
    ),
    githubProxyRollbackId: _definition(
      id: githubProxyRollbackId,
      name: '恢复 GitHub 代理旧值',
      description: '按计划保存的原值精确恢复 GitHub host-scoped Git 代理。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'planId': _string('曾应用的代理计划 ID'),
        'digest': _string('代理计划摘要'),
      },
      required: <String>['planId', 'digest'],
    ),
    windowsNodeInspectId: _definition(
      id: windowsNodeInspectId,
      name: '体检 Windows 测试节点',
      description: '普通权限只读检查 Windows、硬件、D 盘、网络、OpenSSH、防火墙、运行时、电源、目录、账户和公钥。',
      properties: <String, Object?>{'rootPath': _string(r'固定为 D:\KEMI-Test')},
    ),
    windowsNodeHelperStatusId: _definition(
      id: windowsNodeHelperStatusId,
      name: '检查 Windows 节点 Helper',
      description: '读取当前 Release 中 helper 实体和 manifest 状态；缺失或不匹配时明确关闭系统写入工具。',
      properties: const <String, Object?>{},
    ),
    windowsNodePlanId: _definition(
      id: windowsNodePlanId,
      name: '生成 Windows 节点变更计划',
      description: '根据短期体检 ID 生成幂等动作、风险、依赖、取消边界、回滚和摘要；不执行系统修改。',
      properties: <String, Object?>{
        'inspectionId': _string('windows_node.inspect 返回的短期 ID'),
      },
      required: <String>['inspectionId'],
    ),
    windowsNodeApplyId: _unavailableDefinition(
      id: windowsNodeApplyId,
      name: '应用 Windows 节点计划',
      description: '等待签名窄权限 UAC helper 随 Release 交付；不回退为任意管理员 PowerShell。',
      risk: HarnessToolRisk.controlsDevice,
    ),
    windowsNodeVerifyId: _unavailableDefinition(
      id: windowsNodeVerifyId,
      name: '跨设备验证 Windows 节点',
      description: '必须从另一台真实设备执行 SSH/SFTP、SHA-256、取消和断网验收，本机 localhost 不替代。',
    ),
    windowsNodeListDevicesId: _definition(
      id: windowsNodeListDevicesId,
      name: '列出节点设备',
      description: '读取独立 Ed25519 设备登记、状态、指纹和最近连接时间；不返回私钥。',
      properties: const <String, Object?>{},
    ),
    windowsNodeEnrollDeviceId: _unavailableDefinition(
      id: windowsNodeEnrollDeviceId,
      name: '登记节点设备公钥',
      description: '等待签名 helper 提供原子 authorized_keys 与 ACL 操作；不接收私钥。',
      risk: HarnessToolRisk.writesData,
    ),
    windowsNodeRevokeDeviceId: _unavailableDefinition(
      id: windowsNodeRevokeDeviceId,
      name: '撤销节点设备',
      description: '等待单设备撤销和其他设备不受影响的真实验收。',
      risk: HarnessToolRisk.writesData,
    ),
    windowsNodeExportOnboardingId: _definition(
      id: windowsNodeExportOnboardingId,
      name: '导出节点 onboarding',
      description: '生成不含秘密的主机、端口、用户、固定 host key、私网范围和 SSH config。',
      properties: <String, Object?>{
        'host': _string('节点局域网 IP 或主机名'),
        'port': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 65535,
        },
        'hostKeyFingerprint': _string('SHA256 host key 指纹'),
        'allowedCidr': _string('Private IPv4 /24 或更窄范围'),
      },
      required: <String>['host', 'hostKeyFingerprint', 'allowedCidr'],
    ),
    windowsNodeRollbackId: _unavailableDefinition(
      id: windowsNodeRollbackId,
      name: '回滚 Windows 节点变更',
      description: '等待签名 helper 和修改前状态审计闭环；禁止用删除账户或卸载组件冒充回滚。',
      risk: HarnessToolRisk.controlsDevice,
    ),
    windowsNodeEnsureClientIdentityId: _unavailableDefinition(
      id: windowsNodeEnsureClientIdentityId,
      name: '确保客户端独立身份',
      description: '等待 macOS Keychain/受保护文件实现；只返回公钥和不透明凭据引用，永不返回私钥。',
      risk: HarnessToolRisk.writesData,
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
      description: '在 Vibekits 中打开指定主机的 SSH 登录界面；用户认证一次后自动复用该连接展示 SFTP 双栏文件。',
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
    runtimeInspectId: _definition(
      id: runtimeInspectId,
      name: '检查代理与虚拟机运行时',
      description: '只读检查 Vibekits 发布包中的 Mihomo 与 QEMU 版本和绝对路径。',
      properties: const <String, Object?>{},
    ),
    runtimeStatusId: _definition(
      id: runtimeStatusId,
      name: '读取代理与虚拟机状态',
      description: '只读返回 Mihomo/QEMU 运行状态、进程号和有界日志。',
      properties: const <String, Object?>{},
    ),
    proxyStartId: _definition(
      id: proxyStartId,
      name: '启动 Clash Verge 内核',
      description: '使用用户明确选择的 YAML 配置启动内置 Mihomo；不自动修改系统代理或 TUN。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'configPath': _string('Clash YAML 配置绝对路径'),
        'dataDirectory': _string('Mihomo 数据目录'),
        'systemProxyPort': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 65535,
          'description': '可选；提供时启动成功后同步启用 Windows 系统代理',
        },
      },
      required: <String>['configPath', 'dataDirectory'],
    ),
    proxyStopId: _definition(
      id: proxyStopId,
      name: '停止 Clash Verge 内核',
      description: '停止由 Vibekits 启动的 Mihomo 子进程。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'dataDirectory': _string('可选；提供时先恢复保存在该目录的原系统代理'),
      },
    ),
    proxySystemApplyId: _definition(
      id: proxySystemApplyId,
      name: '启用 Windows 系统代理',
      description: '保存当前用户代理后，把 Windows 系统代理切换到本机 Mihomo 端口；可由恢复工具还原。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'port': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 65535,
        },
        'dataDirectory': _string('保存原代理设置的绝对数据目录'),
      },
      required: <String>['port', 'dataDirectory'],
    ),
    proxySystemRestoreId: _definition(
      id: proxySystemRestoreId,
      name: '恢复 Windows 原系统代理',
      description: '从 Vibekits 备份恢复启用代理前的 Windows 用户代理设置。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{'dataDirectory': _string('保存原代理设置的绝对数据目录')},
      required: <String>['dataDirectory'],
    ),
    vmStartId: _definition(
      id: vmStartId,
      name: '启动轻量虚拟机',
      description: '使用内置 QEMU 启动用户明确指定的虚拟磁盘或 ISO。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'diskPath': _string('可选虚拟磁盘绝对路径'),
        'isoPath': _string('可选 ISO 绝对路径'),
        'memoryMiB': <String, Object?>{
          'type': 'integer',
          'minimum': 256,
          'maximum': 32768,
        },
        'cpuCount': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 16,
        },
        'headless': <String, Object?>{
          'type': 'boolean',
          'description': '无窗口后台验收或服务器任务使用；默认 false',
        },
      },
    ),
    vmStopId: _definition(
      id: vmStopId,
      name: '停止轻量虚拟机',
      description: '停止由 Vibekits 启动的 QEMU 子进程。',
      risk: HarnessToolRisk.controlsDevice,
      properties: const <String, Object?>{},
    ),
    vmCreateDiskId: _definition(
      id: vmCreateDiskId,
      name: '创建 QEMU 虚拟磁盘',
      description: '使用内置 qemu-img 创建新的 qcow2 稀疏磁盘，不覆盖已有文件。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'path': _string('新 qcow2 磁盘绝对路径'),
        'sizeGiB': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 2048,
        },
      },
      required: <String>['path', 'sizeGiB'],
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
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.waitingApproval,
        message: '等待批准 ${definition.name}',
        toolId: toolId,
        toolName: definition.name,
        target: target,
      );
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
        HarnessWorkStatusHub.publish(
          phase: HarnessWorkPhase.ready,
          message: '已拒绝 ${definition.name}',
          toolId: toolId,
          toolName: definition.name,
          target: target,
        );
        return const HarnessToolCallResult.cancelled();
      }
    }
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.runningTool,
      message: '正在执行 ${definition.name}',
      toolId: toolId,
      toolName: definition.name,
      target: target,
    );
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
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.ready,
        message: '${definition.name} 执行成功',
        toolId: toolId,
        toolName: definition.name,
        target: target,
      );
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
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.failed,
        message: '${definition.name} 执行失败',
        toolId: toolId,
        toolName: definition.name,
        target: target,
      );
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
      description: <String>[
        spec.description,
        '适合：${spec.aiUseWhen ?? '用户明确需要“${spec.name}”结果时。'}',
        '不适合：${spec.aiAvoidWhen ?? '输入或目标不符合说明时；不要猜测参数。'}',
        if (spec.aiExamples.isNotEmpty) '示例：${spec.aiExamples.join('；')}',
        '本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。',
      ].join(' '),
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
    if (toolId == adbShellId) return _runAdbShell;
    if (toolId == adbLogcatId) return _readAdbLogcat;
    if (toolId == adbInstallApkId) return _installAdbApk;
    if (toolId == adbPushFileId) return _pushAdbFile;
    if (toolId == adbPullFileId) return _pullAdbFile;
    if (toolId == adbScreenshotId) return _captureAdbScreenshot;
    if (toolId == serialListPortsId) return _listSerialPorts;
    if (toolId == serialTransactId) return _serialTransact;
    if (toolId == sqliteInspectId) return _inspectSqlite;
    if (toolId == sqliteQueryId) return _querySqlite;
    if (toolId == gitInspectId) return _inspectGit;
    if (toolId == gitCompareRefsId) return _compareGitRefs;
    if (toolId == gitCreateLocalBranchId) return _createGitLocalBranch;
    if (toolId == gitBackupPreviewId) return _previewGitBackup;
    if (toolId == gitBackupCommitId) return _commitGitBackup;
    if (toolId == gitBackupPushId) return _pushGitBackup;
    if (toolId == gitVerifyRemoteRefId) return _verifyGitRemoteRef;
    if (toolId == fileSearchId) return _searchFiles;
    if (toolId == apiRequestId) return _requestHttp;
    if (toolId == githubDiagnosticsId) return _diagnoseGithub;
    if (toolId == githubProxyCandidatesId) return _githubProxyCandidates;
    if (toolId == githubProxyPlanId) return _githubProxyPlan;
    if (toolId == githubProxyApplyId) return _githubProxyApply;
    if (toolId == githubProxyRollbackId) return _githubProxyRollback;
    if (toolId == windowsNodeInspectId) return _inspectWindowsNode;
    if (toolId == windowsNodeHelperStatusId) return _windowsNodeHelperStatus;
    if (toolId == windowsNodePlanId) return _planWindowsNode;
    if (toolId == windowsNodeListDevicesId) return _listWindowsNodeDevices;
    if (toolId == windowsNodeExportOnboardingId) {
      return _exportWindowsNodeOnboarding;
    }
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
    if (toolId == runtimeInspectId) return _inspectBundledRuntimes;
    if (toolId == runtimeStatusId) return _runtimeStatus;
    if (toolId == proxyStartId) return _startProxy;
    if (toolId == proxyStopId) return _stopProxy;
    if (toolId == proxySystemApplyId) return _applySystemProxy;
    if (toolId == proxySystemRestoreId) return _restoreSystemProxy;
    if (toolId == vmStartId) return _startVm;
    if (toolId == vmStopId) return _stopVm;
    if (toolId == vmCreateDiskId) return _createVmDisk;
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

  Future<Map<String, Object?>> _inspectBundledRuntimes(
    Map<String, Object?> arguments,
  ) async {
    final List<BundledRuntimeStatus> runtimes = await Future.wait(
      <Future<BundledRuntimeStatus>>[
        NetworkVirtualizationService.inspectMihomo(
          executable: _mihomoRuntimeExecutable,
        ),
        NetworkVirtualizationService.inspectQemu(
          executable: _qemuRuntimeExecutable,
        ),
      ],
    );
    return <String, Object?>{
      'runtimes': runtimes
          .map((BundledRuntimeStatus value) => value.toJson())
          .toList(),
    };
  }

  Future<Map<String, Object?>> _runtimeStatus(
    Map<String, Object?> arguments,
  ) async => NetworkVirtualizationService.status();

  Future<Map<String, Object?>> _startProxy(
    Map<String, Object?> arguments,
  ) async {
    final String dataDirectory = (arguments['dataDirectory'] ?? '').toString();
    final ManagedToolProcess process =
        await NetworkVirtualizationService.startMihomo(
          configPath: (arguments['configPath'] ?? '').toString(),
          dataDirectory: dataDirectory,
          executable: _mihomoRuntimeExecutable,
          bindProcessTree: _runtimeBindProcessTree,
          releaseProcessTree: _runtimeReleaseProcessTree,
        );
    SystemProxySnapshot? systemProxy;
    final int? port = arguments['systemProxyPort'] == null
        ? null
        : _integer(arguments['systemProxyPort'], 7890);
    try {
      if (port != null) {
        systemProxy = await SystemProxyService().applyLocal(
          port: port,
          dataDirectory: dataDirectory,
        );
      }
    } on Object {
      await NetworkVirtualizationService.stopMihomo();
      rethrow;
    }
    return <String, Object?>{
      'started': true,
      'pid': process.process.pid,
      if (systemProxy != null) 'systemProxy': systemProxy.toJson(),
    };
  }

  Future<Map<String, Object?>> _stopProxy(
    Map<String, Object?> arguments,
  ) async {
    SystemProxySnapshot? systemProxy;
    final String dataDirectory = (arguments['dataDirectory'] ?? '').toString();
    if (dataDirectory.trim().isNotEmpty) {
      systemProxy = await SystemProxyService().restore(
        dataDirectory: dataDirectory,
      );
    }
    await NetworkVirtualizationService.stopMihomo();
    return <String, Object?>{
      'stopped': true,
      if (systemProxy != null) 'systemProxy': systemProxy.toJson(),
    };
  }

  Future<Map<String, Object?>> _applySystemProxy(
    Map<String, Object?> arguments,
  ) async {
    final SystemProxySnapshot snapshot = await SystemProxyService().applyLocal(
      port: _integer(arguments['port'], 7890),
      dataDirectory: (arguments['dataDirectory'] ?? '').toString(),
    );
    return snapshot.toJson();
  }

  Future<Map<String, Object?>> _restoreSystemProxy(
    Map<String, Object?> arguments,
  ) async {
    final SystemProxySnapshot snapshot = await SystemProxyService().restore(
      dataDirectory: (arguments['dataDirectory'] ?? '').toString(),
    );
    return snapshot.toJson();
  }

  Future<Map<String, Object?>> _startVm(Map<String, Object?> arguments) async {
    final ManagedToolProcess process =
        await NetworkVirtualizationService.startQemu(
          diskPath: (arguments['diskPath'] ?? '').toString(),
          isoPath: (arguments['isoPath'] ?? '').toString(),
          memoryMiB: _integer(arguments['memoryMiB'], 2048),
          cpuCount: _integer(arguments['cpuCount'], 2),
          headless: arguments['headless'] == true,
          executable: _qemuRuntimeExecutable,
          bindProcessTree: _runtimeBindProcessTree,
          releaseProcessTree: _runtimeReleaseProcessTree,
        );
    return <String, Object?>{'started': true, 'pid': process.process.pid};
  }

  Future<Map<String, Object?>> _stopVm(Map<String, Object?> arguments) async {
    await NetworkVirtualizationService.stopQemu();
    return const <String, Object?>{'stopped': true};
  }

  Future<Map<String, Object?>> _createVmDisk(Map<String, Object?> arguments) =>
      NetworkVirtualizationService.createQemuDisk(
        path: (arguments['path'] ?? '').toString(),
        sizeGiB: _integer(arguments['sizeGiB'], 32),
        executable: _qemuImgRuntimeExecutable,
      );

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

  Future<Map<String, Object?>> _runAdbShell(
    Map<String, Object?> arguments,
  ) async {
    final List<String> values = _stringList(arguments['arguments']);
    if (values.isEmpty) throw const FormatException('缺少 Android shell 参数');
    return _executeSemanticAdb(arguments, <String>['shell', ...values]);
  }

  Future<Map<String, Object?>> _readAdbLogcat(
    Map<String, Object?> arguments,
  ) async {
    final int lines = _integer(arguments['lines'], 500).clamp(1, 2000);
    final String tag = (arguments['tag'] ?? '').toString().trim();
    if (tag.contains(RegExp(r'[\r\n\s:*]'))) {
      throw const FormatException('Logcat tag 不能包含空白、冒号或星号');
    }
    return _executeSemanticAdb(arguments, <String>[
      'logcat',
      '-d',
      '-t',
      '$lines',
      if (tag.isNotEmpty) ...<String>['$tag:D', '*:S'],
    ]);
  }

  Future<Map<String, Object?>> _installAdbApk(
    Map<String, Object?> arguments,
  ) async {
    final String apkPath = _absoluteLocalFile(
      arguments['apkPath'],
      extension: '.apk',
    );
    return _executeSemanticAdb(arguments, <String>[
      'install',
      if (arguments['replace'] == true) '-r',
      apkPath,
    ]);
  }

  Future<Map<String, Object?>> _pushAdbFile(
    Map<String, Object?> arguments,
  ) async {
    final String localPath = _absoluteLocalFile(arguments['localPath']);
    final String remotePath = _androidAbsolutePath(arguments['remotePath']);
    return _executeSemanticAdb(arguments, <String>[
      'push',
      localPath,
      remotePath,
    ]);
  }

  Future<Map<String, Object?>> _pullAdbFile(
    Map<String, Object?> arguments,
  ) async {
    final String remotePath = _androidAbsolutePath(arguments['remotePath']);
    final String localPath = _absoluteOutputPath(
      arguments['localPath'],
      overwrite: arguments['overwrite'] == true,
    );
    final Map<String, Object?> result = await _executeSemanticAdb(
      arguments,
      <String>['pull', remotePath, localPath],
    );
    if (_adbRunner == null) {
      final File output = File(localPath);
      if (!await output.exists()) throw StateError('ADB 未生成本地文件');
      result['bytes'] = await output.length();
    }
    result['localPath'] = localPath;
    result['remotePath'] = remotePath;
    return result;
  }

  Future<Map<String, Object?>> _captureAdbScreenshot(
    Map<String, Object?> arguments,
  ) async {
    final String localPath = _absoluteOutputPath(
      arguments['localPath'],
      overwrite: arguments['overwrite'] == true,
      extension: '.png',
    );
    final String remotePath =
        '/data/local/tmp/vibekits-${DateTime.now().microsecondsSinceEpoch}.png';
    await _executeSemanticAdb(arguments, <String>[
      'shell',
      'screencap',
      '-p',
      remotePath,
    ]);
    try {
      await _executeSemanticAdb(arguments, <String>[
        'pull',
        remotePath,
        localPath,
      ]);
    } finally {
      try {
        await _executeSemanticAdb(arguments, <String>[
          'shell',
          'rm',
          '-f',
          remotePath,
        ]);
      } on Object {
        // The local screenshot result is still useful if remote cleanup fails.
      }
    }
    int? bytes;
    if (_adbRunner == null) {
      final File output = File(localPath);
      if (!await output.exists()) throw StateError('ADB 截图未保存到本地');
      bytes = await output.length();
      if (bytes == 0) throw StateError('ADB 截图为空文件');
    }
    return <String, Object?>{
      'localPath': localPath,
      'bytes': bytes,
      'source': 'adb-screencap',
    };
  }

  Future<Map<String, Object?>> _executeSemanticAdb(
    Map<String, Object?> arguments,
    List<String> command,
  ) async {
    final String serial = (arguments['serial'] ?? '').toString().trim();
    if (serial.isEmpty || serial.contains(RegExp(r'[\r\n\s]'))) {
      throw const FormatException('缺少或无效的 ADB 设备序列号');
    }
    final String executable =
        _adbExecutable ?? AdbService.bundledExecutablePath();
    final List<String> adbArguments = <String>['-s', serial, ...command];
    final AdbCommandResult result = _adbRunner == null
        ? await AdbService.runCommand(
            executable,
            adbArguments,
            timeout: switch (command.first) {
              'install' => const Duration(minutes: 5),
              'push' || 'pull' => const Duration(minutes: 2),
              _ => const Duration(seconds: 30),
            },
          )
        : await _adbRunner(executable, adbArguments);
    if (result.exitCode != 0) {
      throw StateError(
        result.stderr.trim().isEmpty
            ? 'ADB 操作失败（exit ${result.exitCode}）'
            : result.stderr.trim(),
      );
    }
    return <String, Object?>{
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
      'arguments': command,
    };
  }

  static String _absoluteLocalFile(Object? value, {String? extension}) {
    final String raw = (value ?? '').toString().trim();
    final File file = File(raw);
    if (raw.isEmpty || !file.isAbsolute || !file.existsSync()) {
      throw const FormatException('本地输入文件不存在');
    }
    if (extension != null && !file.path.toLowerCase().endsWith(extension)) {
      throw FormatException('文件必须是 $extension');
    }
    return file.path;
  }

  static String _absoluteOutputPath(
    Object? value, {
    required bool overwrite,
    String? extension,
  }) {
    final String raw = (value ?? '').toString().trim();
    final File file = File(raw);
    if (raw.isEmpty || !file.isAbsolute) {
      throw const FormatException('本地输出必须是绝对路径');
    }
    if (extension != null && !file.path.toLowerCase().endsWith(extension)) {
      throw FormatException('输出文件必须是 $extension');
    }
    if (file.existsSync() && !overwrite) {
      throw StateError('本地目标已存在；如需覆盖请明确设置 overwrite=true');
    }
    final Directory parent = file.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    return file.path;
  }

  static String _androidAbsolutePath(Object? value) {
    final String path = (value ?? '').toString().trim();
    if (!path.startsWith('/') || path.contains(RegExp(r'[\r\n\x00]'))) {
      throw const FormatException('设备端路径必须是 Android 绝对路径');
    }
    return path;
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

  Future<Map<String, Object?>> _previewGitBackup(
    Map<String, Object?> arguments,
  ) async => (await GitRepositoryService.previewBackup(
    (arguments['path'] ?? '').toString(),
    remoteId: (arguments['remoteId'] ?? '').toString(),
    deviceLabel: (arguments['deviceLabel'] ?? '').toString().trim().isEmpty
        ? null
        : (arguments['deviceLabel'] ?? '').toString(),
  )).toJson();

  Future<Map<String, Object?>> _commitGitBackup(
    Map<String, Object?> arguments,
  ) async => (await GitRepositoryService.commitBackup(
    previewId: (arguments['previewId'] ?? '').toString(),
    includedPaths: _stringList(arguments['includedPaths']),
    message: (arguments['message'] ?? '').toString(),
  )).toJson();

  Future<Map<String, Object?>> _pushGitBackup(
    Map<String, Object?> arguments,
  ) async => (await GitRepositoryService.pushBackup(
    previewId: (arguments['previewId'] ?? '').toString(),
    commitSha: (arguments['commitSha'] ?? '').toString(),
  )).toJson();

  Future<Map<String, Object?>> _verifyGitRemoteRef(
    Map<String, Object?> arguments,
  ) async {
    final String sha = await GitRepositoryService.verifyRemoteRef(
      (arguments['path'] ?? '').toString(),
      remoteId: (arguments['remoteId'] ?? '').toString(),
      targetBranch: (arguments['targetBranch'] ?? '').toString(),
    );
    return <String, Object?>{
      'remoteId': (arguments['remoteId'] ?? '').toString(),
      'targetBranch': (arguments['targetBranch'] ?? '').toString(),
      'remoteCommitSha': sha,
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

  Future<Map<String, Object?>> _githubProxyCandidates(
    Map<String, Object?> arguments,
  ) async => <String, Object?>{
    'candidates': (await _githubProxyService.discoverCandidates())
        .map((GithubProxyCandidate item) => item.toJson())
        .toList(growable: false),
    'scope': '仅 GitHub Git',
  };

  Future<Map<String, Object?>> _githubProxyPlan(
    Map<String, Object?> arguments,
  ) async => (await _githubProxyService.createPlan(
    (arguments['candidateId'] ?? '').toString(),
  )).toJson();

  Future<Map<String, Object?>> _githubProxyApply(
    Map<String, Object?> arguments,
  ) async => (await _githubProxyService.apply(
    (arguments['planId'] ?? '').toString(),
    digest: (arguments['digest'] ?? '').toString(),
  )).toJson();

  Future<Map<String, Object?>> _githubProxyRollback(
    Map<String, Object?> arguments,
  ) async => (await _githubProxyService.rollback(
    (arguments['planId'] ?? '').toString(),
    digest: (arguments['digest'] ?? '').toString(),
  )).toJson();

  Future<Map<String, Object?>> _inspectWindowsNode(
    Map<String, Object?> arguments,
  ) async => (await _windowsTestNodeService.inspect(
    rootPath: (arguments['rootPath'] ?? WindowsTestNodeService.requiredRoot)
        .toString(),
  )).toJson();

  Future<Map<String, Object?>> _windowsNodeHelperStatus(
    Map<String, Object?> arguments,
  ) async {
    final String executableDirectory = File(Platform.resolvedExecutable)
        .parent
        .path;
    final File helper = File(
      '$executableDirectory${Platform.pathSeparator}tools'
      '${Platform.pathSeparator}windows-node${Platform.pathSeparator}vibekits-node-helper.exe',
    );
    final bool exists = await helper.exists();
    return <String, Object?>{
      'available': false,
      'absolutePath': helper.path,
      'signatureValid': false,
      'publisher': null,
      'sha256': null,
      'fileVersion': null,
      'protocolVersion': WindowsNodeHelperRequest.currentProtocolVersion,
      'manifestMatch': false,
      'executableActions': const <String>[],
      'unavailableReason': exists
          ? 'helper 存在，但生产 Authenticode/manifest 适配器尚未完成，拒绝执行'
          : '当前 Release 未包含签名 Windows 节点 helper',
    };
  }

  Future<Map<String, Object?>> _planWindowsNode(
    Map<String, Object?> arguments,
  ) async => _windowsTestNodeService
      .plan((arguments['inspectionId'] ?? '').toString())
      .toJson();

  Future<Map<String, Object?>> _listWindowsNodeDevices(
    Map<String, Object?> arguments,
  ) async {
    final List<WindowsNodeDevice> devices = await _windowsNodeDeviceService
        .list();
    return <String, Object?>{
      'devices': devices
          .map((WindowsNodeDevice item) => item.toJson(includePublicKey: false))
          .toList(growable: false),
      'active': devices
          .where(
            (WindowsNodeDevice item) =>
                item.status == WindowsNodeDeviceStatus.active,
          )
          .length,
    };
  }

  Future<Map<String, Object?>> _exportWindowsNodeOnboarding(
    Map<String, Object?> arguments,
  ) async => _windowsNodeDeviceService
      .onboarding(
        host: (arguments['host'] ?? '').toString(),
        port: _integer(arguments['port'], 22),
        hostKeyFingerprint: (arguments['hostKeyFingerprint'] ?? '').toString(),
        allowedCidr: (arguments['allowedCidr'] ?? '').toString(),
      )
      .toJson();

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
    final List<InstalledApplication> installed =
        await InstalledApplicationService.load();
    final List<SoftwareStorageSummary> software =
        SoftwareStorageAnalyzer.summarize(analysis, installed);
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
      'softwareStorage': software
          .take(300)
          .map(
            (SoftwareStorageSummary item) => <String, Object?>{
              'name': item.name,
              'publisher': item.application?.publisher ?? '',
              'version': item.application?.version ?? '',
              'installBytes': item.installBytes,
              'dataBytes': item.dataBytes,
              'cacheBytes': item.cacheBytes,
              'totalBytes': item.totalBytes,
              'assessment': item.level.name,
              'assessmentLabel': item.level.label,
              'reason': item.assessment,
              'canCleanCache': item.canCleanCache,
              'canUninstall': item.canUninstall,
              'cachePaths': item.cacheEntries
                  .where((SystemDriveUsageEntry entry) => entry.canDelete)
                  .map((SystemDriveUsageEntry entry) => entry.path)
                  .toList(growable: false),
            },
          )
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

  static HarnessToolDefinition _unavailableDefinition({
    required String id,
    required String name,
    required String description,
    HarnessToolRisk risk = HarnessToolRisk.readOnly,
  }) => HarnessToolDefinition(
    id: id,
    name: name,
    description: description,
    risk: risk,
    inputSchema: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
    available: false,
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
    if (<String>{
      adbCommandId,
      adbShellId,
      adbLogcatId,
      adbInstallApkId,
      adbPushFileId,
      adbPullFileId,
      adbScreenshotId,
    }.contains(toolId)) {
      return (arguments['serial'] ?? '').toString();
    }
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
        toolId == gitCreateLocalBranchId ||
        toolId == gitBackupPreviewId ||
        toolId == gitVerifyRemoteRefId) {
      return (arguments['path'] ?? '').toString();
    }
    if (toolId == gitBackupCommitId || toolId == gitBackupPushId) {
      return (arguments['previewId'] ?? '').toString();
    }
    if (toolId == githubProxyApplyId || toolId == githubProxyRollbackId) {
      return (arguments['planId'] ?? '').toString();
    }
    if (toolId == proxySystemApplyId || toolId == proxySystemRestoreId) {
      return (arguments['dataDirectory'] ?? '').toString();
    }
    if (toolId == vmCreateDiskId) return (arguments['path'] ?? '').toString();
    if (toolId == vmStartId) {
      return (arguments['diskPath'] ?? arguments['isoPath'] ?? '').toString();
    }
    if (toolId.startsWith('vibekits.windows_node.')) {
      return (arguments['rootPath'] ?? WindowsTestNodeService.requiredRoot)
          .toString();
    }
    return (arguments['input'] ?? toolId).toString();
  }
}
