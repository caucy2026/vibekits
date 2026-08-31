import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Learns reusable, semantic workflows from successful Harness tool calls.
///
/// This is intentionally not a mouse-coordinate macro recorder. A recording
/// stores tool intent, structured arguments, observable outcomes and explicit
/// completion criteria. On replay, Harness receives a bound skill plan and
/// must resolve tools against the current MCP catalog and verify every step.
class SemanticWorkflowService {
  SemanticWorkflowService({Directory? directory})
    : directory =
          directory ??
          Directory(
            '${Directory.current.absolute.path}${Platform.pathSeparator}'
            '.runtime-cache${Platform.pathSeparator}harness'
            '${Platform.pathSeparator}semantic_workflows',
          );

  static final SemanticWorkflowService instance = SemanticWorkflowService();
  static const int maxWorkflows = 100;
  static const int maxSteps = 200;
  static const int maxFileBytes = 2 * 1024 * 1024;

  final Directory directory;
  _ActiveRecording? _active;

  bool get recording => _active != null;

  Future<Map<String, Object?>> start(Map<String, Object?> arguments) async {
    if (_active != null) throw StateError('已有示教正在录制，请先停止');
    final String name = _requiredText(arguments['name'], 'name', 100);
    final String goal = _requiredText(arguments['goal'], 'goal', 2000);
    final List<String> successCriteria = _stringList(
      arguments['successCriteria'],
      maxItems: 20,
      maxLength: 500,
    );
    if (successCriteria.isEmpty) {
      throw const FormatException('successCriteria 至少需要一项可验证标准');
    }
    final List<_WorkflowVariable> variables = _parseVariables(
      arguments['variables'],
    );
    final DateTime now = DateTime.now();
    _active = _ActiveRecording(
      id: 'workflow-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 24)}',
      name: name,
      goal: goal,
      successCriteria: successCriteria,
      variables: variables,
      startedAt: now,
    );
    return <String, Object?>{
      'recording': true,
      'workflowId': _active!.id,
      'name': name,
      'goal': goal,
      'nextAction':
          '完成一次真实示范；Harness 的 MCP 工具调用会被转成语义步骤。完成后调用 workflow.record_stop。',
    };
  }

  Future<void> capture({
    required String toolId,
    required String toolName,
    required String target,
    required Map<String, Object?> arguments,
    required Object? result,
    required String status,
    required DateTime startedAt,
  }) async {
    final _ActiveRecording? active = _active;
    if (active == null ||
        toolId.startsWith('vibekits.workflow.') ||
        active.steps.length >= maxSteps) {
      return;
    }
    active.steps.add(
      _RecordedStep(
        order: active.steps.length + 1,
        toolId: toolId,
        toolName: toolName,
        target: target,
        arguments: Map<String, Object?>.from(arguments),
        observedResult: result,
        succeeded: status == 'succeeded',
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      ),
    );
  }

  Future<Map<String, Object?>> stop(Map<String, Object?> arguments) async {
    final _ActiveRecording? active = _active;
    if (active == null) throw StateError('当前没有正在进行的示教');
    _active = null;
    if (active.steps.isEmpty) throw StateError('示教中没有捕获到 MCP 工具调用');
    final String notes = _optionalText(arguments['notes'], 2000);
    final Map<String, Object?> workflow = <String, Object?>{
      'version': 1,
      'id': active.id,
      'name': active.name,
      'goal': active.goal,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'successCriteria': active.successCriteria,
      'variables': <Map<String, Object?>>[
        for (final _WorkflowVariable variable in active.variables)
          variable.toJson(),
      ],
      'steps': <Map<String, Object?>>[
        for (final _RecordedStep step in active.steps)
          step.toSemanticJson(active.variables),
      ],
      if (notes.isNotEmpty) 'notes': notes,
      'replayPolicy': <String, Object?>{
        'mode': 'adaptive-semantic',
        'refreshMcpCatalogBeforeRun': true,
        'verifyAfterEveryStep': true,
        'coordinateReplayForbidden': true,
        'stopOnUnverifiedMutation': true,
      },
    };
    await _writeWorkflow(active.id, workflow);
    return <String, Object?>{
      'recording': false,
      'workflowId': active.id,
      'name': active.name,
      'stepCount': active.steps.length,
      'failedDemonstrationSteps': active.steps
          .where((_RecordedStep step) => !step.succeeded)
          .length,
      'skill': workflow,
      'nextAction': '以后调用 workflow.prepare_replay 并提供本次变化的输入；Harness 应按当前 MCP 能力重新规划并逐步验证。',
    };
  }

