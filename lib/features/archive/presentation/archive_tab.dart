import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/supported_file_types.dart';
import '../domain/archive_service.dart';
import '../domain/seven_zip.dart';

enum _ArchiveSource { files, directory }

/// T1 解压缩 Tab（对标 7-Zip 的操作习惯，docs/08 §3）。
class ArchiveTab extends StatefulWidget {
  const ArchiveTab({
    super.key,
    this.initialPath,
    this.openRequest,
    this.maxEntries = 100000,
    this.maxSingleExpandedBytes = 20 * 1024 * 1024 * 1024,
  });

  final String? initialPath;
  final ValueListenable<int>? openRequest;
  final int maxEntries;
  final int maxSingleExpandedBytes;

  @override
  State<ArchiveTab> createState() => _ArchiveTabState();
}

class _ArchiveTabState extends State<ArchiveTab> {
  ArchiveListing? _listing;
  List<SevenZipEntry>? _sevenEntries;
  String? _sevenPath;
  String _archiveName = '';
  final Set<String> _selected = <String>{};
  ConflictPolicy _policy = ConflictPolicy.rename;
  String _message = '';
  bool _extracting = false;
  ArchiveCancellationToken? _extractToken;
  ArchiveExtractProgress? _extractProgress;
  Stopwatch? _extractClock;

