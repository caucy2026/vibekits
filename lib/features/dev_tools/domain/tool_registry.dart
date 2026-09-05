import 'dart:convert';

import 'audio_analysis_service.dart';
import 'crypto_tools.dart';
import 'development_object_router.dart';
import 'code_statistics_service.dart';
import 'code_structure_search_service.dart';
import 'encoding_tools.dart';
import 'file_tools.dart';
import 'format_tools.dart';
import 'network_tools.dart';
import 'micro_benchmark_service.dart';
import 'time_tools.dart';
import 'tool_result.dart';
import 'utility_plus_tools.dart';

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
  static const String virtualization = '虚拟化';
  static const String file = '文件工具';
  static const String audio = '音频调试';
  static const String system = '系统诊断';
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
    this.aiUseWhen,
    this.aiAvoidWhen,
    this.aiExamples = const <String>[],
    this.harnessToolIds = const <String>[],
  });

  final String id;
  final String name;
  final String group;
  final String description;
  final bool offline;
  final String? paramLabel;
  final String? aiUseWhen;
  final String? aiAvoidWhen;
  final List<String> aiExamples;
  final List<String> harnessToolIds;
  final ToolResult Function(String input, String params)? run;
  final Future<ToolResult> Function(String input, String params)? runAsync;
}

ToolSpec _plusTool({
  required String id,
  required String name,
  required String group,
  required String description,
  required ToolResult Function(String input, String params) run,
  String? paramLabel,
}) => ToolSpec(
  id: id,
  name: name,
  group: group,
  description: description,
  paramLabel: paramLabel,
  aiUseWhen: '需要确定、离线地完成$name时。',
  aiAvoidWhen: '输入格式不明确、需要联网验证或需要修改源文件时不要使用。',
  aiExamples: <String>['使用$name处理当前输入'],
  run: run,
);

