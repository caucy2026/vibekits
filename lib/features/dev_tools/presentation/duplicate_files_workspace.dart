import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../cleaner/domain/cleanup_deleter.dart';
import '../../cleaner/domain/cleanup_report.dart';
import '../../cleaner/domain/cleanup_scanner.dart';
import '../../cleaner/domain/cleanup_task.dart';
import '../domain/duplicate_file_scanner.dart';

typedef DuplicateDirectoryPicker = Future<String?> Function();
typedef DuplicateScanRunner = Future<DuplicateScanResult> Function(
  String root, {
  required bool recursive,
  required int minimumSize,
  required CleanupCancellationToken cancellationToken,
  required void Function(DuplicateScanProgress progress) onProgress,
});
typedef DuplicateDeleteRunner = Future<CleanupDeleteResult> Function(
  List<CleanupCandidate> candidates, {
  required void Function(CleanupDeleteProgress progress) onProgress,
});
typedef DuplicateReportWriter = Future<File> Function(
  CleanupDeleteResult result,
);

class DuplicateFilesWorkspace extends StatefulWidget {
  const DuplicateFilesWorkspace({
    super.key,
    this.directoryPicker,
    this.scanRunner,
    this.deleteRunner,
    this.reportWriter,
    this.reportDirectory,
  });

  final DuplicateDirectoryPicker? directoryPicker;
  final DuplicateScanRunner? scanRunner;
  final DuplicateDeleteRunner? deleteRunner;
  final DuplicateReportWriter? reportWriter;
  final Directory? reportDirectory;

  @override
  State<DuplicateFilesWorkspace> createState() =>
      _DuplicateFilesWorkspaceState();
}

