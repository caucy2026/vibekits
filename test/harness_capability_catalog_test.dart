import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

import '../tool/export_harness_capability_catalog.dart';

void main() {
  test('每个独立工作区都声明真实连续使用合同', () {
    expect(devToolUsageContracts.keys.toSet(), {
      for (final ToolSpec tool in devToolRegistry) tool.id,
    });
    for (final ToolUsageContract contract in devToolUsageContracts.values) {
      expect(contract.repeatUse, isNotEmpty);
      expect(contract.multiTarget, isNotEmpty);
      expect(contract.secretHandling, isNotEmpty);
    }
  });

  test('Harness 能力 Markdown 与实际注册表一致并会注入 DSH', () async {
    final String generated = buildHarnessCapabilityCatalog();
    final File document = File('docs/37_HARNESS_CAPABILITY_CATALOG.md');
    const bool update = bool.fromEnvironment(
      'VIBEKITS_UPDATE_HARNESS_CAPABILITY_DOC',
    );
    if (update) {
      await document.writeAsString(generated, flush: true);
    }
    expect(await document.readAsString(), generated);

    final String instructions = await File('assets/harness/AGENTS.md')
        .readAsString();
    expect(instructions, contains('vibekits.system.capability_check'));
    expect(instructions, contains('inputSchema'));
    expect(
      DeepSeekHarnessService.harnessCapabilityInstructions,
      contains('vibekits.system.capability_check'),
    );
    expect(
      DeepSeekHarnessService.harnessCapabilityInstructions,
      contains('MCP Schema'),
    );
  });

  test('DSH 全局说明可重复更新且保留用户自己的指令', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'vibekits_harness_instructions_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File instructions = File(
      '${directory.path}${Platform.pathSeparator}AGENTS.md',
    );
    await instructions.writeAsString('# 用户自己的要求\n\n保留这段。\n');

    await DeepSeekHarnessService.prepareHarnessCapabilityInstructions(
      directory: directory,
    );
    await DeepSeekHarnessService.prepareHarnessCapabilityInstructions(
      directory: directory,
    );
    final String content = await instructions.readAsString();
    expect(content, contains('保留这段。'));
    expect(
      '<!-- VIBEKITS_CAPABILITIES_BEGIN -->'.allMatches(content).length,
      1,
    );
    expect('<!-- VIBEKITS_CAPABILITIES_END -->'.allMatches(content).length, 1);
    expect(content, contains('vibekits.system.capability_check'));
  });

  test('DSH Web 冷启动不加载未使用的多提供商、遥测和 HMR', () {
    expect(
      DeepSeekHarnessService.harnessWebPerformancePatch,
      contains('- id: llm-pi-ai\n  disabled: true'),
    );
    expect(
      DeepSeekHarnessService.harnessWebPerformancePatch,
      contains('- id: session-telemetry-otel\n  disabled: true'),
    );
    expect(
      DeepSeekHarnessService.harnessWebPerformancePatch,
      contains('- id: client-hmr\n  disabled: true'),
    );
  });
}