/// 完整能力清单。左侧导航只展示独立工作区，微工具由集合工作区消费。
final List<ToolSpec> allDevToolRegistry = <ToolSpec>[
  ToolSpec(
    id: 'stopwatch',
    name: '秒表（1/100 秒）',
    group: ToolGroups.time,
    description: '圆形时钟与数字同步显示，支持开始、暂停、计次和复位，精度 0.01 秒。',
    paramLabel: '秒数',
    run: (String input, String params) => TimeTools.stopwatchFormat(input),
  ),
  const ToolSpec(
    id: 'programmer_calculator',
    name: '程序员计算器（HEX/DEC）',
    group: ToolGroups.calculate,
    description: '整数表达式、进制转换、位运算和有符号/无符号解释。',
    harnessToolIds: <String>['vibekits.calculator.programmer'],
  ),
  const ToolSpec(
    id: 'system_resources',
    name: '资源诊断（CPU/GPU）',
    group: ToolGroups.system,
    description:
        '采样 Windows、macOS、Android 的 CPU、内存、GPU、磁盘和 Top 进程，也可通过内置 ADB 分析 Android 设备。',
    aiUseWhen: '用户说系统卡顿、发热、快死机、内存不足、CPU/GPU 占用高或想找异常进程时。',
    aiAvoidWhen: '一次快照不能证明间歇性问题；不得据此直接结束进程或删除文件。',
    aiExamples: <String>['帮我分析当前系统为什么卡', '检查这台 Android 设备的 CPU、内存和磁盘'],
    harnessToolIds: <String>[
      'vibekits.system.resources',
      'vibekits.system.capability_check',
    ],
  ),
  const ToolSpec(
    id: 'database_manager',
    name: '数据库管理（SQL）',
    group: ToolGroups.database,
    description: '拖入 SQLite 数据库，浏览表和视图并运行有界只读 SQL。',
    harnessToolIds: <String>[
      'vibekits.sqlite.inspect',
      'vibekits.sqlite.query',
      'vibekits.database.remote_list_profiles',
      'vibekits.database.remote_inspect',
      'vibekits.database.remote_query',
    ],
  ),
  const ToolSpec(
    id: 'remote_workspace',
    name: '远程连接（SSH/SFTP）',
    group: ToolGroups.remote,
    description: '统一管理安全终端、双栏文件和本地/远程/SOCKS5 端口转发。',
    harnessToolIds: <String>[
      'vibekits.remote.list_profiles',
      'vibekits.remote.open_interactive',
      'vibekits.remote.ssh_exec',
      'vibekits.remote.sftp_list',
      'vibekits.remote.sftp_upload',
      'vibekits.remote.sftp_download',
      'vibekits.windows_node.inspect',
      'vibekits.windows_node.plan',
      'vibekits.windows_node.apply',
      'vibekits.windows_node.verify',
      'vibekits.windows_node.list_devices',
      'vibekits.windows_node.enroll_device',
      'vibekits.windows_node.revoke_device',
      'vibekits.windows_node.export_onboarding',
      'vibekits.windows_node.rollback',
    ],
  ),
  const ToolSpec(
    id: 'serial_port',
    name: '串口调试（Serial）',
    group: ToolGroups.remote,
    description: '打开 Windows/macOS 串口，配置波特率和帧格式并进行文本或 HEX 收发。',
    harnessToolIds: <String>[
      'vibekits.serial.list_ports',
      'vibekits.serial.transact',
      'vibekits.serial.session_open',
      'vibekits.serial.session_read',
      'vibekits.serial.session_write',
      'vibekits.serial.session_close',
    ],
  ),
  const ToolSpec(
    id: 'adb_workspace',
    name: '安卓调试（ADB）',
    group: ToolGroups.remote,
    description: '管理 Android USB/无线设备、Shell、文件、Logcat、截图和 APK。',
    offline: false,
    harnessToolIds: <String>[
      'vibekits.adb.list_devices',
      'vibekits.adb.connect',
      'vibekits.adb.command',
      'vibekits.adb.shell',
      'vibekits.adb.logcat',
      'vibekits.adb.install_apk',
      'vibekits.adb.push_file',
      'vibekits.adb.pull_file',
      'vibekits.adb.screenshot',
      'vibekits.adb.session_open',
      'vibekits.adb.session_status',
      'vibekits.adb.session_close',
    ],
  ),
  const ToolSpec(
    id: 'api_workspace',
    name: '接口调试（API）',
    group: ToolGroups.network,
    description: '发送有界 HTTP 请求，查看状态、响应头、耗时和正文。',
    offline: false,
    harnessToolIds: <String>['vibekits.http.request'],
  ),
  const ToolSpec(
    id: 'packet_capture',
    name: '网络抓包（PCAP）',
    group: ToolGroups.network,
    description: '使用内置 WinDivert 实时抓取和过滤网络包，保存、读取并分析标准 PCAP 文件。',
    offline: false,
    aiUseWhen: '用户需要抓包、保存网络流量、读取 PCAP、定位协议或端点流量时。',
    aiAvoidWhen: '不得抓取未获授权的第三方设备流量；实时抓包在 Windows 需要管理员权限。',
    aiExamples: <String>['抓 30 秒 DNS 包并保存', '分析这个 PCAP 里流量最多的端点'],
    harnessToolIds: <String>[
      'vibekits.capture.status',
      'vibekits.capture.start',
      'vibekits.capture.stop',
      'vibekits.capture.read',
      'vibekits.capture.analyze',
    ],
  ),
  const ToolSpec(
    id: 'git_workspace',
    name: '版本控制（Git）',
    group: ToolGroups.sourceControl,
    description:
        '查看仓库、Diff 和提交；读取 Gerrit/远端 refs 与 manifest，按需浅克隆单仓；通过预览、秘密阻断及分离审批安全备份。',
    harnessToolIds: <String>[
      'vibekits.git.inspect',
      'vibekits.git.list_remote_refs',
      'vibekits.git.read_remote_file',
      'vibekits.git.clone_minimal',
      'vibekits.git.compare_refs',
      'vibekits.git.create_local_branch',
      'vibekits.git.backup_preview',
      'vibekits.git.backup_commit',
      'vibekits.git.backup_push',
      'vibekits.git.verify_remote_ref',
    ],
  ),
  const ToolSpec(
    id: 'file_diff',
    name: '文件比较（Diff）',
    group: ToolGroups.file,
    description: '选择任意两个文本或源码文件，自动识别编码并按行比较、复制或保存差异。',
    harnessToolIds: <String>['vibekits.file_diff'],
  ),
  const ToolSpec(
    id: 'github_diagnostics',
    name: '网络诊断（GitHub）',
    group: ToolGroups.network,
    description: '分层检查 GitHub 凭据与网络，发现真实回环代理并可回滚地只修复 GitHub Git。',
    offline: false,
    harnessToolIds: <String>[
      'vibekits.github.diagnose',
      'vibekits.github.proxy_candidates',
      'vibekits.github.proxy_plan',
      'vibekits.github.proxy_apply',
      'vibekits.github.proxy_rollback',
    ],
  ),
  const ToolSpec(
    id: 'network_virtualization',
    name: '网络代理（Clash Verge）',
    group: ToolGroups.network,
    description: '使用内置 Mihomo 管理订阅、节点、测速、连接、规则、日志与系统代理。',
    harnessToolIds: <String>[
      'vibekits.runtime.inspect',
      'vibekits.proxy.start',
      'vibekits.proxy.stop',
      'vibekits.proxy.system_apply',
      'vibekits.proxy.system_restore',
      'vibekits.runtime.status',
    ],
  ),
  const ToolSpec(
    id: 'virtual_machine',
    name: '轻量虚拟机（QEMU）',
    group: ToolGroups.virtualization,
    description: '使用内置 QEMU 创建虚拟磁盘并运行 Windows、Linux 等本地虚拟机。',
    harnessToolIds: <String>[
      'vibekits.runtime.inspect',
      'vibekits.vm.start',
      'vibekits.vm.stop',
      'vibekits.vm.create_disk',
      'vibekits.runtime.status',
    ],
  ),
  ToolSpec(
    id: 'audio_analyzer',
    name: '音频调试（PCM/WAV）',
    group: ToolGroups.audio,
    description:
        '打开 PCM/WAV，查看多声道波形、播放声音并分析格式、峰值、RMS、谐波、THD、THD+N、SNR、噪声底、削波、静音和直流偏置。',
    aiUseWhen: '需要判断 PCM/WAV 参数、信号是否削波或静音、查看音频基础质量指标时。',
    aiAvoidWhen: '需要修改原始音频、主观评价内容或分析未知压缩编码时不要直接使用。',
    aiExamples: const <String>['分析这份 PCM 的波形和信号质量', '检查 WAV 是否削波、静音或存在直流偏置'],
    harnessToolIds: const <String>[
      'vibekits.audio.inspect',
      'vibekits.audio.pcm_to_wav',
      'vibekits.audio.play',
      'vibekits.audio.pause',
      'vibekits.audio.stop',
      'vibekits.audio.generate_tone',
    ],
    runAsync: (String input, String params) async {
      try {
        final Object? decoded = params.trim().isEmpty
            ? const <String, Object?>{}
            : jsonDecode(params);
        final Map<String, Object?> options = decoded is Map
            ? decoded.map(
                (Object? key, Object? value) => MapEntry('$key', value),
              )
            : const <String, Object?>{};
        final AudioAnalysisResult result = await AudioAnalysisService.inspect(
          input,
          rawFormat: PcmAudioFormat.fromJson(options),
        );
        return ToolSuccess(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );
      } on Object catch (error) {
        return ToolFailure('$error');
      }
    },
  ),
  _plusTool(
    id: 'json_minify',
    name: 'JSON 压缩',
    group: ToolGroups.format,
    description: '校验 JSON 并移除无意义空白。',
    run: (input, params) => UtilityPlusTools.jsonMinify(input),
  ),
  _plusTool(
    id: 'json_escape',
    name: 'JSON 字符串转义',
    group: ToolGroups.format,
    description: '把任意文本转换为合法 JSON 字符串字面量。',
    run: (input, params) => UtilityPlusTools.jsonEscape(input),
  ),
  _plusTool(
    id: 'json_unescape',
    name: 'JSON 字符串反转义',
    group: ToolGroups.format,
    description: '解析 JSON 字符串字面量并还原原文。',
    run: (input, params) => UtilityPlusTools.jsonUnescape(input),
  ),
  _plusTool(
    id: 'xml_format',
    name: 'XML 格式化',
    group: ToolGroups.format,
    description: '校验并缩进 XML。',
    run: (input, params) => UtilityPlusTools.xmlFormat(input),
  ),
  _plusTool(
    id: 'xml_minify',
    name: 'XML 压缩',
    group: ToolGroups.format,
    description: '校验 XML 并移除格式化空白。',
    run: (input, params) => UtilityPlusTools.xmlMinify(input),
  ),
  _plusTool(
    id: 'csv_to_json',
    name: 'CSV 转 JSON',
    group: ToolGroups.format,
    description: '以首行为表头，将标准 CSV 转为对象数组。',
    run: (input, params) => UtilityPlusTools.csvToJson(input),
  ),
  _plusTool(
    id: 'json_to_csv',
    name: 'JSON 转 CSV',
    group: ToolGroups.format,
    description: '将 JSON 对象数组转换为带表头的 CSV。',
    run: (input, params) => UtilityPlusTools.jsonToCsv(input),
  ),
  _plusTool(
    id: 'jwt_decode',
    name: 'JWT 解码',
    group: ToolGroups.crypto,
    description: '离线解码 JWT header/payload，并明确标注未验证签名。',
    run: (input, params) => UtilityPlusTools.jwtDecode(input),
  ),
  _plusTool(
    id: 'jwt_expiry',
    name: 'JWT 过期检查',
    group: ToolGroups.crypto,
    description: '读取 JWT exp 并计算过期时间；不验证签名。',
    run: (input, params) => UtilityPlusTools.jwtExpiry(input),
  ),
  _plusTool(
    id: 'number_base_convert',
    name: '2～36 进制转换',
    group: ToolGroups.calculate,
    description: '使用任意精度整数在 2～36 进制间转换。',
    paramLabel: '源进制|目标进制',
    run: UtilityPlusTools.numberBaseConvert,
  ),
  _plusTool(
    id: 'endian_swap',
    name: '字节序反转',
    group: ToolGroups.calculate,
    description: '按字节反转十六进制数据的端序。',
    run: (input, params) => UtilityPlusTools.endianSwap(input),
  ),
  _plusTool(
    id: 'ascii_inspect',
    name: '字符码检查',
    group: ToolGroups.encoding,
    description: '列出字符的 Unicode、十进制码点和原字符。',
    run: (input, params) => UtilityPlusTools.asciiInspect(input),
  ),
  _plusTool(
    id: 'chmod_decode',
    name: 'chmod 权限解码',
    group: ToolGroups.calculate,
    description: '将八进制 Unix 权限转换为 rwx 符号。',
    run: (input, params) => UtilityPlusTools.chmodDecode(input),
  ),
  _plusTool(
    id: 'chmod_encode',
    name: 'chmod 权限编码',
    group: ToolGroups.calculate,
    description: '将九位 rwx 符号转换为八进制权限。',
    run: (input, params) => UtilityPlusTools.chmodEncode(input),
  ),
  _plusTool(
    id: 'semver_compare',
    name: '语义版本比较',
    group: ToolGroups.calculate,
    description: '按 SemVer 规则比较正式版和预发布版本。',
    paramLabel: '另一个版本',
    run: UtilityPlusTools.semverCompare,
  ),
  _plusTool(
    id: 'bytes_convert',
    name: '存储单位转换',
    group: ToolGroups.calculate,
    description: '转换 B/KB/MB/GB 与 KiB/MiB/GiB。',
    paramLabel: '源单位|目标单位',
    run: UtilityPlusTools.bytesConvert,
  ),
  _plusTool(
    id: 'duration_convert',
    name: '时间单位转换',
    group: ToolGroups.calculate,
    description: '转换毫秒、秒、分钟、小时和天。',
    paramLabel: '源单位|目标单位',
    run: UtilityPlusTools.durationConvert,
  ),
  _plusTool(
    id: 'hex_to_rgb',
    name: 'HEX 转 RGB',
    group: ToolGroups.encoding,
    description: '将 #RGB/#RRGGBB 转为结构化 RGB。',
    run: (input, params) => UtilityPlusTools.hexToRgb(input),
  ),
  _plusTool(
    id: 'rgb_to_hex',
    name: 'RGB 转 HEX',
    group: ToolGroups.encoding,
    description: '将三个 RGB 分量转换为十六进制颜色。',
    run: (input, params) => UtilityPlusTools.rgbToHex(input),
  ),
  _plusTool(
    id: 'query_parse',
    name: '查询参数解析',
    group: ToolGroups.network,
    description: '把 URL query string 解析为保留重复键的 JSON。',
    run: (input, params) => UtilityPlusTools.queryParse(input),
  ),
  _plusTool(
    id: 'query_build',
    name: '查询参数生成',
    group: ToolGroups.network,
    description: '把 JSON 对象编码为 URL query string。',
    run: (input, params) => UtilityPlusTools.queryBuild(input),
  ),
  _plusTool(
    id: 'regex_escape',
    name: '正则字面量转义',
    group: ToolGroups.time,
    description: '把普通文本安全转义为正则字面量。',
    run: (input, params) => UtilityPlusTools.regexEscape(input),
  ),
  _plusTool(
    id: 'glob_test',
    name: 'Glob 匹配测试',
    group: ToolGroups.time,
    description: '测试路径是否匹配 *, ** 和 ? glob。',
    paramLabel: 'Glob 模式',
    run: UtilityPlusTools.globTest,
  ),
  _plusTool(
    id: 'line_sort',
    name: '文本行排序',
    group: ToolGroups.time,
    description: '按 Unicode 顺序排列文本行。',
    paramLabel: 'asc 或 desc',
    run: UtilityPlusTools.lineSort,
  ),
  _plusTool(
    id: 'line_unique',
    name: '文本行去重',
    group: ToolGroups.time,
    description: '保持首次出现顺序删除重复行。',
    run: (input, params) => UtilityPlusTools.lineUnique(input),
  ),
  _plusTool(
    id: 'text_statistics',
    name: '文本统计',
    group: ToolGroups.time,
    description: '统计字符、UTF-8 字节、单词和行数。',
    run: (input, params) => UtilityPlusTools.textStatistics(input),
  ),
  _plusTool(
    id: 'case_convert',
    name: '命名风格转换',
    group: ToolGroups.time,
    description: '转换大小写、snake、kebab、camel、Pascal 和标题格式。',
    paramLabel: '目标格式',
    run: UtilityPlusTools.caseConvert,
  ),
  _plusTool(
    id: 'line_ending_normalize',
    name: '换行符规范化',
    group: ToolGroups.time,
    description: '统一为 LF 或 CRLF，不修改原文件。',
    paramLabel: 'lf 或 crlf',
    run: UtilityPlusTools.normalizeLineEndings,
  ),
  _plusTool(
    id: 'http_status_lookup',
    name: 'HTTP 状态码查询',
    group: ToolGroups.network,
    description: '查询常见 HTTP 状态码名称和类别。',
    run: (input, params) => UtilityPlusTools.httpStatusLookup(input),
  ),
  _plusTool(
    id: 'mime_lookup',
    name: 'MIME 类型查询',
    group: ToolGroups.network,
    description: '按文件扩展名查询常见 MIME 类型。',
    run: (input, params) => UtilityPlusTools.mimeLookup(input),
  ),
  ToolSpec(
    id: 'next_action_recommendation',
    name: '下一步建议',
    group: ToolGroups.ai,
    description: '识别文件、设备、连接或报告，返回最有价值的下一步工具动作。',
    paramLabel: '可选对象类型',
    aiUseWhen: '当用户给出一个对象但没有指定操作，或当前工具已产生结果时。',
    aiAvoidWhen: '用户已明确指定工具和操作时不要增加额外步骤。',
    aiExamples: <String>['为 adb://192.168.3.63:5555 推荐下一步'],
    run: DevelopmentObjectRouter.recommend,
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
    id: 'json_query',
    name: '结构化数据查询',
    group: ToolGroups.format,
    description: '安全查询 JSON/YAML/TOML/XML，支持点路径、数组下标和通配，例如 auto|.items[*].id。',
    paramLabel: '格式|查询路径，如 yaml|.server.port',
    aiUseWhen: '需要从 API 响应、配置或日志中精确提取字段时，优先于读取整段文本。',
    aiAvoidWhen: '需要执行任意 jq/yq 表达式、修改源文件或输入不是结构化数据时不要使用。',
    aiExamples: <String>['从 API 响应提取 auto|.data.items[*].id'],
    run: (String input, String params) =>
        FormatTools.structuredQuery(input, params),
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
    name: '文件哈希（Hash）',
    group: ToolGroups.file,
    description: '计算文件哈希，参数为算法（md5/sha1/sha256/sha512），输入为路径。',
    paramLabel: '算法',
    run: (String input, String params) => FileTools.fileHash(
      input,
      params.trim().isEmpty ? 'sha256' : params.trim(),
    ),
  ),
  ToolSpec(
    id: 'code_statistics',
    name: '代码统计（LOC）',
    group: ToolGroups.file,
    description: '后台统计项目或单文件的语言、文件数、代码、注释和空白行，自动跳过依赖与构建目录。',
    paramLabel: '可选扩展名，如 dart,ts,rs',
    aiUseWhen: '需要快速了解项目规模、主要语言、代码与注释构成时，优先于逐文件读取。',
    aiAvoidWhen: '需要语义分析、复杂度、安全漏洞判断或精确编译器 AST 结果时不要使用。',
    aiExamples: <String>['统计当前工作区主要语言和代码行数'],
    runAsync: (String input, String params) =>
        CodeStatisticsService.analyze(input, extensions: params),
  ),
  ToolSpec(
    id: 'code_structure_search',
    name: '代码结构搜索（Structure）',
    group: ToolGroups.file,
    description: '后台按声明结构查找类、类型和函数，返回文件、行号与声明；不修改源码。',
    paramLabel: '类型|符号，如 class|UserService',
    aiUseWhen: '需要定位类、函数或类型定义时，优先于读取整个仓库或普通全文搜索。',
    aiAvoidWhen: '需要完整编译器语义、引用关系、宏展开或自动改写时不要使用。',
    aiExamples: <String>['在工作区定位 class|HarnessToolBridge'],
    runAsync: (String input, String params) =>
        CodeStructureSearchService.search(input, params),
  ),
  ToolSpec(
    id: 'safe_benchmark',
    name: '安全性能基准（Benchmark）',
    group: ToolGroups.calculate,
    description: '对内置 SHA-256、JSON 解析或 Base64 做预热和多轮统计，不执行任意命令。',
    paramLabel: '操作|次数，如 json_parse|50',
    aiUseWhen: '需要在当前机器比较内置数据处理操作的相对耗时时使用。',
    aiAvoidWhen: '需要运行 shell、外部程序、清缓存或得出跨机器绝对性能结论时不要使用。',
    aiExamples: <String>['对这段 JSON 执行 json_parse|50'],
    runAsync: (String input, String params) =>
        MicroBenchmarkService.run(input, params),
  ),
  ToolSpec(
    id: 'batch_rename',
    name: '批量重命名（Rename）',
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
    name: '重复文件（Duplicate）',
    group: ToolGroups.file,
    description: '按大小预筛并用完整 SHA-256 确认重复内容，复核后移入回收站。',
    harnessToolIds: <String>['vibekits.files.duplicate_scan'],
  ),
  const ToolSpec(
    id: 'file_search',
    name: '文件搜索（Search）',
    group: ToolGroups.file,
    description: '按文件名或内容快速搜索，结果可定位、复制路径并继续计算哈希。',
    harnessToolIds: <String>['vibekits.files.search'],
  ),
];