  Future<Map<String, Object?>> list() async {
    if (!await directory.exists()) {
      return <String, Object?>{
        'recording': recording,
        'workflows': <Object?>[],
      };
    }
    final List<Map<String, Object?>> workflows = <Map<String, Object?>>[];
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final Map<String, Object?> item = await _readFile(entity);
        workflows.add(<String, Object?>{
          'id': item['id'],
          'name': item['name'],
          'goal': item['goal'],
          'createdAt': item['createdAt'],
          'stepCount': item['steps'] is List
              ? (item['steps']! as List).length
              : 0,
        });
      } on Object {
        // A malformed user-edited workflow is omitted, never executed.
      }
    }
    workflows.sort(
      (a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'),
    );
    return <String, Object?>{
      'recording': recording,
      'workflows': workflows.take(maxWorkflows).toList(growable: false),
    };
  }

  Future<Map<String, Object?>> prepareReplay(
    Map<String, Object?> arguments,
  ) async {
    final String id = _safeId('${arguments['workflowId'] ?? ''}');
    if (id.isEmpty) throw const FormatException('workflowId 无效');
    final File file = File(
      '${directory.path}${Platform.pathSeparator}$id.json',
    );
    final Map<String, Object?> workflow = await _readFile(file);
    final Map<String, Object?> inputs = arguments['inputs'] is Map
        ? Map<String, Object?>.from(arguments['inputs']! as Map)
        : const <String, Object?>{};
    final List<Object?> variables = workflow['variables'] is List
        ? workflow['variables']! as List
        : const <Object?>[];
    final List<String> missing = <String>[];
    for (final Object? raw in variables) {
      if (raw is! Map) continue;
      final String name = '${raw['name'] ?? ''}';
      if (raw['required'] == true && !inputs.containsKey(name))
        missing.add(name);
    }
    if (missing.isNotEmpty) {
      throw FormatException('缺少回放输入：${missing.join(', ')}');
    }
    final Object? bound = _bind(workflow, inputs);
    return <String, Object?>{
      'workflow': bound,
      'executionContract': <String, Object?>{
        'plannerInstruction':
            '先实时刷新本 APP、本机、局域网 MCP 目录；按每步 intent 选择当前可用工具，'
            '不要复现坐标或盲目重复旧参数。每步执行后检查 expectedOutcome；环境变化时可改用等价工具，'
            '但写入或控制步骤无法验证时必须停止并报告。最后逐项验证 successCriteria。',
        'approval': '遵循当前 Harness 权限策略，不继承录制时的一次性批准',
      },
    };
  }

  Future<void> _writeWorkflow(String id, Map<String, Object?> workflow) async {
    await directory.create(recursive: true);
    final String payload = const JsonEncoder.withIndent('  ').convert(workflow);
    if (utf8.encode(payload).length > maxFileBytes) {
      throw const FileSystemException('语义工作流超过 2 MiB');
    }
    final File target = File(
      '${directory.path}${Platform.pathSeparator}$id.json',
    );
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<Map<String, Object?>> _readFile(File file) async {
    if (!await file.exists() || await file.length() > maxFileBytes) {
      throw const FileSystemException('语义工作流不存在或过大');
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('语义工作流格式无效');
    }
    return Map<String, Object?>.from(decoded);
  }

  static List<_WorkflowVariable> _parseVariables(Object? value) {
    if (value is! List) return const <_WorkflowVariable>[];
    final List<_WorkflowVariable> result = <_WorkflowVariable>[];
    for (final Object? raw in value.take(30)) {
      if (raw is! Map) continue;
      final String name = _safeVariable('${raw['name'] ?? ''}');
      final String recordedValue = _optionalText(raw['recordedValue'], 2000);
      if (name.isEmpty || recordedValue.isEmpty) continue;
      result.add(
        _WorkflowVariable(
          name: name,
          description: _optionalText(raw['description'], 500),
          recordedValue: recordedValue,
          required: raw['required'] != false,
        ),
      );
    }
    return result;
  }

  static Object? _bind(Object? value, Map<String, Object?> inputs) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _bind(entry.value, inputs),
      };
    }
    if (value is List)
      return <Object?>[for (final Object? item in value) _bind(item, inputs)];
    if (value is! String) return value;
    String result = value;
    for (final MapEntry<String, Object?> input in inputs.entries) {
      result = result.replaceAll('{{${input.key}}}', '${input.value}');
    }
    return result;
  }

  static String _requiredText(Object? value, String name, int max) {
    final String result = _optionalText(value, max);
    if (result.isEmpty) throw FormatException('$name 不能为空');
    return result;
  }

  static String _optionalText(Object? value, int max) {
    final String result = value is String ? value.trim() : '';
    return result.length <= max ? result : result.substring(0, max);
  }

  static List<String> _stringList(
    Object? value, {
    required int maxItems,
    required int maxLength,
  }) => value is List
      ? value
            .whereType<String>()
            .map((String item) => _optionalText(item, maxLength))
            .where((String item) => item.isNotEmpty)
            .take(maxItems)
            .toList(growable: false)
      : const <String>[];

  static String _safeId(String value) =>
      RegExp(r'^workflow-[a-zA-Z0-9-]{8,100}$').hasMatch(value) ? value : '';
  static String _safeVariable(String value) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(value) ? value : '';
}

