import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/file_search_background_runner.dart';
import '../domain/file_search_service.dart';

typedef FileSearchDirectoryPicker = Future<String?> Function();
typedef FileSearchRunner = Future<FileSearchResult> Function(
  FileSearchRequest request,
  FileSearchCancellation cancellation,
  FileSearchProgressCallback onProgress,
);
typedef FileSearchReveal = Future<void> Function(String path);

class FileSearchWorkspace extends StatefulWidget {
  const FileSearchWorkspace({
    super.key,
    this.directoryPicker,
    this.searchRunner,
    this.reveal,
    this.onHashRequested,
  });

  final FileSearchDirectoryPicker? directoryPicker;
  final FileSearchRunner? searchRunner;
  final FileSearchReveal? reveal;
  final ValueChanged<String>? onHashRequested;

  @override
  State<FileSearchWorkspace> createState() => _FileSearchWorkspaceState();
}

class _FileSearchWorkspaceState extends State<FileSearchWorkspace> {
  final TextEditingController _directory = TextEditingController();
  final TextEditingController _query = TextEditingController();
  final TextEditingController _extensions = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  FileSearchMode _mode = FileSearchMode.name;
  bool _recursive = true;
  bool _includeHidden = false;
  bool _showOptions = false;
  int _minimumBytes = 0;
  int _modifiedDays = 0;
  bool _running = false;
  FileSearchCancellation? _cancellation;
  FileSearchProgress? _progress;
  FileSearchResult? _result;
  String? _message;

  @override
  void dispose() {
    _cancellation?.cancel();
    _directory.dispose();
    _query.dispose();
    _extensions.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<bool> _pickDirectory() async {
    final String? selected =
        await (widget.directoryPicker?.call() ??
            getDirectoryPath(confirmButtonText: '在此搜索'));
    if (!mounted || selected == null || selected.trim().isEmpty) return false;
    setState(() {
      _directory.text = selected.trim();
      _result = null;
      _progress = null;
      _message = null;
    });
    _queryFocus.requestFocus();
    return true;
  }

  Future<void> _search() async {
    if (_running) return;
    if (_directory.text.trim().isEmpty && !await _pickDirectory()) return;
    final FileSearchRequest request = FileSearchRequest(
      root: _directory.text,
      query: _query.text,
      mode: _mode,
      recursive: _recursive,
      includeHidden: _includeHidden,
      extensions: _extensions.text
          .split(RegExp(r'[,;\s]+'))
          .map(
            (String value) => value.trim().toLowerCase().replaceFirst('.', ''),
          )
          .where((String value) => RegExp(r'^[a-z0-9]{1,16}$').hasMatch(value))
          .toSet(),
      minimumBytes: _minimumBytes,
      modifiedAfter: _modifiedDays == 0
          ? null
          : DateTime.now().subtract(Duration(days: _modifiedDays)),
    );
    try {
      request.validate();
    } on FormatException catch (error) {
      _show(error.message);
      _queryFocus.requestFocus();
      return;
    }

    final FileSearchCancellation cancellation = FileSearchCancellation();
    _cancellation = cancellation;
    setState(() {
      _running = true;
      _progress = null;
      _result = null;
      _message = null;
    });
    try {
      final FileSearchResult result = widget.searchRunner == null
          ? await FileSearchBackgroundRunner.search(
              request,
              cancellation: cancellation,
              onProgress: _updateProgress,
            )
          : await widget.searchRunner!(request, cancellation, _updateProgress);
      if (!mounted || !identical(_cancellation, cancellation)) return;
      setState(() {
        _result = result;
        _message = result.cancelled
            ? '搜索已取消，已保留当前结果'
            : result.matches.isEmpty
            ? '没有找到匹配文件'
            : null;
      });
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _message = '搜索失败：${error.message}');
    } on Object catch (error) {
      if (mounted) setState(() => _message = '搜索失败：$error');
    } finally {
      if (mounted && identical(_cancellation, cancellation)) {
        setState(() => _running = false);
        _cancellation = null;
      }
    }
  }

