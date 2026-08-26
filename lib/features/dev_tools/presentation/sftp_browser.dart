import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/sftp_service.dart';

typedef SftpLocalDirectoryScanner =
    Future<({String path, List<(String, String, bool, int)> entries})> Function(
      String path,
    );

class SftpBrowser extends StatefulWidget {
  const SftpBrowser({
    super.key,
    required this.client,
    this.initialLocalPath,
    this.initialRemotePath = '.',
    this.scanLocalDirectory,
  });

  final RemoteFileClient client;
  final String? initialLocalPath;
  final String initialRemotePath;
  final SftpLocalDirectoryScanner? scanLocalDirectory;

  @override
  State<SftpBrowser> createState() => _SftpBrowserState();
}

class _SftpBrowserState extends State<SftpBrowser> {
  late final TextEditingController _localPath = TextEditingController(
    text: widget.initialLocalPath ?? Directory.current.path,
  );
  late final TextEditingController _remotePath = TextEditingController(
    text: widget.initialRemotePath,
  );
  List<_LocalFileEntry> _localEntries = <_LocalFileEntry>[];
  List<RemoteFileEntry> _remoteEntries = <RemoteFileEntry>[];
  _LocalFileEntry? _selectedLocal;
  RemoteFileEntry? _selectedRemote;
  _TransferJob? _job;
  String? _error;
  bool _loadingLocal = true;
  bool _loadingRemote = true;
  final List<String> _localHistory = <String>[];
  final List<String> _remoteHistory = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshAll());
  }

  @override
  void dispose() {
    _job?.cancellation.cancel();
    _localPath.dispose();
    _remotePath.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait(<Future<bool>>[_refreshLocal(), _refreshRemote()]);
  }

  Future<bool> _refreshLocal() async {
    setState(() {
      _loadingLocal = true;
      _error = null;
    });
    try {
      final ({String path, List<(String, String, bool, int)> entries}) result =
          await (widget.scanLocalDirectory?.call(_localPath.text) ??
              _scanLocalDirectory(_localPath.text));
      if (!mounted) return false;
      setState(() {
        _localPath.text = result.path;
        _localEntries = result.entries
            .map(
              ((String, String, bool, int) item) => _LocalFileEntry(
                name: item.$1,
                path: item.$2,
                isDirectory: item.$3,
                size: item.$4,
              ),
            )
            .toList(growable: false);
        _selectedLocal = null;
        _loadingLocal = false;
      });
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      setState(() {
        _loadingLocal = false;
        _error = '本地目录：$error';
      });
      return false;
    }
  }

  Future<bool> _refreshRemote() async {
    setState(() {
      _loadingRemote = true;
      _error = null;
    });
    try {
      final String canonical = await widget.client.absolute(_remotePath.text);
      final List<RemoteFileEntry> entries = await widget.client.listDirectory(
        canonical,
      );
      if (!mounted) return false;
      setState(() {
        _remotePath.text = canonical;
        _remoteEntries = entries;
        _selectedRemote = null;
        _loadingRemote = false;
      });
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      setState(() {
        _loadingRemote = false;
        _error = '远端目录：$error';
      });
      return false;
    }
  }

  Future<void> _navigateLocal(String target, {bool remember = true}) async {
    if (_loadingLocal) return;
    final String previous = _localPath.text;
    _localPath.text = target;
    if (await _refreshLocal()) {
      if (remember && previous != _localPath.text) {
        setState(() => _localHistory.add(previous));
      }
      return;
    }
    _localPath.text = previous;
  }

  Future<void> _navigateRemote(String target, {bool remember = true}) async {
    if (_loadingRemote) return;
    final String previous = _remotePath.text;
    _remotePath.text = target;
    if (await _refreshRemote()) {
      if (remember && previous != _remotePath.text) {
        setState(() => _remoteHistory.add(previous));
      }
      return;
    }
    _remotePath.text = previous;
  }

  Future<void> _backLocal() async {
    if (_localHistory.isEmpty || _loadingLocal) return;
    final String target = _localHistory.removeLast();
    final String current = _localPath.text;
    setState(() {});
    await _navigateLocal(target, remember: false);
    if (_localPath.text == current && mounted) {
      setState(() => _localHistory.add(target));
    }
  }

  Future<void> _backRemote() async {
    if (_remoteHistory.isEmpty || _loadingRemote) return;
    final String target = _remoteHistory.removeLast();
    final String current = _remotePath.text;
    setState(() {});
    await _navigateRemote(target, remember: false);
    if (_remotePath.text == current && mounted) {
      setState(() => _remoteHistory.add(target));
    }
  }

  String? get _localParent {
    final Directory current = Directory(_localPath.text).absolute;
    final String parent = current.parent.path;
    return parent == current.path ? null : parent;
  }

  String? get _remoteParent {
    String current = _remotePath.text.replaceAll('\\', '/');
    if (current.isEmpty || current == '/') return null;
    while (current.length > 1 && current.endsWith('/')) {
      current = current.substring(0, current.length - 1);
    }
    final int separator = current.lastIndexOf('/');
    return separator <= 0 ? '/' : current.substring(0, separator);
  }

  Future<void> _openLocal(_LocalFileEntry entry) async {
    if (!entry.isDirectory) {
      setState(() => _selectedLocal = entry);
      return;
    }
    await _navigateLocal(entry.path);
  }

  Future<void> _openRemote(RemoteFileEntry entry) async {
    if (!entry.isDirectory) {
      setState(() => _selectedRemote = entry);
      return;
    }
    await _navigateRemote(entry.path);
  }

  Future<_ConflictChoice> _resolveConflict({
    required String name,
    required bool remote,
  }) async {
    final bool exists = remote
        ? _remoteEntries.any((RemoteFileEntry item) => item.name == name)
        : _localEntries.any((_LocalFileEntry item) => item.name == name);
    if (!exists) return _ConflictChoice.overwrite;
    if (!mounted) return _ConflictChoice.cancel;
    return await showDialog<_ConflictChoice>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('目标已存在同名文件'),
            content: Text('“$name”已存在。请选择本次传输的处理方式。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, _ConflictChoice.cancel),
                child: const Text('取消'),
              ),
              OutlinedButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, _ConflictChoice.skip),
                child: const Text('跳过'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, _ConflictChoice.rename),
                child: const Text('重命名'),
              ),
              FilledButton(
                key: const Key('sftp-conflict-overwrite'),
                onPressed: () =>
                    Navigator.pop(context, _ConflictChoice.overwrite),
                child: const Text('覆盖'),
              ),
            ],
          ),
        ) ??
        _ConflictChoice.cancel;
  }

  String _availableName(String original, Iterable<String> existing) {
    final Set<String> names = existing.toSet();
    final int dot = original.lastIndexOf('.');
    final String stem = dot > 0 ? original.substring(0, dot) : original;
    final String suffix = dot > 0 ? original.substring(dot) : '';
    for (int index = 1; index < 10000; index += 1) {
      final String candidate = '$stem ($index)$suffix';
      if (!names.contains(candidate)) return candidate;
    }
    throw StateError('无法生成不冲突的文件名');
  }

  Future<void> _upload(_LocalFileEntry entry) async {
    if (entry.isDirectory || _job?.running == true) return;
    final bool targetExists = _remoteEntries.any(
      (RemoteFileEntry item) => item.name == entry.name,
    );
    final _ConflictChoice choice = await _resolveConflict(
      name: entry.name,
      remote: true,
    );
    if (choice == _ConflictChoice.cancel || choice == _ConflictChoice.skip) {
      return;
    }
    final String name = choice == _ConflictChoice.rename
        ? _availableName(
            entry.name,
            _remoteEntries.map((RemoteFileEntry item) => item.name),
          )
        : entry.name;
    final String target = _joinRemote(_remotePath.text, name);
    await _runTransfer(
      label: '上传 ${entry.name}',
      total: entry.size,
      retry: () => _upload(entry),
      operation:
          (SftpCancellationToken token, void Function(int, int) progress) =>
              widget.client.upload(
                entry.path,
                target,
                overwrite: targetExists && choice == _ConflictChoice.overwrite,
                cancellation: token,
                onProgress: progress,
              ),
    );
  }

  Future<void> _download(RemoteFileEntry entry) async {
    if (entry.isDirectory || _job?.running == true) return;
    final bool targetExists = _localEntries.any(
      (_LocalFileEntry item) => item.name == entry.name,
    );
    final _ConflictChoice choice = await _resolveConflict(
      name: entry.name,
      remote: false,
    );
    if (choice == _ConflictChoice.cancel || choice == _ConflictChoice.skip) {
      return;
    }
    final String name = choice == _ConflictChoice.rename
        ? _availableName(
            entry.name,
            _localEntries.map((_LocalFileEntry item) => item.name),
          )
        : entry.name;
    final String target = _joinLocal(_localPath.text, name);
    await _runTransfer(
      label: '下载 ${entry.name}',
      total: entry.size,
      retry: () => _download(entry),
      operation:
          (SftpCancellationToken token, void Function(int, int) progress) =>
              widget.client.download(
                entry.path,
                target,
                total: entry.size,
                overwrite: targetExists && choice == _ConflictChoice.overwrite,
                cancellation: token,
                onProgress: progress,
              ),
    );
  }

  Future<void> _runTransfer({
    required String label,
    required int total,
    required Future<void> Function() retry,
    required Future<void> Function(
      SftpCancellationToken token,
      void Function(int bytes, int total) progress,
    )
    operation,
  }) async {
    final _TransferJob job = _TransferJob(
      label: label,
      total: total,
      retry: retry,
    );
    setState(() {
      _job = job;
      _error = null;
    });
    try {
      await operation(job.cancellation, (int bytes, int totalBytes) {
        if (!mounted || _job != job) return;
        setState(() {
          job.bytes = bytes;
          job.total = totalBytes;
        });
      });
      if (!mounted || _job != job) return;
      setState(() {
        job.running = false;
        job.completed = true;
      });
      await _refreshAll();
    } on SftpTransferCancelled {
      if (!mounted || _job != job) return;
      setState(() {
        job.running = false;
        job.cancelled = true;
      });
    } on Object catch (error) {
      if (!mounted || _job != job) return;
      setState(() {
        job.running = false;
        job.error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _error!,
              key: const Key('sftp-error'),
              style: const TextStyle(
                color: VibekitsColors.danger,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _LocalPane(
                  path: _localPath,
                  entries: _localEntries,
                  loading: _loadingLocal,
                  selected: _selectedLocal,
                  onRefresh: () async {
                    await _refreshLocal();
                  },
                  onNavigate: _navigateLocal,
                  onBack: _localHistory.isEmpty || _loadingLocal
                      ? null
                      : _backLocal,
                  onUp: _localParent == null || _loadingLocal
                      ? null
                      : () => _navigateLocal(_localParent!),
                  onOpen: _openLocal,
                  onDropRemote: _download,
                ),
              ),
              SizedBox(
                width: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      key: const Key('sftp-upload-selected'),
                      tooltip: '上传所选',
                      onPressed:
                          _selectedLocal?.isDirectory == false &&
                              _job?.running != true
                          ? () => _upload(_selectedLocal!)
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    IconButton(
                      key: const Key('sftp-download-selected'),
                      tooltip: '下载所选',
                      onPressed:
                          _selectedRemote?.isDirectory == false &&
                              _job?.running != true
                          ? () => _download(_selectedRemote!)
                          : null,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _RemotePane(
                  path: _remotePath,
                  entries: _remoteEntries,
                  loading: _loadingRemote,
                  selected: _selectedRemote,
                  onRefresh: () async {
                    await _refreshRemote();
                  },
                  onNavigate: _navigateRemote,
                  onBack: _remoteHistory.isEmpty || _loadingRemote
                      ? null
                      : _backRemote,
                  onUp: _remoteParent == null || _loadingRemote
                      ? null
                      : () => _navigateRemote(_remoteParent!),
                  onOpen: _openRemote,
                  onDropLocal: _upload,
                ),
              ),
            ],
          ),
        ),
        if (_job != null)
          _TransferBar(job: _job!, onCancel: _job!.cancellation.cancel),
      ],
    );
  }
}

