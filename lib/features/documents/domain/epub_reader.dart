import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// EPUB 解析器（docs/00 §5.4，DOC-203）。
///
/// 仅解析受信任范围内的 ZIP 结构，拒绝 DRM、路径穿越、压缩炸弹与超大条目。
class EpubBook {
  EpubBook._(this.title, this.chapterPaths, this._archive);

  final String title;
  final List<String> chapterPaths;
  final Archive _archive;

  static const int _maxEntries = 5000;
  static const int _maxEntryBytes = 32 * 1024 * 1024;
  static const int _maxTotalBytes = 256 * 1024 * 1024;

  int get chapterCount => chapterPaths.length;

  static EpubBook parse(Uint8List bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Map<String, ArchiveFile> entries = <String, ArchiveFile>{};
    int total = 0;
    for (final ArchiveFile file in archive.files) {
      if (entries.length >= _maxEntries) {
        throw const FormatException('EPUB 条目过多');
      }
      if (file.size > _maxEntryBytes) {
        throw const FormatException('EPUB 条目过大');
      }
      total += file.size;
      if (total > _maxTotalBytes) {
        throw const FormatException('EPUB 展开大小超限');
      }
      final String name = file.name.replaceAll('\\', '/');
      if (name.contains('..')) {
        throw const FormatException('EPUB 路径越界');
      }
      entries[name] = file;
    }

    if (entries.containsKey('META-INF/encryption.xml')) {
      throw const FormatException('不支持带 DRM 或加密的 EPUB');
    }

    final String containerPath = _readEntry(entries, 'META-INF/container.xml');
    final XmlDocument container = XmlDocument.parse(containerPath);
    String? opfPath;
    for (final XmlElement rootfile in container.findAllElements('rootfile')) {
      final String? fullPath = rootfile.getAttribute('full-path');
      if (fullPath != null && opfPath == null) {
        opfPath = fullPath;
      }
    }
    if (opfPath == null) {
      throw const FormatException('EPUB 缺少 OPF 路径');
    }

    final String opf = _readEntry(entries, opfPath);
    final XmlDocument opfDoc = XmlDocument.parse(opf);
    final String baseDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final Map<String, String> manifest = <String, String>{};
    for (final XmlElement item in opfDoc.findAllElements('item')) {
      final String? id = item.getAttribute('id');
      final String? href = item.getAttribute('href');
      if (id != null && href != null) {
        manifest[id] = _resolve(baseDir, href);
      }
    }

    final List<String> chapters = <String>[];
    for (final XmlElement itemref in opfDoc.findAllElements('itemref')) {
      final String? idref = itemref.getAttribute('idref');
      if (idref != null) {
        final String? path = manifest[idref];
        if (path != null && entries.containsKey(path)) {
          chapters.add(path);
        }
      }
    }
    if (chapters.isEmpty) {
      throw const FormatException('EPUB spine 为空');
    }

    String title = 'EPUB';
    for (final XmlElement element in opfDoc.descendantElements) {
      if (element.name.local == 'title' &&
          element.innerText.trim().isNotEmpty) {
        title = element.innerText.trim();
        break;
      }
    }

    return EpubBook._(title, chapters, archive);
  }

  static String _readEntry(Map<String, ArchiveFile> entries, String name) {
    final ArchiveFile? file = entries[name];
    if (file == null) {
      throw FormatException('EPUB 缺少条目 $name');
    }
    return utf8.decode(file.content);
  }

  static String _resolve(String baseDir, String href) {
    final String withoutFragment = href.contains('#')
        ? href.substring(0, href.indexOf('#'))
        : href;
    return '$baseDir$withoutFragment';
  }

  /// 读取第 [index] 章的 XHTML，并移除脚本等危险内容。
  String chapterHtml(int index) {
    final ArchiveFile? file = _archive.findFile(chapterPaths[index]);
    if (file == null) {
      throw FormatException('EPUB 章节不存在');
    }
    final String html = utf8.decode(file.content);
    return html
        .replaceAll(
          RegExp(
            r'<script\b[^>]*>.*?</script\s*>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<(?:iframe|object|embed)\b[^>]*>.*?</(?:iframe|object|embed)\s*>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        );
  }
}
