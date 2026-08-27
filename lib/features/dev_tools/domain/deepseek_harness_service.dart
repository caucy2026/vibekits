import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../app/platform_process_lifecycle.dart';
import '../../../app/platform_storage_layout.dart';
import 'harness_session_store.dart';
import 'harness_tool_bridge.dart';
import 'harness_tool_server.dart';
import 'harness_agent_preferences.dart';

class HarnessEnvironmentReport {
  const HarnessEnvironmentReport({
    required this.ready,
    required this.nodeVersion,
    required this.npxVersion,
    this.baseUrl,
    this.model,
    required this.message,
  });
  final bool ready;
  final String? nodeVersion;
  final String? npxVersion;
  final String? baseUrl;
  final String? model;
  final String message;
}

class HarnessLaunchSpec {
  const HarnessLaunchSpec({required this.workspace, this.port = 3080});
  static const String packageSpec = '@deepseek-ai/dsh@0.1.0-rc.7';
  final String workspace;
  final int port;
  Uri get url => Uri.parse('http://127.0.0.1:$port');
  List<String> get arguments => <String>['web', '--port', '$port'];
  void validate() {
    if (port < 1024 || port > 65535) {
      throw const FormatException('端口必须在 1024 到 65535 之间');
    }
    final Directory directory = Directory(workspace.trim());
    if (workspace.trim().isEmpty || !directory.isAbsolute) {
      throw const FormatException('请选择绝对路径的工作区');
    }
    if (!directory.existsSync()) {
      throw const FormatException('工作区不存在或无法访问');
    }
  }
}

class HarnessAgentRequest {
  const HarnessAgentRequest({
    required this.workspace,
    required this.prompt,
    this.apiKey = '',
    this.baseUrl = DeepSeekHarnessService.defaultBaseUrl,
    this.model = DeepSeekHarnessService.defaultModel,
    this.debugDirectory = '',
    this.permissionMode = HarnessAgentPermissionMode.assisted,
    this.approveTool,
    this.toolBridge,
    this.allowedToolIds = const <String>{},
  });
  final String workspace;
  final String prompt;
  final String apiKey;
  final String baseUrl;
  final String model;
  final String debugDirectory;
  final HarnessAgentPermissionMode permissionMode;
  final HarnessToolApproval? approveTool;
  final VibekitsHarnessToolBridge? toolBridge;
  final Set<String> allowedToolIds;
  String get nativeSandboxMode => switch (permissionMode) {
    HarnessAgentPermissionMode.requestApproval ||
    HarnessAgentPermissionMode.assisted => 'workspace-write',
    HarnessAgentPermissionMode.fullAccess => 'danger-full-access',
  };
  List<String> get arguments => <String>[
    '--profile',
    'headless',
    prompt.trim(),
  ];
  void validate() {
    final Directory directory = Directory(workspace.trim());
    if (workspace.trim().isEmpty || !directory.isAbsolute) {
      throw const FormatException('请选择绝对路径的工作区');
    }
    if (!directory.existsSync()) {
      throw const FormatException('工作区不存在或无法访问');
    }
    if (prompt.trim().isEmpty) {
      throw const FormatException('请输入要交给智能体的任务');
    }
    if (debugDirectory.trim().isNotEmpty &&
        !Directory(debugDirectory.trim()).isAbsolute) {
      throw const FormatException('调试目录必须是绝对路径');
    }
  }
}

class HarnessWebRequest {
  const HarnessWebRequest({
    required this.workspace,
    required this.apiKey,
    required this.port,
    this.baseUrl = DeepSeekHarnessService.defaultBaseUrl,
    this.model = DeepSeekHarnessService.defaultModel,
    this.debugDirectory = '',
    this.approveTool,
    this.toolBridge,
  });

  final String workspace;
  final String apiKey;
  final int port;
  final String baseUrl;
  final String model;
  final String debugDirectory;
  final HarnessToolApproval? approveTool;
  final VibekitsHarnessToolBridge? toolBridge;

  Uri get url => Uri.parse('http://127.0.0.1:$port');
  List<String> get arguments => <String>['web', '--port', '$port'];

  void validate() {
    final Directory directory = Directory(workspace.trim());
    if (workspace.trim().isEmpty || !directory.isAbsolute) {
      throw const FormatException('请选择绝对路径的工作区');
    }
    if (!directory.existsSync()) {
      throw const FormatException('工作区不存在或无法访问');
    }
    if (port < 1024 || port > 65535) {
      throw const FormatException('端口必须在 1024 到 65535 之间');
    }
    if (debugDirectory.trim().isNotEmpty &&
        !Directory(debugDirectory.trim()).isAbsolute) {
      throw const FormatException('调试目录必须是绝对路径');
    }
  }
}

class HarnessDebugPaths {
  const HarnessDebugPaths({
    required this.root,
    required this.logs,
    required this.screenshots,
    required this.temp,
  });

  final Directory root;
  final Directory logs;
  final Directory screenshots;
  final Directory temp;
}

enum HarnessCredentialMigration {
  noLegacyCredential,
  alreadyConfigured,
  migrated,
}

abstract interface class HarnessSessionHandle {
  Stream<String> get output;
  Future<int> get exitCode;
  bool get running;
  Uri get url;
  Future<void> stop();
}

abstract interface class HarnessAgentHandle {
  Stream<String> get output;
  Future<int> get exitCode;
  bool get running;
  Future<void> stop();
}