const Set<String> _standaloneToolIds = <String>{
  'stopwatch',
  'programmer_calculator',
  'system_resources',
  'database_manager',
  'remote_workspace',
  'serial_port',
  'adb_workspace',
  'api_workspace',
  'packet_capture',
  'git_workspace',
  'file_diff',
  'github_diagnostics',
  'network_virtualization',
  'virtual_machine',
  'audio_analyzer',
  'file_hash',
  'file_search',
  'batch_rename',
  'duplicate_files',
};

const ToolSpec utilityCollectionTool = ToolSpec(
  id: 'utility_collection',
  name: '转换与检查（Convert）',
  group: ToolGroups.format,
  description: '编码、哈希、格式化、时间、正则和网络小工具集中在右侧 Tab。',
);

/// UI、审计记录与 Harness 合同共同使用的唯一工具 ID 来源。
Set<String> harnessToolIdsFor(ToolSpec tool) {
  if (tool.id == utilityCollectionTool.id) {
    return <String>{
      for (final ToolSpec utility in utilityToolRegistry)
        ...harnessToolIdsFor(utility),
    };
  }
  return tool.harnessToolIds.isEmpty
      ? <String>{'vibekits.${tool.id}'}
      : tool.harnessToolIds.toSet();
}

/// 左侧只保留具有独立任务流的工作区。
final List<ToolSpec> devToolRegistry = <ToolSpec>[
  allDevToolRegistry.singleWhere(
    (ToolSpec tool) => tool.id == 'programmer_calculator',
  ),
  allDevToolRegistry.singleWhere(
    (ToolSpec tool) => tool.id == 'network_virtualization',
  ),
  allDevToolRegistry.singleWhere(
    (ToolSpec tool) => tool.id == 'virtual_machine',
  ),
  for (final ToolSpec tool in allDevToolRegistry)
    if (_standaloneToolIds.contains(tool.id) &&
        tool.id != 'programmer_calculator' &&
        tool.id != 'network_virtualization' &&
        tool.id != 'virtual_machine')
      tool,
  utilityCollectionTool,
];

