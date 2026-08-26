import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

String buildHarnessCapabilityCatalog() {
  final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
  final List<HarnessToolDefinition> executable = bridge.executableCatalog;
  final Map<String, String> groupByToolId = <String, String>{};
  for (final ToolSpec spec in allDevToolRegistry) {
    for (final String id in harnessToolIdsFor(spec)) {
      groupByToolId.putIfAbsent(id, () => spec.group);
    }
  }
  final Map<String, List<HarnessToolDefinition>> grouped =
      <String, List<HarnessToolDefinition>>{};
  for (final HarnessToolDefinition tool in executable) {
    final String group = groupByToolId[tool.id] ?? ToolGroups.system;
    grouped.putIfAbsent(group, () => <HarnessToolDefinition>[]).add(tool);
  }
  for (final List<HarnessToolDefinition> tools in grouped.values) {
    tools.sort(
      (HarnessToolDefinition a, HarnessToolDefinition b) =>
          a.id.compareTo(b.id),
    );
  }

  String schemaSummary(HarnessToolDefinition tool) {
    final Map<String, Object?> properties =
        (tool.inputSchema['properties'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final List<String> required =
        (tool.inputSchema['required'] as List?)
            ?.map((Object? value) => '$value')
            .toList() ??
        const <String>[];
    if (properties.isEmpty) return '`{}`';
    return properties.keys
        .map((String key) => required.contains(key) ? '`$key`*' : '`$key`')
        .join(', ');
  }

  final StringBuffer markdown = StringBuffer()
    ..writeln('# Harness 功能模块与工具接口目录')
    ..writeln()
    ..writeln(
      '> 本文由 `tool/export_harness_capability_catalog.dart` 从实际 `ToolSpec` 与 `VibekitsHarnessToolBridge` 生成。带 `*` 的参数为必填；运行时以 MCP `inputSchema` 为最终准则。',
    )
    ..writeln()
    ..writeln('## 数量口径')
    ..writeln()
    ..writeln('- 产品一级页面：5（智能体、解压缩、系统清理、文档阅读、开发工具）。')
    ..writeln('- 开发工具业务能力条目：${allDevToolRegistry.length}。')
    ..writeln('- 开发工具独立工作区入口：${devToolRegistry.length}。')
    ..writeln('- Harness 定义接口：${bridge.fullCatalog.length}。')
    ..writeln('- Harness 当前可执行接口：${executable.length}。')
    ..writeln('- 当前不可公开接口：${bridge.fullCatalog.length - executable.length}。')
    ..writeln()
    ..writeln(
      '不要把以上数字相加称为“总功能数”：页面、业务条目和机器接口是三种不同层级。Harness 回答时先调用 `vibekits.system.capability_check` 获取本次运行的动态数字。',
    )
    ..writeln()
    ..writeln('## 统一调用协议')
    ..writeln()
    ..writeln('1. 通过 MCP 工具目录发现 `vibekits.*`。')
    ..writeln('2. 读取目标工具的 `description`、风险级别和 `inputSchema`。')
    ..writeln('3. 使用符合 Schema 的 JSON 对象调用；没有参数的工具传 `{}`。')
    ..writeln('4. 只读工具直接执行；写数据、控制设备或破坏性操作按当前权限模式审批。')
    ..writeln('5. 读取结构化结果，并在对应模块 Harness 记录中核对真实日志。')
    ..writeln()
    ..writeln(
      '外部 MCP 客户端采用标准 `tools/call`，`name` 为下表工具 ID，`arguments` 为 JSON 参数。VibeKits 内置 Harness 会自动完成这层协议。',
    )
    ..writeln()
    ..writeln('## 模块汇总')
    ..writeln()
    ..writeln('| 模块 | 可执行接口数 |')
    ..writeln('| --- | ---: |');
  for (final MapEntry<String, List<HarnessToolDefinition>> entry
      in grouped.entries) {
    markdown.writeln('| ${entry.key} | ${entry.value.length} |');
  }
  for (final MapEntry<String, List<HarnessToolDefinition>> entry
      in grouped.entries) {
    markdown
      ..writeln()
      ..writeln('## ${entry.key}（${entry.value.length}）')
      ..writeln()
      ..writeln('| 工具 ID | 名称 | 风险 | 参数 |')
      ..writeln('| --- | --- | --- | --- |');
    for (final HarnessToolDefinition tool in entry.value) {
      markdown.writeln(
        '| `${tool.id}` | ${tool.name.replaceAll('|', '\\|')} | `${tool.risk.name}` | ${schemaSummary(tool)} |',
      );
    }
  }
  markdown
    ..writeln()
    ..writeln('## 典型闭环')
    ..writeln()
    ..writeln('- 串口：`serial.list_ports → serial.transact`。')
    ..writeln(
      '- ADB：`adb.list_devices/connect → shell/logcat/screenshot/push/pull/install_apk`。',
    )
    ..writeln(
      '- SSH/SFTP：`remote.list_profiles/open_interactive → ssh_exec/sftp_*`。',
    )
    ..writeln(
      '- Git 备份：`git.inspect → backup_preview → backup_commit → backup_push → verify_remote_ref`。',
    )
    ..writeln(
      '- 代理：`runtime.inspect → proxy.start → runtime.status → proxy.system_apply`；退出前恢复系统代理。',
    )
    ..writeln(
      '- 虚拟机：`runtime.inspect → vm.create_disk → vm.start → runtime.status → vm.stop`。',
    )
    ..writeln('- 能力自检：`system.capability_check`；它只证明注册与处理器接线，不替代真机/网络/凭据门禁。');

  return markdown.toString();
}

Future<void> main(List<String> arguments) async {
  final String outputPath = arguments.isEmpty
      ? 'docs${Platform.pathSeparator}37_HARNESS_CAPABILITY_CATALOG.md'
      : arguments.first;
  final File output = File(outputPath);
  await output.parent.create(recursive: true);
  final String catalog = buildHarnessCapabilityCatalog();
  await output.writeAsString(catalog, flush: true);
  stdout.writeln('WROTE=${output.absolute.path}');
}
