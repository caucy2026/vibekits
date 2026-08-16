import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/file_hash_background_runner.dart';
import '../domain/file_hash_service.dart';

typedef FileHashPicker = Future<List<String>> Function();
typedef FileHashCalculator = Future<FileHashResult> Function(
  String path,
  FileHashAlgorithm algorithm,
  FileHashCancellation cancellation,
  FileHashProgress onProgress,
);

class FileHashWorkspace extends StatefulWidget {
  const FileHashWorkspace({
    super.key,
    this.pickFiles,
    this.calculate,
    this.initialPaths = const <String>[],
  });

  final FileHashPicker? pickFiles;
  final FileHashCalculator? calculate;
  final List<String> initialPaths;

  @override
  State<FileHashWorkspace> createState() => _FileHashWorkspaceState();
}

class _FileHashWorkspaceState extends State<FileHashWorkspace> {
  final List<_HashRow> _rows = <_HashRow>[];
  FileHashAlgorithm _algorithm = FileHashAlgorithm.sha256;
  FileHashCancellation? _cancellation;
  int _runSerial = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _rows.addAll(widget.initialPaths.map(_HashRow.new));
    if (_rows.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _calculateAll());
    }
  }

  Future<List<String>> _pickFiles() async {
    if (widget.pickFiles != null) return widget.pickFiles!();
    final List<XFile> files = await openFiles();
    return files.map((XFile file) => file.path).toList(growable: false);
  }

  Future<void> _chooseFiles() async {
    final List<String> paths = await _pickFiles();
    if (!mounted || paths.isEmpty) return;
    final Set<String> existing = _rows.map((_HashRow row) => row.path).toSet();
    setState(() {
      for (final String path in paths) {
        if (existing.add(path)) _rows.add(_HashRow(path));
      }
    });
    await _calculateAll();
  }

  Future<void> _calculateAll() async {
    if (_rows.isEmpty) return;
    _cancellation?.cancel();
    final int serial = ++_runSerial;
    final FileHashCancellation cancellation = FileHashCancellation();
    _cancellation = cancellation;
    setState(() {
      _running = true;
      for (final _HashRow row in _rows) {
        row
          ..digest = null
          ..error = null
          ..progress = 0
          ..state = _HashState.waiting;
      }
    });

    for (final _HashRow row in List<_HashRow>.of(_rows)) {
      if (cancellation.isCancelled || serial != _runSerial) break;
      if (!mounted) return;
      setState(() => row.state = _HashState.running);
      void onProgress(int processed, int total) {
        if (!mounted || serial != _runSerial) return;
        setState(() {
          row.totalBytes = total;
          row.progress = total == 0 ? 1 : processed / total;
        });
      }

      final FileHashResult result = widget.calculate == null
          ? await FileHashBackgroundRunner.calculate(
              row.path,
              _algorithm,
              cancellation: cancellation,
              onProgress: onProgress,
            )
          : await widget.calculate!(
              row.path,
              _algorithm,
              cancellation,
              onProgress,
            );
      if (!mounted || serial != _runSerial) return;
      setState(() {
        row.totalBytes = result.totalBytes;
        row.digest = result.digest;
        row.error = result.error;
        row.state = result.cancelled
            ? _HashState.cancelled
            : result.succeeded
            ? _HashState.done
            : _HashState.failed;
        if (result.succeeded) row.progress = 1;
      });
    }
    if (!mounted || serial != _runSerial) return;
    setState(() => _running = false);
  }

  void _cancel() {
    _cancellation?.cancel();
    setState(() {
      _running = false;
      for (final _HashRow row in _rows) {
        if (row.state == _HashState.running ||
            row.state == _HashState.waiting) {
          row.state = _HashState.cancelled;
        }
      }
    });
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('哈希已复制')));
    }
  }

  Future<void> _copyAll() async {
    final String text = _rows
        .where((_HashRow row) => row.digest != null)
        .map((_HashRow row) => '${row.digest}  ${row.path}')
        .join('\n');
    if (text.isNotEmpty) await _copy(text);
  }

  void _remove(_HashRow row) {
    if (_running) _cancel();
    setState(() => _rows.remove(row));
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int completed = _rows
        .where((_HashRow row) => row.state == _HashState.done)
        .length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '文件哈希',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              const _OfflineBadge(),
              const Spacer(),
              Text(
                _running
                    ? '正在计算 ${completed + 1}/${_rows.length}'
                    : '$completed 项完成',
                style: TextStyle(fontSize: 12, color: context.vibe.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('hash-pick-files'),
                onPressed: _chooseFiles,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('选择文件'),
              ),
              SegmentedButton<FileHashAlgorithm>(
                segments: FileHashAlgorithm.values
                    .map(
                      (FileHashAlgorithm value) =>
                          ButtonSegment<FileHashAlgorithm>(
                            value: value,
                            label: Text(value.label),
                          ),
                    )
                    .toList(growable: false),
                selected: <FileHashAlgorithm>{_algorithm},
                onSelectionChanged: _running
                    ? null
                    : (Set<FileHashAlgorithm> values) {
                        setState(() => _algorithm = values.single);
                        if (_rows.isNotEmpty) _calculateAll();
                      },
              ),
              if (_running)
                OutlinedButton.icon(
                  key: const Key('hash-cancel'),
                  onPressed: _cancel,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('取消'),
                )
              else if (_rows.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _calculateAll,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新计算'),
                ),
              OutlinedButton.icon(
                onPressed: completed == 0 ? null : _copyAll,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('复制全部'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '选择后自动计算；大文件分块读取，不占用整文件内存。MD5 适合兼容校验，安全校验建议 SHA-256。',
            style: TextStyle(fontSize: 12, color: context.vibe.muted),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _rows.isEmpty
                ? _EmptyHashState(onPick: _chooseFiles)
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) =>
                        _buildRow(_rows[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_HashRow row) {
    final String name = row.path.replaceAll('\\', '/').split('/').last;
    return Card(
      key: ValueKey<String>('hash-row-${row.path}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Icon(
              row.state == _HashState.done
                  ? Icons.check_circle_outline
                  : row.state == _HashState.failed
                  ? Icons.error_outline
                  : Icons.description_outlined,
              color: row.state == _HashState.done
                  ? VibekitsColors.primary
                  : row.state == _HashState.failed
                  ? VibekitsColors.danger
                  : context.vibe.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                  const SizedBox(height: 7),
                  if (row.state == _HashState.running)
                    LinearProgressIndicator(value: row.progress)
                  else
                    SelectableText(
                      row.digest ?? row.error ?? _stateLabel(row.state),
                      key: ValueKey<String>('hash-result-${row.path}'),
                      style: TextStyle(
                        fontFamily: 'Cascadia Mono',
                        fontSize: 12,
                        color: row.error == null
                            ? Theme.of(context).colorScheme.onSurface
                            : VibekitsColors.danger,
                      ),
                    ),
                ],
              ),
            ),
            if (row.digest != null)
              IconButton(
                tooltip: '复制哈希',
                onPressed: () => _copy(row.digest!),
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
            IconButton(
              tooltip: '移除',
              onPressed: () => _remove(row),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(_HashState state) => switch (state) {
    _HashState.waiting => '等待计算',
    _HashState.running => '正在计算',
    _HashState.done => '已完成',
    _HashState.failed => '计算失败',
    _HashState.cancelled => '已取消',
  };
}

class _HashRow {
  _HashRow(this.path);

  final String path;
  int totalBytes = 0;
  double progress = 0;
  String? digest;
  String? error;
  _HashState state = _HashState.waiting;
}

enum _HashState { waiting, running, done, failed, cancelled }

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: VibekitsColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      '离线',
      style: TextStyle(fontSize: 11, color: VibekitsColors.primary),
    ),
  );
}

class _EmptyHashState extends StatelessWidget {
  const _EmptyHashState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('hash-empty-state'),
    borderRadius: BorderRadius.circular(12),
    onTap: onPick,
    child: Container(
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: context.vibe.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.fingerprint, size: 42, color: context.vibe.muted),
          const SizedBox(height: 10),
          const Text('选择一个或多个文件，立即计算哈希'),
          const SizedBox(height: 4),
          Text(
            '结果可逐项复制，也可按常见校验文件格式复制全部',
            style: TextStyle(fontSize: 12, color: context.vibe.muted),
          ),
        ],
      ),
    ),
  );
}
