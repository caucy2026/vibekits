import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/git_repository_service.dart';

typedef GitInspector = Future<GitRepositorySnapshot> Function(String directory);
typedef GitDirectoryPicker = Future<String?> Function();
typedef GitBackupPreviewer = Future<GitBackupPreview> Function(
  String directory,
  String remoteId,
);
typedef GitBackupCommitter = Future<GitBackupCommitResult> Function(
  String previewId,
  List<String> includedPaths,
  String message,
);
typedef GitBackupPusher = Future<GitBackupPushResult> Function(
  String previewId,
  String commitSha,
);

class GitWorkspace extends StatefulWidget {
  const GitWorkspace({
    super.key,
    this.inspect,
    this.pickDirectory,
    this.previewBackup,
    this.commitBackup,
    this.pushBackup,
  });

  final GitInspector? inspect;
  final GitDirectoryPicker? pickDirectory;
  final GitBackupPreviewer? previewBackup;
  final GitBackupCommitter? commitBackup;
  final GitBackupPusher? pushBackup;

  @override
  State<GitWorkspace> createState() => _GitWorkspaceState();
}

class _GitWorkspaceState extends State<GitWorkspace> {
  final TextEditingController _directory = TextEditingController();
  final TextEditingController _remote = TextEditingController(text: 'backup');
  final TextEditingController _commitMessage = TextEditingController(
    text: 'backup: save local changes',
  );
  GitRepositorySnapshot? _snapshot;
  GitBackupPreview? _backupPreview;
  GitBackupCommitResult? _backupCommit;
  GitBackupPushResult? _backupPush;
  final Set<String> _backupPaths = <String>{};
  String? _error;
  bool _loading = false;
  int _view = 0;

  @override
  void dispose() {
    _directory.dispose();
    _remote.dispose();
    _commitMessage.dispose();
    super.dispose();
  }

