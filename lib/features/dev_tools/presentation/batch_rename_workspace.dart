import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/file_tools.dart';

typedef DirectoryPicker = Future<String?> Function();

class BatchRenameWorkspace extends StatefulWidget {
  const BatchRenameWorkspace({super.key, this.directoryPicker});

  final DirectoryPicker? directoryPicker;

  @override
  State<BatchRenameWorkspace> createState() => _BatchRenameWorkspaceState();
}

class _BatchRenameWorkspaceState extends State<BatchRenameWorkspace> {
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();
  final TextEditingController _suffixController = TextEditingController();
  final TextEditingController _startController = TextEditingController(
    text: '1',
  );
  final TextEditingController _paddingController = TextEditingController(
    text: '2',
  );

  String? _directory;
  BatchRenamePlan? _plan;
  RenameLetterCase _letterCase = RenameLetterCase.keep;
  bool _addSequence = false;
  bool _executing = false;
  bool _suppressRefresh = false;
  String? _completedSummary;

  @override
  void initState() {
    super.initState();
    for (final TextEditingController controller in <TextEditingController>[
      _findController,
      _replaceController,
      _prefixController,
      _suffixController,
      _startController,
      _paddingController,
    ]) {
      controller.addListener(_refreshPlan);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _findController,
      _replaceController,
      _prefixController,
      _suffixController,
      _startController,
      _paddingController,
    ]) {
      controller.removeListener(_refreshPlan);
      controller.dispose();
    }
    super.dispose();
  }

  BatchRenameOptions get _options => BatchRenameOptions(
    find: _findController.text,
    replace: _replaceController.text,
    prefix: _prefixController.text,
    suffix: _suffixController.text,
    letterCase: _letterCase,
    addSequence: _addSequence,
    sequenceStart: int.tryParse(_startController.text) ?? 1,
    sequencePadding: (int.tryParse(_paddingController.text) ?? 2).clamp(1, 8),
  );

  void _refreshPlan() {
    if (!mounted || _directory == null || _suppressRefresh) return;
    setState(() {
      _completedSummary = null;
      _plan = FileTools.buildBatchRenamePlan(_directory!, _options);
    });
  }

  Future<void> _pickDirectory() async {
    final String? path =
        await (widget.directoryPicker?.call() ??
            getDirectoryPath(confirmButtonText: '选择此文件夹'));
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      _directory = path;
      _completedSummary = null;
      _plan = FileTools.buildBatchRenamePlan(path, _options);
    });
  }

  Future<void> _execute() async {
    final BatchRenamePlan? plan = _plan;
    if (plan == null || !plan.canExecute) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('重命名 ${plan.renameCount} 个文件？'),
            content: const Text('将按预览结果修改当前文件夹中的文件名。遇到错误会立即停止，并尽力恢复已经处理的文件。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('batch-rename-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认重命名'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _executing = true);
    final BatchRenameReport report = await Future<BatchRenameReport>(
      () => FileTools.executeBatchRename(plan),
    );
    if (!mounted) return;
    if (report.isSuccess) {
      _suppressRefresh = true;
      _findController.clear();
      _replaceController.clear();
      _prefixController.clear();
      _suffixController.clear();
      _suppressRefresh = false;
    }
    setState(() {
      _executing = false;
      _completedSummary = report.summary;
      if (report.isSuccess) {
        _addSequence = false;
        _letterCase = RenameLetterCase.keep;
        _plan = FileTools.buildBatchRenamePlan(_directory!, _options);
      }
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(report.summary)));
  }

  @override
  Widget build(BuildContext context) {
    final BatchRenamePlan? plan = _plan;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '批量重命名',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              const _OfflineBadge(),
              const Spacer(),
              OutlinedButton.icon(
                key: const Key('batch-rename-pick-directory'),
                onPressed: _executing ? null : _pickDirectory,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(_directory == null ? '选择文件夹' : '更换文件夹'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _directory ?? '选择一个文件夹后，规则变化会立即生成预览；只处理当前层文件。',
            key: const Key('batch-rename-directory'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _buildRules(),
          const SizedBox(height: 12),
          Expanded(child: _buildPreview(plan)),
          const SizedBox(height: 10),
          _buildActionBar(plan),
        ],
      ),
    );
  }

  Widget _buildRules() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _ruleField(_findController, '查找', hint: '文件名，可含扩展名'),
        _ruleField(_replaceController, '替换为'),
        _ruleField(_prefixController, '前缀'),
        _ruleField(_suffixController, '后缀'),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<RenameLetterCase>(
            initialValue: _letterCase,
            decoration: const InputDecoration(
              labelText: '大小写',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<RenameLetterCase>>[
              DropdownMenuItem(value: RenameLetterCase.keep, child: Text('保持')),
              DropdownMenuItem(
                value: RenameLetterCase.lower,
                child: Text('小写'),
              ),
              DropdownMenuItem(
                value: RenameLetterCase.upper,
                child: Text('大写'),
              ),
            ],
            onChanged: (RenameLetterCase? value) {
              if (value == null) return;
              _letterCase = value;
              _refreshPlan();
            },
          ),
        ),
        FilterChip(
          label: const Text('添加序号'),
          selected: _addSequence,
          onSelected: (bool value) {
            _addSequence = value;
            _refreshPlan();
          },
        ),
        if (_addSequence) ...<Widget>[
          _ruleField(_startController, '起始', width: 78, numbersOnly: true),
          _ruleField(_paddingController, '位数', width: 78, numbersOnly: true),
        ],
      ],
    );
  }

  Widget _ruleField(
    TextEditingController controller,
    String label, {
    String? hint,
    double width = 170,
    bool numbersOnly = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: numbersOnly ? TextInputType.number : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildPreview(BatchRenamePlan? plan) {
    if (_directory == null) {
      return const Center(child: Text('先选择文件夹，不会自动修改任何文件'));
    }
    if (plan == null || plan.items.isEmpty) {
      return const Center(child: Text('该文件夹没有可处理的文件'));
    }
    final List<BatchRenameItem> visible = plan.items
        .where(
          (BatchRenameItem item) =>
              item.oldName != item.newName || item.issue != null,
        )
        .toList(growable: false);
    if (visible.isEmpty) {
      return Center(child: Text(_completedSummary ?? '当前规则不会改变文件名'));
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          const _PreviewHeader(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final BatchRenameItem item = visible[index];
                return _PreviewRow(item: item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BatchRenamePlan? plan) {
    final int count = plan?.renameCount ?? 0;
    final int issues = plan?.issueCount ?? 0;
    return Row(
      children: <Widget>[
        Icon(
          issues > 0 ? Icons.error_outline : Icons.verified_outlined,
          size: 18,
          color: issues > 0
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            issues > 0
                ? '$issues 个问题，修正规则后才能执行'
                : count > 0
                ? '$count 个文件已通过冲突与名称检查'
                : (_completedSummary ?? '等待有效的重命名规则'),
          ),
        ),
        FilledButton.icon(
          key: const Key('batch-rename-execute'),
          onPressed: _executing || plan?.canExecute != true ? null : _execute,
          icon: _executing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.drive_file_rename_outline, size: 18),
          label: Text(_executing ? '正在重命名…' : '重命名 $count 个文件'),
        ),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader();

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('原文件名', style: style)),
          const SizedBox(width: 28),
          Expanded(child: Text('新文件名', style: style)),
          SizedBox(width: 150, child: Text('状态', style: style)),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});

  final BatchRenameItem item;

  @override
  Widget build(BuildContext context) {
    final bool hasIssue = item.issue != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(item.oldName, overflow: TextOverflow.ellipsis)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 16),
          ),
          Expanded(child: Text(item.newName, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 150,
            child: Text(
              hasIssue ? item.issue! : '可重命名',
              style: TextStyle(
                color: hasIssue
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.offline_bolt_outlined, size: 15),
      label: const Text('离线'),
      labelStyle: const TextStyle(fontSize: 11),
    );
  }
}