typedef HarnessEnvironmentChecker = Future<HarnessEnvironmentReport> Function();
typedef HarnessSessionStarter = Future<HarnessSessionHandle> Function(
  HarnessLaunchSpec spec,
);
typedef HarnessBrowserOpener = Future<void> Function(Uri url);
typedef HarnessAgentRunner = Future<HarnessAgentHandle> Function(
  HarnessAgentRequest request,
);
typedef HarnessModelLister = Future<List<String>> Function(
  String apiKey,
  String baseUrl,
);

abstract final class DeepSeekHarnessService {
  /// Official DSH ships optional multi-provider, telemetry and HMR plugins.
  /// VibeKits currently exposes only DeepSeek inside a production WebView, so
  /// loading those dormant dependency trees on every cold start only makes
  /// Windows inspect thousands of files before the local server can bind.
  static const String harnessWebPerformancePatch =
      '- id: llm-pi-ai\n'
      '  disabled: true\n'
      '- id: session-telemetry-otel\n'
      '  disabled: true\n'
      '- id: client-hmr\n'
      '  disabled: true\n';

  static const String harnessCapabilityInstructions =
      r'''<!-- VIBEKITS_CAPABILITIES_BEGIN -->
# VibeKits Harness 工具使用准则

你运行在 VibeKits 内部。询问 APP 功能时，先调用只读工具 `vibekits.system.capability_check`，并分别报告 5 个产品一级页面、业务功能模块、`definedTools` 定义接口数和 `executableTools` 可执行接口数，不得混为一个数字。

从当前 MCP 工具目录选择 `vibekits.*` 接口；每个工具的 `description` 与 `inputSchema` 是参数唯一权威来源。参数必须是符合 Schema 的 JSON 对象。有 VibeKits 专用接口时优先调用它，不得用 shell、PowerShell、系统 ADB、系统 Git 或第三方程序绕过 APP。

遵循 `list/inspect/status → plan/preview → apply/start/send → verify/status`：先只读发现并锁定目标，再执行写入或设备控制。写数据、控制设备和破坏性操作服从当前权限模式。工具结果必须形成证据；工具存在不等于真实设备已验收。

产品一级页面：智能体（Harness）、解压缩、系统清理、文档阅读、开发工具。业务模块：计算调试、系统诊断、数据库、远程连接、网络开发、版本控制、文件工具、音频调试、编码转换、加密生成、时间文本、格式处理和虚拟化。

常用链路：串口短任务 `serial.list_ports → serial.transact`，持续调试 `serial.session_open → session_read/write → session_close`；ADB `adb.list_devices/connect → adb.*`，长连接用 `adb.session_open → session_status → session_close`；SSH/SFTP `remote.list_profiles/open_interactive → ssh_exec/sftp_*`；Git `git.inspect → backup_preview → backup_commit → backup_push → verify_remote_ref`；代理 `runtime.inspect → proxy.start → runtime.status → proxy.system_apply`，结束时恢复系统代理；虚拟机 `runtime.inspect → vm.create_disk → vm.start → runtime.status → vm.stop`。修改 VibeKits 自身前先 `project.iteration_inspect`，完成后调用 `project.build` 执行分析、接口测试和 Release 构建门禁；构建产物不得自动覆盖正在运行的 APP，安装升级必须由用户确认。

完整目录位于项目 `docs/37_HARNESS_CAPABILITY_CATALOG.md`；运行时以本轮 `capability_check` 和 MCP Schema 为准。
<!-- VIBEKITS_CAPABILITIES_END -->''';
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-v4-flash';
  static const String _deepSeekCredentialRef = 'DEEPSEEK_API_KEY';
  static Future<_HarnessRuntime>? _runtimeFuture;

  static String defaultDebugDirectory() {
    return PlatformStorageLayout.current().harnessDebugDirectory;
  }

  static String redactSensitiveOutput(String output, Iterable<String> secrets) {
    String safe = output;
    for (final String secret in secrets) {
      if (secret.isNotEmpty) safe = safe.replaceAll(secret, '[REDACTED]');
    }
    return safe;
  }

  static Future<HarnessDebugPaths> prepareDebugDirectory([
    String configured = '',
  ]) async {
    final String path = configured.trim().isEmpty
        ? defaultDebugDirectory()
        : configured.trim();
    final Directory root = Directory(path);
    if (!root.isAbsolute) {
      throw const FormatException('调试目录必须是绝对路径');
    }
    final Directory logs = Directory(
      '${root.path}${Platform.pathSeparator}logs',
    );
    final Directory screenshots = Directory(
      '${root.path}${Platform.pathSeparator}screenshots',
    );
    final Directory temp = Directory(
      '${root.path}${Platform.pathSeparator}temp',
    );
    try {
      await Future.wait(<Future<Directory>>[
        root.create(recursive: true),
        logs.create(recursive: true),
        screenshots.create(recursive: true),
        temp.create(recursive: true),
      ]);
    } on FileSystemException catch (error) {
      throw FileSystemException(
        '无法创建 Harness 调试目录，请在设置中选择可写目录',
        path,
        error.osError,
      );
    }
    return HarnessDebugPaths(
      root: root,
      logs: logs,
      screenshots: screenshots,
      temp: temp,
    );
  }

