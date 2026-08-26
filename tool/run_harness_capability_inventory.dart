import 'dart:convert';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_agent_preferences.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

Future<void> main() async {
  final Directory harnessHome =
      DeepSeekHarnessService.officialHarnessHomeDirectory();
  final File credentials = File(
    '${harnessHome.path}${Platform.pathSeparator}.credentials.yaml',
  );
  if (!await credentials.exists()) {
    stderr.writeln('Harness 尚未配置 DeepSeek API Key。');
    exitCode = 2;
    return;
  }

  final String credentialText = await credentials.readAsString();
  final Match? keyMatch = RegExp(
    r'^DEEPSEEK_API_KEY\s*:\s*(.+)$',
    multiLine: true,
  ).firstMatch(credentialText);
  if (keyMatch == null) {
    stderr.writeln('Harness 凭据中没有 DeepSeek API Key。');
    exitCode = 2;
    return;
  }
  final String encodedKey = keyMatch.group(1)!.trim();
  final String apiKey = encodedKey.startsWith('"')
      ? jsonDecode(encodedKey) as String
      : encodedKey;

  final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
    activityRecorder: HarnessToolActivityStore.record,
  );
  final Directory evidenceDirectory = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance${Platform.pathSeparator}capabilities',
  );
  await evidenceDirectory.create(recursive: true);
  final Directory workspace = Directory(
    '${evidenceDirectory.path}${Platform.pathSeparator}harness-workspace',
  );
  await workspace.create(recursive: true);
  final DateTime startedAt = DateTime.now();
  final File transcript = File(
    '${evidenceDirectory.path}${Platform.pathSeparator}'
    'harness-capability-${startedAt.toIso8601String().replaceAll(':', '-')}.log',
  );

  await HarnessToolActivityStore.setLoggingEnabled(true);
  await HarnessToolActivityStore.setLoggingEnabled(
    true,
    toolIds: const <String>{VibekitsHarnessToolBridge.capabilityCheckId},
  );
  final Set<String> previousActivityIds = (await HarnessToolActivityStore.load(
    const <String>{VibekitsHarnessToolBridge.capabilityCheckId},
  )).map((HarnessToolActivity item) => item.id).toSet();

  final List<String> models = await DeepSeekHarnessService.listModels(
    apiKey,
    DeepSeekHarnessService.defaultBaseUrl,
  );
  final String model = models.contains('deepseek-v4-pro')
      ? 'deepseek-v4-pro'
      : models.contains('deepseek-chat')
      ? 'deepseek-chat'
      : models.first;

  const String prompt = '''
你现在是 VibeKits 自带的 Harness。请回答：这个 APP 有多少功能，分成哪些功能模块，各模块接口如何调用？

必须遵守：
1. 先调用 vibekits.system.capability_check 获取真实注册数量，禁止凭记忆猜测。
2. 结合当前实际提供给你的 Vibekits MCP 工具目录，按业务模块列出工具 ID。
3. 解释统一调用格式、参数从哪里查看、只读/写数据/控制设备三类权限，以及典型调用链。
4. 明确区分“产品一级页面”“业务功能模块”和“Harness 可执行接口数”，不要把三个数量混成一个。
5. 产品页面和业务模块以 capability_check 返回的 productHierarchy 为准；如果仍无法知道某个数量或接口，明确写不知道以及缺少的资料。
6. 最后一行单独输出 VIBEKITS_HARNESS_CAPABILITY_INVENTORY_OK。
''';

  final StringBuffer output = StringBuffer()
    ..writeln('=== Harness VibeKits 能力认知验收 ===')
    ..writeln('开始时间: ${startedAt.toIso8601String()}')
    ..writeln('模型: $model')
    ..writeln('本地定义工具数: ${bridge.fullCatalog.length}')
    ..writeln('本地可执行工具数: ${bridge.executableCatalog.length}')
    ..writeln('任务:\n${prompt.trim()}')
    ..writeln('\n=== Harness 回答 ===');
  await transcript.writeAsString(output.toString(), flush: true);

  final HarnessAgentHandle agent = DeepSeekHarnessService.startNativeToolAgent(
    HarnessAgentRequest(
      workspace: workspace.path,
      prompt: prompt,
      apiKey: apiKey,
      model: model,
      permissionMode: HarnessAgentPermissionMode.requestApproval,
      approveTool: (HarnessToolApprovalRequest request) async =>
          request.tool.id == VibekitsHarnessToolBridge.capabilityCheckId &&
          request.tool.risk == HarnessToolRisk.readOnly,
      toolBridge: bridge,
    ),
  );

  await for (final String chunk in agent.output) {
    stdout.write(chunk);
    output.write(chunk);
    await transcript.writeAsString(output.toString(), flush: true);
  }
  final int harnessExitCode = await agent.exitCode;
  final List<HarnessToolActivity> created =
      (await HarnessToolActivityStore.load(const <String>{
            VibekitsHarnessToolBridge.capabilityCheckId,
          }))
          .where(
            (HarnessToolActivity item) =>
                !previousActivityIds.contains(item.id),
          )
          .toList(growable: false);
  final bool calledCapabilityCheck = created.any(
    (HarnessToolActivity item) =>
        item.toolId == VibekitsHarnessToolBridge.capabilityCheckId &&
        item.status == HarnessToolActivityStatus.succeeded,
  );
  final bool emittedMarker = output.toString().contains(
    'VIBEKITS_HARNESS_CAPABILITY_INVENTORY_OK',
  );

  output
    ..writeln('\n=== 验收结果 ===')
    ..writeln('Harness 退出代码: $harnessExitCode')
    ..writeln('成功调用 capability_check: $calledCapabilityCheck')
    ..writeln('输出完成标记: $emittedMarker')
    ..writeln('记录文件: ${transcript.path}');
  await transcript.writeAsString(output.toString(), flush: true);

  stdout
    ..writeln('\nHARNESS_EXIT_CODE=$harnessExitCode')
    ..writeln('CAPABILITY_CHECK_CALLED=$calledCapabilityCheck')
    ..writeln('CAPABILITY_MARKER=$emittedMarker')
    ..writeln('TRANSCRIPT=${transcript.path}');
  if (harnessExitCode != 0 || !calledCapabilityCheck || !emittedMarker) {
    throw StateError('Harness 能力认知验收失败');
  }
}
