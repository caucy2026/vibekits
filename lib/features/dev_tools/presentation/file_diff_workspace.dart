import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/file_diff_service.dart';

typedef FileDiffPicker = Future<String?> Function();
typedef FileDiffComparer = Future<FileDiffResult> Function({
  required String leftPath,
  required String rightPath,
  required bool ignoreWhitespace,
  required bool ignoreCase,
});

class FileDiffWorkspace extends StatefulWidget {
  const FileDiffWorkspace({
    super.key,
    this.pickFile,
    this.compare = FileDiffService.compare,
  });

  final FileDiffPicker? pickFile;
  final FileDiffComparer compare;

  @override
  State<FileDiffWorkspace> createState() => _FileDiffWorkspaceState();
}

class _FileDiffWorkspaceState extends State<FileDiffWorkspace> {
  final TextEditingController _left = TextEditingController();
  final TextEditingController _right = TextEditingController();
  FileDiffResult? _result;
  bool _ignoreWhitespace = false;
  bool _ignoreCase = false;
  bool _changesOnly = false;
  bool _running = false;
  String _message = '选择两个文本或源码文件进行比较';

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  Future<String?> _pick() async {
    if (widget.pickFile != null) return widget.pickFile!();
    return (await openFile())?.path;
  }

  Future<void> _pickInto(TextEditingController controller) async {
    final String? path = await _pick();
    if (!mounted || path == null) return;
    setState(() {
      controller.text = path;
      _result = null;
    });
  }

  Future<void> _compare() async {
    if (_running) return;
    setState(() {
      _running = true;
      _message = '正在后台比较…';
    });
    try {
      final FileDiffResult result = await widget.compare(
        leftPath: _left.text,
        rightPath: _right.text,
        ignoreWhitespace: _ignoreWhitespace,
        ignoreCase: _ignoreCase,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _message = result.identical
            ? '两个文件没有差异'
            : '新增 ${result.addedLines} 行 · 删除 ${result.removedLines} 行 · '
                  '未变 ${result.unchangedLines} 行'
                  '${result.exactMinimalDiff ? '' : ' · 大文件使用有界块比较'}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _message = '比较失败：$error';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _swap() {
    final String value = _left.text;
    setState(() {
      _left.text = _right.text;
      _right.text = value;
      _result = null;
      _message = '已交换左右文件，点击比较';
    });
  }

  Future<void> _copy() async {
    final FileDiffResult? result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result.unifiedText));
    if (mounted) setState(() => _message = '统一 Diff 已复制');
  }

  Future<void> _save() async {
    final FileDiffResult? result = _result;
    if (result == null) return;
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'comparison.diff',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Diff', extensions: <String>['diff', 'patch']),
      ],
    );
    if (location == null) return;
    await File(location.path).writeAsString(result.unifiedText, flush: true);
    if (mounted) setState(() => _message = '已保存 ${location.path}');
  }

  @override
  Widget build(BuildContext context) {
    final FileDiffResult? result = _result;
    final List<FileDiffLine> visible = result == null
        ? const <FileDiffLine>[]
        : result.lines
              .where(
                (FileDiffLine line) =>
                    !_changesOnly || line.kind != FileDiffLineKind.equal,
              )
              .toList(growable: false);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: _pathField('左侧原文件', _left)),
                  IconButton(
                    key: const Key('file-diff-swap'),
                    tooltip: '交换左右',
                    onPressed: _running ? null : _swap,
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                  Expanded(child: _pathField('右侧新文件', _right)),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('file-diff-run'),
                    onPressed: _running ? null : _compare,
                    icon: _running
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.difference_outlined, size: 18),
                    label: Text(_running ? '比较中…' : '比较'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  FilterChip(
                    label: const Text('忽略空白'),
                    selected: _ignoreWhitespace,
                    onSelected: _running
                        ? null
                        : (bool value) =>
                              setState(() => _ignoreWhitespace = value),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('忽略大小写'),
                    selected: _ignoreCase,
                    onSelected: _running
                        ? null
                        : (bool value) => setState(() => _ignoreCase = value),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('只看差异'),
                    selected: _changesOnly,
                    onSelected: result == null
                        ? null
                        : (bool value) => setState(() => _changesOnly = value),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _message,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.vibe.muted),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制统一 Diff',
                    onPressed: result == null ? null : _copy,
                    icon: const Icon(Icons.copy_all_outlined, size: 19),
                  ),
                  IconButton(
                    tooltip: '保存 .diff',
                    onPressed: result == null ? null : _save,
                    icon: const Icon(Icons.save_alt_outlined, size: 19),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: result == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.difference_outlined, size: 42),
                      SizedBox(height: 10),
                      Text('选择两个文件，Vibekits 会自动识别编码并按行比较'),
                      SizedBox(height: 4),
                      Text('单文件上限 8 MiB / 50000 行，比较在后台线程运行'),
                    ],
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    key: const Key('file-diff-lines'),
                    itemExtent: 25,
                    itemCount: visible.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _line(visible[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _pathField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: IconButton(
            tooltip: '选择文件',
            onPressed: _running ? null : () => _pickInto(controller),
            icon: const Icon(Icons.folder_open_outlined, size: 19),
          ),
        ),
        onSubmitted: (_) => _compare(),
      );

  Widget _line(FileDiffLine line) {
    final (
      Color background,
      Color foreground,
      String marker,
    ) = switch (line.kind) {
      FileDiffLineKind.equal => (
        Colors.transparent,
        Theme.of(context).colorScheme.onSurface,
        ' ',
      ),
      FileDiffLineKind.added => (
        context.vibe.success.withValues(alpha: 0.12),
        context.vibe.success,
        '+',
      ),
      FileDiffLineKind.removed => (
        VibekitsColors.danger.withValues(alpha: 0.11),
        VibekitsColors.danger,
        '-',
      ),
    };
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(
              line.leftLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: context.vibe.muted),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              line.rightLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: context.vibe.muted),
            ),
          ),
          const SizedBox(width: 10),
          Text(marker, style: TextStyle(color: foreground)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
