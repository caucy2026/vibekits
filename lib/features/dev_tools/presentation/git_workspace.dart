import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/git_repository_service.dart';

typedef GitInspector = Future<GitRepositorySnapshot> Function(String directory);
typedef GitDirectoryPicker = Future<String?> Function();

class GitWorkspace extends StatefulWidget {
  const GitWorkspace({super.key, this.inspect, this.pickDirectory});

  final GitInspector? inspect;
  final GitDirectoryPicker? pickDirectory;

  @override
  State<GitWorkspace> createState() => _GitWorkspaceState();
}

class _GitWorkspaceState extends State<GitWorkspace> {
  final TextEditingController _directory = TextEditingController();
  GitRepositorySnapshot? _snapshot;
  String? _error;
  bool _loading = false;
  int _view = 0;

  @override
  void dispose() {
    _directory.dispose();
    super.dispose();
  }

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
        _error = error is FormatException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', '');
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
              child: SingleChildScrollView(
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
            '本工作区不会自动 add、commit、checkout、reset 或修改 Git 配置。',
            style: TextStyle(fontSize: 11, color: context.vibe.muted),
          ),
        ],
      ),
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