class _ActiveRecording {
  _ActiveRecording({
    required this.id,
    required this.name,
    required this.goal,
    required this.successCriteria,
    required this.variables,
    required this.startedAt,
  });

  final String id;
  final String name;
  final String goal;
  final List<String> successCriteria;
  final List<_WorkflowVariable> variables;
  final DateTime startedAt;
  final List<_RecordedStep> steps = <_RecordedStep>[];
}

class _WorkflowVariable {
  const _WorkflowVariable({
    required this.name,
    required this.description,
    required this.recordedValue,
    required this.required,
  });

  final String name;
  final String description;
  final String recordedValue;
  final bool required;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'required': required,
    'placeholder': '{{$name}}',
  };
}

class _RecordedStep {
  const _RecordedStep({
    required this.order,
    required this.toolId,
    required this.toolName,
    required this.target,
    required this.arguments,
    required this.observedResult,
    required this.succeeded,
    required this.elapsedMs,
  });

  final int order;
  final String toolId;
  final String toolName;
  final String target;
  final Map<String, Object?> arguments;
  final Object? observedResult;
  final bool succeeded;
  final int elapsedMs;

  Map<String, Object?> toSemanticJson(List<_WorkflowVariable> variables) =>
      <String, Object?>{
        'order': order,
        'intent': toolName,
        'preferredTool': toolId,
        'target': _template(target, variables),
        'arguments': _template(arguments, variables),
        'expectedOutcome': _template(observedResult, variables),
        'demonstrationSucceeded': succeeded,
        'observedElapsedMs': elapsedMs,
        'recovery': '刷新 MCP 目录并选择语义等价工具；无法验证写入/控制结果时停止，不盲目重试。',
      };

  static Object? _template(Object? value, List<_WorkflowVariable> variables) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _template(entry.value, variables),
      };
    }
    if (value is List)
      return <Object?>[
        for (final Object? item in value) _template(item, variables),
      ];
    if (value is! String) return value;
    String result = value;
    for (final _WorkflowVariable variable in variables) {
      result = result.replaceAll(
        variable.recordedValue,
        '{{${variable.name}}}',
      );
    }
    return result;
  }
}