  void _updateProgress(FileSearchProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  void _cancel() {
    _cancellation?.cancel();
    setState(() => _message = '正在停止搜索…');
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) _show('路径已复制');
  }

  Future<void> _reveal(String path) async {
    try {
      if (widget.reveal != null) {
        await widget.reveal!(path);
      } else if (Platform.isWindows) {
        await Process.start('explorer.exe', <String>[
          '/select,',
          path,
        ], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', <String>[
          '-R',
          path,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', <String>[
          File(path).parent.path,
        ], mode: ProcessStartMode.detached);
      }
    } on Object catch (error) {
      if (mounted) _show('无法在文件管理器中定位：$error');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(),
          const SizedBox(height: 12),
          _buildDirectoryInput(),
          const SizedBox(height: 9),
          _buildSearchInput(),
          _buildOptions(),
          const SizedBox(height: 10),
          _buildStatus(),
          const SizedBox(height: 8),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        Text(
          '文件搜索',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        const Chip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(Icons.offline_bolt_outlined, size: 15),
          label: Text('本机', style: TextStyle(fontSize: 11)),
        ),
        const Spacer(),
        TextButton.icon(
          key: const Key('file-search-options'),
          onPressed: _running
              ? null
              : () => setState(() => _showOptions = !_showOptions),
          icon: Icon(_showOptions ? Icons.expand_less : Icons.tune, size: 17),
          label: const Text('筛选'),
        ),
      ],
    );
  }

  Widget _buildDirectoryInput() {
    return TextField(
      key: const Key('file-search-directory'),
      controller: _directory,
      readOnly: true,
      onTap: _running ? null : _pickDirectory,
      decoration: InputDecoration(
        labelText: '搜索位置',
        hintText: '选择一个文件夹',
        prefixIcon: const Icon(Icons.folder_outlined, size: 19),
        suffixIcon: IconButton(
          key: const Key('file-search-pick-directory'),
          tooltip: '选择文件夹',
          onPressed: _running ? null : _pickDirectory,
          icon: const Icon(Icons.folder_open_outlined, size: 19),
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildSearchInput() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: const Key('file-search-query'),
            controller: _query,
            focusNode: _queryFocus,
            enabled: !_running,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: _mode == FileSearchMode.name ? '文件名包含' : '文件内容包含',
              hintText: _mode == FileSearchMode.name ? '例如：config' : '例如：TODO',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<FileSearchMode>(
          segments: FileSearchMode.values
              .map(
                (FileSearchMode mode) => ButtonSegment<FileSearchMode>(
                  value: mode,
                  label: Text(mode == FileSearchMode.name ? '文件名' : '内容'),
                ),
              )
              .toList(growable: false),
          selected: <FileSearchMode>{_mode},
          showSelectedIcon: false,
          onSelectionChanged: _running
              ? null
              : (Set<FileSearchMode> value) {
                  setState(() {
                    _mode = value.single;
                    _result = null;
                    _message = null;
                  });
                  _queryFocus.requestFocus();
                },
        ),
        const SizedBox(width: 8),
        if (_running)
          OutlinedButton.icon(
            key: const Key('file-search-cancel'),
            onPressed: _cancel,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('停止'),
          )
        else
          FilledButton.icon(
            key: const Key('file-search-run'),
            onPressed: _search,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('搜索'),
          ),
      ],
    );
  }

  Widget _buildOptions() {
    if (!_showOptions) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: <Widget>[
          FilterChip(
            label: const Text('包含子文件夹'),
            selected: _recursive,
            onSelected: _running
                ? null
                : (bool value) => setState(() => _recursive = value),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              key: const Key('file-search-extensions'),
              controller: _extensions,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: '文件类型',
                hintText: 'dart, md, json',
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<int>(
              key: const Key('file-search-minimum-size'),
              initialValue: _minimumBytes,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '最小大小',
                isDense: true,
              ),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 0, child: Text('不限')),
                DropdownMenuItem(value: 1024, child: Text('1 KB')),
                DropdownMenuItem(value: 1024 * 1024, child: Text('1 MB')),
                DropdownMenuItem(value: 10 * 1024 * 1024, child: Text('10 MB')),
                DropdownMenuItem(
                  value: 100 * 1024 * 1024,
                  child: Text('100 MB'),
                ),
              ],
              onChanged: _running
                  ? null
                  : (int? value) => setState(() => _minimumBytes = value ?? 0),
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<int>(
              key: const Key('file-search-modified-days'),
              initialValue: _modifiedDays,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '修改时间',
                isDense: true,
              ),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 0, child: Text('不限')),
                DropdownMenuItem(value: 1, child: Text('最近 24 小时')),
                DropdownMenuItem(value: 7, child: Text('最近 7 天')),
                DropdownMenuItem(value: 30, child: Text('最近 30 天')),
                DropdownMenuItem(value: 365, child: Text('最近一年')),
              ],
              onChanged: _running
                  ? null
                  : (int? value) => setState(() => _modifiedDays = value ?? 0),
            ),
          ),
          FilterChip(
            label: const Text('包含隐藏项'),
            selected: _includeHidden,
            onSelected: _running
                ? null
                : (bool value) => setState(() => _includeHidden = value),
          ),
          if (_mode == FileSearchMode.content)
            Chip(
              avatar: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('单文件最多读取 8 MB'),
              backgroundColor: context.vibe.panelRaised,
            ),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    final FileSearchProgress? progress = _progress;
    final FileSearchResult? result = _result;
    if (_running) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              progress == null
                  ? '准备搜索…'
                  : '已检查 ${progress.visitedFiles} 个文件，找到 ${progress.matchedFiles} 个',
              style: TextStyle(fontSize: 12, color: context.vibe.muted),
            ),
          ),
        ],
      );
    }
    if (result != null) {
      final String suffix = result.cancelled
          ? ' · 已取消'
          : result.truncated
          ? ' · 已达到 500 项上限'
          : '';
      return Text(
        '找到 ${result.matches.length} 个 · 检查 ${result.visitedFiles} 个 · '
        '${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} 秒$suffix',
        key: const Key('file-search-summary'),
        style: TextStyle(fontSize: 12, color: context.vibe.muted),
      );
    }
    return Text(
      '选择文件夹，输入关键词后按 Enter；默认递归搜索，筛选项按需展开。',
      style: TextStyle(fontSize: 12, color: context.vibe.muted),
    );
  }

  Widget _buildResults() {
    final List<FileSearchMatch> matches =
        _result?.matches ?? const <FileSearchMatch>[];
    if (matches.isEmpty) {
      return Container(
        key: const Key('file-search-empty'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.vibe.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.manage_search, size: 42, color: context.vibe.muted),
            const SizedBox(height: 8),
            Text(_message ?? '快速找到项目或下载目录中的文件'),
            const SizedBox(height: 4),
            Text(
              '结果可直接定位、复制路径或计算 SHA-256',
              style: TextStyle(fontSize: 12, color: context.vibe.muted),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      key: const Key('file-search-results'),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (BuildContext context, int index) =>
          _buildResult(matches[index]),
    );
  }

  Widget _buildResult(FileSearchMatch match) {
    return Card(
      key: ValueKey<String>('file-search-result-${match.path}'),
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.insert_drive_file_outlined, size: 21),
        title: Text(match.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              match.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.vibe.muted),
            ),
            if (match.snippet != null && match.snippet!.isNotEmpty)
              Text(
                '第 ${match.lineNumber} 行 · ${match.snippet}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                '${_formatSize(match.size)} · ${_formatTime(match.modified)}',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
          ],
        ),
        trailing: Wrap(
          spacing: 0,
          children: <Widget>[
            IconButton(
              tooltip: '在文件管理器中定位',
              onPressed: () => _reveal(match.path),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
            ),
            IconButton(
              tooltip: '计算 SHA-256',
              onPressed: widget.onHashRequested == null
                  ? null
                  : () => widget.onHashRequested!(match.path),
              icon: const Icon(Icons.fingerprint, size: 18),
            ),
            IconButton(
              tooltip: '复制路径',
              onPressed: () => _copyPath(match.path),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatTime(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
