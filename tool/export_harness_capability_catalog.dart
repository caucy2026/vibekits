import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

String buildHarnessCapabilityCatalog() {
  final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
  final List<HarnessToolDefinition> catalog = bridge.fullCatalog;
  final List<HarnessToolDefinition> executable = bridge.executableCatalog;
  final Map<String, String> groupByToolId = <String, String>{};
  for (final ToolSpec spec in allDevToolRegistry) {
    for (final String id in harnessToolIdsFor(spec)) {
      groupByToolId.putIfAbsent(id, () => spec.group);
    }
  }
  final Map<String, List<HarnessToolDefinition>> grouped =
      <String, List<HarnessToolDefinition>>{};
  for (final HarnessToolDefinition tool in catalog) {
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
    String detail(String key, Object? raw) {
      final Map<String, Object?> schema = raw is Map
          ? raw.cast<String, Object?>()
          : const <String, Object?>{};
      final List<String> parts = <String>[
        '${schema['type'] ?? 'any'}',
        if (schema.containsKey('default')) '默认=${schema['default']}',
        if (schema['enum'] is List) '枚举=${(schema['enum'] as List).join('/')}',
        if (schema.containsKey('minimum')) '最小=${schema['minimum']}',
        if (schema.containsKey('maximum')) '最大=${schema['maximum']}',
      ];
      return '`$key`${required.contains(key) ? '*' : ''} (${parts.join('；')})';
    }

    return properties.entries
        .map(
          (MapEntry<String, Object?> entry) => detail(entry.key, entry.value),
        )
        .join(', ');
  }

  String mcpName(String toolId) =>
      toolId.replaceFirst(RegExp(r'^vibekits\.'), '').replaceAll('.', '__');

  final StringBuffer markdown = StringBuffer()
    ..writeln('# VibeKits 外部智能体 MCP 与 Harness 工具接口目录')
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
    ..writeln('## MCP 开关、授权和动态远端目录')
    ..writeln()
    ..writeln(
      'MCP 关闭、启动中、开启、排空中和异常必须显示为不同状态。从关闭切换到开启时，APP 必须先展示不可跳过的授权对话框：说明局域网可发现性、证书身份、下列完整工具目录、读取/写入/文件外发/设备控制风险和撤销方法；用户取消时保持关闭。打开开关只授权发布接口，不等于预先批准每次高风险调用。',
    )
    ..writeln()
    ..writeln(
      'VibeKits Harness 通过 `vibekits.mcp.catalog_list` 获取本 APP、本机进程和局域网设备的实时完整目录，通过 `vibekits.mcp.tool_call` 调用本地 stdio 或已完成 TLS 指纹固定和目录摘要校验的局域网工具。固定查找顺序为本机 VibeKits MCP（app）→ 本地其他进程 MCP（local）→ 局域网 MCP（lan），评分只能调整同层候选，不能让远端越级。`vibekits.mcp.reputation_list` 返回跨项目、会话和重启的全局工具类型评分，`vibekits.mcp.reputation_rate` 允许经写权限审批给出 0–5 分；同名工具跨设备共享评分。副作用调用执行前展示实例、真实工具名和参数并进入统一审批、审计；离线、仅发现或目录中不存在的工具不能调用。',
    )
    ..writeln()
    ..writeln('## 外部智能体接入')
    ..writeln()
    ..writeln(
      'VibeKits 对 Codex、Claude Desktop、Cursor、VS Code 智能体和其他支持 stdio MCP 的客户端开放同一套工具。客户端不需要接触 Harness API Key，也不需要复制内部实现。',
    )
    ..writeln()
    ..writeln('Windows 源码工作区推荐把下面命令注册为一个 stdio MCP server：')
    ..writeln()
    ..writeln('```text')
    ..writeln(
      'powershell.exe -NoProfile -ExecutionPolicy Bypass -File <VIBEKITS_ROOT>\\tool\\start_vibekits_mcp.ps1',
    )
    ..writeln('```')
    ..writeln()
    ..writeln('通用 MCP JSON 配置：')
    ..writeln()
    ..writeln('```json')
    ..writeln('{')
    ..writeln('  "mcpServers": {')
    ..writeln('    "vibekits": {')
    ..writeln('      "command": "powershell.exe",')
    ..writeln(
      '      "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<VIBEKITS_ROOT>\\\\tool\\\\start_vibekits_mcp.ps1"]',
    )
    ..writeln('    }')
    ..writeln('  }')
    ..writeln('}')
    ..writeln('```')
    ..writeln()
    ..writeln('Codex `config.toml` 配置：')
    ..writeln()
    ..writeln('```toml')
    ..writeln('[mcp_servers.vibekits]')
    ..writeln('command = "powershell.exe"')
    ..writeln(
      'args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<VIBEKITS_ROOT>\\\\tool\\\\start_vibekits_mcp.ps1"]',
    )
    ..writeln('startup_timeout_sec = 30')
    ..writeln('tool_timeout_sec = 600')
    ..writeln('```')
    ..writeln()
    ..writeln(
      '运行链路：启动脚本确保 VibeKits APP 在运行 → APP 在 `127.0.0.1` 随机端口发布带随机 Bearer Token 的桥接文件 → stdio MCP 读取目录并转发调用。监听不暴露到局域网，连接文件不包含模型 API Key。写入、设备控制和破坏性操作仍遵守 APP 当前权限策略，并写入对应工具日志。',
    )
    ..writeln()
    ..writeln(
      '需要自行实现适配器时，可读取 `%LOCALAPPDATA%\\Vibekits\\Mcp\\tool-bridge.json` 中的临时 `baseUrl` 和 `token`，使用 `Authorization: Bearer <token>` 调用 `GET /catalog`、`POST /invoke` 与 `POST /native-approval`。这是仅限本机的底层协议；普通客户端应优先使用 stdio MCP，以免自行处理令牌轮换和 APP 生命周期。',
    )
    ..writeln()
    ..writeln(
      'MCP 对外名称会去掉 `vibekits.` 前缀并把点转换为双下划线，例如 `vibekits.adb.shell` 对外为 `adb__shell`。客户端必须以运行时 `tools/list` 返回值为准。',
    )
    ..writeln()
    ..writeln('## 统一调用协议')
    ..writeln()
    ..writeln('1. 通过 MCP 工具目录发现 `vibekits.*`。')
    ..writeln('2. 读取目标工具的 `description`、风险级别和 `inputSchema`。')
    ..writeln('3. 使用符合 Schema 的 JSON 对象调用；没有参数的工具传 `{}`。')
    ..writeln('4. 只读工具直接执行；写数据、控制设备或破坏性操作按当前权限模式审批。')
    ..writeln('5. 读取结构化结果，并在对应模块 Harness 记录中核对真实日志。')
    ..writeln(
      '6. 需要精确参数时先调用 `system.describe_tool`；可发现或可安全试探的参数自动配置，仅账号/身份缺失、密码/API Key/Token/私钥口令等秘密才询问用户。',
    )
    ..writeln()
    ..writeln(
      '外部 MCP 客户端采用标准 `tools/list` 与 `tools/call`；下表同时给出内部稳定 ID 和实际 MCP 名称。VibeKits 内置 Harness 自动完成这层协议。',
    )
    ..writeln()
    ..writeln('## 模块汇总')
    ..writeln()
    ..writeln('| 模块 | 定义接口数 |')
    ..writeln('| --- | ---: |');
  for (final MapEntry<String, List<HarnessToolDefinition>> entry
      in grouped.entries) {
    markdown.writeln('| ${entry.key} | ${entry.value.length} |');
  }
  for (final MapEntry<String, List<HarnessToolDefinition>> entry
      in grouped.entries) {
    markdown
      ..writeln()
      ..writeln('## ${entry.key}（定义 ${entry.value.length}）')
      ..writeln()
      ..writeln('| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |')
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final HarnessToolDefinition tool in entry.value) {
      markdown.writeln(
        '| `${tool.id}` | `${mcpName(tool.id)}` | ${tool.name.replaceAll('|', '\\|')} | ${tool.available ? '是' : '否（环境/接线门禁）'} | ${tool.description.replaceAll('|', '\\|').replaceAll(RegExp(r'\s+'), ' ')} | `${tool.risk.name}` | ${schemaSummary(tool)} |',
      );
    }
  }
  markdown
    ..writeln()
    ..writeln('## 典型闭环')
    ..writeln()
    ..writeln(
      '- 串口：`serial.list_ports → serial.auto_detect` 自动选端口并探测 baudRate/dataBits/stopBits/parity/flowControl；一次交互再用 `serial.transact`，持续调试用 `serial.session_open → session_read/session_write → session_close`。',
    )
    ..writeln(
      '- ADB：`adb.list_devices/connect → shell/logcat/screenshot/push/pull/install_apk`；持续任务用 `adb.session_open → session_status → session_close` 保持并核验连接。',
    )
    ..writeln(
      '- SSH/SFTP：`remote.list_profiles/open_interactive → ssh_exec/sftp_*`。',
    )
    ..writeln(
      '- Git 备份：`git.inspect → backup_preview → backup_commit → backup_push → verify_remote_ref`。',
    )
    ..writeln(
      '- 远端源码：`git.list_remote_refs → git.read_remote_file(manifest) → git.clone_minimal(明确单仓)`；禁止无参数 `repo sync`。',
    )
    ..writeln(
      '- 代理：`runtime.inspect → proxy.start → runtime.status → proxy.system_apply`；退出前恢复系统代理。',
    )
    ..writeln(
      '- 虚拟机：`runtime.inspect → vm.create_disk → vm.start → runtime.status → vm.stop`。',
    )
    ..writeln(
      '- APP 自迭代：`project.iteration_inspect → Harness 工作区写入 → project.build`；只生成 Release 产物，安装和发布仍需用户验收。',
    )
    ..writeln('- 能力自检：`system.capability_check`；它只证明注册与处理器接线，不替代真机/网络/凭据门禁。')
    ..writeln()
    ..writeln('## 自动更新规则')
    ..writeln()
    ..writeln(
      '本文不是手工维护的接口清单。新增或修改 `ToolSpec` / `HarnessToolDefinition` 后，`test/harness_capability_catalog_test.dart` 会自动重写并核对本文；发布质量门禁必须运行该测试。需要单独生成时可执行：',
    )
    ..writeln()
    ..writeln('```text')
    ..writeln('dart run tool/export_harness_capability_catalog.dart')
    ..writeln('```');

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
