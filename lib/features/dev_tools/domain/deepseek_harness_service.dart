import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'harness_tool_bridge.dart';
import 'harness_tool_server.dart';

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
    this.approveTool,
    this.toolBridge,
  });
  final String workspace;
  final String prompt;
  final String apiKey;
  final String baseUrl;
  final String model;
  final HarnessToolApproval? approveTool;
  final VibekitsHarnessToolBridge? toolBridge;
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
  }
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
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-v4-flash';

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
    try {
      final _HarnessRuntime runtime = await _resolveBundledRuntime();
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
    final _HarnessRuntime runtime = await _resolveBundledRuntime();
    try {
      final Process process = await Process.start(
        runtime.nodeExecutable,
        <String>[runtime.cliPath, ...spec.arguments],
        workingDirectory: spec.workspace.trim(),
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
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
    final _HarnessRuntime runtime = await _resolveBundledRuntime();
    final HarnessToolServer toolServer = await HarnessToolServer.start(
      approve: request.approveTool,
      bridge: request.toolBridge,
    );
    final Directory harnessHome = await _prepareHarnessHome(request.model);
    try {
      final Process process = await Process.start(
        runtime.nodeExecutable,
        <String>[runtime.cliPath, ...request.arguments],
        workingDirectory: request.workspace.trim(),
        environment: <String, String>{
          'DEEPSEEK_API_KEY': request.apiKey.trim(),
          'DEEPSEEK_BASE_URL': request.baseUrl.trim(),
          'DEEPSEEK_MODEL': request.model.trim().isEmpty
              ? defaultModel
              : request.model.trim(),
          'DSH_HOME': harnessHome.path,
          'DSH_TELEMETRY_MODE': 'DISABLED',
          'DSH_PERMISSION_MODE': 'workspace-write',
          'DSH_TELEMETRY_DISABLED': '1',
          'VIBEKITS_NODE_EXECUTABLE': runtime.nodeExecutable,
          'VIBEKITS_MCP_SERVER': runtime.mcpServerPath,
          'VIBEKITS_TOOL_BRIDGE_URL': toolServer.endpoint.toString(),
          'VIBEKITS_TOOL_BRIDGE_TOKEN': toolServer.token,
        },
        includeParentEnvironment: true,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      return _ProcessHarnessAgent(process, toolServer);
    } on ProcessException catch (error) {
      await toolServer.close();
      throw StateError('无法启动官方 Harness 智能体：${error.message}');
    } on Object {
      await toolServer.close();
      rethrow;
    }
  }

  static void _validateEndpoint(String value) {
    final String raw = value.trim().isEmpty ? defaultBaseUrl : value.trim();
    final Uri base = Uri.parse(raw);
    if (!base.isAbsolute || (base.scheme != 'https' && base.scheme != 'http')) {
      throw const FormatException('API 地址必须是有效的 HTTP/HTTPS 地址');
    }
  }

  static Future<Directory> _prepareHarnessHome(String requestedModel) async {
    final String model = requestedModel.trim().isEmpty
        ? defaultModel
        : requestedModel.trim();
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    final Directory home = Directory(
      Platform.isWindows
          ? '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
          : '$base${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness',
    );
    await home.create(recursive: true);
    final File settings = File(
      '${home.path}${Platform.pathSeparator}settings.yaml',
    );
    await settings.writeAsString(
      'agent-default-model:\n'
      '  provider: deepseek-official\n'
      '  model: ${jsonEncode(model)}\n',
      flush: true,
    );
    final File patch = File(
      '${home.path}${Platform.pathSeparator}cordis.patch.yml',
    );
    await patch.writeAsString(
      '- insert:\n'
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
      '        toolCallTimeoutMs: 60000\n',
      flush: true,
    );
    return home;
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
  });

  final String nodeExecutable;
  final String cliPath;
  final String version;
  final String mcpServerPath;
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
    final File? mcpServer = mcpCandidates
        .where((File file) => file.existsSync())
        .firstOrNull;
    if (cli.isEmpty ||
        version.isEmpty ||
        !node.existsSync() ||
        !cliFile.existsSync() ||
        mcpServer == null) {
      continue;
    }
    return _HarnessRuntime(
      nodeExecutable: node.path,
      cliPath: cliFile.path,
      version: version,
      mcpServerPath: mcpServer.path,
    );
  }
  throw const FileSystemException('内置 Harness 运行时缺失');
}

class _ProcessHarnessAgent implements HarnessAgentHandle {
  _ProcessHarnessAgent(this._process, this._toolServer) {
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
      await _toolServer.close();
      return code;
    });
  }

  final Process _process;
  final HarnessToolServer _toolServer;
  final StreamController<String> _output = StreamController<String>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<int> _exitCode;
  bool _running = true;

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