  static Future<List<String>> listModels(String apiKey, String baseUrl) async {
    final String key = apiKey.trim();
    if (key.isEmpty) throw StateError('请先填写 DeepSeek API Key');
    _validateEndpoint(baseUrl);
    final String base =
        (baseUrl.trim().isEmpty ? defaultBaseUrl : baseUrl.trim()).replaceFirst(
          RegExp(r'/+$'),
          '',
        );
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final HttpClientRequest request = await client
          .getUrl(Uri.parse('$base/models'))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final BytesBuilder bytes = BytesBuilder(copy: false);
      int length = 0;
      await for (final List<int> chunk in response.timeout(
        const Duration(seconds: 12),
      )) {
        length += chunk.length;
        if (length > 1024 * 1024) {
          throw const FormatException('模型列表响应超过 1 MiB');
        }
        bytes.add(chunk);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          response.statusCode == 401 || response.statusCode == 403
              ? 'API Key 无效或无权访问该端点'
              : '读取模型列表失败（HTTP ${response.statusCode}）',
        );
      }
      final Object? decoded = jsonDecode(
        utf8.decode(bytes.takeBytes(), allowMalformed: true),
      );
      if (decoded is! Map || decoded['data'] is! List) {
        throw const FormatException('模型列表格式不兼容');
      }
      final List<String> models =
          (decoded['data']! as List)
              .whereType<Map>()
              .map((Map item) => '${item['id'] ?? ''}'.trim())
              .where((String id) => id.isNotEmpty && id.length <= 200)
              .toSet()
              .toList(growable: false)
            ..sort();
      if (models.isEmpty) throw const FormatException('端点没有返回可用模型');
      return models;
    } on TimeoutException {
      throw TimeoutException('读取模型列表超时');
    } finally {
      client.close(force: true);
    }
  }

  static Future<HarnessEnvironmentReport> checkEnvironment() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return const HarnessEnvironmentReport(
        ready: false,
        nodeVersion: null,
        npxVersion: null,
        baseUrl: defaultBaseUrl,
        model: defaultModel,
        message: '组件测试未启动外部 Harness 进程',
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return const HarnessEnvironmentReport(
        ready: true,
        nodeVersion: null,
        npxVersion: 'mobile-native',
        baseUrl: defaultBaseUrl,
        model: defaultModel,
        message: '移动端原生 Harness 已就绪 · 直接连接模型 API，无需 Node/DSH 运行时',
      );
    }
    try {
      final _HarnessRuntime runtime = await _cachedBundledRuntime();
      final ProcessResult node = await Process.run(
        runtime.nodeExecutable,
        const <String>['--version'],
        runInShell: false,
      ).timeout(const Duration(seconds: 5));
      final String nodeVersion = '${node.stdout}'.trim();
      if (node.exitCode != 0 || !_isSupportedNode(nodeVersion)) {
        return HarnessEnvironmentReport(
          ready: false,
          nodeVersion: nodeVersion.isEmpty ? null : nodeVersion,
          npxVersion: null,
          baseUrl: defaultBaseUrl,
          model: defaultModel,
          message: 'Harness 需要 Node.js 22.19+ 或 24+',
        );
      }
      return HarnessEnvironmentReport(
        ready: true,
        nodeVersion: nodeVersion,
        npxVersion: runtime.version,
        baseUrl: defaultBaseUrl,
        model: defaultModel,
        message: '内置 Harness ${runtime.version} 已就绪',
      );
    } on TimeoutException {
      return const HarnessEnvironmentReport(
        ready: false,
        nodeVersion: null,
        npxVersion: null,
        baseUrl: defaultBaseUrl,
        model: defaultModel,
        message: 'Harness 环境检查超时',
      );
    } on Object {
      return const HarnessEnvironmentReport(
        ready: false,
        nodeVersion: null,
        npxVersion: null,
        baseUrl: defaultBaseUrl,
        model: defaultModel,
        message: '内置 Harness 运行时缺失或损坏，请重新安装 Vibekits',
      );
    }
  }

  static Future<HarnessSessionHandle> start(HarnessLaunchSpec spec) async {
    spec.validate();
    final _HarnessRuntime runtime = await _cachedBundledRuntime();
    try {
      final Process process = await Process.start(
        runtime.nodeExecutable,
        <String>[runtime.cliPath, ...spec.arguments],
        workingDirectory: spec.workspace.trim(),
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      await _bindProcessToAppLifetime(process);
      return _ProcessHarnessSession(process, spec.url);
    } on ProcessException catch (error) {
      throw StateError('无法启动官方 Harness：${error.message}');
    }
  }

  static Future<HarnessAgentHandle> startAgent(
    HarnessAgentRequest request,
  ) async {
    request.validate();
    if (request.apiKey.trim().isEmpty) {
      throw StateError('请先填写 DeepSeek API Key');
    }
    _validateEndpoint(request.baseUrl);
    if (Platform.isAndroid || Platform.isIOS) {
      return _MobileHarnessAgent.start(request);
    }
    final _HarnessRuntime runtime = await _cachedBundledRuntime();
    final HarnessDebugPaths debug = await prepareDebugDirectory(
      request.debugDirectory,
    );
    final HarnessToolServer toolServer = await HarnessToolServer.start(
      approve: request.approveTool,
      bridge: request.toolBridge,
    );
    final Directory harnessHome = await _prepareHarnessHome(
      runtime.approvalPluginPath,
    );
    final Directory nodeCompileCache = await _prepareNodeCompileCache(
      harnessHome,
    );
    try {
      final Process process = await Process.start(
        runtime.nodeExecutable,
        <String>[runtime.cliPath, ...request.arguments],
        workingDirectory: request.workspace.trim(),
        environment: <String, String>{
          if (request.apiKey.trim().isNotEmpty)
            'DEEPSEEK_API_KEY': request.apiKey.trim(),
          'DEEPSEEK_BASE_URL': request.baseUrl.trim(),
          'DEEPSEEK_MODEL': request.model.trim().isEmpty
              ? defaultModel
              : request.model.trim(),
          'DSH_HOME': harnessHome.path,
          'NODE_COMPILE_CACHE': nodeCompileCache.path,
          'NODE_COMPILE_CACHE_PORTABLE': '1',
          'DSH_TELEMETRY_MODE': 'DISABLED',
          'DSH_PERMISSION_MODE': request.nativeSandboxMode,
          'DSH_TELEMETRY_DISABLED': '1',
          'DSH_LOG_DIR': debug.logs.path,
          'VIBEKITS_DEBUG_DIR': debug.root.path,
          'VIBEKITS_SCREENSHOT_DIR': debug.screenshots.path,
          'TEMP': debug.temp.path,
          'TMP': debug.temp.path,
          'TMPDIR': debug.temp.path,
          'VIBEKITS_NODE_EXECUTABLE': runtime.nodeExecutable,
          'VIBEKITS_MCP_SERVER': runtime.mcpServerPath,
          'VIBEKITS_TOOL_BRIDGE_URL': toolServer.endpoint.toString(),
          'VIBEKITS_TOOL_BRIDGE_TOKEN': toolServer.token,
        },
        includeParentEnvironment: true,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      await _bindProcessToAppLifetime(process);
      final File logFile = File(
        '${debug.logs.path}${Platform.pathSeparator}harness-'
        '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.log',
      );
      return _ProcessHarnessAgent(
        process,
        toolServer,
        logFile,
        request.apiKey.trim(),
      );
    } on ProcessException catch (error) {
      await toolServer.close();
      throw StateError('无法启动官方 Harness 智能体：${error.message}');
    } on Object {
      await toolServer.close();
      rethrow;
    }
  }

  /// Runs the same model-driven tool loop used by the mobile Harness client.
  ///
  /// Desktop normally launches the bundled DSH process. This entry point is a
  /// bounded fallback for diagnostics when that process cannot reach its first
  /// turn; the model still has to select and invoke tools through the native
  /// Vibekits bridge.
  static HarnessAgentHandle startNativeToolAgent(HarnessAgentRequest request) {
    request.validate();
    if (request.apiKey.trim().isEmpty) {
      throw StateError('请先填写 DeepSeek API Key');
    }
    _validateEndpoint(request.baseUrl);
    return _MobileHarnessAgent.start(request);
  }

  static Future<HarnessSessionHandle> startWebAgent(
    HarnessWebRequest request,
  ) async {
    request.validate();
    _validateEndpoint(request.baseUrl);
    // Runtime discovery, writable-directory preparation and the native tool
    // bridge are independent. Running them together removes avoidable serial
    // disk waits from every Web workspace launch.
    final Future<_HarnessRuntime> runtimeFuture = _cachedBundledRuntime();
    final Future<HarnessDebugPaths> debugFuture = prepareDebugDirectory(
      request.debugDirectory,
    );
    final _HarnessRuntime runtime = await runtimeFuture;
    final HarnessDebugPaths debug = await debugFuture;
    final HarnessToolServer toolServer = await HarnessToolServer.start(
      approve: request.approveTool,
      bridge: request.toolBridge,
    );
    final Directory harnessHome = await _prepareHarnessHome(
      runtime.approvalPluginPath,
      includeApprovalBridge: false,
    );
    final Directory nodeCompileCache = await _prepareNodeCompileCache(
      harnessHome,
    );
    await migrateLegacyCredentialToOfficialStore(
      request.apiKey,
      harnessHome: harnessHome,
    );
    try {
      final Process process = await Process.start(
        runtime.nodeExecutable,
        <String>[runtime.cliPath, ...request.arguments],
        workingDirectory: request.workspace.trim(),
        environment: <String, String>{
          'DSH_HOME': harnessHome.path,
          'NODE_COMPILE_CACHE': nodeCompileCache.path,
          'NODE_COMPILE_CACHE_PORTABLE': '1',
          'DSH_TELEMETRY_MODE': 'DISABLED',
          'DSH_TELEMETRY_DISABLED': '1',
          'DSH_TOOLS_MODE': 'native',
          'DSH_LOG_DIR': debug.logs.path,
          'VIBEKITS_DEBUG_DIR': debug.root.path,
          'VIBEKITS_SCREENSHOT_DIR': debug.screenshots.path,
          'TEMP': debug.temp.path,
          'TMP': debug.temp.path,
          'TMPDIR': debug.temp.path,
          'VIBEKITS_NODE_EXECUTABLE': runtime.nodeExecutable,
          'VIBEKITS_MCP_SERVER': runtime.mcpServerPath,
          'VIBEKITS_TOOL_BRIDGE_URL': toolServer.endpoint.toString(),
          'VIBEKITS_TOOL_BRIDGE_TOKEN': toolServer.token,
        },
        includeParentEnvironment: true,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      await _bindProcessToAppLifetime(process);
      final File logFile = File(
        '${debug.logs.path}${Platform.pathSeparator}harness-web-'
        '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.log',
      );
      await logFile.writeAsString(
        '[${DateTime.now().toUtc().toIso8601String()}] '
        'pid=${process.pid} url=${request.url} bundled=true\n',
        flush: true,
      );
      return _ProcessHarnessWebSession(
        process,
        request.url,
        toolServer,
        logFile,
        request.apiKey.trim(),
      );
    } on Object {
      await toolServer.close();
      rethrow;
    }
  }

  static Future<int> findFreeLoopbackPort() async {
    final ServerSocket socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int port = socket.port;
    await socket.close();
    return port;
  }

  static void _validateEndpoint(String value) {
    final String raw = value.trim().isEmpty ? defaultBaseUrl : value.trim();
    final Uri base = Uri.parse(raw);
    if (!base.isAbsolute || (base.scheme != 'https' && base.scheme != 'http')) {
      throw const FormatException('API 地址必须是有效的 HTTP/HTTPS 地址');
    }
  }

  /// Moves a key saved by pre-official Vibekits builds into the writable
  /// credential store owned by Harness. Injecting it through the environment
  /// would intentionally make the official Models field read-only.
  static Future<HarnessCredentialMigration>
  migrateLegacyCredentialToOfficialStore(
    String legacyKey, {
    Directory? harnessHome,
  }) async {
    final String key = legacyKey.trim();
    if (key.isEmpty) return HarnessCredentialMigration.noLegacyCredential;
    final Directory home = harnessHome ?? officialHarnessHomeDirectory();
    await home.create(recursive: true);
    final File credentials = File(
      '${home.path}${Platform.pathSeparator}.credentials.yaml',
    );
    String current = '';
    if (await credentials.exists()) {
      current = await credentials.readAsString();
      if (RegExp(r'^DEEPSEEK_API_KEY\s*:', multiLine: true).hasMatch(current)) {
        return HarnessCredentialMigration.alreadyConfigured;
      }
    }
    final String separator = current.isEmpty || current.endsWith('\n')
        ? ''
        : '\n';
    await credentials.writeAsString(
      '$current$separator$_deepSeekCredentialRef: ${jsonEncode(key)}\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      final ProcessResult chmod = await Process.run('chmod', <String>[
        '600',
        credentials.path,
      ], runInShell: false);
      if (chmod.exitCode != 0) {
        throw StateError('无法限制 Harness 凭据文件权限');
      }
    }
    return HarnessCredentialMigration.migrated;
  }

  /// Fast local check used before touching the platform credential vault.
  ///
  /// Once the legacy key has been migrated, the official DSH credentials file
  /// is authoritative. Windows Credential Manager can take seconds to answer
  /// on a full or busy system drive, so reading it again on every workspace
  /// launch adds latency without changing the result.
  static Future<bool> hasOfficialDeepSeekCredential() async {
    final File credentials = File(
      '${officialHarnessHomeDirectory().path}'
      '${Platform.pathSeparator}.credentials.yaml',
    );
    if (!await credentials.exists()) return false;
    try {
      final String value = await credentials.readAsString();
      return RegExp(
        r'^DEEPSEEK_API_KEY\s*:\s*\S+',
        multiLine: true,
      ).hasMatch(value);
    } on FileSystemException {
      return false;
    }
  }

  static Directory officialHarnessHomeDirectory() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return Directory(
      Platform.isWindows
          ? '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
          : '$base${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness',
    );
  }

  static Future<Directory> _prepareHarnessHome(
    String approvalPluginPath, {
    bool includeApprovalBridge = true,
  }) async {
    final Directory home = officialHarnessHomeDirectory();
    await home.create(recursive: true);
    // Old native acceptance probes used a fresh TEMP workspace on every run.
    // Their orphaned session folders are not real user workspaces and can be
    // rediscovered by DSH as ghost rows even after the session is gone.
    await HarnessSessionStore(home: home).deleteLegacyNativeProbeSessions();
    final File patch = File(
      '${home.path}${Platform.pathSeparator}cordis.patch.yml',
    );
    final String approvalPatch = includeApprovalBridge
        ? '- insert:\n'
              '    - id: vibekits-native-approval\n'
              '      name: ${jsonEncode(Uri.file(approvalPluginPath).toString())}\n'
        : '';
    final String patchContents =
        '$harnessWebPerformancePatch- insert:\n'
        '    - id: vibekits-mcp\n'
        "      name: '@deepseek-ai/dsh-mcp-client'\n"
        '      config:\n'
        '        serverName: vibekits\n'
        '        transport: stdio\n'
        '        command: !!js process.env.VIBEKITS_NODE_EXECUTABLE\n'
        '        args:\n'
        '          - !!js process.env.VIBEKITS_MCP_SERVER\n'
        '        env:\n'
        '          VIBEKITS_TOOL_BRIDGE_URL: !!js process.env.VIBEKITS_TOOL_BRIDGE_URL\n'
        '          VIBEKITS_TOOL_BRIDGE_TOKEN: !!js process.env.VIBEKITS_TOOL_BRIDGE_TOKEN\n'
        '        failOnStartupError: true\n'
        '        toolCallTimeoutMs: 60000\n'
        '$approvalPatch';
    // This file is read on every DSH boot. Rewriting and force-flushing an
    // identical patch invalidates filesystem caches and makes Defender scan it
    // again, so only touch it when the configuration actually changes.
    final String current = await patch.exists()
        ? await patch.readAsString()
        : '';
    if (current != patchContents) {
      await patch.writeAsString(patchContents, flush: true);
    }
    await prepareHarnessCapabilityInstructions(directory: home);
    return home;
  }

  /// Installs the app-owned instruction block without overwriting user text.
  ///
  /// DSH's official agent-instructions plugin loads `$DSH_HOME/AGENTS.md` on
  /// the first turn, so this makes the live Harness aware of the VibeKits
  /// catalog in every workspace rather than only documenting it for humans.
  static Future<File> prepareHarnessCapabilityInstructions({
    Directory? directory,
  }) async {
    final Directory harnessDirectory =
        directory ?? officialHarnessHomeDirectory();
    await harnessDirectory.create(recursive: true);
    final File instructions = File(
      '${harnessDirectory.path}${Platform.pathSeparator}AGENTS.md',
    );
    final String current = await instructions.exists()
        ? await instructions.readAsString()
        : '';
    const String begin = '<!-- VIBEKITS_CAPABILITIES_BEGIN -->';
    const String end = '<!-- VIBEKITS_CAPABILITIES_END -->';
    final int beginIndex = current.indexOf(begin);
    final int endIndex = current.indexOf(end);
    final String next;
    if (beginIndex >= 0 && endIndex >= beginIndex) {
      next =
          '${current.substring(0, beginIndex)}'
          '$harnessCapabilityInstructions'
          '${current.substring(endIndex + end.length)}';
    } else {
      next = current.trim().isEmpty
          ? '$harnessCapabilityInstructions\n'
          : '${current.trimRight()}\n\n$harnessCapabilityInstructions\n';
    }
    if (next != current) {
      await instructions.writeAsString(next, flush: true);
    }
    return instructions;
  }

  static Future<_HarnessRuntime> _cachedBundledRuntime() {
    return _runtimeFuture ??= _resolveBundledRuntime().catchError((
      Object error,
    ) {
      _runtimeFuture = null;
      throw error;
    });
  }

  static Future<Directory> _prepareNodeCompileCache(
    Directory harnessHome,
  ) async {
    final Directory cache = Directory(
      '${harnessHome.path}${Platform.pathSeparator}node-compile-cache',
    );
    await cache.create(recursive: true);
    return cache;
  }

  static bool _isSupportedNode(String value) {
    final Match? match = RegExp(r'v?(\d+)\.(\d+)').firstMatch(value.trim());
    if (match == null) return false;
    final int major = int.parse(match.group(1)!);
    final int minor = int.parse(match.group(2)!);
    return (major == 22 && minor >= 19) || major >= 24;
  }

  static Future<void> openBrowser(Uri url) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw const FormatException('地址无效');
    }
    final String executable = Platform.isWindows
        ? 'rundll32.exe'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    final List<String> arguments = Platform.isWindows
        ? <String>['url.dll,FileProtocolHandler', '$url']
        : <String>['$url'];
    await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }
}