class _DuplicateFilesWorkspaceState extends State<DuplicateFilesWorkspace> {
  String? _directory;
  bool _recursive = true;
  int _minimumSize = 1024 * 1024;
  bool _scanning = false;
  bool _deleting = false;
  CleanupCancellationToken? _token;
  DuplicateScanProgress? _scanProgress;
  CleanupDeleteProgress? _deleteProgress;
  DuplicateScanResult? _result;
  List<DuplicateFileGroup> _groups = const <DuplicateFileGroup>[];
  final Set<String> _selected = <String>{};
  String? _message;
  File? _report;

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final String? path =
        await (widget.directoryPicker?.call() ??
            getDirectoryPath(confirmButtonText: '扫描此文件夹'));
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      _directory = path;
      _groups = const <DuplicateFileGroup>[];
      _result = null;
      _selected.clear();
      _message = null;
      _report = null;
    });
  }

  Future<void> _scan() async {
    final String? root = _directory;
    if (root == null || _scanning || _deleting) return;
    final CleanupCancellationToken token = CleanupCancellationToken();
    _token = token;
    setState(() {
      _scanning = true;
      _scanProgress = null;
      _groups = const <DuplicateFileGroup>[];
      _result = null;
      _selected.clear();
      _message = null;
      _report = null;
    });
    try {
      final DuplicateScanResult result = widget.scanRunner == null
          ? await DuplicateFileScanner.scan(
              root,
              recursive: _recursive,
              minimumSize: _minimumSize,
              cancellationToken: token,
              onProgress: _updateScanProgress,
            )
          : await widget.scanRunner!(
              root,
              recursive: _recursive,
              minimumSize: _minimumSize,
              cancellationToken: token,
              onProgress: _updateScanProgress,
            );
      if (!mounted) return;
      setState(() {
        _result = result;
        _groups = result.groups;
        _message = result.cancelled
            ? '扫描已取消，未执行任何删除'
            : result.groups.isEmpty
            ? '没有发现内容完全一致的重复文件'
            : null;
      });
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _message = '扫描失败：${error.message}');
    } catch (error) {
      if (mounted) setState(() => _message = '扫描失败：$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
      if (identical(_token, token)) _token = null;
    }
  }

  void _updateScanProgress(DuplicateScanProgress progress) {
    if (mounted) setState(() => _scanProgress = progress);
  }

  void _selectSuggestions() {
    setState(() {
      _selected.clear();
      for (final DuplicateFileGroup group in _groups) {
        for (final DuplicateFileEntry file in group.files.skip(1)) {
          _selected.add(file.path);
        }
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _deleting || _scanning) return;
    final List<DuplicateFileEntry> entries = <DuplicateFileEntry>[
      for (final DuplicateFileGroup group in _groups)
        for (final DuplicateFileEntry file in group.files)
          if (_selected.contains(file.path)) file,
    ];
    final int selectedBytes = entries.fold<int>(
      0,
      (int total, DuplicateFileEntry file) => total + file.size,
    );
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('将 ${entries.length} 个文件移入回收站？'),
            content: Text(
              '预计释放 ${_formatSize(selectedBytes)}。只处理你勾选且扫描后未变化的文件；不会永久删除。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('duplicates-confirm-delete'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('移入回收站'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final List<CleanupCandidate> candidates = entries
        .map(
          (DuplicateFileEntry file) => CleanupCandidate(
            path: file.path,
            size: file.size,
            modified: file.modified,
            identity: file.identity,
            category: CleanupCategory.duplicateFiles,
            reason: 'SHA-256 完全一致的重复文件',
            sourceLabel: '重复文件扫描',
          ),
        )
        .toList(growable: false);
    setState(() {
      _deleting = true;
      _deleteProgress = null;
      _message = null;
    });
    try {
      final CleanupDeleteResult deleted = widget.deleteRunner == null
          ? await CleanupDeleter.deleteCandidates(
              candidates,
              onProgress: _updateDeleteProgress,
            )
          : await widget.deleteRunner!(
              candidates,
              onProgress: _updateDeleteProgress,
            );
      File? report;
      String? reportWarning;
      try {
        report = widget.reportWriter == null
            ? await CleanupReportWriter.write(
                deleted,
                directory: widget.reportDirectory,
              )
            : await widget.reportWriter!(deleted);
      } catch (error) {
        reportWarning = '；报告保存失败：${error.runtimeType}';
      }
      if (!mounted) return;
      final Set<String> removed = deleted.items
          .where(
            (CleanupItemResult item) =>
                item.status == CleanupItemStatus.succeeded,
          )
          .map((CleanupItemResult item) => item.candidate.path)
          .toSet();
      setState(() {
        _report = report;
        _selected.removeAll(removed);
        _groups = <DuplicateFileGroup>[
          for (final DuplicateFileGroup group in _groups)
            if (group.files
                    .where(
                      (DuplicateFileEntry file) => !removed.contains(file.path),
                    )
                    .length >=
                2)
              DuplicateFileGroup(
                sha256: group.sha256,
                size: group.size,
                files: group.files
                    .where(
                      (DuplicateFileEntry file) => !removed.contains(file.path),
                    )
                    .toList(growable: false),
              ),
        ];
        _message =
            '完成：成功 ${deleted.succeeded}，跳过 ${deleted.skipped}，失败 ${deleted.failed}，释放 ${_formatSize(deleted.releasedBytes)}${reportWarning ?? ''}';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '删除失败：$error；请确认文件未被占用后重试');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _updateDeleteProgress(CleanupDeleteProgress progress) {
    if (mounted) setState(() => _deleteProgress = progress);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHeader(context),
          const SizedBox(height: 10),
          Text(
            _directory ?? '选择要检查的文件夹。扫描只读取文件，删除前会再次确认。',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _buildOptions(),
          if (_scanning || _deleting) ...<Widget>[
            const SizedBox(height: 12),
            _buildProgress(),
          ],
          const SizedBox(height: 12),
          Expanded(child: _buildResults()),
          const SizedBox(height: 10),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          '重复文件',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        const Chip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(Icons.offline_bolt_outlined, size: 15),
          label: Text('本地 SHA-256', style: TextStyle(fontSize: 11)),
        ),
        const Spacer(),
        OutlinedButton.icon(
          key: const Key('duplicates-pick-directory'),
          onPressed: _scanning || _deleting ? null : _pickDirectory,
          icon: const Icon(Icons.folder_open, size: 18),
          label: Text(_directory == null ? '选择文件夹' : '更换文件夹'),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<int>(
            initialValue: _minimumSize,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '最小文件',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem(value: 0, child: Text('不限大小')),
              DropdownMenuItem(value: 1024 * 1024, child: Text('1 MB（推荐）')),
              DropdownMenuItem(value: 10 * 1024 * 1024, child: Text('10 MB')),
              DropdownMenuItem(value: 100 * 1024 * 1024, child: Text('100 MB')),
            ],
            onChanged: _scanning || _deleting
                ? null
                : (int? value) {
                    if (value != null) setState(() => _minimumSize = value);
                  },
          ),
        ),
        FilterChip(
          label: const Text('包含子文件夹'),
          selected: _recursive,
          onSelected: _scanning || _deleting
              ? null
              : (bool value) => setState(() => _recursive = value),
        ),
        FilledButton.icon(
          key: const Key('duplicates-scan'),
          onPressed: _directory == null || _scanning || _deleting
              ? null
              : _scan,
          icon: const Icon(Icons.manage_search, size: 18),
          label: const Text('开始扫描'),
        ),
        if (_scanning)
          TextButton.icon(
            onPressed: _token?.cancel,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('取消'),
          ),
      ],
    );
  }

  Widget _buildProgress() {
    final DuplicateScanProgress? scan = _scanProgress;
    final CleanupDeleteProgress? deletion = _deleteProgress;
    double? value;
    String label;
    if (_deleting) {
      value = deletion == null || deletion.total == 0
          ? null
          : deletion.completed / deletion.total;
      label = deletion == null
          ? '准备移入回收站…'
          : '正在处理 ${deletion.completed}/${deletion.total}';
    } else if (scan?.phase == DuplicateScanPhase.hashing) {
      value = scan!.totalHashBytes == 0
          ? null
          : scan.hashedBytes / scan.totalHashBytes;
      label = '正在计算 SHA-256：${scan.hashCompleted}/${scan.hashTotal}';
    } else {
      label = '正在查找文件：已检查 ${scan?.visitedFiles ?? 0} 个';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LinearProgressIndicator(value: value?.clamp(0, 1)),
        const SizedBox(height: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildResults() {
    if (_groups.isEmpty) {
      return Center(
        child: Text(
          _result == null ? '扫描结果会按内容分组，默认不选择任何文件' : '当前没有待处理的重复文件组',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${_groups.length} 组 · ${_currentDuplicateFiles()} 个重复副本 · 可释放 ${_formatSize(_currentReclaimableBytes())}',
              ),
            ),
            TextButton(
              onPressed: _deleting ? null : _selectSuggestions,
              child: const Text('选择每组建议项'),
            ),
            TextButton(
              onPressed: _selected.isEmpty || _deleting
                  ? null
                  : () => setState(_selected.clear),
              child: const Text('清空选择'),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _groups.length,
            itemBuilder: (BuildContext context, int index) =>
                _buildGroup(_groups[index], index),
          ),
        ),
      ],
    );
  }

  Widget _buildGroup(DuplicateFileGroup group, int index) {
    return ExpansionTile(
      key: PageStorageKey<String>('duplicate-${group.sha256}-$index'),
      initiallyExpanded: index < 3,
      leading: const Icon(Icons.content_copy_outlined),
      title: Text('${group.files.length} 个相同文件 · ${_formatSize(group.size)}'),
      subtitle: Text(
        'SHA-256 ${group.sha256.substring(0, 12)}… · 可释放 ${_formatSize(group.reclaimableBytes)}',
      ),
      children: <Widget>[
        for (int fileIndex = 0; fileIndex < group.files.length; fileIndex++)
          _buildFile(group.files[fileIndex], fileIndex == 0),
      ],
    );
  }

  Widget _buildFile(DuplicateFileEntry file, bool suggestedKeep) {
    return CheckboxListTile(
      key: ValueKey<String>('duplicate-file-${file.path}'),
      value: _selected.contains(file.path),
      onChanged: _deleting
          ? null
          : (bool? selected) {
              setState(() {
                if (selected == true) {
                  _selected.add(file.path);
                } else {
                  _selected.remove(file.path);
                }
              });
            },
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(_fileName(file.path), overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_parentPath(file.path)} · ${_formatDate(file.modified)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      secondary: suggestedKeep
          ? const Chip(
              visualDensity: VisualDensity.compact,
              label: Text('建议保留最新'),
            )
          : null,
    );
  }

  Widget _buildActionBar() {
    final int bytes = <DuplicateFileEntry>[
      for (final DuplicateFileGroup group in _groups)
        for (final DuplicateFileEntry file in group.files)
          if (_selected.contains(file.path)) file,
    ].fold<int>(0, (int total, DuplicateFileEntry file) => total + file.size);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            _message ??
                (_selected.isEmpty
                    ? '默认不选择；请先检查路径和保留建议'
                    : '已选择 ${_selected.length} 个文件，共 ${_formatSize(bytes)}'),
          ),
        ),
        if (_report != null)
          Tooltip(
            message: _report!.path,
            child: const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.description_outlined, size: 18),
            ),
          ),
        FilledButton.icon(
          key: const Key('duplicates-delete'),
          onPressed: _selected.isEmpty || _scanning || _deleting
              ? null
              : _deleteSelected,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('移入回收站 ${_selected.length}'),
        ),
      ],
    );
  }

  static String _fileName(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static String _parentPath(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? '' : path.substring(0, slash);
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int _currentDuplicateFiles() => _groups.fold<int>(
    0,
    (int total, DuplicateFileGroup group) => total + group.files.length - 1,
  );

  int _currentReclaimableBytes() => _groups.fold<int>(
    0,
    (int total, DuplicateFileGroup group) => total + group.reclaimableBytes,
  );
}
