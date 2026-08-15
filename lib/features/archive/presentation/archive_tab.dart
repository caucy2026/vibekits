import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/archive_service.dart';
import '../domain/seven_zip.dart';

/// T1 解压缩 Tab（对标 7-Zip 的操作习惯，docs/08 §3）。
class ArchiveTab extends StatefulWidget {
  const ArchiveTab({super.key});

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

  Future<void> _open() async {
    const XTypeGroup group = XTypeGroup(
      label: '压缩包',
      extensions: <String>[
        'zip',
        'tar',
        'gz',
        'tgz',
        'bz2',
        'tbz2',
        'xz',
        'txz',
        '7z',
        'rar',
        'iso',
      ],
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file == null) return;
    try {
      final ArchiveFormat format = archiveFormatForPath(file.name);
      if (format == ArchiveFormat.sevenZip) {
        final List<SevenZipEntry> entries = await SevenZip.list(file.path);
        setState(() {
          _sevenEntries = entries;
          _sevenPath = file.path;
          _listing = null;
          _archiveName = file.name;
          _selected.clear();
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
      final Uint8List bytes = await file.readAsBytes();
      final ArchiveListing listing = ArchiveService.list(bytes, file.name);
      setState(() {
        _listing = listing;
        _sevenEntries = null;
        _sevenPath = null;
        _archiveName = file.name;
        _selected.clear();
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
    final String? dir = await getDirectoryPath();
    if (dir == null) return;

    // 7z 走 SevenZip 外部进程。
    if (_sevenPath != null) {
      try {
        await SevenZip.extract(
          _sevenPath!,
          dir,
          selectedEntries: _selected.toList(),
          policy: _policy == ConflictPolicy.overwrite
              ? 'overwrite'
              : _policy == ConflictPolicy.skip
              ? 'skip'
              : 'rename',
        );
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('7z 解压完成')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('解压失败：$e')));
        }
      }
      return;
    }

    final ArchiveListing? listing = _listing;
    if (listing == null) return;
    final ExtractResult result = ArchiveService.extract(
      listing: listing,
      targetDir: dir,
      selectedNames: _selected,
      policy: _policy,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '解压完成：成功 ${result.succeeded}，跳过 ${result.skipped}，失败 ${result.failed}',
          ),
        ),
      );
    }
  }

  Future<void> _create() async {
    const XTypeGroup group = XTypeGroup(
      label: '任意文件',
      extensions: <String>['*'],
    );
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[group],
    );
    if (files.isEmpty) return;
    try {
      final List<(String, List<int>)> entries = <(String, List<int>)>[];
      for (final XFile file in files) {
        entries.add((file.name, await file.readAsBytes()));
      }
      final Uint8List bytes = ArchiveService.createArchive(
        files: entries,
        format: ArchiveFormat.zip,
      );
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: 'archive.zip',
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
                style: const TextStyle(
                  fontSize: 13,
                  color: VibekitsColors.textPrimary,
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
            onPressed: _open,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('打开压缩包'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _create,
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
              ],
              onChanged: (ConflictPolicy? p) {
                if (p != null) setState(() => _policy = p);
              },
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _extract, child: const Text('解压')),
          ],
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
      return const Center(
        child: Text(
          '打开一个压缩包查看内容\n支持 zip / tar / tar.gz / gz / bz2 / xz / 7z',
          textAlign: TextAlign.center,
          style: TextStyle(color: VibekitsColors.textSecondary),
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
                style: const TextStyle(
                  fontSize: 13,
                  color: VibekitsColors.textPrimary,
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
                style: const TextStyle(
                  fontSize: 12,
                  color: VibekitsColors.textSecondary,
                ),
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
