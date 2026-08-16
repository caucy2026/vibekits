import 'dart:typed_data';

import '../../../app/supported_file_types.dart';

/// 文档查看模式（docs/00 §5.1）。
enum DocViewMode { empty, text, markdown, hex, structured, web, unsupported }

/// 根据后缀路由到查看模式。
///
/// 纯函数，便于单元测试。结构化与 Web 格式在 M3 实现，首片返回对应模式供占位。
DocViewMode documentModeForPath(String path) {
  final String lower = path.toLowerCase();
  if (SupportedFileTypes.isSpecialDocumentPath(path)) {
    return DocViewMode.text;
  }
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return DocViewMode.markdown;
  }
  if (lower.endsWith('.bin')) {
    return DocViewMode.hex;
  }
  final List<String> textExts = SupportedFileTypes.documentExtensions
      .where(
        (String extension) => !<String>{
          'md',
          'markdown',
          'bin',
          'csv',
          'tsv',
          'json',
          'xml',
          'html',
          'htm',
          'epub',
          'svg',
          'svgz',
        }.contains(extension),
      )
      .map((String extension) => '.$extension')
      .toList(growable: false);
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

/// 未知/无后缀文件的自动查看模式。只读取首段样本，不按文件大小整块载入。
DocViewMode documentModeForUnknownBytes(Uint8List bytes) {
  if (bytes.isEmpty) return DocViewMode.text;
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (int index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  // 文本 BOM 优先，UTF-16 中的零字节不能因此被误判为二进制。
  if (startsWith(<int>[0xef, 0xbb, 0xbf]) ||
      startsWith(<int>[0xff, 0xfe]) ||
      startsWith(<int>[0xfe, 0xff])) {
    return DocViewMode.text;
  }

  // 常见二进制容器/可执行文件即使头部含可读 ASCII，也应进入 Hex。
  const List<List<int>> binarySignatures = <List<int>>[
    <int>[0x25, 0x50, 0x44, 0x46], // PDF
    <int>[0x89, 0x50, 0x4e, 0x47], // PNG
    <int>[0xff, 0xd8, 0xff], // JPEG
    <int>[0x47, 0x49, 0x46, 0x38], // GIF
    <int>[0x52, 0x49, 0x46, 0x46], // RIFF/WAV/WEBP
    <int>[0x4d, 0x5a], // PE/EXE
    <int>[0x7f, 0x45, 0x4c, 0x46], // ELF
    <int>[0x53, 0x51, 0x4c, 0x69, 0x74, 0x65], // SQLite
    <int>[0xd0, 0xcf, 0x11, 0xe0], // OLE
  ];
  if (binarySignatures.any(startsWith)) return DocViewMode.hex;

  int controlBytes = 0;
  for (final int byte in bytes) {
    if (byte == 0) return DocViewMode.hex;
    if (byte < 0x20 &&
        byte != 0x09 &&
        byte != 0x0a &&
        byte != 0x0c &&
        byte != 0x0d) {
      controlBytes++;
    }
  }
  return controlBytes * 100 <= bytes.length * 2
      ? DocViewMode.text
      : DocViewMode.hex;
}