class _HarnessRuntime {
  const _HarnessRuntime({
    required this.nodeExecutable,
    required this.cliPath,
    required this.version,
    required this.mcpServerPath,
    required this.approvalPluginPath,
  });

  final String nodeExecutable;
  final String cliPath;
  final String version;
  final String mcpServerPath;
  final String approvalPluginPath;
}

Future<_HarnessRuntime> _resolveBundledRuntime() async {
  final String executableDirectory = File(Platform.resolvedExecutable)
      .parent
      .path;
  final List<Directory> candidates = <Directory>[
    Directory(
      '$executableDirectory${Platform.pathSeparator}tools${Platform.pathSeparator}harness',
    ),
    Directory(
      '${Directory.current.path}${Platform.pathSeparator}native${Platform.pathSeparator}harness${Platform.pathSeparator}${Platform.isWindows ? 'windows' : 'macos'}${Platform.pathSeparator}runtime',
    ),
  ];
  for (final Directory root in candidates) {
    final File manifest = File(
      '${root.path}${Platform.pathSeparator}harness-runtime.json',
    );
    if (!manifest.existsSync()) continue;
    final Object? decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) continue;
    final String cli = '${decoded['cli'] ?? ''}'.trim();
    final String version = '${decoded['version'] ?? ''}'.trim();
    final File node = File(
      '${root.path}${Platform.pathSeparator}${Platform.isWindows ? 'node.exe' : 'bin/node'}',
    );
    final File cliFile = File('${root.path}${Platform.pathSeparator}$cli');
    final List<File> mcpCandidates = <File>[
      File('${root.path}${Platform.pathSeparator}vibekits-mcp-server.mjs'),
      File(
        '${root.parent.parent.path}${Platform.pathSeparator}vibekits-mcp-server.mjs',
      ),
    ];
    final List<File> approvalCandidates = <File>[
      File('${root.path}${Platform.pathSeparator}vibekits-approval.mjs'),
      File(
        '${root.parent.parent.path}${Platform.pathSeparator}vibekits-approval.mjs',
      ),
    ];
    final File? mcpServer = mcpCandidates
        .where((File file) => file.existsSync())
        .firstOrNull;
    final File? approvalPlugin = approvalCandidates
        .where((File file) => file.existsSync())
        .firstOrNull;
    if (cli.isEmpty ||
        version.isEmpty ||
        !node.existsSync() ||
        !cliFile.existsSync() ||
        mcpServer == null ||
        approvalPlugin == null) {
      continue;
    }
    return _HarnessRuntime(
      nodeExecutable: node.path,
      cliPath: cliFile.path,
      version: version,
      mcpServerPath: mcpServer.path,
      approvalPluginPath: approvalPlugin.path,
    );
  }
  throw const FileSystemException('内置 Harness 运行时缺失');
}