class ToolUsageContract {
  const ToolUsageContract({
    required this.repeatUse,
    required this.multiTarget,
    required this.secretHandling,
  });

  final String repeatUse;
  final String multiTarget;
  final String secretHandling;

  Map<String, String> toJson() => <String, String>{
    'repeatUse': repeatUse,
    'multiTarget': multiTarget,
    'secretHandling': secretHandling,
  };
}

/// Real-work usage rules shared by UI acceptance and Harness planning.
/// Every independent workspace must declare how repeat visits, multiple
/// targets and credentials behave; adding only a button is not sufficient.
const Map<String, ToolUsageContract> devToolUsageContracts =
    <String, ToolUsageContract>{
      'stopwatch': ToolUsageContract(
        repeatUse: '保留当前计时和计次，直到用户明确复位',
        multiTarget: '单工作区单计时器；计次用于记录多个阶段',
        secretHandling: '不处理凭据',
      ),
      'programmer_calculator': ToolUsageContract(
        repeatUse: '保留当前表达式直到用户清空',
        multiTarget: '单工作区连续计算，无目标账户',
        secretHandling: '不处理凭据',
      ),
      'network_virtualization': ToolUsageContract(
        repeatUse: '持久化订阅、活动配置和节点选择',
        multiTarget: '多个订阅并存，可一键切换',
        secretHandling: '订阅密钥进入系统凭据库',
      ),
      'virtual_machine': ToolUsageContract(
        repeatUse: '复用已有磁盘与镜像路径',
        multiTarget: '允许多个虚拟磁盘和运行实例',
        secretHandling: '不保存客户机密码',
      ),
      'system_resources': ToolUsageContract(
        repeatUse: '重新采样并保留本轮对比上下文',
        multiTarget: '本机与多个 ADB 设备按序列号区分',
        secretHandling: '不处理凭据',
      ),
      'database_manager': ToolUsageContract(
        repeatUse: '保存本地最近文件和远程连接资料',
        multiTarget: '多个数据库配置并存',
        secretHandling: '密码只进入系统凭据库',
      ),
      'remote_workspace': ToolUsageContract(
        repeatUse: '成功后自动记住主机、用户、端口和指纹',
        multiTarget: '多设备、多终端标签并存，SSH 会话复用 SFTP',
        secretHandling: '密码和私钥口令只进入系统凭据库',
      ),
      'serial_port': ToolUsageContract(
        repeatUse: '恢复上次端口、波特率、帧格式和流控',
        multiTarget: '按 USB 身份区分端口，重新枚举不串设备',
        secretHandling: '不处理凭据',
      ),
      'adb_workspace': ToolUsageContract(
        repeatUse: '重新发现设备并复用已授权无线目标',
        multiTarget: '多个序列号并存，命令绑定明确设备',
        secretHandling: '不保存 Android 解锁信息',
      ),
      'api_workspace': ToolUsageContract(
        repeatUse: '保存最近 30 个方法、URL 和非敏感请求头',
        multiTarget: '多个接口历史并存，可一键恢复',
        secretHandling: '不保存正文、Authorization、Cookie、Token 或 API Key',
      ),
      'packet_capture': ToolUsageContract(
        repeatUse: '保留 PCAP 文件，重新打开后可继续分析',
        multiTarget: '不同网卡/过滤条件分别记录',
        secretHandling: '抓包内容默认只留本地',
      ),
      'git_workspace': ToolUsageContract(
        repeatUse: '复用最近仓库与远端',
        multiTarget: '多个仓库互不共享分支和提交状态',
        secretHandling: 'Git 凭据交给系统 Git 凭据管理器',
      ),
      'file_diff': ToolUsageContract(
        repeatUse: '保留当前左右文件直到替换或关闭',
        multiTarget: '每次比较显式绑定左右文件',
        secretHandling: '文件正文不写 Harness 审计日志',
      ),
      'github_diagnostics': ToolUsageContract(
        repeatUse: '复用已确认代理并支持一键回滚',
        multiTarget: '仅作用于 GitHub Git 配置，不污染全局代理',
        secretHandling: '诊断输出隐藏 Token',
      ),
      'audio_analyzer': ToolUsageContract(
        repeatUse: '保留当前音频和分析参数直到替换',
        multiTarget: '多个文件逐个形成独立分析结果',
        secretHandling: '音频默认不上传',
      ),
      'file_hash': ToolUsageContract(
        repeatUse: '同批文件可重复选择算法计算',
        multiTarget: '一个列表容纳多个文件',
        secretHandling: '只记录路径和摘要，不记录正文',
      ),
      'file_search': ToolUsageContract(
        repeatUse: '保留当前目录和过滤条件直到修改',
        multiTarget: '每次任务绑定一个明确根目录',
        secretHandling: '搜索结果默认只留本地',
      ),
      'batch_rename': ToolUsageContract(
        repeatUse: '预览规则后再执行，失败可定位到单个文件',
        multiTarget: '一个任务可包含多个文件',
        secretHandling: '不处理凭据',
      ),
      'duplicate_files': ToolUsageContract(
        repeatUse: '扫描结果保留到重新扫描或关闭',
        multiTarget: '一个任务可选择多个目录',
        secretHandling: '不上传文件内容',
      ),
      'utility_collection': ToolUsageContract(
        repeatUse: 'Tab 间保留输入输出直到用户清空',
        multiTarget: '同一输入可连续交给多个转换工具',
        secretHandling: '密码生成结果不进入普通历史',
      ),
    };

/// 小而同构的输入/输出工具，不再占用左侧导航。
final List<ToolSpec> utilityToolRegistry = <ToolSpec>[
  for (final ToolSpec tool in allDevToolRegistry)
    if (!_standaloneToolIds.contains(tool.id)) tool,
];