  Future<void> _previewBackup() async {
    setState(() {
      _loading = true;
      _error = null;
      _backupPreview = null;
      _backupCommit = null;
      _backupPush = null;
      _backupPaths.clear();
    });
    try {
      final GitBackupPreview preview = await (widget.previewBackup != null
          ? widget.previewBackup!(_directory.text, _remote.text)
          : GitRepositoryService.previewBackup(
              _directory.text,
              remoteId: _remote.text,
            ));
      if (!mounted) return;
      setState(() {
        _backupPreview = preview;
        _backupPaths.addAll(preview.includedPaths);
        _directory.text = preview.repositoryRoot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _commitSelectedBackup() async {
    final GitBackupPreview? preview = _backupPreview;
    if (preview == null ||
        _backupPaths.isEmpty ||
        preview.blockers.isNotEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('创建本地备份提交？'),
        content: Text(
          '将暂存并提交 ${_backupPaths.length} 个已预览文件。\n'
          '本步骤不会上传网络，push 将再次单独询问。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('git-backup-confirm-commit'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<String> paths = _backupPaths.toList()..sort();
      final GitBackupCommitResult result = await (widget.commitBackup != null
          ? widget.commitBackup!(preview.id, paths, _commitMessage.text)
          : GitRepositoryService.commitBackup(
              previewId: preview.id,
              includedPaths: paths,
              message: _commitMessage.text,
            ));
      if (!mounted) return;
      setState(() {
        _backupCommit = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _pushCommittedBackup() async {
    final GitBackupPreview? preview = _backupPreview;
    final GitBackupCommitResult? commit = _backupCommit;
    if (preview == null || commit == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('推送到远端备份分支？'),
        content: SelectableText(
          '${preview.remoteId} → ${preview.targetBranch}\n${commit.commitSha}\n\n'
          '不会 force、删除远端分支或修改 tag；完成后将读取远端 ref 核对 SHA。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('git-backup-confirm-push'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认推送'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final GitBackupPushResult result = await (widget.pushBackup != null
          ? widget.pushBackup!(preview.id, commit.commitSha)
          : GitRepositoryService.pushBackup(
              previewId: preview.id,
              commitSha: commit.commitSha,
            ));
      if (!mounted) return;
      setState(() {
        _backupPush = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  String _messageFor(Object error) => error is FormatException
      ? error.message
      : error.toString().replaceFirst('Bad state: ', '');

  Future<void> _pick() async {
    final String? path = widget.pickDirectory != null
        ? await widget.pickDirectory!()
        : await getDirectoryPath(confirmButtonText: '打开仓库');
    if (path != null) {
      _directory.text = path;
      await _inspect();
    }
  }

  Future<void> _inspect() async {
    setState(() {
      _loading = true;
      _error = null;
      _backupPreview = null;
      _backupCommit = null;
      _backupPush = null;
      _backupPaths.clear();
    });
    try {
      final GitRepositorySnapshot snapshot = await (widget.inspect != null
          ? widget.inspect!(_directory.text)
          : GitRepositoryService.inspect(_directory.text));
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _directory.text = snapshot.root;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final GitRepositorySnapshot? snapshot = _snapshot;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const Icon(Icons.account_tree_outlined, size: 21),
              const Text(
                'Git 工作区',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              _GitBadge(text: '只读检查', color: context.vibe.success),
              if (snapshot != null)
                Text(
                  snapshot.branch,
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('git-directory'),
                  controller: _directory,
                  enabled: !_loading,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _inspect(),
                  decoration: const InputDecoration(
                    labelText: '仓库或其子目录',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : _pick,
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: const Text('选择'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('git-refresh'),
                onPressed: _loading ? null : _inspect,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('刷新'),
              ),
            ],
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const Key('git-error'),
                style: const TextStyle(
                  color: VibekitsColors.danger,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 0, label: Text('变更')),
              ButtonSegment<int>(value: 1, label: Text('Diff')),
              ButtonSegment<int>(value: 2, label: Text('日志')),
              ButtonSegment<int>(value: 3, label: Text('安全备份')),
            ],
            selected: <int>{_view},
            onSelectionChanged: (Set<int> value) =>
                setState(() => _view = value.first),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              key: const Key('git-output'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.vibe.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.vibe.border),
              ),
              child: _view == 3
                  ? _buildBackupPanel()
                  : SingleChildScrollView(
                      child: SelectableText(
                        snapshot == null
                            ? '选择项目目录后自动找到仓库根目录。'
                            : switch (_view) {
                                0 => snapshot.status,
                                1 => snapshot.diff,
                                _ => snapshot.log,
                              },
                        style: const TextStyle(
                          fontFamily: 'Cascadia Mono',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '只读检查不修改仓库；安全备份必须先 preview，commit 与 push 分别确认，永不 force。',
            style: TextStyle(fontSize: 11, color: context.vibe.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupPanel() {
    final GitBackupPreview? preview = _backupPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 180,
              child: TextField(
                key: const Key('git-backup-remote'),
                controller: _remote,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: '已有 remote 名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('git-backup-preview'),
              onPressed: _loading || _directory.text.trim().isEmpty
                  ? null
                  : _previewBackup,
              icon: const Icon(Icons.fact_check_outlined, size: 17),
              label: const Text('备份预览'),
            ),
            if (preview != null) ...<Widget>[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${preview.remoteId} → ${preview.targetBranch}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (preview == null)
          const Expanded(
            child: Center(child: Text('选择仓库后输入已有 remote 名称，先预览再决定是否提交。')),
          )
        else ...<Widget>[
          if (preview.blockers.isNotEmpty)
            Text(
              '已阻断：${preview.blockers.join('；')}',
              key: const Key('git-backup-blockers'),
              style: const TextStyle(color: VibekitsColors.danger),
            ),
          if (preview.warnings.isNotEmpty)
            Text(
              '需复核：${preview.warnings.join('；')}',
              style: const TextStyle(color: VibekitsColors.warning),
            ),
          const SizedBox(height: 5),
          Expanded(
            child: ListView.builder(
              key: const Key('git-backup-paths'),
              itemCount: preview.includedPaths.length,
              itemBuilder: (BuildContext context, int index) {
                final String path = preview.includedPaths[index];
                return Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    dense: true,
                    value: _backupPaths.contains(path),
                    onChanged:
                        _backupCommit != null || preview.blockers.isNotEmpty
                        ? null
                        : (bool? selected) => setState(() {
                            if (selected == true) {
                              _backupPaths.add(path);
                            } else {
                              _backupPaths.remove(path);
                            }
                          }),
                    title: Text(
                      path,
                      style: const TextStyle(
                        fontFamily: 'Cascadia Mono',
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('git-backup-message'),
                  controller: _commitMessage,
                  enabled: !_loading && _backupCommit == null,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '提交说明',
                    isDense: true,
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('git-backup-commit'),
                onPressed:
                    _loading ||
                        preview.blockers.isNotEmpty ||
                        _backupPaths.isEmpty ||
                        _backupCommit != null
                    ? null
                    : _commitSelectedBackup,
                child: const Text('创建本地提交'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('git-backup-push'),
                onPressed:
                    _loading || _backupCommit == null || _backupPush != null
                    ? null
                    : _pushCommittedBackup,
                child: Text(
                  _backupPush?.verified == true ? '远端 SHA 已核验' : '推送并核验',
                ),
              ),
            ],
          ),
          if (_backupCommit != null)
            SelectableText(
              '本地 commit：${_backupCommit!.commitSha}${_backupPush == null ? ' · 尚未 push' : '\n远端 commit：${_backupPush!.remoteCommitSha} · ${_backupPush!.verified ? '一致' : '不一致'}'}',
              key: const Key('git-backup-result'),
              style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 11),
            ),
        ],
      ],
    );
  }
}

class _GitBadge extends StatelessWidget {
  const _GitBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
