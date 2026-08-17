import 'crypto_tools.dart';
import 'encoding_tools.dart';
import 'file_tools.dart';
import 'format_tools.dart';
import 'network_tools.dart';
import 'time_tools.dart';
import 'tool_result.dart';

/// 工具组（按 docs/06 §6.1 分组）。
abstract final class ToolGroups {
  static const String calculate = '计算调试';
  static const String ai = '智能开发';
  static const String database = '数据库';
  static const String remote = '远程连接';
  static const String sourceControl = '版本控制';
  static const String encoding = '编码转换';
  static const String crypto = '加密生成';
  static const String time = '时间文本';
  static const String format = '格式处理';
  static const String network = '网络开发';
  static const String file = '文件工具';
}

/// 一个开发工具的静态描述。
class ToolSpec {
  const ToolSpec({
    required this.id,
    required this.name,
    required this.group,
    required this.description,
    this.run,
    this.runAsync,
    this.offline = true,
    this.paramLabel,
  });

  final String id;
  final String name;
  final String group;
  final String description;
  final bool offline;
  final String? paramLabel;
  final ToolResult Function(String input, String params)? run;
  final Future<ToolResult> Function(String input, String params)? runAsync;
}

/// 完整能力清单。左侧导航只展示独立工作区，微工具由集合工作区消费。
final List<ToolSpec> allDevToolRegistry = <ToolSpec>[
  const ToolSpec(
    id: 'programmer_calculator',
    name: '程序员计算器',
    group: ToolGroups.calculate,
    description: '整数表达式、进制转换、位运算和有符号/无符号解释。',
  ),
  const ToolSpec(
    id: 'database_manager',
    name: '数据库管理器',
    group: ToolGroups.database,
    description: '拖入 SQLite 数据库，浏览表和视图并运行有界只读 SQL。',
  ),
  const ToolSpec(
    id: 'remote_workspace',
    name: 'SSH / SFTP',
    group: ToolGroups.remote,
    description: '统一管理安全终端、双栏文件和本地/远程/SOCKS5 端口转发。',
  ),
  const ToolSpec(
    id: 'serial_port',
    name: '串口调试',
    group: ToolGroups.remote,
    description: '打开 Windows/macOS 串口，配置波特率和帧格式并进行文本或 HEX 收发。',
  ),
  const ToolSpec(
    id: 'api_workspace',
    name: 'API 调试',
    group: ToolGroups.network,
    description: '发送有界 HTTP 请求，查看状态、响应头、耗时和正文。',
    offline: false,
  ),
  const ToolSpec(
    id: 'git_workspace',
    name: 'Git 工作区',
    group: ToolGroups.sourceControl,
    description: '只读查看仓库根目录、分支、工作区变更、Diff 和最近提交。',
  ),
  const ToolSpec(
    id: 'github_diagnostics',
    name: 'GitHub 网络诊断',
    group: ToolGroups.network,
    description: '只读检查 GitHub 的 DNS、TLS、HTTPS、代理、hosts 与 SSH 端口。',
    offline: false,
  ),
  ToolSpec(
    id: 'base64_encode',
    name: 'Base64 编码',
    group: ToolGroups.encoding,
    description: '将 UTF-8 文本编码为 Base64。',
    run: (String input, String params) => EncodingTools.base64Encode(input),
  ),
  ToolSpec(
    id: 'base64_decode',
    name: 'Base64 解码',
    group: ToolGroups.encoding,
    description: '将 Base64 解码为 UTF-8 文本。',
    run: (String input, String params) => EncodingTools.base64Decode(input),
  ),
  ToolSpec(
    id: 'url_encode',
    name: 'URL 编码',
    group: ToolGroups.encoding,
    description: '对文本进行百分号编码。',
    run: (String input, String params) => EncodingTools.urlEncode(input),
  ),
  ToolSpec(
    id: 'url_decode',
    name: 'URL 解码',
    group: ToolGroups.encoding,
    description: '对百分号编码进行解码。',
    run: (String input, String params) => EncodingTools.urlDecode(input),
  ),
  ToolSpec(
    id: 'html_encode',
    name: 'HTML 实体编码',
    group: ToolGroups.encoding,
    description: '将 & < > " \' 转义为 HTML 实体。',
    run: (String input, String params) => EncodingTools.htmlEncode(input),
  ),
  ToolSpec(
    id: 'html_decode',
    name: 'HTML 实体解码',
    group: ToolGroups.encoding,
    description: '将 HTML 实体还原为字符。',
    run: (String input, String params) => EncodingTools.htmlDecode(input),
  ),
  ToolSpec(
    id: 'unicode_escape',
    name: 'Unicode 转义',
    group: ToolGroups.encoding,
    description: '将非 ASCII 字符转为 \\uXXXX 转义序列。',
    run: (String input, String params) => EncodingTools.unicodeEscape(input),
  ),
  ToolSpec(
    id: 'unicode_unescape',
    name: 'Unicode 反转义',
    group: ToolGroups.encoding,
    description: '将 \\uXXXX 转义序列还原为字符。',
    run: (String input, String params) => EncodingTools.unicodeUnescape(input),
  ),
  ToolSpec(
    id: 'hex_encode',
    name: 'Hex 编码',
    group: ToolGroups.encoding,
    description: '将 UTF-8 文本转为十六进制字节串。',
    run: (String input, String params) => EncodingTools.hexEncode(input),
  ),
  ToolSpec(
    id: 'hex_decode',
    name: 'Hex 解码',
    group: ToolGroups.encoding,
    description: '将十六进制字节串解码为 UTF-8 文本。',
    run: (String input, String params) => EncodingTools.hexDecode(input),
  ),
  ToolSpec(
    id: 'md5',
    name: 'MD5',
    group: ToolGroups.crypto,
    description: '计算 UTF-8 文本的 MD5。',
    run: (String input, String params) => CryptoTools.md5(input),
  ),
  ToolSpec(
    id: 'sha1',
    name: 'SHA-1',
    group: ToolGroups.crypto,
    description: '计算 UTF-8 文本的 SHA-1。',
    run: (String input, String params) => CryptoTools.sha1(input),
  ),
  ToolSpec(
    id: 'sha256',
    name: 'SHA-256',
    group: ToolGroups.crypto,
    description: '计算 UTF-8 文本的 SHA-256。',
    run: (String input, String params) => CryptoTools.sha256(input),
  ),
  ToolSpec(
    id: 'sha512',
    name: 'SHA-512',
    group: ToolGroups.crypto,
    description: '计算 UTF-8 文本的 SHA-512。',
    run: (String input, String params) => CryptoTools.sha512(input),
  ),
  ToolSpec(
    id: 'hmac_sha256',
    name: 'HMAC-SHA256',
    group: ToolGroups.crypto,
    description: '使用密钥计算消息的 HMAC-SHA256。',
    paramLabel: '密钥',
    run: (String input, String params) => CryptoTools.hmacSha256(params, input),
  ),
  ToolSpec(
    id: 'uuid_v4',
    name: 'UUID v4',
    group: ToolGroups.crypto,
    description: '生成随机 UUID v4，参数为数量（默认 1）。',
    paramLabel: '数量',
    run: (String input, String params) => CryptoTools.uuidV4(params),
  ),
  ToolSpec(
    id: 'random_password',
    name: '随机密码',
    group: ToolGroups.crypto,
    description: '生成随机密码，参数为长度（默认 16）。',
    paramLabel: '长度',
    run: (String input, String params) => CryptoTools.randomPassword(params),
  ),
  ToolSpec(
    id: 'timestamp_to_date',
    name: '时间戳转日期',
    group: ToolGroups.time,
    description: '将 Unix 秒/毫秒时间戳转为本地时间和 UTC。',
    run: (String input, String params) => TimeTools.timestampToDate(input),
  ),
  ToolSpec(
    id: 'date_to_timestamp',
    name: '日期转时间戳',
    group: ToolGroups.time,
    description: '将日期时间转为 Unix 秒/毫秒时间戳。',
    run: (String input, String params) => TimeTools.dateToTimestamp(input),
  ),
  ToolSpec(
    id: 'regex_test',
    name: '正则测试',
    group: ToolGroups.time,
    description: '测试正则表达式，参数为模式，输入为文本。',
    paramLabel: '模式',
    run: (String input, String params) => TimeTools.regexTest(params, input),
  ),
  ToolSpec(
    id: 'json_format',
    name: 'JSON 格式化',
    group: ToolGroups.format,
    description: '校验并格式化 JSON。',
    run: (String input, String params) => FormatTools.jsonFormat(input),
  ),
  ToolSpec(
    id: 'json_validate',
    name: 'JSON 校验',
    group: ToolGroups.format,
    description: '校验 JSON 并报告顶层类型。',
    run: (String input, String params) => FormatTools.jsonValidate(input),
  ),
  ToolSpec(
    id: 'url_parse',
    name: 'URL 分解',
    group: ToolGroups.network,
    description: '分解 URL 为 scheme/host/port/path/query/fragment。',
    run: (String input, String params) => NetworkTools.urlParse(input),
  ),
  ToolSpec(
    id: 'cidr_calc',
    name: 'IP/CIDR 计算',
    group: ToolGroups.network,
    description: '计算 IPv4 CIDR 的网络地址、广播地址与可用数量。',
    run: (String input, String params) => NetworkTools.cidrCalc(input),
  ),
  ToolSpec(
    id: 'dns_lookup',
    name: 'DNS 查询',
    group: ToolGroups.network,
    description: '查询域名的 A/AAAA 记录。',
    offline: false,
    runAsync: (String input, String params) => NetworkTools.dnsLookup(input),
  ),
  ToolSpec(
    id: 'tcp_port',
    name: 'TCP 端口测试',
    group: ToolGroups.network,
    description: '测试 host:port 是否可连接。',
    offline: false,
    runAsync: (String input, String params) {
      final List<String> parts = input.trim().split(':');
      final int? port = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (parts.isEmpty || port == null) {
        return Future<ToolResult>.value(const ToolFailure('输入格式应为 host:port'));
      }
      return NetworkTools.tcpPort(parts[0], port);
    },
  ),
  ToolSpec(
    id: 'file_hash',
    name: '文件哈希',
    group: ToolGroups.file,
    description: '计算文件哈希，参数为算法（md5/sha1/sha256/sha512），输入为路径。',
    paramLabel: '算法',
    run: (String input, String params) => FileTools.fileHash(
      input,
      params.trim().isEmpty ? 'sha256' : params.trim(),
    ),
  ),
  ToolSpec(
    id: 'batch_rename',
    name: '批量重命名',
    group: ToolGroups.file,
    description: '选择文件夹，预览并安全执行查找替换、前后缀、大小写和序号规则。',
    paramLabel: '查找|替换',
    run: (String input, String params) {
      final List<String> parts = params.split('|');
      return FileTools.batchRenamePlan(
        input,
        parts.isNotEmpty ? parts[0] : '',
        parts.length > 1 ? parts[1] : '',
      );
    },
  ),
  const ToolSpec(
    id: 'duplicate_files',
    name: '重复文件',
    group: ToolGroups.file,
    description: '按大小预筛并用完整 SHA-256 确认重复内容，复核后移入回收站。',
  ),
  const ToolSpec(
    id: 'file_search',
    name: '文件搜索',
    group: ToolGroups.file,
    description: '按文件名或内容快速搜索，结果可定位、复制路径并继续计算哈希。',
  ),
];

const Set<String> _standaloneToolIds = <String>{
  'programmer_calculator',
  'database_manager',
  'remote_workspace',
  'serial_port',
  'api_workspace',
  'git_workspace',
  'github_diagnostics',
  'file_hash',
  'file_search',
  'batch_rename',
  'duplicate_files',
};

const ToolSpec utilityCollectionTool = ToolSpec(
  id: 'utility_collection',
  name: '转换与检查',
  group: ToolGroups.format,
  description: '编码、哈希、格式化、时间、正则和网络小工具集中在右侧 Tab。',
);

/// 左侧只保留具有独立任务流的工作区。
final List<ToolSpec> devToolRegistry = <ToolSpec>[
  for (final ToolSpec tool in allDevToolRegistry)
    if (_standaloneToolIds.contains(tool.id)) tool,
  utilityCollectionTool,
];

/// 小而同构的输入/输出工具，不再占用左侧导航。
final List<ToolSpec> utilityToolRegistry = <ToolSpec>[
  for (final ToolSpec tool in allDevToolRegistry)
    if (!_standaloneToolIds.contains(tool.id)) tool,
];