class _LocalPane extends StatelessWidget {
  const _LocalPane({
    required this.path,
    required this.entries,
    required this.loading,
    required this.selected,
    required this.onRefresh,
    required this.onNavigate,
    required this.onBack,
    required this.onUp,
    required this.onOpen,
    required this.onDropRemote,
  });

  final TextEditingController path;
  final List<_LocalFileEntry> entries;
  final bool loading;
  final _LocalFileEntry? selected;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onNavigate;
  final Future<void> Function()? onBack;
  final Future<void> Function()? onUp;
  final Future<void> Function(_LocalFileEntry) onOpen;
  final Future<void> Function(RemoteFileEntry) onDropRemote;

  @override
  Widget build(BuildContext context) => _PaneFrame(
    title: '本地',
    path: path,
    onRefresh: onRefresh,
    onNavigate: onNavigate,
    onBack: onBack,
    onUp: onUp,
    keyPrefix: 'sftp-local',
    child: DragTarget<RemoteFileEntry>(
      onWillAcceptWithDetails: (DragTargetDetails<RemoteFileEntry> details) =>
          !details.data.isDirectory,
      onAcceptWithDetails: (DragTargetDetails<RemoteFileEntry> details) =>
          onDropRemote(details.data),
      builder: (_, _, _) => loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              key: const Key('sftp-local-list'),
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int index) {
                final _LocalFileEntry entry = entries[index];
                final Widget row = _FileRow(
                  name: entry.name,
                  size: entry.size,
                  isDirectory: entry.isDirectory,
                  selected: selected?.path == entry.path,
                  onTap: () => onOpen(entry),
                );
                return entry.isDirectory
                    ? row
                    : Draggable<_LocalFileEntry>(
                        data: entry,
                        feedback: _DragFeedback(entry.name),
                        childWhenDragging: Opacity(opacity: 0.4, child: row),
                        child: row,
                      );
              },
            ),
    ),
  );
}

