import 'package:flutter/material.dart';

import '../../dev_tools/domain/mcp_capability_models.dart';

Future<bool> showMcpExposureConsentDialog({
  required BuildContext context,
  required String deviceName,
  required List<McpToolInterface> tools,
  required String certificateFingerprint,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('mcp-exposure-consent-dialog'),
        icon: const Icon(Icons.security_rounded, size: 36),
        title: const Text('允许打开 MCP 权限？'),
        content: SizedBox(
          width: 680,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('设备：$deviceName'),
              const Text('当前对外身份：LMCP/2 HTTPS Streamable HTTP'),
              SelectableText(
                '实例证书：$certificateFingerprint',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              const Text('打开后，同一局域网内的设备可以发现本应用、读取下面的工具目录，并向这些工具发起调用。'),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '风险提示\n'
                  '• 设备名、应用版本、传输身份和工具说明会在局域网内公开；采用 LMCP/2 的 APP 还会公开证书指纹。\n'
                  '• 工具可能读取本机信息、写入文件、发送文件或控制已连接设备。\n'
                  '• 局域网中的恶意设备可能反复尝试连接；传输必须经过认证，敏感操作仍需审批并写入审计记录。\n'
                  '• 可随时关闭 MCP；关闭会停止新调用并广播离线。',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '本应用将公开 ${tools.length} 个工具接口',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: tools.isEmpty
                    ? const Center(child: Text('工具目录尚未就绪，不能授权打开。'))
                    : ListView.builder(
                        itemCount: tools.length,
                        itemBuilder: (BuildContext context, int index) {
                          final McpToolInterface tool = tools[index];
                          return ExpansionTile(
                            dense: true,
                            title: SelectableText(tool.name),
                            subtitle: Text(
                              '${tool.title.isEmpty ? '未提供标题' : tool.title} · 风险 ${tool.risk.isEmpty ? '提供者未声明' : tool.risk}',
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              12,
                            ),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: <Widget>[
                              SelectableText(
                                tool.description.isEmpty
                                    ? '提供者未填写用途、前置条件和副作用说明。'
                                    : tool.description,
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('mcp-exposure-deny'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消，保持关闭'),
          ),
          FilledButton.icon(
            key: const Key('mcp-exposure-allow'),
            onPressed: tools.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('允许并打开 MCP'),
          ),
        ],
      ),
    ) ??
    false;
