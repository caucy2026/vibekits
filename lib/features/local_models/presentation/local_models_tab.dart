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
  const LocalModelsTab({super.key});

  @override
  State<LocalModelsTab> createState() => _LocalModelsTabState();
}

class _LocalModelsTabState extends State<LocalModelsTab> {
  final String _directory = defaultModelDirectory();
  List<ModelInfo> _models = const <ModelInfo>[];
  String _message = '';
  String _workspace = 'OCR';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _models = ModelStore.list(_directory);
    });
  }

  Future<void> _import() async {
    const XTypeGroup group = XTypeGroup(
      label: '模型文件',
      extensions: <String>['onnx', 'bin', 'gguf', 'model', '*'],
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
    final bool ok = ModelStore.delete(
      '$_directory${Platform.pathSeparator}${model.fileName}',
    );
    setState(() {
      _message = ok ? '已删除 ${model.fileName}' : '删除失败';
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _buildList()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildWorkspace()),
      ],
    );
  }

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
                icon: const Icon(Icons.download, size: 18),
                label: const Text('导入模型'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              const Spacer(),
              const Icon(Icons.folder_open, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _directory,
                  style: const TextStyle(
                    fontSize: 11,
                    color: VibekitsColors.textSecondary,
                  ),
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
              style: const TextStyle(
                fontSize: 12,
                color: VibekitsColors.textPrimary,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _models.isEmpty
              ? const Center(
                  child: Text(
                    '暂无模型\n点击“导入模型”添加本地模型文件',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VibekitsColors.textSecondary),
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
                        '${model.capability} · ${_formatSize(model.size)}',
                        style: const TextStyle(fontSize: 11),
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

  Widget _buildWorkspace() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment(value: 'OCR', label: Text('OCR')),
              ButtonSegment(value: 'ASR', label: Text('ASR')),
              ButtonSegment(value: 'TTS', label: Text('TTS')),
            ],
            selected: <String>{_workspace},
            onSelectionChanged: (Set<String> s) =>
                setState(() => _workspace = s.first),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Text(
                '$_workspace 工作区\n\n推理运行时（ONNX Runtime / sherpa-onnx）待接入，\n'
                '模型管理、导入、校验已就绪。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: VibekitsColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
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