class _RemotePane extends StatelessWidget {
  const _RemotePane({
    required this.path,
    required this.entries,
    required this.loading,
    required this.selected,
    required this.onRefresh,
    required this.onNavigate,
    required this.onBack,
    required this.onUp,
    required this.onOpen,
    required this.onDropLocal,
  });

  final TextEditingController path;
  final List<RemoteFileEntry> entries;
  final bool loading;
  final RemoteFileEntry? selected;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onNavigate;
  final Future<void> Function()? onBack;
  final Future<void> Function()? onUp;
  final Future<void> Function(RemoteFileEntry) onOpen;
  final Future<void> Function(_LocalFileEntry) onDropLocal;

  @override
  Widget build(BuildContext context) => _PaneFrame(
    title: '远端',
    path: path,
    onRefresh: onRefresh,
    onNavigate: onNavigate,
    onBack: onBack,
    onUp: onUp,
    keyPrefix: 'sftp-remote',
    child: DragTarget<_LocalFileEntry>(
      onWillAcceptWithDetails: (DragTargetDetails<_LocalFileEntry> details) =>
          !details.data.isDirectory,
      onAcceptWithDetails: (DragTargetDetails<_LocalFileEntry> details) =>
          onDropLocal(details.data),
      builder: (_, _, _) => loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              key: const Key('sftp-remote-list'),
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int index) {
                final RemoteFileEntry entry = entries[index];
                final Widget row = _FileRow(
                  name: entry.name,
                  size: entry.size,
                  isDirectory: entry.isDirectory,
                  selected: selected?.path == entry.path,
                  onTap: () => onOpen(entry),
                );
                return entry.isDirectory
                    ? row
                    : Draggable<RemoteFileEntry>(
                        data: entry,
                        feedback: _DragFeedback(entry.name),
                        childWhenDragging: Opacity(opacity: 0.4, child: row),
                        child: row,
                      );
              },
            ),
    ),
  );
}

