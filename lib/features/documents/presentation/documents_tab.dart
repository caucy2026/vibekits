import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../app/app_theme.dart';
import '../../../app/supported_file_types.dart';
import '../domain/csv_table.dart';
import '../domain/epub_reader.dart';
import '../domain/file_line_index.dart';
import '../domain/format_router.dart';
import '../domain/hex_view.dart';
import '../domain/json_tree.dart';
import '../domain/log_level.dart';
import '../domain/structured_node.dart';
import '../domain/svg_source.dart';
import '../domain/text_encoding.dart';
import '../domain/xml_tree.dart';
import 'svg_document_view.dart';
import 'web_document_view.dart';

/// 文本文件完整读取上限（大文件流式读取属后续迭代，DOC-102 索引结构已就绪）。
const int _kMaxTextBytes = 64 * 1024 * 1024;
const int _kMaxHexBytes = 256 * 1024 * 1024;

/// T3 文档阅读 Tab。
///
/// 对标 Notepad++ / VS Code / 010 Editor 的操作习惯（docs/08 §5）。
class DocumentsTab extends StatefulWidget {
  const DocumentsTab({
    super.key,
    this.initialPath,
    this.openRequest,
    this.findRequest,
  });

  final String? initialPath;
  final ValueListenable<int>? openRequest;
  final ValueListenable<int>? findRequest;

  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  final ScrollController _scrollController = ScrollController();

  String? _path;
  String _name = '';
  Uint8List? _bytes;
  String _text = '';
  List<String> _lines = const <String>[];
  DocEncoding _encoding = DocEncoding.utf8;
  DocViewMode _mode = DocViewMode.empty;
  String _error = '';

  bool _wrap = true;
  bool _markdownPreview = true;
  int _bytesPerLine = 16;
  bool _showInfo = true;
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  final List<int> _matchLines = <int>[];
  int _activeMatch = -1;
  StructuredNode? _tree;
  CsvTable? _csvTable;
  bool _structuredSource = false;
  final Set<String> _expanded = <String>{};
  String _webHtml = '';
  EpubBook? _epubBook;
  int _epubChapter = 0;
  String _svgText = '';
  FileLineIndex? _streamIndex;
  final List<String> _recent = <String>[];

