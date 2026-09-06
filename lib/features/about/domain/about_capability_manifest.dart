import '../../../app/supported_file_types.dart';
import '../../dev_tools/domain/tool_registry.dart';

class AboutFormatGroup {
  const AboutFormatGroup(this.title, this.description, this.values);
  final String title;
  final String description;
  final List<String> values;
}

class AboutToolGroup {
  const AboutToolGroup(this.title, this.tools);
  final String title;
  final List<ToolSpec> tools;
}

/// About-page facts derived from the same registries used by routing and UI.
abstract final class AboutCapabilityManifest {
  static List<String> _extensions(List<String> values) =>
      values.map((String value) => '.$value').toSet().toList(growable: false);

  static List<AboutFormatGroup> get formatGroups => <AboutFormatGroup>[
    AboutFormatGroup(
      '压缩包、安装包与磁盘映像',
      '可识别并安全查看；ZIP、7z、TAR 与常见压缩流支持创建或解压，复杂格式由随包 7-Zip 处理。',
      _extensions(SupportedFileTypes.archiveExtensions),
    ),
    AboutFormatGroup(
      '文本、配置、源码与结构化数据',
      '文本和源码支持编码识别、查找与编辑；JSON/XML/CSV/TSV 提供结构化查看，HTML/EPUB/SVG 使用隔离预览。',
      <String>[
        ..._extensions(SupportedFileTypes.documentExtensions),
        ...SupportedFileTypes.specialDocumentFileNames,
      ],
    ),
    AboutFormatGroup(
      '图片',
      '常见位图在本地解码预览；动画或多页格式当前显示首帧，超大图片受像素与内存上限保护。',
      _extensions(SupportedFileTypes.imageExtensions),
    ),
    AboutFormatGroup(
      '数据库',
      'SQLite 文件可浏览表、视图并执行有界只读查询。',
      _extensions(SupportedFileTypes.databaseExtensions),
    ),
    AboutFormatGroup(
      '模型',
      '识别常见本地模型容器；已集成的 ONNX 能力按具体工具和模型兼容性执行。',
      _extensions(SupportedFileTypes.modelExtensions),
    ),
    AboutFormatGroup(
      '音频',
      'PCM/RAW/WAV 可查看波形、播放并分析峰值、RMS、SNR、THD 与削波等指标。',
      _extensions(SupportedFileTypes.audioExtensions),
    ),
    const AboutFormatGroup(
      'VibeKits 自有数据与协议',
      '当前不发明私有文档后缀，避免把用户数据锁在专有格式中。工程状态、Harness 审计和 LMCP/MCP 调用结果使用可检查的 JSON/JSONL、标准 PCAP、SQLite 或原始工具格式。',
      <String>['JSON', 'JSONL', 'PCAP', 'SQLite', 'LMCP/2', 'MCP'],
    ),
  ];

  static List<AboutToolGroup> get toolGroups {
    final Map<String, List<ToolSpec>> groups = <String, List<ToolSpec>>{};
    for (final ToolSpec tool in allDevToolRegistry) {
      groups.putIfAbsent(tool.group, () => <ToolSpec>[]).add(tool);
    }
    return <AboutToolGroup>[
      for (final MapEntry<String, List<ToolSpec>> entry in groups.entries)
        AboutToolGroup(entry.key, List<ToolSpec>.unmodifiable(entry.value)),
    ];
  }

  static int get supportedExtensionCount =>
      SupportedFileTypes.allExtensions.toSet().length;

  static int get specialFileNameCount =>
      SupportedFileTypes.specialDocumentFileNames.length;

  static int get toolCount => allDevToolRegistry.length;

  static int get independentWorkspaceCount => devToolRegistry.length;

  static int get harnessEntryCount => <String>{
    for (final ToolSpec tool in devToolRegistry) ...harnessToolIdsFor(tool),
  }.length;
}
