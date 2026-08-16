import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/model_store.dart';

/// 模型目录默认位置（docs/02 §7）。
String defaultModelDirectory() {
  final String base =
      Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['APPDATA'] ??
      '.';
  return '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Models';
}

/// T5 本地模型 Tab（模型管理已实现；推理运行时属后续接入）。
class LocalModelsTab extends StatefulWidget {
  const LocalModelsTab({super.key, this.directory = ''});

  final String directory;

  @override
  State<LocalModelsTab> createState() => _LocalModelsTabState();
}

class _LocalModelsTabState extends State<LocalModelsTab> {
  late final String _directory = widget.directory.trim().isEmpty
      ? defaultModelDirectory()
      : widget.directory.trim();
  List<ModelInfo> _models = const <ModelInfo>[];
  String _message = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final List<ModelInfo> models = await ModelStore.list(_directory);
    if (mounted) setState(() => _models = models);
  }

  Future<void> _import() async {
    const XTypeGroup group = XTypeGroup(
      label: '模型文件',
      extensions: <String>['onnx', 'bin', 'gguf', 'model'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file == null) return;
    try {
      final ModelInfo info = await ModelStore.import(file.path, _directory);
      setState(() {
        _message = '已导入 ${info.fileName}，SHA-256 ${info.shaPrefix}…';
      });
      _refresh();
    } catch (e) {
      setState(() => _message = '导入失败：$e');
    }
  }

  Future<void> _delete(ModelInfo model) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除本地模型？'),
        content: Text(
          '将永久删除 ${model.fileName}（${_formatSize(model.size)}）。'
          '此操作不会进入回收站。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final bool ok = ModelStore.delete(
      '$_directory${Platform.pathSeparator}${model.fileName}',
    );
    setState(() {
      _message = ok ? '已删除 ${model.fileName}' : '删除失败';
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) => _buildList();

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('导入模型'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              const Spacer(),
              Text(
                '仅管理本地文件 · 单个上限 100MB',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.folder_open, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _directory,
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (_message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _message,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _models.isEmpty
              ? Center(
                  child: Text(
                    '暂无模型\n点击“导入模型”添加本地模型文件',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.vibe.muted),
                  ),
                )
              : ListView.builder(
                  itemCount: _models.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ModelInfo model = _models[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.memory, size: 20),
                      title: Text(
                        model.fileName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${model.capability} · ${_formatSize(model.size)} · ${switch (model.integrity) {
                          ModelIntegrity.verified => '校验通过',
                          ModelIntegrity.modified => '文件已变化',
                          ModelIntegrity.untracked => '未登记',
                        }}',
                        style: TextStyle(
                          fontSize: 11,
                          color: model.integrity == ModelIntegrity.modified
                              ? VibekitsColors.danger
                              : null,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _delete(model),
                      ),
                    );
                  },
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
