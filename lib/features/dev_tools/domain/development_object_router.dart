import 'dart:convert';

import 'tool_result.dart';

enum DevelopmentObjectKind {
  sourceFile,
  logFile,
  archive,
  database,
  gitRepository,
  project,
  androidDevice,
  serialDevice,
  sshHost,
  apiService,
  screenshot,
  cleanupReport,
  unknown,
}

class DevelopmentNextAction {
  const DevelopmentNextAction({
    required this.toolId,
    required this.label,
    required this.reason,
    this.requiresApproval = false,
  });

  final String toolId;
  final String label;
  final String reason;
  final bool requiresApproval;

  Map<String, Object?> toJson() => <String, Object?>{
    'toolId': toolId,
    'label': label,
    'reason': reason,
    'requiresApproval': requiresApproval,
  };
}

class DevelopmentObjectRouter {
  const DevelopmentObjectRouter._();

  static ToolResult recommend(String input, String kindHint) {
    final String value = input.trim();
    if (value.isEmpty) return const ToolFailure('请输入文件、目录、设备或服务标识');
    final DevelopmentObjectKind kind = classify(value, hint: kindHint);
    final List<DevelopmentNextAction> actions = nextActions(kind);
    return ToolSuccess(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'kind': kind.name,
        'input': value,
        'actions': <Map<String, Object?>>[
          for (final DevelopmentNextAction action in actions) action.toJson(),
        ],
      }),
    );
  }

  static DevelopmentObjectKind classify(String value, {String hint = ''}) {
    final String normalizedHint = hint.trim().toLowerCase();
    for (final DevelopmentObjectKind kind in DevelopmentObjectKind.values) {
      if (kind.name.toLowerCase() == normalizedHint) return kind;
    }
    final String lower = value.trim().toLowerCase().replaceAll('\\', '/');
    if (lower.startsWith('adb://') ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}:5555$').hasMatch(lower)) {
      return DevelopmentObjectKind.androidDevice;
    }
    if (lower.startsWith('serial://') || RegExp(r'^com\d+$').hasMatch(lower)) {
      return DevelopmentObjectKind.serialDevice;
    }
    if (lower.startsWith('ssh://')) return DevelopmentObjectKind.sshHost;
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return DevelopmentObjectKind.apiService;
    }
    if (lower.endsWith('.cleanup.json')) {
      return DevelopmentObjectKind.cleanupReport;
    }
    if (RegExp(r'\.(png|jpe?g|webp|bmp)$').hasMatch(lower)) {
      return DevelopmentObjectKind.screenshot;
    }
    if (RegExp(r'\.(zip|7z|rar|tar|gz|bz2|xz|zst)$').hasMatch(lower)) {
      return DevelopmentObjectKind.archive;
    }
    if (RegExp(r'\.(sqlite3?|db)$').hasMatch(lower)) {
      return DevelopmentObjectKind.database;
    }
    if (RegExp(r'\.(log|trace|out)$').hasMatch(lower)) {
      return DevelopmentObjectKind.logFile;
    }
    if (RegExp(
      r'\.(dart|rs|go|py|js|jsx|ts|tsx|java|kt|swift|c|cc|cpp|h|hpp|cs|rb|php|sh|ps1)$',
    ).hasMatch(lower)) {
      return DevelopmentObjectKind.sourceFile;
    }
    if (lower.endsWith('.git') || lower.contains('/.git')) {
      return DevelopmentObjectKind.gitRepository;
    }
    return DevelopmentObjectKind.unknown;
  }

  static List<DevelopmentNextAction> nextActions(DevelopmentObjectKind kind) =>
      switch (kind) {
        DevelopmentObjectKind.sourceFile => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.file_diff',
            label: '比较差异',
            reason: '快速审查与另一版本的变化',
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.file_hash',
            label: '计算哈希',
            reason: '生成可验证的文件指纹',
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.code_structure_search',
            label: '定位结构',
            reason: '继续查找相关类和函数',
          ),
        ],
        DevelopmentObjectKind.logFile => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.regex_test',
            label: '提取错误',
            reason: '快速筛选重复错误和关键字',
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.file_search',
            label: '关联源码',
            reason: '根据错误符号定位实现',
          ),
        ],
        DevelopmentObjectKind.androidDevice => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.adb.command',
            label: '读取设备信息',
            reason: '先确认系统和当前状态',
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.adb.command',
            label: '采集 Logcat',
            reason: '获取真实运行时证据',
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.adb.command',
            label: '截图并 OCR',
            reason: '关联屏幕状态与日志',
          ),
        ],
        DevelopmentObjectKind.sshHost => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.remote.open_interactive',
            label: '打开 SSH',
            reason: '建立可复用的认证会话',
            requiresApproval: true,
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.remote.sftp_list',
            label: '同会话打开 SFTP',
            reason: '无需重复输入密码',
          ),
        ],
        DevelopmentObjectKind.database => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.sqlite.inspect',
            label: '检查结构',
            reason: '先以只读方式了解表和视图',
          ),
          DevelopmentNextAction(
            toolId: 'vibekits.sqlite.query',
            label: '查询数据',
            reason: '运行有界只读 SQL',
          ),
        ],
        DevelopmentObjectKind.archive => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.file_hash',
            label: '校验完整性',
            reason: '解压前生成文件指纹',
          ),
        ],
        DevelopmentObjectKind.apiService => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.http.request',
            label: '发送请求',
            reason: '记录状态码、耗时和脱敏响应',
            requiresApproval: true,
          ),
        ],
        DevelopmentObjectKind.screenshot => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.screenshot.ocr',
            label: 'OCR 识别',
            reason: '提取屏幕错误供 Harness 继续分析',
          ),
        ],
        DevelopmentObjectKind.serialDevice => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.serial.transact',
            label: '打开串口调试',
            reason: '使用已保存参数进行收发',
            requiresApproval: true,
          ),
        ],
        DevelopmentObjectKind.cleanupReport => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.disk.analyze',
            label: '重新分析空间',
            reason: '验证清理后的真实可用容量',
          ),
        ],
        _ => const <DevelopmentNextAction>[
          DevelopmentNextAction(
            toolId: 'vibekits.file_hash',
            label: '识别并校验',
            reason: '未知对象先执行安全只读检查',
          ),
        ],
      };
}