class _PaneFrame extends StatelessWidget {
  const _PaneFrame({
    required this.title,
    required this.path,
    required this.onRefresh,
    required this.onNavigate,
    required this.onBack,
    required this.onUp,
    required this.keyPrefix,
    required this.child,
  });

  final String title;
  final TextEditingController path;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onNavigate;
  final Future<void> Function()? onBack;
  final Future<void> Function()? onUp;
  final String keyPrefix;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: context.vibe.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(7),
          child: Row(
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 3),
              IconButton(
                key: Key('$keyPrefix-back'),
                tooltip: '后退到上一目录',
                onPressed: onBack,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
              IconButton(
                key: Key('$keyPrefix-up'),
                tooltip: '返回上级目录',
                onPressed: onUp,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: TextField(
                  controller: path,
                  onSubmitted: onNavigate,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int size;
  final bool isDirectory;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    selected: selected,
    leading: Icon(
      isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
      size: 18,
    ),
    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: isDirectory ? null : Text(_formatBytes(size)),
    onTap: onTap,
  );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 5,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(name),
    ),
  );
}

class _TransferBar extends StatelessWidget {
  const _TransferBar({required this.job, required this.onCancel});

  final _TransferJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final double? progress = job.total > 0
        ? (job.bytes / job.total).clamp(0, 1)
        : null;
    final String state = job.completed
        ? '完成'
        : job.cancelled
        ? '已取消'
        : job.error != null
        ? '失败'
        : '${_formatBytes(job.bytes)} / ${_formatBytes(job.total)}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${job.label} · $state', key: const Key('sftp-job-state')),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: job.running
                      ? progress
                      : job.completed
                      ? 1
                      : 0,
                ),
                if (job.error != null)
                  Text(
                    job.error!,
                    style: const TextStyle(
                      color: VibekitsColors.danger,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (job.running)
            TextButton(
              key: const Key('sftp-cancel-transfer'),
              onPressed: onCancel,
              child: const Text('取消'),
            )
          else if (job.error != null)
            TextButton(
              key: const Key('sftp-retry-transfer'),
              onPressed: job.retry,
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _LocalFileEntry {
  const _LocalFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
}

class _TransferJob {
  _TransferJob({required this.label, required this.total, required this.retry});

  final String label;
  final SftpCancellationToken cancellation = SftpCancellationToken();
  final Future<void> Function() retry;
  int bytes = 0;
  int total;
  bool running = true;
  bool completed = false;
  bool cancelled = false;
  String? error;
}

enum _ConflictChoice { overwrite, rename, skip, cancel }

Future<({String path, List<(String, String, bool, int)> entries})>
_scanLocalDirectory(String source) => Isolate.run(() async {
  final String canonical = Directory(source).absolute.path;
  final Directory directory = Directory(canonical);
  if (!await directory.exists()) throw const FileSystemException('目录不存在');
  final List<(String, String, bool, int)> entries =
      <(String, String, bool, int)>[];
  await for (final FileSystemEntity entity in directory.list(
    followLinks: false,
  )) {
    final FileStat stat = await entity.stat();
    final bool isDirectory = stat.type == FileSystemEntityType.directory;
    if (!isDirectory && stat.type != FileSystemEntityType.file) continue;
    entries.add((
      entity.uri.pathSegments.where((String value) => value.isNotEmpty).last,
      entity.path,
      isDirectory,
      isDirectory ? 0 : stat.size,
    ));
  }
  entries.sort(((String, String, bool, int) a, (String, String, bool, int) b) {
    if (a.$3 != b.$3) return a.$3 ? -1 : 1;
    return a.$1.toLowerCase().compareTo(b.$1.toLowerCase());
  });
  return (path: canonical, entries: entries);
});

String _joinRemote(String directory, String name) =>
    directory == '/' ? '/$name' : '$directory/$name';

String _joinLocal(String directory, String name) =>
    '$directory${Platform.pathSeparator}$name';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}
