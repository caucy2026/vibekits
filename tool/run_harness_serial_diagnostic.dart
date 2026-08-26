import 'dart:convert';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_agent_preferences.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

Future<void> main() async {
  const Set<String> serialToolIds = <String>{
    VibekitsHarnessToolBridge.serialListPortsId,
    VibekitsHarnessToolBridge.serialTransactId,
  };
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

  final Directory evidenceDirectory = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance${Platform.pathSeparator}serial',
  );
  await evidenceDirectory.create(recursive: true);
  final Directory isolatedWorkspace = Directory(
    '${evidenceDirectory.path}${Platform.pathSeparator}harness-workspace',
  );
  await isolatedWorkspace.create(recursive: true);
  final String workspace = isolatedWorkspace.path;
  final DateTime startedAt = DateTime.now();
  final File transcript = File(
    '${evidenceDirectory.path}${Platform.pathSeparator}'
    'harness-serial-work-${startedAt.toIso8601String().replaceAll(':', '-')}.log',
  );

  await HarnessToolActivityStore.setLoggingEnabled(true);
  await HarnessToolActivityStore.setLoggingEnabled(
    true,
    toolIds: serialToolIds,
  );
  final List<HarnessToolActivity> before = await HarnessToolActivityStore.load(
    serialToolIds,
  );
  final Set<String> previousIds = before
      .map((HarnessToolActivity item) => item.id)
      .toSet();
  final List<String> availableModels = await DeepSeekHarnessService.listModels(
    apiKey,
    DeepSeekHarnessService.defaultBaseUrl,
  );
  final String selectedModel = availableModels.contains('deepseek-v4-pro')
      ? 'deepseek-v4-pro'
      : availableModels.contains('deepseek-chat')
      ? 'deepseek-chat'
      : availableModels.first;

  const String prompt = '''
请调试这台电脑当前已经连接的串口，必须由你自主调用 Vibekits 本地工具完成。

验收要求：
1. 必须调用 vibekits.serial.list_ports，禁止用 shell、PowerShell、注册表或猜测代替。
2. 找出当前真正的 USB 物理串口，区分蓝牙等虚拟串口。
3. 报告端口名、设备描述、传输类型、VID 和 PID，并说明判断依据。
4. 因为用户尚未提供设备协议，不要发送任何字节，也不要调用 transact。
5. 最终答复必须写明实际调用的工具 ID 和工具返回证据。
6. 工具不可用或调用失败时如实说明缺少什么，不得伪造结果。
''';

  final StringBuffer fullOutput = StringBuffer()
    ..writeln('=== VibeKits Harness 串口诊断工作记录 ===')
    ..writeln('开始时间: ${startedAt.toIso8601String()}')
    ..writeln('工作区: $workspace')
    ..writeln('API 返回模型: ${availableModels.join(', ')}')
    ..writeln('实际模型: $selectedModel')
    ..writeln('任务:\n${prompt.trim()}')
    ..writeln('\n=== Harness 实时输出 ===');
  await transcript.writeAsString(fullOutput.toString(), flush: true);

  final HarnessAgentHandle agent = DeepSeekHarnessService.startNativeToolAgent(
    HarnessAgentRequest(
      workspace: workspace,
      prompt: prompt,
      apiKey: apiKey,
      model: selectedModel,
      permissionMode: HarnessAgentPermissionMode.requestApproval,
      approveTool: (HarnessToolApprovalRequest request) async =>
          request.tool.id == VibekitsHarnessToolBridge.serialListPortsId &&
          request.tool.risk == HarnessToolRisk.readOnly,
      toolBridge: VibekitsHarnessToolBridge(
        activityRecorder: HarnessToolActivityStore.record,
      ),
      allowedToolIds: const <String>{
        VibekitsHarnessToolBridge.serialListPortsId,
      },
    ),
  );

  await for (final String chunk in agent.output) {
    stdout.write(chunk);
    fullOutput.write(chunk);
    await transcript.writeAsString(fullOutput.toString(), flush: true);
  }
  final int harnessExitCode = await agent.exitCode;
  final List<HarnessToolActivity> after = await HarnessToolActivityStore.load(
    serialToolIds,
  );
  final List<HarnessToolActivity> created = after
      .where((HarnessToolActivity item) => !previousIds.contains(item.id))
      .toList(growable: false);

  fullOutput
    ..writeln('\n=== Harness 执行结果 ===')
    ..writeln('退出代码: $harnessExitCode')
    ..writeln('串口工具调用数: ${created.length}');
  for (final HarnessToolActivity activity in created) {
    fullOutput
      ..writeln('工具: ${activity.toolId}')
      ..writeln('状态: ${activity.status.name}')
      ..writeln('目标: ${activity.target}')
      ..writeln('参数: ${activity.argumentsSummary}')
      ..writeln('结果: ${activity.resultSummary}')
      ..writeln('耗时: ${activity.elapsedMs} ms');
  }
  fullOutput.writeln('结束时间: ${DateTime.now().toIso8601String()}');
  await transcript.writeAsString(fullOutput.toString(), flush: true);

  stdout
    ..writeln('\nHARNESS_EXIT_CODE=$harnessExitCode')
    ..writeln('SERIAL_TOOL_CALLS=${created.length}')
    ..writeln('TRANSCRIPT=${transcript.path}');
  if (harnessExitCode != 0 ||
      created.every(
        (HarnessToolActivity item) =>
            item.toolId != VibekitsHarnessToolBridge.serialListPortsId ||
            item.status != HarnessToolActivityStatus.succeeded,
      )) {
    throw StateError('Harness 未成功调用 serial.list_ports，验收失败');
  }
}
