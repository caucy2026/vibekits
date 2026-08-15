/// 文档查看模式（docs/00 §5.1）。
enum DocViewMode { empty, text, markdown, hex, structured, web, unsupported }

/// 根据后缀路由到查看模式。
///
/// 纯函数，便于单元测试。结构化与 Web 格式在 M3 实现，首片返回对应模式供占位。
DocViewMode documentModeForPath(String path) {
  final String lower = path.toLowerCase();
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return DocViewMode.markdown;
  }
  if (lower.endsWith('.bin')) {
    return DocViewMode.hex;
  }
  const List<String> textExts = <String>[
    '.txt',
    '.log',
    '.ini',
    '.cfg',
    '.conf',
    '.properties',
    '.yaml',
    '.yml',
    '.toml',
    '.diff',
    '.patch',
    '.tex',
    '.latex',
  ];
  for (final String ext in textExts) {
    if (lower.endsWith(ext)) {
      return DocViewMode.text;
    }
  }
  const List<String> structuredExts = <String>['.csv', '.tsv', '.json', '.xml'];
  for (final String ext in structuredExts) {
    if (lower.endsWith(ext)) {
      return DocViewMode.structured;
    }
  }
  const List<String> webExts = <String>[
    '.html',
    '.htm',
    '.epub',
    '.svg',
    '.svgz',
  ];
  for (final String ext in webExts) {
    if (lower.endsWith(ext)) {
      return DocViewMode.web;
    }
  }
  return DocViewMode.unsupported;
}