  @override
  void initState() {
    super.initState();
    final String? initialPath = widget.initialPath;
    if (initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openPath(initialPath),
      );
    }
    widget.openRequest?.addListener(_handleOpenRequest);
  }

  void _handleOpenRequest() => _open();

  @override
  void didUpdateWidget(covariant ArchiveTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openRequest != widget.openRequest) {
      oldWidget.openRequest?.removeListener(_handleOpenRequest);
      widget.openRequest?.addListener(_handleOpenRequest);
    }
  }

  @override
  void dispose() {
    widget.openRequest?.removeListener(_handleOpenRequest);
    _extractToken?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    const XTypeGroup group = XTypeGroup(
      label: '压缩包',
      extensions: SupportedFileTypes.archiveExtensions,
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file == null) return;
    await _openPath(file.path);
  }

  Future<void> _openPath(String path) async {
    try {
      final File source = File(path);
      final String fileName = source.uri.pathSegments.last;
      final RandomAccessFile headerFile = await source.open();
      late final Uint8List header;
      try {
        final int headerLength = (await source.length()).clamp(0, 0x8006);
        header = await headerFile.read(headerLength);
      } finally {
        await headerFile.close();
      }
      final ArchiveFormat format = archiveFormatForBytes(
        header,
        path: fileName,
      );
      if (format == ArchiveFormat.sevenZip) {
        final List<SevenZipEntry> entries = await SevenZip.list(path);
        setState(() {
          _sevenEntries = entries;
          _sevenPath = path;
          _listing = null;
          _archiveName = fileName;
          _selected
            ..clear()
            ..addAll(
              entries
                  .where((SevenZipEntry entry) => !entry.isDirectory)
                  .map((SevenZipEntry entry) => entry.name),
            );
          _message = '';
        });
        return;
      }
      if (format == ArchiveFormat.rar || format == ArchiveFormat.iso) {
        setState(() {
          _listing = null;
          _sevenEntries = null;
          _sevenPath = null;
          _message = '暂不支持 rar/iso 格式（需 unrar 或系统工具）';
        });
        return;
      }
      final Uint8List bytes = await source.readAsBytes();
      final ArchiveListing listing = ArchiveService.list(
        bytes,
        fileName,
        maxEntries: widget.maxEntries,
        maxSingleExpandedBytes: widget.maxSingleExpandedBytes,
      );
      setState(() {
        _listing = listing;
        _sevenEntries = null;
        _sevenPath = null;
        _archiveName = fileName;
        _selected
          ..clear()
          ..addAll(
            listing.entries
                .where((ArchiveEntry entry) => !entry.isDirectory)
                .map((ArchiveEntry entry) => entry.name),
          );
        _message = '';
      });
    } catch (e) {
      setState(() {
        _listing = null;
        _sevenEntries = null;
        _sevenPath = null;
        _message = '打开失败：$e';
      });
    }
  }

  Future<void> _extract() async {
    if (_selected.isEmpty) {
      setState(() => _message = '请至少选择一个要解压的文件');
      return;
    }
    final String? dir = await getDirectoryPath();
    if (dir == null) return;

    // 7z 走 SevenZip 外部进程。
    if (_sevenPath != null) {
      final ArchiveCancellationToken token = ArchiveCancellationToken();
      setState(() {
        _extracting = true;
        _extractToken = token;
        _extractProgress = null;
        _extractClock = Stopwatch()..start();
        _message = '';
      });
      try {
        final ExtractResult result = await SevenZip.extractCancellable(
          _sevenPath!,
          dir,
          selectedEntries: _selected.toList(),
          policy: _policy == ConflictPolicy.overwrite
              ? 'overwrite'
              : _policy == ConflictPolicy.skip
              ? 'skip'
              : _policy == ConflictPolicy.ask
              ? 'ask'
              : 'rename',
          cancellationToken: token,
          onProgress: (ArchiveExtractProgress progress) {
            if (mounted) setState(() => _extractProgress = progress);
          },
          onConflict: _askConflict,
        );
        if (mounted) {
          setState(() {
            _message =
                '${result.cancelled ? '7z 解压已取消' : '7z 解压完成'}：'
                '成功 ${result.succeeded}，跳过 ${result.skipped}，失败 ${result.failed}，'
                '已写入 ${_formatSize(result.writtenBytes)}';
          });
        }
      } catch (e) {
        if (mounted) setState(() => _message = '7z 解压失败：$e');
      } finally {
        _extractClock?.stop();
        if (mounted) {
          setState(() {
            _extracting = false;
            _extractToken = null;
          });
        }
      }
      return;
    }

    final ArchiveListing? listing = _listing;
    if (listing == null) return;
    final ArchiveCancellationToken token = ArchiveCancellationToken();
    setState(() {
      _extracting = true;
      _extractToken = token;
      _extractProgress = null;
      _extractClock = Stopwatch()..start();
      _message = '';
    });
    try {
      final ExtractResult result = await ArchiveService.extractAsync(
        listing: listing,
        targetDir: dir,
        selectedNames: Set<String>.from(_selected),
        policy: _policy,
        cancellationToken: token,
        onProgress: (ArchiveExtractProgress progress) {
          if (mounted) setState(() => _extractProgress = progress);
        },
        onConflict: _askConflict,
      );
      if (mounted) {
        setState(() {
          _message =
              '${result.cancelled ? '解压已取消' : '解压完成'}：'
              '成功 ${result.succeeded}，跳过 ${result.skipped}，失败 ${result.failed}，'
              '已写入 ${_formatSize(result.writtenBytes)}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '解压失败：$error');
    } finally {
      _extractClock?.stop();
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractToken = null;
        });
      }
    }
  }

  Future<void> _create() async {
    final ArchiveFormat? format = await showDialog<ArchiveFormat>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('选择压缩格式'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ArchiveFormat.zip),
            child: const ListTile(
              leading: Icon(Icons.folder_zip_outlined),
              title: Text('ZIP'),
              subtitle: Text('兼容性最好'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ArchiveFormat.tar),
            child: const ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('TAR'),
              subtitle: Text('仅打包，不压缩'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ArchiveFormat.gzip),
            child: const ListTile(
              leading: Icon(Icons.compress),
              title: Text('TAR.GZ'),
              subtitle: Text('TAR 打包后使用 GZip 压缩'),
            ),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final _ArchiveSource? source = await showDialog<_ArchiveSource>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('选择来源'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_ArchiveSource.files),
            child: const ListTile(
              leading: Icon(Icons.insert_drive_file_outlined),
              title: Text('选择文件'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_ArchiveSource.directory),
            child: const ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text('选择目录'),
            ),
          ),
        ],
      ),
    );
    if (source == null) return;
    const XTypeGroup group = XTypeGroup(
      label: '任意文件',
      extensions: <String>['*'],
    );
    try {
      final List<(String, List<int>)> entries;
      if (source == _ArchiveSource.directory) {
        final String? directory = await getDirectoryPath();
        if (directory == null) return;
        entries = await ArchiveService.collectDirectory(
          directory,
          maxEntries: widget.maxEntries,
          maxTotalBytes: widget.maxSingleExpandedBytes,
        );
      } else {
        final List<XFile> files = await openFiles(
          acceptedTypeGroups: <XTypeGroup>[group],
        );
        if (files.isEmpty) return;
        entries = <(String, List<int>)>[];
        for (final XFile file in files) {
          entries.add((file.name, await file.readAsBytes()));
        }
      }
      if (entries.isEmpty) throw const FormatException('所选来源中没有可打包文件');
      final Uint8List bytes = ArchiveService.createArchive(
        files: entries,
        format: format,
      );
      final String suggestedName = switch (format) {
        ArchiveFormat.zip => 'archive.zip',
        ArchiveFormat.tar => 'archive.tar',
        ArchiveFormat.gzip => 'archive.tar.gz',
        _ => 'archive.bin',
      };
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: suggestedName,
      );
      final String? path = location?.path;
      if (path == null) return;
      await File(path).writeAsBytes(bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已创建 $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildToolbar(),
        if (_message.isNotEmpty)
          Container(
            width: double.infinity,
            color: VibekitsColors.danger.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(8),
            child: Text(
              _message,
              style: const TextStyle(
                color: VibekitsColors.danger,
                fontSize: 12,
              ),
            ),
          ),
        if (_extracting) _buildExtractProgress(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSevenZipBody(List<SevenZipEntry> entries) {
    final bool allSelected =
        _selected.length == entries.length && entries.isNotEmpty;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Checkbox(
              value: allSelected,
              onChanged: (bool? v) => setState(() {
                if (v == true) {
                  _selected.addAll(entries.map((SevenZipEntry e) => e.name));
                } else {
                  _selected.clear();
                }
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_archiveName  共 ${entries.length} 项',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int index) {
              final SevenZipEntry entry = entries[index];
              return CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(entry.name),
                title: Text(
                  entry.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                secondary: entry.isDirectory
                    ? const Icon(Icons.folder, size: 18)
                    : const Icon(Icons.insert_drive_file, size: 18),
                subtitle: Text(
                  entry.isDirectory ? '目录' : _formatSize(entry.size),
                  style: const TextStyle(fontSize: 11),
                ),
                onChanged: (bool? v) => setState(() {
                  if (v == true) {
                    _selected.add(entry.name);
                  } else {
                    _selected.remove(entry.name);
                  }
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          ElevatedButton.icon(
            onPressed: _extracting ? null : _open,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('打开压缩包'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _extracting ? null : _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('创建压缩包'),
          ),
          const Spacer(),
          if (_listing != null || _sevenEntries != null) ...[
            DropdownButton<ConflictPolicy>(
              value: _policy,
              underline: const SizedBox.shrink(),
              items: const <DropdownMenuItem<ConflictPolicy>>[
                DropdownMenuItem(
                  value: ConflictPolicy.overwrite,
                  child: Text('覆盖'),
                ),
                DropdownMenuItem(value: ConflictPolicy.skip, child: Text('跳过')),
                DropdownMenuItem(
                  value: ConflictPolicy.rename,
                  child: Text('重命名'),
                ),
                DropdownMenuItem(
                  value: ConflictPolicy.ask,
                  child: Text('逐个询问'),
                ),
              ],
              onChanged: _extracting
                  ? null
                  : (ConflictPolicy? p) {
                      if (p != null) setState(() => _policy = p);
                    },
            ),
            const SizedBox(width: 8),
            if (_extracting)
              OutlinedButton.icon(
                onPressed: () => _extractToken?.cancel(),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('取消'),
              )
            else
              ElevatedButton(onPressed: _extract, child: const Text('解压')),
          ],
        ],
      ),
    );
  }

  Future<ConflictPolicy> _askConflict(String path) async {
    if (!mounted) return ConflictPolicy.skip;
    final ConflictPolicy? result = await showDialog<ConflictPolicy>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('目标文件已存在'),
        content: SizedBox(
          width: 520,
          child: Text(path, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(ConflictPolicy.skip),
            child: const Text('跳过'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ConflictPolicy.rename),
            child: const Text('重命名'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(ConflictPolicy.overwrite),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    return result ?? ConflictPolicy.skip;
  }

  Widget _buildExtractProgress() {
    final ArchiveExtractProgress? progress = _extractProgress;
    final double? value = progress == null || progress.totalBytes <= 0
        ? null
        : (progress.writtenBytes / progress.totalBytes).clamp(0, 1);
    final int elapsedMs = _extractClock?.elapsedMilliseconds ?? 0;
    final double bytesPerSecond = progress == null || elapsedMs <= 0
        ? 0
        : progress.writtenBytes * 1000 / elapsedMs;
    return Container(
      width: double.infinity,
      color: context.vibe.panelRaised,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: value),
          const SizedBox(height: 6),
          Text(
            progress == null
                ? '正在准备解压…'
                : '${progress.currentFile} · ${progress.completedFiles}/${progress.totalFiles} · '
                      '${_formatSize(progress.writtenBytes)}/${_formatSize(progress.totalBytes)} · '
                      '${_formatSize(bytesPerSecond.round())}/s',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final List<SevenZipEntry>? sevenEntries = _sevenEntries;
    if (sevenEntries != null) {
      return _buildSevenZipBody(sevenEntries);
    }
    final ArchiveListing? listing = _listing;
    if (listing == null) {
      return Center(
        child: Text(
          '打开一个压缩包查看内容\n支持 zip / tar / tar.gz / gz / bz2 / xz / 7z',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.vibe.muted),
        ),
      );
    }
    final List<ArchiveEntry> entries = listing.entries;
    final bool allSelected =
        _selected.length == entries.length && entries.isNotEmpty;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Checkbox(
              value: allSelected,
              onChanged: (bool? v) => setState(() {
                if (v == true) {
                  _selected.addAll(entries.map((ArchiveEntry e) => e.name));
                } else {
                  _selected.clear();
                }
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_archiveName  共 ${entries.length} 项 / '
                '${_formatSize(listing.totalUncompressedSize)}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int index) {
              final ArchiveEntry entry = entries[index];
              final bool selected = _selected.contains(entry.name);
              return CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected,
                title: Text(
                  entry.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                secondary: entry.isDirectory
                    ? const Icon(Icons.folder, size: 18)
                    : const Icon(Icons.insert_drive_file, size: 18),
                subtitle: Text(
                  entry.isDirectory ? '目录' : _formatSize(entry.size),
                  style: const TextStyle(fontSize: 11),
                ),
                onChanged: (bool? v) => setState(() {
                  if (v == true) {
                    _selected.add(entry.name);
                  } else {
                    _selected.remove(entry.name);
                  }
                }),
              );
            },
          ),
        ),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Text(
                '已选 ${_selected.length} 项',
                style: TextStyle(fontSize: 12, color: context.vibe.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
