import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../app/app_settings.dart';
import '../../../app/platform_storage_layout.dart';
import '../../cleaner/domain/cleanup_platform_policy.dart';
import '../../cleaner/domain/cleanup_task.dart';
import '../../cleaner/domain/installed_application_service.dart';
import '../../cleaner/domain/software_storage_analyzer.dart';
import '../../cleaner/domain/system_drive_analysis_runner.dart';
import '../../cleaner/domain/system_drive_analyzer.dart';
import '../../cleaner/domain/system_drive_insights.dart';
import 'adb_service.dart';
import 'audio_harness_service.dart';
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
import 'harness_runtime_log_store.dart';
import 'harness_connection_sessions.dart';
import 'harness_work_status.dart';
import 'lark_cli_service.dart';
import 'lan_peer_discovery_service.dart';
import 'network_virtualization_service.dart';
import 'network_download_service.dart';
import 'packet_capture_service.dart';
import 'system_proxy_service.dart';
import 'system_resource_service.dart';
import 'programmer_calculator.dart';
import 'project_iteration_service.dart';
import 'platform_credential_store.dart';
import 'remote_connection_record.dart';
import 'remote_connection_status.dart';
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
typedef HarnessSerialOpener = Future<SerialPortSession> Function(
  SerialConnectionSettings settings,
);

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
    HarnessSerialOpener? serialOpener,
    GithubProxyService? githubProxyService,
    WindowsTestNodeService? windowsTestNodeService,
    WindowsNodeDeviceService? windowsNodeDeviceService,
    String? runtimeToolRoot,
    String? downloadDirectory,
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
    serialOpener,
    githubProxyService ?? GithubProxyService(),
    windowsTestNodeService ?? WindowsTestNodeService(),
    windowsNodeDeviceService ?? WindowsNodeDeviceService(),
    runtimeToolRoot,
    downloadDirectory,
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
    this._serialOpener,
    this._githubProxyService,
    this._windowsTestNodeService,
    this._windowsNodeDeviceService,
    this._runtimeToolRoot,
    this._downloadDirectory,
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
  static const String adbSessionOpenId = 'vibekits.adb.session_open';
  static const String adbSessionStatusId = 'vibekits.adb.session_status';
  static const String adbSessionCloseId = 'vibekits.adb.session_close';
  static const String serialListPortsId = 'vibekits.serial.list_ports';
  static const String serialAutoDetectId = 'vibekits.serial.auto_detect';
  static const String serialTransactId = 'vibekits.serial.transact';
  static const String serialSessionOpenId = 'vibekits.serial.session_open';
  static const String serialSessionReadId = 'vibekits.serial.session_read';
  static const String serialSessionWriteId = 'vibekits.serial.session_write';
  static const String serialSessionCloseId = 'vibekits.serial.session_close';
  static const String sqliteInspectId = 'vibekits.sqlite.inspect';
  static const String sqliteQueryId = 'vibekits.sqlite.query';
  static const String gitInspectId = 'vibekits.git.inspect';
  static const String gitListRemoteRefsId = 'vibekits.git.list_remote_refs';
  static const String gitReadRemoteFileId = 'vibekits.git.read_remote_file';
  static const String gitCloneMinimalId = 'vibekits.git.clone_minimal';
  static const String gitCompareRefsId = 'vibekits.git.compare_refs';
  static const String gitCreateLocalBranchId =
      'vibekits.git.create_local_branch';
  static const String gitBackupPreviewId = 'vibekits.git.backup_preview';
  static const String gitBackupCommitId = 'vibekits.git.backup_commit';
  static const String gitBackupPushId = 'vibekits.git.backup_push';
  static const String gitVerifyRemoteRefId = 'vibekits.git.verify_remote_ref';
  static const String fileSearchId = 'vibekits.files.search';
  static const String apiRequestId = 'vibekits.http.request';
  static const String networkDownloadId = 'vibekits.network.download';
  static const String larkCliInspectId = 'vibekits.feishu.inspect';
  static const String larkCliAuthStatusId = 'vibekits.feishu.auth_status';
  static const String larkCliSchemaId = 'vibekits.feishu.schema';
  static const String larkCliExecuteId = 'vibekits.feishu.execute';
  static const String lanPeersListId = 'vibekits.peers.list';
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
  static const String systemDriveAnalyzeStartId =
      'vibekits.cleaner.analyze_drive_start';
  static const String systemDriveAnalyzeStatusId =
      'vibekits.cleaner.analyze_drive_status';
  static const String systemDriveAnalyzeCancelId =
      'vibekits.cleaner.analyze_drive_cancel';
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
  static const String audioInspectId = 'vibekits.audio.inspect';
  static const String audioPcmToWavId = 'vibekits.audio.pcm_to_wav';
  static const String audioPlayId = 'vibekits.audio.play';
  static const String audioPauseId = 'vibekits.audio.pause';
  static const String audioStopId = 'vibekits.audio.stop';
  static const String audioGenerateToneId = 'vibekits.audio.generate_tone';
  static const String systemResourcesId = 'vibekits.system.resources';
  static const String capabilityCheckId = 'vibekits.system.capability_check';
  static const String describeToolId = 'vibekits.system.describe_tool';
  static const String harnessDiagnosticsId = 'vibekits.harness.diagnostics';
  static const String projectIterationInspectId =
      'vibekits.project.iteration_inspect';
  static const String projectBuildId = 'vibekits.project.build';
  static const String captureStatusId = 'vibekits.capture.status';
  static const String captureStartId = 'vibekits.capture.start';
  static const String captureStopId = 'vibekits.capture.stop';
  static const String captureReadId = 'vibekits.capture.read';
  static const String captureAnalyzeId = 'vibekits.capture.analyze';

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
  final HarnessSerialOpener? _serialOpener;
  final GithubProxyService _githubProxyService;
  final WindowsTestNodeService _windowsTestNodeService;
  final WindowsNodeDeviceService _windowsNodeDeviceService;
  final String? _runtimeToolRoot;
  final String? _downloadDirectory;
  final Future<void> Function(int processId)? _runtimeBindProcessTree;
  final Future<void> Function(int processId)? _runtimeReleaseProcessTree;
  final AudioHarnessService _audioHarnessService = AudioHarnessService();
  final PacketCaptureService _packetCaptureService =
      PacketCaptureService.instance;
  final ProjectIterationService _projectIterationService =
      ProjectIterationService();
  late final LarkCliService _larkCliService = LarkCliService(
    executable: _runtimeToolRoot == null
        ? null
        : '$_runtimeToolRoot${Platform.pathSeparator}lark-cli'
              '${Platform.pathSeparator}${Platform.isWindows ? 'lark-cli.exe' : 'lark-cli'}',
  );
  final Map<String, _DriveAnalysisTask> _driveAnalysisTasks =
      <String, _DriveAnalysisTask>{};
  late final HarnessConnectionSessions _connectionSessions =
      HarnessConnectionSessions(checkAdb: _checkAdbHealth);

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
    systemResourcesId: _definition(
      id: systemResourcesId,
      name: '检查系统资源',
      description: '只读采样本机 Windows/macOS/Android，或通过 Vibekits 内置 ADB 采样指定 Android 设备。返回 CPU、内存、GPU、磁盘、Top 进程、异常建议和证据来源。单次快照正常时不得断言间歇性卡顿已排除。',
      properties: <String, Object?>{
        'adbSerial': _string('可选；已连接 Android 设备序列号，留空分析本机'),
        'samples': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 10,
          'description': '连续采样次数，默认 3；间歇卡顿建议 5-10',
        },
        'intervalMs': const <String, Object?>{
          'type': 'integer',
          'minimum': 250,
          'maximum': 5000,
          'description': '采样间隔毫秒，默认 700',
        },
      },
    ),
    capabilityCheckId: _definition(
      id: capabilityCheckId,
      name: '检查智能体工具链',
      description: '只读核对 Vibekits 向 Harness 公开的每个工具是否具有本地执行器，并列出因安全或环境原因未公开的能力。用于任务前自检，不能替代硬件和外部服务的真实验收。',
      properties: const <String, Object?>{},
    ),
    describeToolId: _definition(
      id: describeToolId,
      name: '精确说明工具参数',
      description:
          '按工具 ID 返回当前运行版本的完整 inputSchema、必填项、枚举、默认值、风险和自动配置原则。回答参数配置问题前必须调用。',
      properties: <String, Object?>{
        'toolId': _string('完整工具 ID，例如 vibekits.serial.session_open'),
      },
      required: <String>['toolId'],
    ),
    harnessDiagnosticsId: _definition(
      id: harnessDiagnosticsId,
      name: '查询 Harness 诊断日志',
      description: '只读返回 Harness 最近的启动/运行日志和 Vibekits 工具调用记录，用于定位超时、退出、工具失败和耗时异常；敏感字段会脱敏。',
      properties: <String, Object?>{
        'limit': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '返回最近记录数，默认 20',
        },
        'includeLogTail': const <String, Object?>{
          'type': 'boolean',
          'description': '是否附带最新运行日志尾部，默认 true',
        },
      },
    ),
    projectIterationInspectId: _definition(
      id: projectIterationInspectId,
      name: '检查 APP 自迭代工作区',
      description:
          '检查 Vibekits 源码、ToolSpec 单一注册表和 Harness 桥接位置，并返回新增工具必须遵循的自动发现流程。',
      properties: <String, Object?>{
        'workspace': _string('Vibekits Flutter 工作区绝对路径'),
      },
      required: <String>['workspace'],
    ),
    projectBuildId: _definition(
      id: projectBuildId,
      name: '验证并编译 Vibekits APP',
      description: '在指定源码工作区依次执行 Analyze、Harness 自动注册合同测试和目标平台 Release 构建。只生成 build 产物，不覆盖运行中的 APP。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'workspace': _string('Vibekits Flutter 工作区绝对路径'),
        'target': <String, Object?>{
          'type': 'string',
          'enum': <String>['windows', 'android', 'macos'],
        },
        'flutterExecutable': _string('可选；Flutter 可执行文件绝对路径'),
        'runTests': <String, Object?>{'type': 'boolean'},
      },
      required: <String>['workspace', 'target'],
    ),
    captureStatusId: _definition(
      id: captureStatusId,
      name: '检查网络抓包状态',
      description: '只读返回内置 WinDivert 抓包内核、当前任务、已收包数、输出 PCAP 和最近错误。',
      properties: const <String, Object?>{},
    ),
    captureStartId: _definition(
      id: captureStartId,
      name: '开始网络抓包',
      description: '使用 APP 内置 WinDivert 在后台抓取本机网络包，按过滤器筛选并持续保存为标准 PCAP。Windows 首次加载驱动需要管理员权限。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'outputPath': _string('可选；PCAP 输出绝对路径，留空写入 APP tmp/network-capture'),
        'filter': _string('WinDivert 过滤器，默认 true；例如 tcp、udp.DstPort == 53'),
        'maxPackets': const <String, Object?>{
          'type': 'integer',
          'minimum': 0,
          'maximum': 1000000,
        },
      },
    ),
    captureStopId: _definition(
      id: captureStopId,
      name: '停止并保存网络抓包',
      description: '停止当前抓包，刷新 PCAP 文件并返回实际包数、协议统计和保存路径。',
      risk: HarnessToolRisk.controlsDevice,
      properties: const <String, Object?>{},
    ),
    captureReadId: _definition(
      id: captureReadId,
      name: '读取 PCAP 数据包',
      description: '只读解析标准 PCAP，返回时间、协议、源、目标、长度及汇总；不会修改原文件。',
      properties: <String, Object?>{
        'path': _string('PCAP 文件绝对路径'),
        'maxPackets': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 10000,
        },
      },
      required: const <String>['path'],
    ),
    captureAnalyzeId: _definition(
      id: captureAnalyzeId,
      name: '分析 PCAP 流量',
      description: '只读统计协议、字节数和 Top 端点，给智能体提供可核验的网络流量证据。',
      properties: <String, Object?>{'path': _string('PCAP 文件绝对路径')},
      required: const <String>['path'],
    ),
    audioInspectId: _definition(
      id: audioInspectId,
      name: '分析 PCM / WAV 质量',
      description: '后台分析 PCM/WAV 的格式、波形、峰值、RMS、直流偏置、削波、静音、主频、谐波、THD、THD+N、SNR、噪声底、有效位数和声道相关性，并返回谐波和噪声最明显的时间段。复杂音乐的单音指标仅作诊断参考。',
      properties: _audioProperties(includePath: true),
      required: const <String>['path'],
    ),
    audioPcmToWavId: _definition(
      id: audioPcmToWavId,
      name: 'PCM 转 WAV',
      description: '按照明确的 RAW PCM 参数封装为 WAV，不重新采样、不改变样本。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'inputPath': _string('输入 PCM 绝对路径'),
        'outputPath': _string('输出 WAV 绝对路径'),
        ..._audioProperties(),
      },
      required: const <String>['inputPath', 'outputPath'],
    ),
    audioPlayId: _definition(
      id: audioPlayId,
      name: '播放 PCM / WAV',
      description: '播放 WAV；RAW PCM 会先按给定格式生成临时 WAV 再播放。',
      risk: HarnessToolRisk.controlsDevice,
      properties: _audioProperties(includePath: true),
      required: const <String>['path'],
    ),
    audioPauseId: _definition(
      id: audioPauseId,
      name: '暂停音频',
      description: '暂停由 Harness 音频工具启动的本地播放。',
      risk: HarnessToolRisk.controlsDevice,
      properties: const <String, Object?>{},
    ),
    audioStopId: _definition(
      id: audioStopId,
      name: '停止音频',
      description: '停止由 Harness 音频工具启动的本地播放。',
      risk: HarnessToolRisk.controlsDevice,
      properties: const <String, Object?>{},
    ),
    audioGenerateToneId: _definition(
      id: audioGenerateToneId,
      name: '生成音频测试音',
      description: '生成 16-bit PCM WAV 正弦测试音并立即返回质量分析，便于闭环校验音频链路。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'outputPath': _string('输出 WAV 绝对路径'),
        'frequencyHz': const <String, Object?>{
          'type': 'number',
          'minimum': 1,
          'description': '正弦频率，默认 1000 Hz',
        },
        'durationSeconds': const <String, Object?>{
          'type': 'number',
          'minimum': 0.01,
          'maximum': 60,
          'description': '时长，默认 1 秒',
        },
        'amplitude': const <String, Object?>{
          'type': 'number',
          'exclusiveMinimum': 0,
          'maximum': 1,
          'description': '峰值幅度，默认 0.5',
        },
        ..._audioProperties(),
      },
      required: const <String>['outputPath'],
    ),
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
      description: '连接用户明确指定的 Android 无线调试地址；1..254 的主机别名自动映射到 192.168.3.x:5555，并在连接后核验设备身份。',
      risk: HarnessToolRisk.controlsDevice,
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'address': <String, Object?>{
            'type': 'string',
            'description': 'IP、IP:端口或主机别名，例如 53 自动解析为 192.168.3.53:5555',
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
      description:
          '把明确的本地 APK 安装到选定设备；覆盖或尝试版本降级必须显式指定。降级仍受 Android 设备策略约束，失败时不得自动卸载应用。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'apkPath': _string('本地 APK 绝对路径'),
        'replace': <String, Object?>{'type': 'boolean'},
        'allowDowngrade': <String, Object?>{
          'type': 'boolean',
          'description': '显式传入 true 时追加 adb install -d；不会自动卸载或清除应用数据',
          'default': false,
        },
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
    adbSessionOpenId: _definition(
      id: adbSessionOpenId,
      name: '保持 ADB 长连接',
      description: '为指定设备建立带真实 get-state 心跳的长连接；后续用 session_status 检查，完成后显式关闭。底层复用内置 ADB server 连接。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'serial': _string('设备序列号或 IP:端口'),
        'heartbeatSeconds': <String, Object?>{
          'type': 'integer',
          'minimum': 3,
          'maximum': 60,
        },
      },
      required: <String>['serial'],
    ),
    adbSessionStatusId: _definition(
      id: adbSessionStatusId,
      name: '读取 ADB 长连接状态',
      description: '返回真实心跳次数、最后检查时间和设备连接状态。',
      properties: <String, Object?>{'sessionId': _string('ADB 长连接 ID')},
      required: <String>['sessionId'],
    ),
    adbSessionCloseId: _definition(
      id: adbSessionCloseId,
      name: '关闭 ADB 长连接',
      description: '停止指定设备的后台心跳；不杀死其他工具正在使用的 ADB server。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{'sessionId': _string('ADB 长连接 ID')},
      required: <String>['sessionId'],
    ),
    serialListPortsId: _definition(
      id: serialListPortsId,
      name: '列出串口',
      description: '在后台线程读取 Windows/macOS 可用串口及 USB 描述。',
      properties: const <String, Object?>{},
    ),
    serialAutoDetectId: _definition(
      id: serialAutoDetectId,
      name: '自动探测串口配置',
      description: '自动选择物理 USB 串口，并以只监听、不发送数据的方式分阶段尝试常见波特率、数据位、停止位、奇偶校验和全部 8 种流控组合；返回逐项证据及推荐配置，不要求用户手工填写。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'port': _string('可选串口名；留空时按 USB VID/PID、描述和端口名自动选择'),
        'baudRates': <String, Object?>{
          'type': 'array',
          'description': '可选候选波特率；默认依次尝试 115200、921600、460800、230400、57600、38400、19200、9600',
          'items': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 12000000,
          },
          'maxItems': 16,
        },
        'listenMs': <String, Object?>{
          'type': 'integer',
          'description': '每个候选只监听的毫秒数；默认 300，范围 100-3000',
          'minimum': 100,
          'maximum': 3000,
          'default': 300,
        },
      },
    ),
    serialTransactId: _definition(
      id: serialTransactId,
      name: '串口收发与监听',
      description: '后台打开串口；data 为空时仅实时监听，非空时发送文本或 HEX，再接收后自动关闭。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'port': _string('串口名，例如 COM3'),
        'baudRate': <String, Object?>{
          'type': 'integer',
          'description': '默认 115200；建议先采用 serial.auto_detect 返回值',
          'minimum': 1,
          'maximum': 12000000,
          'default': 115200,
        },
        'dataBits': <String, Object?>{
          'type': 'integer',
          'description': '数据位，默认 8',
          'enum': <int>[5, 6, 7, 8],
          'default': 8,
        },
        'stopBits': <String, Object?>{
          'type': 'integer',
          'description': '停止位，默认 1',
          'enum': <int>[1, 2],
          'default': 1,
        },
        'parity': <String, Object?>{
          'type': 'string',
          'description': '奇偶校验，默认 none',
          'enum': <String>['none', 'even', 'odd', 'mark', 'space'],
          'default': 'none',
        },
        'flowControl': <String, Object?>{
          'type': 'string',
          'description': '流控/波控，默认 none；支持三种基础流控及其组合',
          'enum': <String>[
            'none',
            'dtrDsr',
            'rtsCts',
            'xonXoff',
            'dtrDsrRtsCts',
            'dtrDsrXonXoff',
            'rtsCtsXonXoff',
            'all',
          ],
          'default': 'none',
        },
        'data': _string('待发送文本或 HEX 字节'),
        'mode': <String, Object?>{
          'type': 'string',
          'description': '数据解释模式，默认 text',
          'enum': <String>['text', 'hex'],
          'default': 'text',
        },
        'waitMs': <String, Object?>{
          'type': 'integer',
          'description': '发送后或纯监听等待时间，默认 3000 ms',
          'minimum': 50,
          'maximum': 30000,
          'default': 3000,
        },
      },
      required: <String>['port'],
    ),
    serialSessionOpenId: _definition(
      id: serialSessionOpenId,
      name: '打开串口长连接',
      description: '在独立 Isolate 中持续持有串口并缓存实时接收数据，直到显式关闭或 APP 退出。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'port': _string('串口名，例如 COM33'),
        'baudRate': <String, Object?>{
          'type': 'integer',
          'description': '默认 115200；优先使用 serial.auto_detect 推荐值',
          'minimum': 1,
          'maximum': 12000000,
          'default': 115200,
        },
        'dataBits': <String, Object?>{
          'type': 'integer',
          'description': '数据位，默认 8',
          'enum': <int>[5, 6, 7, 8],
          'default': 8,
        },
        'stopBits': <String, Object?>{
          'type': 'integer',
          'description': '停止位，默认 1',
          'enum': <int>[1, 2],
          'default': 1,
        },
        'parity': <String, Object?>{
          'type': 'string',
          'description': '奇偶校验，默认 none',
          'enum': <String>['none', 'even', 'odd', 'mark', 'space'],
          'default': 'none',
        },
        'flowControl': <String, Object?>{
          'type': 'string',
          'description': '流控/波控，默认 none；自动探测会覆盖 DTR/DSR、RTS/CTS、XON/XOFF 及组合',
          'enum': <String>[
            'none',
            'dtrDsr',
            'rtsCts',
            'xonXoff',
            'dtrDsrRtsCts',
            'dtrDsrXonXoff',
            'rtsCtsXonXoff',
            'all',
          ],
          'default': 'none',
        },
      },
      required: <String>['port'],
    ),
    serialSessionReadId: _definition(
      id: serialSessionReadId,
      name: '读取串口长连接',
      description: '读取长连接已缓存的实时数据，可选择文本或 HEX；默认读取后清空缓存。',
      properties: <String, Object?>{
        'sessionId': _string('串口长连接 ID'),
        'mode': <String, Object?>{
          'type': 'string',
          'enum': <String>['text', 'hex'],
        },
        'clear': <String, Object?>{'type': 'boolean'},
      },
      required: <String>['sessionId'],
    ),
    serialSessionWriteId: _definition(
      id: serialSessionWriteId,
      name: '写入串口长连接',
      description: '通过已打开的串口句柄发送文本或 HEX，不重新打开端口。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'sessionId': _string('串口长连接 ID'),
        'data': _string('待发送文本或 HEX'),
        'mode': <String, Object?>{
          'type': 'string',
          'enum': <String>['text', 'hex'],
        },
        'lineEnding': <String, Object?>{
          'type': 'string',
          'enum': <String>['none', 'lf', 'crlf', 'cr'],
        },
      },
      required: <String>['sessionId', 'data'],
    ),
    serialSessionCloseId: _definition(
      id: serialSessionCloseId,
      name: '关闭串口长连接',
      description: '释放指定串口句柄和后台 Isolate。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{'sessionId': _string('串口长连接 ID')},
      required: <String>['sessionId'],
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
    gitListRemoteRefsId: _definition(
      id: gitListRemoteRefsId,
      name: '列出 Git 远端引用',
      description: '使用 APP 内置 Git 只读执行 ls-remote，列出远端分支和提交；不克隆仓库、不输出凭据。',
      properties: <String, Object?>{
        'remoteUrl': _string('SSH、HTTP 或 HTTPS Git 远端地址；不得包含明文密码'),
        'pattern': _string('可选 ref 匹配，例如 refs/heads/*'),
        'timeoutSeconds': <String, Object?>{
          'type': 'integer',
          'minimum': 5,
          'maximum': 120,
          'default': 30,
        },
      },
      required: <String>['remoteUrl'],
    ),
    gitReadRemoteFileId: _definition(
      id: gitReadRemoteFileId,
      name: '读取 Git 远端文件',
      description:
          '浅取指定 ref 到 APP 临时目录并只返回一个有界文本文件，适合读取 manifest；完成后自动删除临时对象，不同步整仓。',
      properties: <String, Object?>{
        'remoteUrl': _string('SSH、HTTP 或 HTTPS Git 远端地址；不得包含明文密码'),
        'ref': _string('明确的分支、标签或提交，例如 master'),
        'path': _string('仓库内安全相对路径，例如 default.xml'),
        'maxBytes': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 2097152,
          'default': 1048576,
        },
        'timeoutSeconds': <String, Object?>{
          'type': 'integer',
          'minimum': 5,
          'maximum': 180,
          'default': 60,
        },
      },
      required: <String>['remoteUrl', 'ref', 'path'],
    ),
    gitCloneMinimalId: _definition(
      id: gitCloneMinimalId,
      name: '按需浅克隆 Git 仓库',
      description: '将明确指定的单个仓库和分支浅克隆到不存在的独立目录；禁止覆盖目录，不执行无参数 repo sync。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'remoteUrl': _string('明确的单仓库 SSH、HTTP 或 HTTPS 地址'),
        'destination': _string('必须不存在的独立目标目录'),
        'ref': _string('分支或标签，默认 master'),
        'depth': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 100,
          'default': 1,
        },
        'timeoutSeconds': <String, Object?>{
          'type': 'integer',
          'minimum': 30,
          'maximum': 1800,
          'default': 300,
        },
      },
      required: <String>['remoteUrl', 'destination'],
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
    networkDownloadId: _definition(
      id: networkDownloadId,
      name: '下载网络文件',
      description: '把 HTTP/HTTPS 文件流式下载到 APP 配置的下载目录，完成后返回绝对路径、大小、SHA-256 和 HTTP 证据。APK 会校验 ZIP/APK 签名，适合随后调用 adb.install_apk。',
      risk: HarnessToolRisk.writesData,
      properties: <String, Object?>{
        'url': _string('完整 HTTP/HTTPS URL'),
        'fileName': _string('可选目标文件名；只能是文件名，不能含目录'),
        'outputDirectory': _string('可选绝对下载目录；默认使用 APP 设置的工具下载目录'),
        'overwrite': const <String, Object?>{
          'type': 'boolean',
          'default': false,
        },
        'expectedSha256': _string('可选 64 位 SHA-256，用于强校验'),
        'timeoutSeconds': const <String, Object?>{
          'type': 'integer',
          'minimum': 5,
          'maximum': 1800,
          'default': 300,
        },
        'maxBytes': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 8589934592,
          'default': 2147483648,
        },
      },
      required: <String>['url'],
    ),
    larkCliInspectId: _definition(
      id: larkCliInspectId,
      name: '检查官方飞书CLI运行时',
      description: '只读检查Vibekits内置的官方larksuite/cli版本、路径、许可证和JSON输出契约，不读取或回显凭证。',
      properties: const <String, Object?>{},
    ),
    larkCliAuthStatusId: _definition(
      id: larkCliAuthStatusId,
      name: '检查飞书授权状态',
      description: '调用官方lark-cli auth status，返回结构化授权状态或not_configured提示；不回显App Secret和Token。',
      properties: const <String, Object?>{},
    ),
    larkCliSchemaId: _definition(
      id: larkCliSchemaId,
      name: '读取飞书命令Schema',
      description:
          '从官方CLI读取指定命令的参数、类型、必填项、身份、scope和风险元数据；Harness必须先调用本接口再执行陌生命令。',
      properties: <String, Object?>{
        'command': _string('命令路径，例如 calendar.events.get；留空返回Schema目录'),
      },
    ),
    larkCliExecuteId: _definition(
      id: larkCliExecuteId,
      name: '执行官方飞书CLI命令',
      description: '以参数数组调用内置官方lark-cli并返回有界JSON结果。禁止传入Secret或Token；写操作必须先读取Schema并优先使用--dry-run。',
      risk: HarnessToolRisk.controlsDevice,
      properties: <String, Object?>{
        'arguments': const <String, Object?>{
          'type': 'array',
          'description': '逐项参数数组，例如 ["calendar","events","get","--calendar-id","...","--event-id","..."]；不得拼成shell字符串',
          'items': <String, Object?>{'type': 'string'},
          'minItems': 1,
          'maxItems': 64,
        },
        'timeoutSeconds': const <String, Object?>{
          'type': 'integer',
          'minimum': 5,
          'maximum': 1800,
          'default': 300,
        },
      },
      required: <String>['arguments'],
    ),
    lanPeersListId: _definition(
      id: lanPeersListId,
      name: '发现局域网VibeKits节点',
      description:
          '列出同一私网内正在广播的VibeKits实例及SSH MCP入口。发现不等于授权；未由主机批准公钥前不得调用或分派任务。',
      properties: const <String, Object?>{},
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
      description: '列出已保存的 SSH/SFTP 历史、最近使用时间和当前在线连接数；不返回密码或私钥内容。',
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
      description: '同步分析较小的磁盘或目录并返回有界结果；大磁盘必须使用 analyze_drive_start/status，避免 MCP 超时和重复扫描。不删除任何文件。',
      properties: <String, Object?>{
        'root': _string('磁盘或待分析目录的绝对路径'),
        'maxResults': <String, Object?>{
          'type': 'integer',
          'description': '每类最多返回多少条，默认 50，范围 10..200',
          'minimum': 10,
          'maximum': 200,
          'default': 50,
        },
      },
      required: <String>['root'],
    ),
    systemDriveAnalyzeStartId: _definition(
      id: systemDriveAnalyzeStartId,
      name: '启动磁盘占用分析',
      description: '启动长耗时只读磁盘分析并立即返回 taskId。同一根目录只保留一个运行任务；Harness 应轮询 status，禁止因等待或超时重复启动。',
      properties: <String, Object?>{
        'root': _string('磁盘或待分析目录的绝对路径'),
        'maxResults': <String, Object?>{
          'type': 'integer',
          'description': '完成后每类最多返回多少条，默认 50，范围 10..200',
          'minimum': 10,
          'maximum': 200,
          'default': 50,
        },
      },
      required: <String>['root'],
    ),
    systemDriveAnalyzeStatusId: _definition(
      id: systemDriveAnalyzeStatusId,
      name: '查询磁盘分析状态',
      description: '按 taskId 长轮询进度；任务运行时最多等待 waitSeconds，完成时立即返回有界结果。若仍为 running，继续查询同一 taskId，不得重新启动。',
      properties: <String, Object?>{
        'taskId': _string('analyze_drive_start 返回的任务 ID'),
        'waitSeconds': const <String, Object?>{
          'type': 'integer',
          'description': '长轮询等待秒数，默认 20，范围 0..45；必须小于 MCP 工具超时',
          'minimum': 0,
          'maximum': 45,
          'default': 20,
        },
      },
      required: <String>['taskId'],
    ),
    systemDriveAnalyzeCancelId: _definition(
      id: systemDriveAnalyzeCancelId,
      name: '取消磁盘占用分析',
      description: '取消指定只读分析任务；不会删除或修改任何文件。',
      properties: <String, Object?>{
        'taskId': _string('analyze_drive_start 返回的任务 ID'),
      },
      required: <String>['taskId'],
    ),
    screenshotOcrId: HarnessToolDefinition(
      id: screenshotOcrId,
      name: '截图并 OCR 分析',
      description:
          '让用户框选屏幕区域并在本机 OCR。返回原图尺寸、文字、像素框 boundsPx、0..1 '
          '归一化框 boundsRelative、九宫格 region 和 spatialText；没有多模态视觉的智能体应依据这些字段理解控件位置、阅读顺序和空间关系。',
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
    if ((Platform.isAndroid || Platform.isIOS) && requiresDesktopNode(toolId)) {
      final Map<String, Object?> gate = <String, Object?>{
        'available': false,
        'executed': false,
        'platform': Platform.operatingSystem,
        'requiresDesktopNode': true,
        'toolId': toolId,
        'reason': '该能力需要桌面系统的驱动、端口或内置二进制，移动端不会伪执行。',
        'nextAction': '连接已登记的 Vibekits Windows/macOS 桌面节点后重试。',
      };
      await _recordActivity(
        toolId: toolId,
        toolName: definition.name,
        target: target,
        arguments: arguments,
        result: gate,
        status: HarnessToolActivityStatus.failed,
        startedAt: startedAt,
      );
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.ready,
        message: '${definition.name}需要桌面节点',
        toolId: toolId,
        toolName: definition.name,
        target: target,
      );
      return HarnessToolCallResult.success(gate);
    }
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

  /// Tools that remain visible to the mobile agent but must execute on a
  /// registered desktop node. Keeping them in the schema lets Harness explain
  /// and plan the workflow instead of silently pretending the APP lacks them.
  static bool requiresDesktopNode(String toolId) {
    const Set<String> prefixes = <String>{
      'vibekits.adb.',
      'vibekits.capture.',
      'vibekits.proxy.',
      'vibekits.vm.',
      'vibekits.runtime.',
      'vibekits.windows_',
      'vibekits.serial',
      'vibekits.git.',
      'vibekits.github',
      'vibekits.project.',
    };
    return prefixes.any(toolId.startsWith);
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
          'input': <String, Object?>{
            'type': 'string',
            'description': '用户任务的主要输入；能从当前文件或拖入对象获得时自动采用',
          },
          'params': <String, Object?>{
            'type': 'string',
            'description': '可选附加参数；无明确需要时使用工具默认值',
          },
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
    if (toolId == adbSessionOpenId) return _openAdbSession;
    if (toolId == adbSessionStatusId) return _adbSessionStatus;
    if (toolId == adbSessionCloseId) return _closeAdbSession;
    if (toolId == serialListPortsId) return _listSerialPorts;
    if (toolId == serialAutoDetectId) return _autoDetectSerial;
    if (toolId == serialTransactId) return _serialTransact;
    if (toolId == serialSessionOpenId) return _openSerialSession;
    if (toolId == serialSessionReadId) return _readSerialSession;
    if (toolId == serialSessionWriteId) return _writeSerialSession;
    if (toolId == serialSessionCloseId) return _closeSerialSession;
    if (toolId == describeToolId) return _describeTool;
    if (toolId == harnessDiagnosticsId) return _readHarnessDiagnostics;
    if (toolId == sqliteInspectId) return _inspectSqlite;
    if (toolId == sqliteQueryId) return _querySqlite;
    if (toolId == gitInspectId) return _inspectGit;
    if (toolId == gitListRemoteRefsId) return _listGitRemoteRefs;
    if (toolId == gitReadRemoteFileId) return _readGitRemoteFile;
    if (toolId == gitCloneMinimalId) return _cloneGitMinimal;
    if (toolId == gitCompareRefsId) return _compareGitRefs;
    if (toolId == gitCreateLocalBranchId) return _createGitLocalBranch;
    if (toolId == gitBackupPreviewId) return _previewGitBackup;
    if (toolId == gitBackupCommitId) return _commitGitBackup;
    if (toolId == gitBackupPushId) return _pushGitBackup;
    if (toolId == gitVerifyRemoteRefId) return _verifyGitRemoteRef;
    if (toolId == fileSearchId) return _searchFiles;
    if (toolId == apiRequestId) return _requestHttp;
    if (toolId == networkDownloadId) return _downloadNetworkFile;
    if (toolId == larkCliInspectId) return _inspectLarkCli;
    if (toolId == larkCliAuthStatusId) return _larkCliAuthStatus;
    if (toolId == larkCliSchemaId) return _larkCliSchema;
    if (toolId == larkCliExecuteId) return _executeLarkCli;
    if (toolId == lanPeersListId) return _listLanPeers;
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
    if (toolId == systemDriveAnalyzeStartId) {
      return _startSystemDriveAnalysis;
    }
    if (toolId == systemDriveAnalyzeStatusId) {
      return _systemDriveAnalysisStatus;
    }
    if (toolId == systemDriveAnalyzeCancelId) {
      return _cancelSystemDriveAnalysis;
    }
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
    if (toolId == audioInspectId) return _audioHarnessService.inspect;
    if (toolId == audioPcmToWavId) return _audioHarnessService.pcmToWav;
    if (toolId == audioPlayId) return _audioHarnessService.play;
    if (toolId == audioPauseId) return _audioHarnessService.pause;
    if (toolId == audioStopId) return _audioHarnessService.stop;
    if (toolId == audioGenerateToneId) {
      return _audioHarnessService.generateTone;
    }
    if (toolId == systemResourcesId) return _inspectSystemResources;
    if (toolId == capabilityCheckId) return _checkHarnessCapabilities;
    if (toolId == projectIterationInspectId) return _inspectProjectIteration;
    if (toolId == projectBuildId) return _buildProjectIteration;
    if (toolId == captureStatusId) return _captureStatus;
    if (toolId == captureStartId) return _captureStart;
    if (toolId == captureStopId) return _captureStop;
    if (toolId == captureReadId) return _captureRead;
    if (toolId == captureAnalyzeId) return _captureAnalyze;
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

  Future<Map<String, Object?>> _captureStatus(
    Map<String, Object?> arguments,
  ) async {
    final File helper = File(_packetCaptureService.helperPath);
    return <String, Object?>{
      'available': Platform.isWindows && await helper.exists(),
      'helperPath': helper.path,
      'capturing': _packetCaptureService.isCapturing,
      'packetCount': _packetCaptureService.packetCount,
      'outputPath': _packetCaptureService.outputPath,
      'lastError': _packetCaptureService.lastError,
      'requiresAdministrator': Platform.isWindows,
    };
  }

  Future<Map<String, Object?>> _captureStart(
    Map<String, Object?> arguments,
  ) async {
    final String requestedPath = (arguments['outputPath'] ?? '')
        .toString()
        .trim();
    final String outputPath = requestedPath.isEmpty
        ? await _packetCaptureService.defaultOutputPath()
        : requestedPath;
    await _packetCaptureService.start(
      outputPath: outputPath,
      filter: (arguments['filter'] ?? 'true').toString(),
      maxPackets: (arguments['maxPackets'] as num?)?.toInt() ?? 0,
    );
    return <String, Object?>{
      'started': true,
      'outputPath': outputPath,
      'filter': (arguments['filter'] ?? 'true').toString(),
      'note': '抓包在后台运行；完成后调用 vibekits.capture.stop。',
    };
  }

  Future<Map<String, Object?>> _captureStop(
    Map<String, Object?> arguments,
  ) async {
    final String? path = _packetCaptureService.outputPath;
    await _packetCaptureService.stop();
    if (path == null || !await File(path).exists()) {
      return <String, Object?>{
        'stopped': true,
        'outputPath': path,
        'packetCount': 0,
      };
    }
    final PacketCaptureSummary summary = await _packetCaptureService.read(path);
    return <String, Object?>{'stopped': true, ...summary.toJson()};
  }

  Future<Map<String, Object?>> _captureRead(
    Map<String, Object?> arguments,
  ) async {
    final PacketCaptureSummary summary = await _packetCaptureService.read(
      (arguments['path'] ?? '').toString(),
      maxPackets: (arguments['maxPackets'] as num?)?.toInt() ?? 2000,
    );
    return summary.toJson();
  }

  Future<Map<String, Object?>> _captureAnalyze(
    Map<String, Object?> arguments,
  ) async {
    final PacketCaptureSummary summary = await _packetCaptureService.read(
      (arguments['path'] ?? '').toString(),
      maxPackets: 10000,
    );
    final Map<String, Object> json = summary.toJson();
    json.remove('packets');
    return json;
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

  Future<Map<String, Object?>> _inspectSystemResources(
    Map<String, Object?> arguments,
  ) async {
    final String serial = (arguments['adbSerial'] ?? '').toString().trim();
    final int sampleCount = _integer(arguments['samples'], 3).clamp(1, 10);
    final int intervalMs = _integer(
      arguments['intervalMs'],
      700,
    ).clamp(250, 5000);
    final List<SystemResourceSnapshot> snapshots = <SystemResourceSnapshot>[];
    for (int index = 0; index < sampleCount; index += 1) {
      snapshots.add(
        serial.isEmpty
            ? await SystemResourceService.inspectLocal()
            : await SystemResourceService.inspectAndroidDevice(
                serial: serial,
                adbExecutable:
                    _adbExecutable ?? AdbService.bundledExecutablePath(),
              ),
      );
      if (index + 1 < sampleCount) {
        await Future<void>.delayed(Duration(milliseconds: intervalMs));
      }
    }
    final SystemResourceSnapshot latest = snapshots.last;
    double average(double Function(SystemResourceSnapshot value) read) =>
        snapshots.map(read).reduce((double a, double b) => a + b) /
        snapshots.length;
    double maximum(double Function(SystemResourceSnapshot value) read) =>
        snapshots.map(read).reduce((double a, double b) => a > b ? a : b);
    final Map<String, int> recurringProcesses = <String, int>{};
    for (final SystemResourceSnapshot snapshot in snapshots) {
      for (final ResourceProcessSample process in snapshot.processes.take(5)) {
        recurringProcesses.update(
          process.name,
          (int value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return <String, Object?>{
      ...latest.toJson(),
      'series': snapshots
          .map(
            (SystemResourceSnapshot value) => <String, Object?>{
              'capturedAt': value.capturedAt.toIso8601String(),
              'cpuPercent': value.cpuPercent,
              'memoryUsedPercent': value.memoryUsedPercent,
              if (value.gpuPercent != null) 'gpuPercent': value.gpuPercent,
            },
          )
          .toList(),
      'summary': <String, Object?>{
        'samples': snapshots.length,
        'cpuAveragePercent': average(
          (SystemResourceSnapshot value) => value.cpuPercent,
        ),
        'cpuMaximumPercent': maximum(
          (SystemResourceSnapshot value) => value.cpuPercent,
        ),
        'memoryAveragePercent': average(
          (SystemResourceSnapshot value) => value.memoryUsedPercent,
        ),
        'memoryMaximumPercent': maximum(
          (SystemResourceSnapshot value) => value.memoryUsedPercent,
        ),
        'recurringTopProcesses': recurringProcesses.entries
            .where((MapEntry<String, int> value) => value.value > 1)
            .map(
              (MapEntry<String, int> value) => <String, Object?>{
                'name': value.key,
                'appearances': value.value,
              },
            )
            .toList(),
      },
    };
  }

  Future<Map<String, Object?>> _checkHarnessCapabilities(
    Map<String, Object?> arguments,
  ) async {
    final List<HarnessToolDefinition> executable = executableCatalog;
    final List<String> missingHandlers = <String>[
      for (final HarnessToolDefinition tool in executable)
        if (_handlerFor(tool.id) == null) tool.id,
    ];
    final List<Map<String, Object?>> unavailable = <Map<String, Object?>>[
      for (final HarnessToolDefinition tool in fullCatalog)
        if (!tool.available && !_customHandlers.containsKey(tool.id))
          <String, Object?>{
            'id': tool.id,
            'name': tool.name,
            'reason': tool.description,
          },
    ];
    final Map<String, int> riskCounts = <String, int>{};
    for (final HarnessToolDefinition tool in executable) {
      riskCounts.update(
        tool.risk.name,
        (int value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final List<String> businessModules = <String>[];
    for (final ToolSpec spec in allDevToolRegistry) {
      if (!businessModules.contains(spec.group)) {
        businessModules.add(spec.group);
      }
    }
    return <String, Object?>{
      'ready': missingHandlers.isEmpty,
      'protocol': protocolVersion,
      'productHierarchy': <String, Object?>{
        'topLevelPageCount': 5,
        'topLevelPages': const <String>[
          '智能体（Harness）',
          '解压缩',
          '系统清理',
          '文档阅读',
          '开发工具',
        ],
        'developerCapabilityEntries': allDevToolRegistry.length,
        'independentDeveloperWorkspaces': devToolRegistry.length,
        'businessModuleCount': businessModules.length,
        'businessModules': businessModules,
        'countingRule': '页面、业务能力、工作区和机器接口属于不同层级，不得相加为总功能数',
        'usageContracts': <String, Object?>{
          for (final ToolSpec tool in devToolRegistry)
            tool.id: devToolUsageContracts[tool.id]!.toJson(),
        },
      },
      'definedTools': fullCatalog.length,
      'executableTools': executable.length,
      'missingHandlers': missingHandlers,
      'unavailableTools': unavailable,
      'riskCounts': riskCounts,
      'autoConfigurationPolicy': <String, Object?>{
        'rule': '自动发现和安全试探优先；不向用户询问机器可推导的配置',
        'askUserOnlyFor': const <String>[
          '未保存的账号或登录身份',
          '密码、API Key、Token、私钥口令等秘密',
          '业务任务本身缺少的目标或内容',
          '破坏性操作确认',
        ],
        'discoveryFlows': const <String>[
          '串口 list_ports → auto_detect → session_open',
          'ADB list_devices/connect → session_open',
          'SSH/SFTP list_profiles → 复用保存会话',
          '数据库 remote_list_profiles → 复用保存会话',
          '代理/虚拟机 runtime.inspect → start → status',
          'Git inspect → preview → apply → verify',
          '文件和系统工具从拖入对象、当前工作区或 inspect 结果取得路径',
        ],
        'exactSchemaTool': describeToolId,
        'serialSkill': <String, Object?>{
          'tool': serialAutoDetectId,
          'parameters': const <String>[
            'port',
            'baudRate',
            'dataBits',
            'stopBits',
            'parity',
            'flowControl',
          ],
          'passiveProbe': true,
        },
      },
      'platform': <String, Object?>{
        'name': Platform.operatingSystem,
        'storageLocations': PlatformStorageLayout.current().toJson(),
        'cleanup': CleanupPlatformPolicy.capabilities(CleanupPlatform.current)
            .toJson(),
        'allToolsVisibleToHarness': true,
        'desktopNodeToolCount': executable
            .where((HarnessToolDefinition tool) => requiresDesktopNode(tool.id))
            .length,
        'localToolCount': executable
            .where(
              (HarnessToolDefinition tool) => !requiresDesktopNode(tool.id),
            )
            .length,
        'desktopNodeRule': '移动端保留完整 Schema；桌面专属项返回 requiresDesktopNode，不伪执行。',
      },
      'checkedAt': DateTime.now().toIso8601String(),
      'scope': '注册、公开状态与执行器接线；真实设备、网络、凭据和硬件另按环境门禁验收',
    };
  }

  Future<Map<String, Object?>> _inspectProjectIteration(
    Map<String, Object?> arguments,
  ) => _projectIterationService.inspect(
    (arguments['workspace'] ?? '').toString(),
  );

  Future<Map<String, Object?>> _buildProjectIteration(
    Map<String, Object?> arguments,
  ) => _projectIterationService.build(
    workspace: (arguments['workspace'] ?? '').toString(),
    target: (arguments['target'] ?? '').toString(),
    flutterExecutable: (arguments['flutterExecutable'] ?? '').toString(),
    runTests: arguments['runTests'] != false,
  );

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
    final String target = AdbService.normalizeWirelessAddress(address);
    final List<AdbDevice> devices = await AdbService.listDevices(
      executable,
      runner: _adbRunner,
    );
    final AdbDevice? connected = devices
        .where((AdbDevice device) => device.serial == target)
        .firstOrNull;
    return <String, Object?>{
      'address': target,
      'output': output,
      'verified': connected?.ready ?? false,
      if (connected != null)
        'device': <String, Object?>{
          'serial': connected.serial,
          'state': connected.state.name,
          if (connected.model != null) 'model': connected.model,
          if (connected.product != null) 'product': connected.product,
          if (connected.device != null) 'device': connected.device,
          if (connected.transportId != null)
            'transportId': connected.transportId,
        },
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
      if (arguments['allowDowngrade'] == true) '-d',
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

  Future<Map<String, Object?>> _autoDetectSerial(
    Map<String, Object?> arguments,
  ) async {
    final List<SerialPortDescriptor> ports =
        await SerialPortService.listPorts();
    if (ports.isEmpty) throw StateError('未检测到可用串口');
    String portName = (arguments['port'] ?? '').toString().trim();
    String selectionReason = '使用调用方指定端口';
    if (portName.isEmpty) {
      final List<SerialPortDescriptor> ranked =
          List<SerialPortDescriptor>.of(ports)
            ..sort((SerialPortDescriptor left, SerialPortDescriptor right) {
              int score(SerialPortDescriptor port) {
                final String text = '${port.description} ${port.transport}'
                    .toLowerCase();
                return (port.vendorId != null ? 100 : 0) +
                    (port.productId != null ? 50 : 0) +
                    (text.contains('usb') ? 25 : 0) +
                    (text.contains('serial') || text.contains('uart') ? 10 : 0);
              }

              return score(right).compareTo(score(left));
            });
      portName = ranked.first.name;
      selectionReason =
          '未要求用户输入：按 USB VID/PID、USB/Serial 描述自动选择 ${ranked.first.label}';
    }
    final Object? rawBaudRates = arguments['baudRates'];
    final List<int> baudRates = rawBaudRates is List
        ? rawBaudRates
              .map((Object? value) => int.tryParse('$value'))
              .whereType<int>()
              .where((int value) => value >= 1 && value <= 12000000)
              .take(16)
              .toList(growable: false)
        : SerialAutoDetector.defaultBaudRates;
    final Map<String, Object?> result = await SerialAutoDetector.detect(
      portName: portName,
      baudRates: baudRates.isEmpty
          ? SerialAutoDetector.defaultBaudRates
          : baudRates,
      listenDuration: Duration(
        milliseconds: _integer(arguments['listenMs'], 300).clamp(100, 3000),
      ),
      open: _serialOpener ?? SerialPortService.open,
    );
    return <String, Object?>{
      ...result,
      'selectionReason': selectionReason,
      'detectedPorts': <Map<String, Object?>>[
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
      dataBits: _integer(arguments['dataBits'], 8),
      stopBits: _integer(arguments['stopBits'], 1),
      parity: _enumValue(
        SerialParity.values,
        arguments['parity'],
        SerialParity.none,
      ),
      flowControl: _enumValue(
        SerialFlowControl.values,
        arguments['flowControl'],
        SerialFlowControl.none,
      ),
    );
    final SerialDataMode mode = arguments['mode'] == 'hex'
        ? SerialDataMode.hex
        : SerialDataMode.text;
    final int waitMs = _integer(arguments['waitMs'], 3000).clamp(50, 30000);
    final SerialPortSession session =
        await (_serialOpener ?? SerialPortService.open)(settings);
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
      final int sent = output.isEmpty ? 0 : await session.send(output);
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

  Future<Map<String, Object?>> _openSerialSession(
    Map<String, Object?> arguments,
  ) => _connectionSessions.openSerial(
    SerialConnectionSettings(
      portName: (arguments['port'] ?? '').toString(),
      baudRate: _integer(arguments['baudRate'], 115200),
      dataBits: _integer(arguments['dataBits'], 8),
      stopBits: _integer(arguments['stopBits'], 1),
      parity: _enumValue(
        SerialParity.values,
        arguments['parity'],
        SerialParity.none,
      ),
      flowControl: _enumValue(
        SerialFlowControl.values,
        arguments['flowControl'],
        SerialFlowControl.none,
      ),
    ),
  );

  Future<Map<String, Object?>> _describeTool(
    Map<String, Object?> arguments,
  ) async {
    final String toolId = (arguments['toolId'] ?? '').toString().trim();
    final HarnessToolDefinition? tool = _definitions[toolId];
    if (tool == null) throw FormatException('未知工具 ID：$toolId');
    final Map<String, Object?> schema = tool.inputSchema;
    final Map<String, Object?> properties =
        (schema['properties'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final Set<String> required =
        ((schema['required'] as List?) ?? const <Object?>[])
            .map((Object? value) => '$value')
            .toSet();
    return <String, Object?>{
      ...tool.toJson(),
      'parameters': <Map<String, Object?>>[
        for (final MapEntry<String, Object?> entry in properties.entries)
          <String, Object?>{
            'name': entry.key,
            'required': required.contains(entry.key),
            if (entry.value is Map)
              ...(entry.value as Map).cast<String, Object?>(),
          },
      ],
      'configurationPolicy': <String, Object?>{
        'automaticFirst': true,
        'askUserOnlyFor': const <String>[
          '账号或登录身份无法从保存记录推断时',
          '密码、API Key、Token、私钥口令等秘密',
          '破坏性操作的明确目标与确认',
        ],
        'doNotAskFor': const <String>[
          '可枚举的设备、端口和路径',
          '可通过 inspect/list/status 得到的运行参数',
          '可安全试探的串口波特率、帧格式和流控',
        ],
      },
    };
  }

  Future<Map<String, Object?>> _readHarnessDiagnostics(
    Map<String, Object?> arguments,
  ) async {
    final int limit = _integer(arguments['limit'], 20).clamp(1, 50);
    final bool includeTail = arguments['includeLogTail'] != false;
    final List<HarnessRuntimeLogEntry> logs =
        await HarnessRuntimeLogStore.listLogs();
    final List<HarnessToolActivity> activities =
        await HarnessToolActivityStore.load(const <String>{});
    final HarnessRuntimeLogEntry? latest = logs.firstOrNull;
    return <String, Object?>{
      'debugDirectory': HarnessRuntimeLogStore.rootPath,
      'runtimeLogs': <Map<String, Object?>>[
        for (final HarnessRuntimeLogEntry entry in logs.take(limit))
          <String, Object?>{
            'name': entry.name,
            'path': entry.path,
            'size': entry.size,
            'modified': entry.modified.toUtc().toIso8601String(),
          },
      ],
      if (includeTail && latest != null)
        'latestLogTail': await HarnessRuntimeLogStore.readTail(
          latest.path,
          maxBytes: 16 * 1024,
        ),
      'toolCalls': <Map<String, Object?>>[
        for (final HarnessToolActivity activity in activities.take(limit))
          activity.toJson(),
      ],
      'loggingEnabledByDefault': true,
      'privacy': 'API Key、密码、Token、Authorization 等敏感字段不会原样返回',
    };
  }

  Future<Map<String, Object?>> _readSerialSession(
    Map<String, Object?> arguments,
  ) async => _connectionSessions.readSerial(
    (arguments['sessionId'] ?? '').toString(),
    clear: arguments['clear'] != false,
    mode: arguments['mode'] == 'hex' ? SerialDataMode.hex : SerialDataMode.text,
  );

  Future<Map<String, Object?>> _writeSerialSession(
    Map<String, Object?> arguments,
  ) => _connectionSessions.writeSerial(
    (arguments['sessionId'] ?? '').toString(),
    (arguments['data'] ?? '').toString(),
    mode: arguments['mode'] == 'hex' ? SerialDataMode.hex : SerialDataMode.text,
    lineEnding: _enumValue(
      SerialLineEnding.values,
      arguments['lineEnding'],
      SerialLineEnding.none,
    ),
  );

  Future<Map<String, Object?>> _closeSerialSession(
    Map<String, Object?> arguments,
  ) => _connectionSessions.closeSerial(
    (arguments['sessionId'] ?? '').toString(),
  );

  Future<AdbCommandResult> _checkAdbHealth(String serial) {
    final String executable =
        _adbExecutable ?? AdbService.bundledExecutablePath();
    if (_adbRunner != null) {
      return _adbRunner(executable, <String>['-s', serial, 'get-state']);
    }
    return AdbService.runCommand(
      executable,
      <String>['-s', serial, 'get-state'],
      timeout: const Duration(seconds: 5),
      audit: AdbCommandAudit(
        toolId: adbSessionStatusId,
        toolName: 'ADB 长连接心跳',
        target: serial,
        recorder: _activityRecorder,
      ),
    );
  }

  Future<Map<String, Object?>> _openAdbSession(
    Map<String, Object?> arguments,
  ) => _connectionSessions.openAdb(
    (arguments['serial'] ?? '').toString(),
    heartbeatSeconds: _integer(arguments['heartbeatSeconds'], 10),
  );

  Future<Map<String, Object?>> _adbSessionStatus(
    Map<String, Object?> arguments,
  ) =>
      _connectionSessions.refreshAdb((arguments['sessionId'] ?? '').toString());

  Future<Map<String, Object?>> _closeAdbSession(
    Map<String, Object?> arguments,
  ) async =>
      _connectionSessions.closeAdb((arguments['sessionId'] ?? '').toString());

  Future<void> dispose() => _connectionSessions.dispose();

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) => values.where((T value) => value.name == '$raw').firstOrNull ?? fallback;

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

  Future<Map<String, Object?>> _listGitRemoteRefs(
    Map<String, Object?> arguments,
  ) async {
    final int timeoutSeconds = _integer(
      arguments['timeoutSeconds'],
      30,
    ).clamp(5, 120);
    final List<GitRemoteReference> refs =
        await GitRepositoryService.listRemoteReferences(
          (arguments['remoteUrl'] ?? '').toString(),
          pattern: (arguments['pattern'] ?? '').toString(),
          timeout: Duration(seconds: timeoutSeconds),
        );
    return <String, Object?>{
      'remoteUrl': _redactedGitRemote(arguments['remoteUrl']),
      'refCount': refs.length,
      'refs': <Map<String, Object?>>[
        for (final GitRemoteReference ref in refs) ref.toJson(),
      ],
      'readOnly': true,
      'evidenceSource': 'bundled-git-ls-remote',
    };
  }

  Future<Map<String, Object?>> _readGitRemoteFile(
    Map<String, Object?> arguments,
  ) async => (await GitRepositoryService.readRemoteTextFile(
    (arguments['remoteUrl'] ?? '').toString(),
    ref: (arguments['ref'] ?? '').toString(),
    path: (arguments['path'] ?? '').toString(),
    maxBytes: _integer(
      arguments['maxBytes'],
      1024 * 1024,
    ).clamp(1, 2 * 1024 * 1024),
    timeout: Duration(
      seconds: _integer(arguments['timeoutSeconds'], 60).clamp(5, 180),
    ),
  )).toJson();

  Future<Map<String, Object?>> _cloneGitMinimal(
    Map<String, Object?> arguments,
  ) async => (await GitRepositoryService.cloneMinimal(
    (arguments['remoteUrl'] ?? '').toString(),
    destination: (arguments['destination'] ?? '').toString(),
    ref: (arguments['ref'] ?? 'master').toString(),
    depth: _integer(arguments['depth'], 1).clamp(1, 100),
    timeout: Duration(
      seconds: _integer(arguments['timeoutSeconds'], 300).clamp(30, 1800),
    ),
  )).toJson();

  static String _redactedGitRemote(Object? raw) {
    final String value = (raw ?? '').toString();
    final Uri? uri = Uri.tryParse(value);
    if (uri != null && uri.hasAuthority && uri.userInfo.isNotEmpty) {
      return uri.replace(userInfo: uri.userInfo.split(':').first).toString();
    }
    return value;
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

  Future<Map<String, Object?>> _downloadNetworkFile(
    Map<String, Object?> arguments,
  ) async {
    final Uri? url = Uri.tryParse((arguments['url'] ?? '').toString().trim());
    if (url == null) throw const FormatException('URL 格式无效');
    final String requestedDirectory = (arguments['outputDirectory'] ?? '')
        .toString()
        .trim();
    final String directory = requestedDirectory.isNotEmpty
        ? Directory(requestedDirectory).absolute.path
        : (_downloadDirectory?.trim().isNotEmpty == true
              ? Directory(_downloadDirectory!).absolute.path
              : PlatformStorageLayout.current().downloadsDirectory);
    final int timeoutSeconds =
        (arguments['timeoutSeconds'] as num?)?.toInt().clamp(5, 1800) ?? 300;
    final int maxBytes =
        (arguments['maxBytes'] as num?)?.toInt().clamp(1, 8589934592) ??
        2147483648;
    final NetworkDownloadResult result = await const NetworkDownloadService()
        .download(
          NetworkDownloadRequest(
            url: url,
            outputDirectory: directory,
            fileName: (arguments['fileName'] ?? '').toString(),
            overwrite: arguments['overwrite'] == true,
            expectedSha256: (arguments['expectedSha256'] ?? '').toString(),
            timeout: Duration(seconds: timeoutSeconds),
            maxBytes: maxBytes,
          ),
        );
    return result.toJson();
  }

  Future<Map<String, Object?>> _inspectLarkCli(
    Map<String, Object?> arguments,
  ) => _larkCliService.inspect();

  Future<Map<String, Object?>> _larkCliAuthStatus(
    Map<String, Object?> arguments,
  ) => _larkCliService.authStatus();

  Future<Map<String, Object?>> _larkCliSchema(Map<String, Object?> arguments) =>
      _larkCliService.schema((arguments['command'] ?? '').toString());

  Future<Map<String, Object?>> _executeLarkCli(Map<String, Object?> arguments) {
    final Object? rawArguments = arguments['arguments'];
    if (rawArguments is! List) {
      throw const FormatException('arguments 必须是字符串数组');
    }
    final List<String> cliArguments = rawArguments
        .map((Object? value) => value is String ? value : '')
        .toList(growable: false);
    final int timeoutSeconds =
        (arguments['timeoutSeconds'] as num?)?.toInt().clamp(5, 1800) ?? 300;
    return _larkCliService.execute(
      cliArguments,
      timeout: Duration(seconds: timeoutSeconds),
    );
  }

  Future<Map<String, Object?>> _listLanPeers(
    Map<String, Object?> arguments,
  ) async => <String, Object?>{
    'running': LanPeerDiscoveryService.instance.running,
    'peers': <Map<String, Object?>>[
      for (final VibekitsLanPeer peer in LanPeerDiscoveryService.instance.peers)
        peer.toJson(),
    ],
    'security': '发现不授予控制权；配对需主机批准Ed25519公钥，控制工具仍需APP审批',
  };

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
              ...() {
                final RemoteConnectionStatus status =
                    RemoteConnectionStatusRegistry.statusFor(profile.id);
                return <String, Object?>{
                  'status': status.online ? 'online' : 'offline',
                  'activeConnections': status.activeConnections,
                  'activeKinds': status.kinds,
                  'connectedSinceEpochMs': status.connectedSinceEpochMs,
                };
              }(),
              'id': profile.id,
              'name': profile.name,
              'mode': profile.mode.name,
              'host': profile.host,
              'port': profile.port,
              'user': profile.user,
              'hostKeyPinned': profile.hostKeyFingerprint != null,
              'hasIdentityFile': profile.identityFile != null,
              'lastUsedEpochMs': profile.lastUsedEpochMs,
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
    final String root = _validatedAnalysisRoot(arguments);
    final int maxResults = _analysisMaxResults(arguments);
    final SystemDriveAnalysis analysis =
        await SystemDriveAnalysisRunner.analyze(
          root,
          cancellationToken: CleanupCancellationToken(),
          onProgress: (_) {},
        );
    return _serializeSystemDriveAnalysis(analysis, maxResults: maxResults);
  }

  Future<Map<String, Object?>> _startSystemDriveAnalysis(
    Map<String, Object?> arguments,
  ) async {
    final String root = _validatedAnalysisRoot(arguments);
    final int maxResults = _analysisMaxResults(arguments);
    final String rootKey = _normalizedAnalysisRoot(root);
    final _DriveAnalysisTask? existing = _driveAnalysisTasks.values
        .where(
          (_DriveAnalysisTask task) =>
              task.rootKey == rootKey &&
              task.phase == _DriveAnalysisPhase.running,
        )
        .firstOrNull;
    if (existing != null) {
      return <String, Object?>{
        ...existing.statusJson(),
        'reused': true,
        'instruction': '相同根目录正在分析；请轮询 analyze_drive_status，禁止重复启动。',
      };
    }
    final String taskId =
        'drive-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final _DriveAnalysisTask task = _DriveAnalysisTask(
      id: taskId,
      root: root,
      rootKey: rootKey,
      maxResults: maxResults,
      token: CleanupCancellationToken(),
      startedAt: DateTime.now(),
    );
    _driveAnalysisTasks[taskId] = task;
    unawaited(_runDriveAnalysisTask(task));
    return <String, Object?>{
      ...task.statusJson(),
      'reused': false,
      'instruction': '分析在后台运行；请轮询 analyze_drive_status，禁止重复启动。',
    };
  }

  Future<void> _runDriveAnalysisTask(_DriveAnalysisTask task) async {
    try {
      final SystemDriveAnalysis analysis =
          await SystemDriveAnalysisRunner.analyze(
            task.root,
            cancellationToken: task.token,
            onProgress: (SystemDriveAnalysisProgress progress) {
              task
                ..currentPath = progress.currentPath
                ..visitedEntries = progress.visitedEntries
                ..measuredBytes = progress.measuredBytes
                ..completedRootEntries = progress.completedRootEntries
                ..totalRootEntries = progress.totalRootEntries
                ..updatedAt = DateTime.now();
            },
          );
      final Map<String, Object?> result = await _serializeSystemDriveAnalysis(
        analysis,
        maxResults: task.maxResults,
      );
      task
        ..result = result
        ..phase = analysis.cancelled
            ? _DriveAnalysisPhase.cancelled
            : _DriveAnalysisPhase.completed
        ..updatedAt = DateTime.now();
    } on Object catch (error) {
      task
        ..phase = _DriveAnalysisPhase.failed
        ..error = _safeErrorText(error)
        ..updatedAt = DateTime.now();
    }
  }

  Future<Map<String, Object?>> _systemDriveAnalysisStatus(
    Map<String, Object?> arguments,
  ) async {
    final String taskId = (arguments['taskId'] ?? '').toString().trim();
    final _DriveAnalysisTask? task = _driveAnalysisTasks[taskId];
    if (task == null) throw StateError('磁盘分析任务不存在或 App 已重启');
    final int waitSeconds = switch (arguments['waitSeconds']) {
      final int number => number,
      final num number => number.toInt(),
      final Object value => int.tryParse(value.toString()) ?? 20,
      null => 20,
    };
    if (waitSeconds < 0 || waitSeconds > 45) {
      throw const FormatException('waitSeconds 必须在 0..45');
    }
    final DateTime deadline = DateTime.now().add(
      Duration(seconds: waitSeconds),
    );
    while (task.phase == _DriveAnalysisPhase.running &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return task.statusJson(includeResult: true);
  }

  Future<Map<String, Object?>> _cancelSystemDriveAnalysis(
    Map<String, Object?> arguments,
  ) async {
    final String taskId = (arguments['taskId'] ?? '').toString().trim();
    final _DriveAnalysisTask? task = _driveAnalysisTasks[taskId];
    if (task == null) throw StateError('磁盘分析任务不存在或 App 已重启');
    if (task.phase == _DriveAnalysisPhase.running) task.token.cancel();
    return <String, Object?>{
      ...task.statusJson(),
      'cancellationRequested': task.phase == _DriveAnalysisPhase.running,
    };
  }

  String _validatedAnalysisRoot(Map<String, Object?> arguments) {
    final String root = (arguments['root'] ?? '').toString().trim();
    if (root.isEmpty || !Directory(root).isAbsolute) {
      throw const FormatException('root 必须是磁盘或目录的绝对路径');
    }
    if (!Directory(root).existsSync()) {
      throw const FormatException('root 指向的目录不存在');
    }
    return Directory(root).absolute.path;
  }

  int _analysisMaxResults(Map<String, Object?> arguments) {
    final int value = switch (arguments['maxResults']) {
      final int number => number,
      final num number => number.toInt(),
      final Object value => int.tryParse(value.toString()) ?? 50,
      null => 50,
    };
    if (value < 10 || value > 200) {
      throw const FormatException('maxResults 必须在 10..200');
    }
    return value;
  }

  String _normalizedAnalysisRoot(String root) =>
      Directory(root).absolute.path
          .replaceAll('/', Platform.pathSeparator)
          .replaceAll(RegExp(r'[\\/]+$'), '')
          .toLowerCase();

  Future<Map<String, Object?>> _serializeSystemDriveAnalysis(
    SystemDriveAnalysis analysis, {
    required int maxResults,
  }) async {
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
          .take(maxResults)
          .map((SystemDriveEntryAssessment item) => item.toJson())
          .toList(growable: false),
      'softwareOwners': insights.softwareOwners
          .take(maxResults)
          .map((SystemDriveEntryAssessment item) => item.toJson())
          .toList(growable: false),
      'softwareStorage': software
          .take(maxResults)
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
      'entries': analysis.entries
          .take(maxResults)
          .map(entry)
          .toList(growable: false),
      'breakdownEntries': analysis.breakdownEntries
          .take(maxResults)
          .map(entry)
          .toList(growable: false),
      'truncated':
          analysis.entries.length > maxResults ||
          analysis.breakdownEntries.length > maxResults ||
          insights.priorities.length > maxResults ||
          software.length > maxResults,
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
  static Map<String, Object?> _audioProperties({bool includePath = false}) =>
      <String, Object?>{
        if (includePath) 'path': _string('PCM/WAV 文件绝对路径'),
        'sampleRate': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'description': 'RAW PCM 采样率，默认 48000',
        },
        'channels': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 8,
          'description': 'RAW PCM 声道数，默认 2',
        },
        'bitsPerSample': const <String, Object?>{
          'type': 'integer',
          'enum': <int>[8, 16, 24, 32],
          'description': 'RAW PCM 位深，默认 16',
        },
        'signed': const <String, Object?>{
          'type': 'boolean',
          'description': 'RAW PCM 是否有符号，默认 true',
        },
        'littleEndian': const <String, Object?>{
          'type': 'boolean',
          'description': 'RAW PCM 是否小端，默认 true',
        },
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
      'properties': <String, Object?>{
        for (final MapEntry<String, Object?> entry in properties.entries)
          entry.key: entry.value is Map
              ? <String, Object?>{
                  ...(entry.value as Map).cast<String, Object?>(),
                  if (!(entry.value as Map).containsKey('description'))
                    'description': '由用户任务、保存记录或前置发现工具获得；无值时采用工具默认行为',
                }
              : entry.value,
      },
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
    if (toolId == systemResourcesId) {
      final String serial = (arguments['adbSerial'] ?? '').toString().trim();
      return serial.isEmpty ? '本机' : serial;
    }
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
      adbSessionOpenId,
    }.contains(toolId)) {
      return (arguments['serial'] ?? '').toString();
    }
    if (<String>{serialTransactId, serialSessionOpenId}.contains(toolId)) {
      return (arguments['port'] ?? '').toString();
    }
    if (<String>{
      adbSessionStatusId,
      adbSessionCloseId,
      serialSessionReadId,
      serialSessionWriteId,
      serialSessionCloseId,
    }.contains(toolId)) {
      return (arguments['sessionId'] ?? '').toString();
    }
    if (toolId == apiRequestId || toolId == networkDownloadId) {
      return (arguments['url'] ?? '').toString();
    }
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
    if (toolId == gitListRemoteRefsId || toolId == gitReadRemoteFileId) {
      return _redactedGitRemote(arguments['remoteUrl']);
    }
    if (toolId == gitCloneMinimalId) {
      return '${_redactedGitRemote(arguments['remoteUrl'])} → '
          '${arguments['destination'] ?? ''}';
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
    if (toolId == audioInspectId || toolId == audioPlayId) {
      return (arguments['path'] ?? '').toString();
    }
    if (toolId == audioPcmToWavId) {
      return '${arguments['inputPath'] ?? ''} → ${arguments['outputPath'] ?? ''}';
    }
    if (toolId == audioGenerateToneId) {
      return (arguments['outputPath'] ?? '').toString();
    }
    if (toolId.startsWith('vibekits.windows_node.')) {
      return (arguments['rootPath'] ?? WindowsTestNodeService.requiredRoot)
          .toString();
    }
    return (arguments['input'] ?? toolId).toString();
  }
}

enum _DriveAnalysisPhase { running, completed, failed, cancelled }

class _DriveAnalysisTask {
  _DriveAnalysisTask({
    required this.id,
    required this.root,
    required this.rootKey,
    required this.maxResults,
    required this.token,
    required this.startedAt,
  }) : updatedAt = startedAt;

  final String id;
  final String root;
  final String rootKey;
  final int maxResults;
  final CleanupCancellationToken token;
  final DateTime startedAt;
  DateTime updatedAt;
  _DriveAnalysisPhase phase = _DriveAnalysisPhase.running;
  String currentPath = '';
  int visitedEntries = 0;
  int measuredBytes = 0;
  int completedRootEntries = 0;
  int totalRootEntries = 0;
  Map<String, Object?>? result;
  String? error;

  Map<String, Object?> statusJson({bool includeResult = false}) =>
      <String, Object?>{
        'taskId': id,
        'root': root,
        'phase': phase.name,
        'running': phase == _DriveAnalysisPhase.running,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'progress': <String, Object?>{
          'currentPath': currentPath,
          'visitedEntries': visitedEntries,
          'measuredBytes': measuredBytes,
          'completedRootEntries': completedRootEntries,
          'totalRootEntries': totalRootEntries,
        },
        if (error != null) 'error': error,
        if (includeResult && result != null) 'result': result,
      };
}

String _safeErrorText(Object error) {
  final String text = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return text.length <= 300 ? text : '${text.substring(0, 300)}…';
}