class _MobileHarnessAgent implements HarnessAgentHandle {
  _MobileHarnessAgent._(this._request) {
    _run();
  }

  static HarnessAgentHandle start(HarnessAgentRequest request) =>
      _MobileHarnessAgent._(request);

  final HarnessAgentRequest _request;
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  HttpClient? _client;
  bool _running = true;
  bool _stopped = false;

  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool get running => _running;

  Future<void> _run() async {
    int code = 0;
    try {
      final VibekitsHarnessToolBridge bridge =
          _request.toolBridge ?? VibekitsHarnessToolBridge();
      final List<Map<String, Object?>> tools = bridge.executableCatalog
          .where(
            (HarnessToolDefinition tool) =>
                _request.allowedToolIds.isEmpty ||
                _request.allowedToolIds.contains(tool.id),
          )
          .map(
            (HarnessToolDefinition tool) => <String, Object?>{
              'type': 'function',
              'function': <String, Object?>{
                'name': _functionName(tool.id),
                'description': tool.description,
                'parameters': tool.inputSchema,
              },
            },
          )
          .toList(growable: false);
      final List<Map<String, Object?>> messages = <Map<String, Object?>>[
        <String, Object?>{
          'role': 'system',
          'content':
              '你是 Vibekits 移动端 Harness。优先使用已提供的本地工具取得真实证据；'
              '全部 APP 工具都会显式提供给你。Android 本地可执行的工具直接执行；'
              '需要 Windows/macOS 二进制、主机端口或驱动的工具会返回结构化的“需要桌面节点”结果。'
              '你必须如实告知用户，不能伪造执行成功。当前工作区：${_request.workspace}',
        },
        <String, Object?>{'role': 'user', 'content': _request.prompt.trim()},
      ];
      for (int turn = 0; turn < 6 && !_stopped; turn++) {
        final Map<String, Object?> message = await _requestCompletion(
          messages,
          tools,
        );
        if (_stopped) break;
        final List<Object?> toolCalls = message['tool_calls'] is List
            ? (message['tool_calls']! as List).cast<Object?>()
            : const <Object?>[];
        final String content = '${message['content'] ?? ''}'.trim();
        if (toolCalls.isEmpty) {
          _emit(content.isEmpty ? '任务已完成。' : content);
          break;
        }
        messages.add(message);
        for (final Object? rawCall in toolCalls) {
          if (_stopped || rawCall is! Map) break;
          final Map<Object?, Object?> call = rawCall;
          final Map<Object?, Object?> function = call['function'] is Map
              ? call['function']! as Map<Object?, Object?>
              : const <Object?, Object?>{};
          final String toolId = _toolId('${function['name'] ?? ''}'.trim());
          final Map<String, Object?> arguments = _decodeArguments(
            function['arguments'],
          );
          _emit(
            '\n[Harness 工具调用]\n工具: $toolId\n参数: ${jsonEncode(arguments)}\n',
          );
          final HarnessToolCallResult result = await bridge.invoke(
            toolId: toolId,
            arguments: arguments,
            approve:
                _request.approveTool ??
                (HarnessToolApprovalRequest _) async => false,
          );
          _emit(
            '[Harness 工具结果]\n工具: $toolId\n'
            '状态: ${result.ok ? '成功' : '失败'}\n'
            '结果: ${jsonEncode(result.toJson())}\n',
          );
          messages.add(<String, Object?>{
            'role': 'tool',
            'tool_call_id': '${call['id'] ?? toolId}',
            'content': jsonEncode(result.toJson()),
          });
        }
      }
    } on Object catch (error) {
      code = _stopped ? 0 : 1;
      if (!_stopped) _emit('移动端 Harness 请求失败：$error');
    } finally {
      _running = false;
      _client?.close(force: true);
      if (!_exit.isCompleted) _exit.complete(code);
      await _output.close();
    }
  }