  @override
  void initState() {
    super.initState();
    final String? initialPath = widget.initialPath;
    if (initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadPath(initialPath),
      );
    }
    widget.openRequest?.addListener(_handleOpenRequest);
    widget.findRequest?.addListener(_handleFindRequest);
  }

  void _handleOpenRequest() => _openFile();

  void _handleFindRequest() {
    if (_mode == DocViewMode.hex || _streamIndex != null) return;
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant DocumentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openRequest != widget.openRequest) {
      oldWidget.openRequest?.removeListener(_handleOpenRequest);
      widget.openRequest?.addListener(_handleOpenRequest);
    }
    if (oldWidget.findRequest != widget.findRequest) {
      oldWidget.findRequest?.removeListener(_handleFindRequest);
      widget.findRequest?.addListener(_handleFindRequest);
    }
  }

  @override
  void dispose() {
    widget.openRequest?.removeListener(_handleOpenRequest);
    widget.findRequest?.removeListener(_handleFindRequest);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openFile() async {
    const XTypeGroup group = XTypeGroup(
      label: '文档',
      extensions: SupportedFileTypes.documentExtensions,
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file != null) {
      await _loadPath(file.path);
    }
  }

  Future<void> _loadPath(String path) async {
    try {
      final File file = File(path);
      final int size = await file.length();
      final DocViewMode mode = documentModeForPath(path);

      // 大文本走流式索引，不把整个文件读入内存（DOC-102）。
      if ((mode == DocViewMode.text || mode == DocViewMode.markdown) &&
          size > _kMaxTextBytes) {
        await _loadStreaming(path, file, mode);
        return;
      }

      final Uint8List bytes = await file.readAsBytes();
      if (mode == DocViewMode.hex) {
        if (size > _kMaxHexBytes) {
          setState(() {
            _mode = DocViewMode.empty;
            _error = '文件过大（$size 字节），十六进制查看上限为 $_kMaxHexBytes 字节';
          });
          return;
        }
      }

      setState(() {
        _path = path;
        _name = file.uri.pathSegments.last;
        _bytes = bytes;
        _mode = mode;
        _error = '';
        _query = '';
        _matchLines.clear();
        _activeMatch = -1;
        _tree = null;
        _csvTable = null;
        _structuredSource = false;
        _expanded.clear();
        _webHtml = '';
        _epubBook = null;
        _epubChapter = 0;
        _svgText = '';
        _streamIndex = null;
        _recent.remove(path);
        _recent.insert(0, path);
        if (_recent.length > 20) {
          _recent.removeLast();
        }

        if (mode == DocViewMode.text || mode == DocViewMode.markdown) {
          _encoding = TextCodecs.detect(bytes);
          _text = TextCodecs.decode(bytes, _encoding);
          _lines = _text.split('\n');
        } else if (mode == DocViewMode.structured) {
          _encoding = TextCodecs.detect(bytes);
          _text = TextCodecs.decode(bytes, _encoding);
          _lines = _text.split('\n');
          final String lower = path.toLowerCase();
          try {
            if (lower.endsWith('.json')) {
              _tree = buildJsonTree(jsonDecode(_text), 'root');
            } else if (lower.endsWith('.xml')) {
              _tree = buildXmlTree(_text);
            } else {
              _csvTable = CsvTable.parse(
                _text,
                delimiter: lower.endsWith('.tsv') ? '\t' : ',',
              );
            }
            _error = '';
          } catch (e) {
            // 结构解析失败：回退源码（DOC-106）。
            _error = '结构解析失败，已回退源码：$e';
          }
        } else if (mode == DocViewMode.web) {
          final String lower = path.toLowerCase();
          try {
            if (lower.endsWith('.epub')) {
              _epubBook = EpubBook.parse(bytes);
              _webHtml = _epubBook!.chapterHtml(0);
              _epubChapter = 0;
            } else if (lower.endsWith('.svg') || lower.endsWith('.svgz')) {
              _svgText = SvgSource.decode(
                bytes,
                compressed: lower.endsWith('.svgz'),
              );
            } else {
              _webHtml = TextCodecs.decode(bytes, TextCodecs.detect(bytes));
            }
            _error = '';
          } catch (e) {
            _error = 'Web 文档打开失败：$e';
          }
        }
      });
    } catch (e) {
      setState(() {
        _mode = DocViewMode.empty;
        _error = '打开失败：$e';
      });
    }
  }

  Future<void> _loadStreaming(String path, File file, DocViewMode mode) async {
    final RandomAccessFile raf = file.openSync();
    final int fileLen = file.lengthSync();
    final int headLen = fileLen < 65536 ? fileLen : 65536;
    final Uint8List head = Uint8List(headLen);
    raf.readIntoSync(head);
    raf.closeSync();
    final DocEncoding encoding = TextCodecs.detect(head);
    final FileLineIndex index = await FileLineIndex.build(path);
    if (!mounted) return;
    setState(() {
      _path = path;
      _name = file.uri.pathSegments.last;
      _bytes = null;
      _mode = mode;
      _encoding = encoding;
      _streamIndex = index;
      _lines = const <String>[];
      _text = '';
      _error = '';
      _query = '';
      _matchLines.clear();
      _activeMatch = -1;
      _tree = null;
      _csvTable = null;
      _structuredSource = false;
      _expanded.clear();
      _webHtml = '';
      _epubBook = null;
      _epubChapter = 0;
      _svgText = '';
      _recent.remove(path);
      _recent.insert(0, path);
      if (_recent.length > 20) _recent.removeLast();
    });
  }

  void _switchEncoding(DocEncoding encoding) {
    if (_bytes == null || _mode == DocViewMode.hex) {
      return;
    }
    setState(() {
      _encoding = encoding;
      try {
        _text = TextCodecs.decode(_bytes!, encoding);
        _lines = _text.split('\n');
        _error = '';
      } catch (e) {
        _error = '以 ${encoding.label} 解码失败：$e';
      }
    });
  }

  void _runSearch(String query) {
    setState(() {
      _query = query;
      _matchLines.clear();
      _activeMatch = -1;
      if (query.isNotEmpty) {
        final String lower = query.toLowerCase();
        for (int index = 0; index < _lines.length; index++) {
          if (_lines[index].toLowerCase().contains(lower)) {
            _matchLines.add(index);
          }
        }
        if (_matchLines.isNotEmpty) {
          _activeMatch = 0;
          _scrollToLine(_matchLines.first);
        }
      }
    });
  }

  void _moveMatch(int delta) {
    if (_matchLines.isEmpty) {
      return;
    }
    setState(() {
      _activeMatch =
          (_activeMatch + delta + _matchLines.length) % _matchLines.length;
      _scrollToLine(_matchLines[_activeMatch]);
    });
  }

  void _scrollToLine(int line) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        (line * 22.0).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _buildSidebar(),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _buildMain()),
        if (_showInfo) ...<Widget>[
          const VerticalDivider(width: 1, thickness: 1),
          _buildInfoPanel(),
        ],
      ],
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton.icon(
              onPressed: _openFile,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('打开文件'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              '最近文件',
              style: TextStyle(
                fontSize: 12,
                color: context.vibe.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: _recent.isEmpty
                ? Center(
                    child: Text(
                      '暂无记录',
                      style: TextStyle(fontSize: 12, color: context.vibe.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: _recent.length,
                    itemBuilder: (BuildContext context, int index) {
                      final String path = _recent[index];
                      final String name = path
                          .split(Platform.pathSeparator)
                          .last;
                      return ListTile(
                        dense: true,
                        title: Text(
                          name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _loadPath(path),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '支持：txt/log/md/配置/Diff/Bin\nCSV/JSON/HTML/EPUB 等将在 M3 支持',
              style: TextStyle(fontSize: 11, color: context.vibe.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    return Column(
      children: <Widget>[
        _buildToolbar(),
        if (_searchOpen) _buildSearchBar(),
        const Divider(height: 1),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _name.isEmpty ? '未打开文档' : _name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_mode == DocViewMode.text || _mode == DocViewMode.markdown) ...[
            DropdownButton<DocEncoding>(
              value: _encoding,
              underline: const SizedBox.shrink(),
              items: DocEncoding.values
                  .map(
                    (DocEncoding e) => DropdownMenuItem<DocEncoding>(
                      value: e,
                      child: Text(
                        e.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (DocEncoding? e) {
                if (e != null) {
                  _switchEncoding(e);
                }
              },
            ),
            const SizedBox(width: 8),
            Row(
              children: <Widget>[
                Text(
                  '换行',
                  style: TextStyle(fontSize: 12, color: context.vibe.muted),
                ),
                Switch(
                  value: _wrap,
                  onChanged: (bool v) => setState(() => _wrap = v),
                ),
              ],
            ),
          ],
          if (_mode == DocViewMode.markdown)
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('预览')),
                ButtonSegment<bool>(value: false, label: Text('源码')),
              ],
              selected: <bool>{_markdownPreview},
              onSelectionChanged: (Set<bool> s) =>
                  setState(() => _markdownPreview = s.first),
            ),
          if (_mode == DocViewMode.structured)
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('树/表格')),
                ButtonSegment<bool>(value: true, label: Text('源码')),
              ],
              selected: <bool>{_structuredSource},
              onSelectionChanged: (Set<bool> s) => setState(() {
                _structuredSource = s.first;
                if (_structuredSource) {
                  _lines = _sourceText().split('\n');
                }
              }),
            ),
          if (_mode == DocViewMode.hex)
            DropdownButton<int>(
              value: _bytesPerLine,
              underline: const SizedBox.shrink(),
              items: const <int>[8, 16, 32]
                  .map(
                    (int n) => DropdownMenuItem<int>(
                      value: n,
                      child: Text(
                        '$n 字节',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (int? n) {
                if (n != null) {
                  setState(() => _bytesPerLine = n);
                }
              },
            ),
          IconButton(
            tooltip: '查找 (Ctrl+F)',
            icon: const Icon(Icons.search, size: 18),
            color: context.vibe.muted,
            onPressed: _mode == DocViewMode.hex || _streamIndex != null
                ? null
                : () => setState(() => _searchOpen = !_searchOpen),
          ),
          IconButton(
            tooltip: _showInfo ? '隐藏信息' : '显示信息',
            icon: Icon(
              _showInfo ? Icons.info : Icons.info_outline,
              size: 18,
              color: _showInfo ? VibekitsColors.primary : context.vibe.muted,
            ),
            onPressed: () => setState(() => _showInfo = !_showInfo),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: context.vibe.panelRaised,
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: const InputDecoration(
                hintText: '查找',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 16),
              ),
              onChanged: _runSearch,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _query.isEmpty
                ? '0 / 0'
                : '${_activeMatch + 1} / ${_matchLines.length}',
            style: TextStyle(fontSize: 12, color: context.vibe.muted),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _matchLines.isEmpty ? null : () => _moveMatch(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _matchLines.isEmpty ? null : () => _moveMatch(1),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error.isNotEmpty && _mode == DocViewMode.empty) {
      return Center(
        child: Text(
          _error,
          style: const TextStyle(color: VibekitsColors.danger),
        ),
      );
    }
    switch (_mode) {
      case DocViewMode.empty:
        return Center(
          child: Text(
            '打开一个文档开始阅读\n支持文本、日志、Markdown、配置、Diff 与二进制',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.vibe.muted),
          ),
        );
      case DocViewMode.text:
        return _buildTextViewer();
      case DocViewMode.markdown:
        return _markdownPreview ? _buildMarkdownPreview() : _buildTextViewer();
      case DocViewMode.hex:
        return _buildHexViewer();
      case DocViewMode.structured:
        return _buildStructuredView();
      case DocViewMode.web:
        return _buildWebView();
      case DocViewMode.unsupported:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('无法识别的文件格式'),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => _forceMode(DocViewMode.text),
                    child: const Text('以文本打开'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _forceMode(DocViewMode.hex),
                    child: const Text('以十六进制打开'),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }

  void _forceMode(DocViewMode mode) {
    if (_bytes == null) {
      return;
    }
    setState(() {
      _mode = mode;
      _error = '';
      if (mode == DocViewMode.text) {
        _encoding = TextCodecs.detect(_bytes!);
        _text = TextCodecs.decode(_bytes!, _encoding);
        _lines = _text.split('\n');
      }
    });
  }

  Widget _buildTextViewer() {
    final FileLineIndex? streamIndex = _streamIndex;
    if (streamIndex != null) {
      return ListView.builder(
        controller: _scrollController,
        itemCount: streamIndex.lineCount,
        itemExtent: 22,
        itemBuilder: (BuildContext context, int index) {
          return FutureBuilder<String>(
            future: streamIndex.readLine(index, _encoding),
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              final String line = snapshot.data ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.vibe.muted,
                        fontFamily: 'Cascadia Mono',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        line.isEmpty ? ' ' : line,
                        maxLines: _wrap ? null : 1,
                        softWrap: _wrap,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontFamily: 'Cascadia Mono',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    final bool colorLogs = _name.toLowerCase().endsWith('.log');
    return ListView.builder(
      controller: _scrollController,
      itemCount: _lines.length,
      itemExtent: 22,
      itemBuilder: (BuildContext context, int index) {
        final String line = _lines[index];
        final LogLevel level = colorLogs ? LogLevel.of(line) : LogLevel.plain;
        final Color color = switch (level) {
          LogLevel.error => const Color(0xFFB42318),
          LogLevel.warn => const Color(0xFFB54708),
          LogLevel.debug => context.vibe.muted,
          _ => Theme.of(context).colorScheme.onSurface,
        };
        final bool active =
            index == _activeMatch ||
            (_activeMatch >= 0 &&
                _matchLines.isNotEmpty &&
                _matchLines[_activeMatch] == index);
        return Container(
          color: active
              ? VibekitsColors.warning.withValues(alpha: 0.15)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.vibe.muted,
                  fontFamily: 'Cascadia Mono',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  line.isEmpty ? ' ' : line,
                  maxLines: _wrap ? null : 1,
                  softWrap: _wrap,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontFamily: 'Cascadia Mono',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMarkdownPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Markdown(
        data: _text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(fontSize: 14, height: 1.6),
          code: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 13),
          codeblockDecoration: BoxDecoration(
            color: context.vibe.canvas,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _buildHexViewer() {
    final Uint8List bytes = _bytes!;
    final int itemCount = (bytes.length + _bytesPerLine - 1) ~/ _bytesPerLine;
    return ListView.builder(
      controller: _scrollController,
      itemCount: itemCount,
      itemExtent: 20,
      itemBuilder: (BuildContext context, int index) {
        final int start = index * _bytesPerLine;
        final int end = (start + _bytesPerLine).clamp(0, bytes.length);
        final String line = HexView.formatLine(
          offset: start,
          bytes: Uint8List.sublistView(bytes, start, end),
          bytesPerLine: _bytesPerLine,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            line,
            style: TextStyle(
              fontFamily: 'Cascadia Mono',
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
      },
    );
  }

  String _sourceText() {
    if (_name.toLowerCase().endsWith('.json')) {
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(_text));
      } catch (_) {
        return _text;
      }
    }
    return _text;
  }

  Widget _buildStructuredView() {
    if (_structuredSource) {
      return _buildTextViewer();
    }
    if (_csvTable != null) {
      return _buildCsvView();
    }
    if (_tree != null) {
      return _buildTreeView();
    }
    return Column(
      children: <Widget>[
        if (_error.isNotEmpty)
          Container(
            width: double.infinity,
            color: VibekitsColors.danger.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(8),
            child: Text(
              _error,
              style: const TextStyle(
                color: VibekitsColors.danger,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(child: _buildTextViewer()),
      ],
    );
  }

  Widget _buildTreeView() {
    final List<_TreeRow> rows = _visibleTree();
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) {
        final _TreeRow row = rows[index];
        return InkWell(
          onTap: row.expandable
              ? () => setState(() {
                  if (_expanded.contains(row.path)) {
                    _expanded.remove(row.path);
                  } else {
                    _expanded.add(row.path);
                  }
                })
              : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8.0 + row.depth * 16.0, 2, 8, 2),
            child: Row(
              children: <Widget>[
                if (row.expandable)
                  Icon(
                    row.expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: context.vibe.muted,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                Text(
                  row.node.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (row.node.value != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      row.node.value!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.vibe.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<_TreeRow> _visibleTree() {
    final List<_TreeRow> result = <_TreeRow>[];
    final StructuredNode? root = _tree;
    if (root == null) {
      return result;
    }

    void visit(StructuredNode node, String path, int depth) {
      final bool expandable = !node.isLeaf;
      final bool expanded = _expanded.contains(path);
      result.add(
        _TreeRow(
          node: node,
          path: path,
          depth: depth,
          expandable: expandable,
          expanded: expanded,
        ),
      );
      if (expandable && expanded) {
        for (int index = 0; index < node.children.length; index++) {
          visit(node.children[index], '$path/$index', depth + 1);
        }
      }
    }

    visit(root, '0', 0);
    return result;
  }

  Widget _buildCsvView() {
    final CsvTable table = _csvTable!;
    if (table.rows.isEmpty) {
      return const Center(child: Text('空表格'));
    }
    final List<String> header = table.rows.first;
    final List<List<String>> dataRows = table.rows.skip(1).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _csvRow(header, header: true),
            for (final List<String> row in dataRows)
              _csvRow(row, header: false),
          ],
        ),
      ),
    );
  }

  Widget _csvRow(List<String> cells, {required bool header}) {
    return Container(
      color: header
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: Row(
        children: cells
            .map(
              (String cell) => Container(
                width: 140,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: context.vibe.border),
                    bottom: BorderSide(color: context.vibe.border),
                  ),
                ),
                child: Text(
                  cell,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: header ? FontWeight.w600 : FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildWebView() {
    if (_error.isNotEmpty && _webHtml.isEmpty && _svgText.isEmpty) {
      return Center(
        child: Text(
          _error,
          style: const TextStyle(color: VibekitsColors.danger),
        ),
      );
    }
    if (_svgText.isNotEmpty) {
      return SvgDocumentView(svgText: _svgText);
    }
    return WebDocumentView(
      html: _webHtml,
      chapterCount: _epubBook?.chapterCount ?? 0,
      chapterIndex: _epubChapter,
      onPrevious: _epubBook == null
          ? null
          : () => _loadEpubChapter(_epubChapter - 1),
      onNext: _epubBook == null
          ? null
          : () => _loadEpubChapter(_epubChapter + 1),
    );
  }

  void _loadEpubChapter(int index) {
    final EpubBook? book = _epubBook;
    if (book == null || index < 0 || index >= book.chapterCount) {
      return;
    }
    setState(() {
      _epubChapter = index;
      _webHtml = book.chapterHtml(index);
    });
  }

  Widget _buildInfoPanel() {
    final String? magic = _bytes == null ? null : detectMagicNumber(_bytes!);
    final int size = _bytes?.length ?? _streamIndex?.fileSize ?? 0;
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '文件信息',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(label: '类型', value: _modeLabel()),
            _InfoRow(label: '路径', value: _path ?? '—'),
            _InfoRow(
              label: '编码',
              value: _mode == DocViewMode.hex ? '—' : _encoding.label,
            ),
            _InfoRow(label: '大小', value: _formatSize(size)),
            if (_mode == DocViewMode.text || _mode == DocViewMode.markdown)
              _InfoRow(label: '行数', value: '${_lines.length}'),
            if (_mode == DocViewMode.hex)
              _InfoRow(label: '每行', value: '$_bytesPerLine 字节'),
            _InfoRow(label: 'Magic', value: magic ?? '—'),
          ],
        ),
      ),
    );
  }

  String _modeLabel() {
    return switch (_mode) {
      DocViewMode.text => '文本',
      DocViewMode.markdown => 'Markdown',
      DocViewMode.hex => '二进制',
      DocViewMode.structured => '结构化数据',
      DocViewMode.web => 'Web/电子书',
      DocViewMode.unsupported => '未知',
      DocViewMode.empty => '—',
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: context.vibe.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeRow {
  const _TreeRow({
    required this.node,
    required this.path,
    required this.depth,
    required this.expandable,
    required this.expanded,
  });

  final StructuredNode node;
  final String path;
  final int depth;
  final bool expandable;
  final bool expanded;
}
