import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'adb_service.dart';
import 'api_request_service.dart';
import 'file_search_service.dart';
import 'git_repository_service.dart';
import 'github_diagnostics.dart';
import 'harness_tool_activity_store.dart';
import 'programmer_calculator.dart';
import 'serial_port_service.dart';
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
  }) => VibekitsHarnessToolBridge._(
    handlers,
    adbRunner,
    adbExecutable,
    activityRecorder,
  );

  VibekitsHarnessToolBridge._(
    this._customHandlers,
    this._adbRunner,
    this._adbExecutable,
    this._activityRecorder,
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
  static const String fileSearchId = 'vibekits.files.search';
  static const String apiRequestId = 'vibekits.http.request';
  static const String githubDiagnosticsId = 'vibekits.github.diagnose';
  static const String programmerCalculatorId = 'vibekits.calculator.programmer';

  final Map<String, HarnessToolHandler> _customHandlers;
  final AdbCommandRunner? _adbRunner;
  final String? _adbExecutable;
  final HarnessToolActivityRecorder? _activityRecorder;

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
          result: data,
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
    if (toolId == fileSearchId) return _searchFiles;
    if (toolId == apiRequestId) return _requestHttp;
    if (toolId == githubDiagnosticsId) return _diagnoseGithub;
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
    return (arguments['input'] ?? toolId).toString();
  }
}