  Future<Map<String, Object?>> _requestCompletion(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
  ) async {
    final String base =
        (_request.baseUrl.trim().isEmpty
                ? DeepSeekHarnessService.defaultBaseUrl
                : _request.baseUrl.trim())
            .replaceFirst(RegExp(r'/+$'), '');
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    _client = client;
    final HttpClientRequest http = await client
        .postUrl(Uri.parse('$base/chat/completions'))
        .timeout(const Duration(seconds: 12));
    http.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${_request.apiKey.trim()}',
    );
    http.headers.contentType = ContentType.json;
    http.write(
      jsonEncode(<String, Object?>{
        'model': _request.model.trim().isEmpty
            ? DeepSeekHarnessService.defaultModel
            : _request.model.trim(),
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
        if (tools.isNotEmpty) 'tool_choice': 'auto',
        'stream': false,
      }),
    );
    final HttpClientResponse response = await http.close().timeout(
      const Duration(seconds: 90),
    );
    final BytesBuilder bytes = BytesBuilder(copy: false);
    int length = 0;
    await for (final List<int> chunk in response.timeout(
      const Duration(seconds: 90),
    )) {
      length += chunk.length;
      if (length > 8 * 1024 * 1024) {
        throw const FormatException('模型响应超过 8 MiB');
      }
      bytes.add(chunk);
    }
    final String body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        response.statusCode == 401 || response.statusCode == 403
            ? 'API Key 无效或无权访问当前模型'
            : '模型接口返回 HTTP ${response.statusCode}：${_safeError(body)}',
      );
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map || decoded['choices'] is! List) {
      throw const FormatException('模型响应格式不兼容');
    }
    final List<Object?> choices = (decoded['choices']! as List).cast<Object?>();
    if (choices.isEmpty || choices.first is! Map) {
      throw const FormatException('模型没有返回回复');
    }
    final Object? rawMessage = (choices.first as Map)['message'];
    if (rawMessage is! Map) throw const FormatException('模型回复缺少 message');
    return rawMessage.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }

  static String _functionName(String toolId) => toolId.replaceAll('.', '__');

  static String _toolId(String functionName) =>
      functionName.replaceAll('__', '.');

  static Map<String, Object?> _decodeArguments(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>(
        (Object? key, Object? item) => MapEntry<String, Object?>('$key', item),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map<String, Object?>(
          (Object? key, Object? item) =>
              MapEntry<String, Object?>('$key', item),
        );
      }
    }
    return <String, Object?>{};
  }

  static String _safeError(String body) {
    final String compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 300 ? compact : '${compact.substring(0, 300)}…';
  }

  void _emit(String value) {
    if (!_stopped && !_output.isClosed) {
      _output.add(
        DeepSeekHarnessService.redactSensitiveOutput(value, <String>[
          _request.apiKey.trim(),
        ]),
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _stopped = true;
    _running = false;
    _client?.close(force: true);
    await _exit.future.timeout(const Duration(seconds: 3), onTimeout: () => 0);
  }
}

class _ProcessHarnessAgent implements HarnessAgentHandle {
  _ProcessHarnessAgent(
    this._process,
    this._toolServer,
    File logFile,
    this._apiKey,
  ) {
    _log = logFile.openWrite(mode: FileMode.append);
    _stdout = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((String chunk) => _forward('stdout', chunk));
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((String chunk) => _forward('stderr', chunk));
    _exitCode = _process.exitCode.then((int code) async {
      _running = false;
      await _stdout.cancel();
      await _stderr.cancel();
      _log.writeln(
        '[${DateTime.now().toUtc().toIso8601String()}] exitCode=$code',
      );
      await _log.flush();
      await _log.close();
      await _output.close();
      await _toolServer.close();
      await PlatformProcessLifecycle.releaseProcessTree(_process.pid);
      return code;
    });
  }

  final Process _process;
  final HarnessToolServer _toolServer;
  final String _apiKey;
  final StreamController<String> _output = StreamController<String>();
  late final IOSink _log;
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<int> _exitCode;
  bool _running = true;

  void _forward(String channel, String chunk) {
    final String safeChunk = DeepSeekHarnessService.redactSensitiveOutput(
      chunk,
      <String>[_apiKey],
    );
    _log.write(
      '[${DateTime.now().toUtc().toIso8601String()}][$channel] $safeChunk',
    );
    _output.add(safeChunk);
  }

  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int> get exitCode => _exitCode;
  @override
  bool get running => _running;
  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _stopProcessTree(_process);
    await _exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}

class _ProcessHarnessSession implements HarnessSessionHandle {
  _ProcessHarnessSession(this._process, this.url) {
    _stdout = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_output.add);
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_output.add);
    _exitCode = _process.exitCode.then((int code) async {
      _running = false;
      await _stdout.cancel();
      await _stderr.cancel();
      await _output.close();
      await PlatformProcessLifecycle.releaseProcessTree(_process.pid);
      return code;
    });
  }

  final Process _process;
  final StreamController<String> _output = StreamController<String>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<int> _exitCode;
  bool _running = true;
  @override
  final Uri url;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int> get exitCode => _exitCode;
  @override
  bool get running => _running;
  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _stopProcessTree(_process);
    await _exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}

