import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/cleanup_deleter.dart';
import '../domain/cleanup_scanner.dart';

/// T2 Windows 清理 Tab（对标 360/CCleaner，docs/08 §4）。
class CleanerTab extends StatefulWidget {
  const CleanerTab({super.key});

  @override
  State<CleanerTab> createState() => _CleanerTabState();
}

class _CleanerTabState extends State<CleanerTab> {
  List<CleanupCandidate> _candidates = const <CleanupCandidate>[];
  final Set<String> _selected = <String>{};
  final Set<String> _whitelist = <String>{};
  bool _scanning = false;
  String _message = '';

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _message = '';
      _candidates = const <CleanupCandidate>[];
      _selected.clear();
    });
    try {
      final List<CleanupCandidate> all = await CleanupScanner.scanUserTemp();
      final List<CleanupCandidate> filtered = all
          .where(
            (CleanupCandidate c) =>
                !_whitelist.any((String w) => c.path.startsWith(w)),
          )
          .toList();
      if (mounted) {
        setState(() {
          _candidates = filtered;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _message = '扫描失败：$e';
        });
      }
    }
  }

  Map<CleanupCategory, List<CleanupCandidate>> get _grouped {
    final Map<CleanupCategory, List<CleanupCandidate>> grouped =
        <CleanupCategory, List<CleanupCandidate>>{};
    for (final CleanupCandidate candidate in _candidates) {
      grouped
          .putIfAbsent(candidate.category, () => <CleanupCandidate>[])
          .add(candidate);
    }
    return grouped;
  }

  int get _selectedSize => _candidates
      .where((CleanupCandidate c) => _selected.contains(c.path))
      .fold<int>(0, (int sum, CleanupCandidate c) => sum + c.size);

  Future<void> _clean() async {
    final List<String> targets = _candidates
        .where((CleanupCandidate c) => _selected.contains(c.path))
        .map((CleanupCandidate c) => c.path)
        .toList();
    if (targets.isEmpty) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认清理'),
        content: Text('将 ${targets.length} 个项目移入回收站，是否继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final bool ok = CleanupDeleter.sendToRecycleBin(targets);
    setState(() {
      _message = ok ? '已请求将 ${targets.length} 个项目移入回收站' : '移入回收站失败，请手动处理';
      _candidates = _candidates
          .where((CleanupCandidate c) => !_selected.contains(c.path))
          .toList();
      _selected.clear();
    });
  }

  Future<void> _manageWhitelist() async {
    final TextEditingController controller = TextEditingController();
    final String? dir = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('添加白名单目录'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '目录路径'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (dir != null && dir.isNotEmpty && Directory(dir).existsSync()) {
      setState(() => _whitelist.add(dir));
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
            color: VibekitsColors.info.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(8),
            child: Text(
              _message,
              style: const TextStyle(
                color: VibekitsColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(child: _buildBody()),
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
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search, size: 18),
            label: Text(_scanning ? '扫描中…' : '开始扫描'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _manageWhitelist,
            icon: const Icon(Icons.block, size: 18),
            label: Text('白名单（${_whitelist.length}）'),
          ),
          const Spacer(),
          Text(
            '已选择 ${_formatSize(_selectedSize)}',
            style: const TextStyle(
              fontSize: 12,
              color: VibekitsColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _selected.isEmpty ? null : _clean,
            child: Text('清理 ${_selected.length} 项'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_candidates.isEmpty) {
      return const Center(
        child: Text(
          '点击“开始扫描”查找可清理的临时文件\n扫描不会删除任何内容',
          textAlign: TextAlign.center,
          style: TextStyle(color: VibekitsColors.textSecondary),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        for (final MapEntry<CleanupCategory, List<CleanupCandidate>> entry
            in _grouped.entries)
          _buildCategory(entry.key, entry.value),
      ],
    );
  }

  Widget _buildCategory(
    CleanupCategory category,
    List<CleanupCandidate> items,
  ) {
    final int selectedCount = items
        .where((CleanupCandidate c) => _selected.contains(c.path))
        .length;
    final bool all = selectedCount == items.length;
    final bool partial = selectedCount > 0 && !all;
    final int totalSize = items.fold<int>(
      0,
      (int sum, CleanupCandidate c) => sum + c.size,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          dense: true,
          title: Text(
            '${category.label}  ${_formatSize(totalSize)}'
            '${category.highRisk ? '（需确认）' : ''}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: category.highRisk
                  ? VibekitsColors.warning
                  : VibekitsColors.textPrimary,
            ),
          ),
          leading: Checkbox(
            tristate: true,
            value: all ? true : (partial ? null : false),
            onChanged: (bool? v) => setState(() {
              for (final CleanupCandidate c in items) {
                if (v == true) {
                  _selected.add(c.path);
                } else {
                  _selected.remove(c.path);
                }
              }
            }),
          ),
        ),
        for (final CleanupCandidate candidate in items)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selected.contains(candidate.path),
            title: Text(
              candidate.path,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatSize(candidate.size)} · ${candidate.reason}',
              style: const TextStyle(fontSize: 11),
            ),
            onChanged: (bool? v) => setState(() {
              if (v == true) {
                _selected.add(candidate.path);
              } else {
                _selected.remove(candidate.path);
              }
            }),
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