class _ProcessHarnessWebSession implements HarnessSessionHandle {
  _ProcessHarnessWebSession(
    this._process,
    this.url,
    this._toolServer,
    File logFile,
    this._apiKey,
  ) {
    _log = logFile.openWrite(mode: FileMode.append);
    _logFlushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_logDirty) return;
      _logDirty = false;
      unawaited(_log.flush());
    });
    _stdout = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((String chunk) => _forward('stdout', chunk));
    _stdoutDone = _stdout.asFuture<void>();
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((String chunk) => _forward('stderr', chunk));
    _stderrDone = _stderr.asFuture<void>();
    _exitCode = _process.exitCode.then((int code) async {
      _running = false;
      try {
        await Future.wait<void>(<Future<void>>[_stdoutDone, _stderrDone])
            .timeout(const Duration(seconds: 2));
      } on Object {
        await _stdout.cancel();
        await _stderr.cancel();
      }
      _log.writeln(
        '[${DateTime.now().toUtc().toIso8601String()}] exitCode=$code',
      );
      _logFlushTimer.cancel();
      await _log.flush();
      await _log.close();
      await _output.close();
      await _toolServer.close();
      await PlatformProcessLifecycle.releaseProcessTree(_process.pid);
      return code;
    });
  }

  final Process _process;
  final HarnessToolServer _toolServer;
  final String _apiKey;
  final StreamController<String> _output = StreamController<String>();
  late final IOSink _log;
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<void> _stdoutDone;
  late final Future<void> _stderrDone;
  late final Future<int> _exitCode;
  late final Timer _logFlushTimer;
  bool _running = true;
  bool _logDirty = false;

  void _forward(String channel, String chunk) {
    final String safe = DeepSeekHarnessService.redactSensitiveOutput(
      chunk,
      <String>[_apiKey],
    );
    _log.write('[${DateTime.now().toUtc().toIso8601String()}][$channel] $safe');
    // IOSink is already buffered. A forced disk flush for every Node output
    // chunk can add seconds to DSH startup on Windows and is unnecessary for a
    // diagnostic log. Periodic flushing above keeps the log durable enough.
    _logDirty = true;
    _output.add(safe);
  }

  @override
  final Uri url;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int> get exitCode => _exitCode;
  @override
  bool get running => _running;
  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _stopProcessTree(_process);
    await _exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}

Future<void> _stopProcessTree(Process process) async {
  if (Platform.isWindows) {
    await Process.run('taskkill.exe', <String>[
      '/PID',
      '${process.pid}',
      '/T',
      '/F',
    ], runInShell: false).timeout(
      const Duration(seconds: 5),
      onTimeout: () => ProcessResult(0, -1, '', ''),
    );
  } else {
    process.kill(ProcessSignal.sigterm);
  }
}

Future<void> _bindProcessToAppLifetime(Process process) async {
  try {
    await PlatformProcessLifecycle.bindProcessTree(process.pid);
  } on Object {
    await _stopProcessTree(process);
    rethrow;
  }
}
