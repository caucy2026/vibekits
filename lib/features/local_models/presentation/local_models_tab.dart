import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/curated_model.dart';
import '../domain/model_store.dart';
import '../domain/vad_inference.dart';

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
  const LocalModelsTab({
    super.key,
    this.directory = '',
    this.initialImportPath,
  });

  final String directory;
  final String? initialImportPath;

  @override
  State<LocalModelsTab> createState() => _LocalModelsTabState();
}

class _LocalModelsTabState extends State<LocalModelsTab> {
  late final String _directory = widget.directory.trim().isEmpty
      ? defaultModelDirectory()
      : widget.directory.trim();
  List<ModelInfo> _models = const <ModelInfo>[];
  String _message = '';
  String? _wavPath;
  VadInferenceResult? _vadResult;
  bool _runningVad = false;
  String? _downloadingId;
  double? _downloadProgress;
  HttpClient? _downloadClient;

  @override
  void initState() {
    super.initState();
    _refresh();
    final String? path = widget.initialImportPath;
    if (path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _importPath(path));
    }
  }

  Future<void> _refresh() async {
    final List<ModelInfo> models = await ModelStore.list(_directory);
    if (mounted) setState(() => _models = models);
  }

  ModelInfo? get _runnableVadModel {
    for (final String preferred in <String>[
      'silero_vad_v6.onnx',
      'silero_vad.onnx',
    ]) {
      final ModelInfo? found = _models
          .where(
            (ModelInfo model) =>
                model.integrity == ModelIntegrity.verified &&
                model.fileName == preferred,
          )
          .firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _download(CuratedModel model) async {
    if (_downloadingId != null) return;
    final Directory temp = Directory.systemTemp.createTempSync(
      'vibekits_model',
    );
    final File downloaded = File(
      '${temp.path}${Platform.pathSeparator}${model.fileName}',
    );
    final HttpClient client = HttpClient();
    _downloadClient = client;
    setState(() {
      _downloadingId = model.id;
      _downloadProgress = null;
      _message = '正在下载 ${model.name}…';
    });
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse(model.sourceUrl),
      );
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final IOSink sink = downloaded.openWrite();
      int received = 0;
      try {
        await for (final List<int> chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted) {
            setState(() {
              _downloadProgress = response.contentLength <= 0
                  ? null
                  : received / response.contentLength;
            });
          }
        }
      } finally {
        await sink.close();
      }
      final String digest =
          (await crypto.sha256.bind(downloaded.openRead()).first).toString();
      if (digest != model.sha256) {
        throw const FormatException('模型 SHA-256 校验失败，文件不会安装');
      }
      final ModelInfo installed = await ModelStore.import(
        downloaded.path,
        _directory,
      );
      if (!mounted) return;
      setState(() => _message = '已安装 ${installed.fileName}，校验通过');
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = '模型安装失败：$error');
    } finally {
      client.close(force: true);
      _downloadClient = null;
      if (temp.existsSync()) temp.deleteSync(recursive: true);
      if (mounted) {
        setState(() {
          _downloadingId = null;
          _downloadProgress = null;
        });
      }
    }
  }

  void _cancelDownload() {
    _downloadClient?.close(force: true);
    setState(() => _message = '已取消模型下载');
  }

  Future<void> _chooseWav() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'WAV 音频', extensions: <String>['wav']),
      ],
    );
    if (file != null && mounted) {
      setState(() {
        _wavPath = file.path;
        _vadResult = null;
      });
    }
  }

  Future<void> _runVad() async {
    final ModelInfo? model = _runnableVadModel;
    final String? wavPath = _wavPath;
    if (model == null || wavPath == null || _runningVad) return;
    setState(() {
      _runningVad = true;
      _vadResult = null;
      _message = '正在本机 CPU 分析 WAV，不会上传音频…';
    });
    try {
      final VadInferenceResult result = await runVadInferenceAsync(
        modelPath: '$_directory${Platform.pathSeparator}${model.fileName}',
        wavPath: wavPath,
      );
      if (!mounted) return;
      setState(() {
        _vadResult = result;
        _message = '分析完成：发现 ${result.segments.length} 个语音片段';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '推理失败：$error');
    } finally {
      if (mounted) setState(() => _runningVad = false);
    }
  }

  Future<void> _import() async {
    const XTypeGroup group = XTypeGroup(
      label: '模型文件',
      extensions: <String>['onnx', 'bin', 'gguf', 'model'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file == null) return;
    await _importPath(file.path);
  }

  Future<void> _importPath(String path) async {
    try {
      final ModelInfo info = await ModelStore.import(path, _directory);
      setState(() {
        _message = '已导入 ${info.fileName}，SHA-256 ${info.shaPrefix}…';
      });
      await _refresh();
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
  void dispose() {
    _downloadClient?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Material(color: Colors.transparent, child: _buildList());

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
                '推理全离线 · 单个模型上限 100MB',
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
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxWidth < 780;
              final Widget models = _buildModelPanel();
              final Widget workspace = _buildVadWorkspace();
              if (compact) {
                return DefaultTabController(
                  length: 2,
                  child: Column(
                    children: <Widget>[
                      const TabBar(
                        tabs: <Widget>[
                          Tab(text: '模型'),
                          Tab(text: '运行'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: <Widget>[models, workspace],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Row(
                children: <Widget>[
                  SizedBox(width: 380, child: models),
                  const VerticalDivider(width: 1),
                  Expanded(child: workspace),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModelPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            '已安装 · ${_models.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: _models.isEmpty
              ? Center(
                  child: Text(
                    '尚未安装模型',
                    style: TextStyle(color: context.vibe.muted),
                  ),
                )
              : ListView.builder(
                  itemCount: _models.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ModelInfo model = _models[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        model.integrity == ModelIntegrity.verified
                            ? Icons.verified_outlined
                            : Icons.warning_amber_outlined,
                        size: 20,
                      ),
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
                        tooltip: '删除模型',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _delete(model),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Text(
            '精选小模型',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          height: 142,
          child: ListView.builder(
            itemCount: curatedModels.length,
            itemBuilder: (BuildContext context, int index) {
              final CuratedModel model = curatedModels[index];
              final bool installed = _models.any(
                (ModelInfo item) =>
                    item.fileName == model.fileName &&
                    item.integrity == ModelIntegrity.verified,
              );
              final bool downloading = _downloadingId == model.id;
              return ListTile(
                dense: true,
                title: Text(model.name, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  '${_formatSize(model.downloadBytes)} · ${model.license} · ${model.runtime}',
                  style: TextStyle(fontSize: 10, color: context.vibe.muted),
                ),
                trailing: downloading
                    ? SizedBox(
                        width: 86,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                              ),
                            ),
                            IconButton(
                              tooltip: '取消下载',
                              onPressed: _cancelDownload,
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      )
                    : TextButton(
                        onPressed: installed || _downloadingId != null
                            ? null
                            : () => _download(model),
                        child: Text(installed ? '已安装' : '安装'),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVadWorkspace() {
    final ModelInfo? model = _runnableVadModel;
    final String wavName = _wavPath == null
        ? '尚未选择音频'
        : _wavPath!.replaceAll('\\', '/').split('/').last;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.graphic_eq, size: 21),
              const SizedBox(width: 8),
              Text(
                '语音片段检测',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: VibekitsColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '本机 CPU · 离线',
                  style: TextStyle(fontSize: 11, color: VibekitsColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '找出 WAV 中真正有人声的时间段，适合录音裁剪、字幕预处理和 ASR 前置降空白。',
            style: TextStyle(fontSize: 12, color: context.vibe.muted),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.vibe.panelRaised,
              border: Border.all(color: context.vibe.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('模型：${model?.fileName ?? '未安装 Silero VAD 兼容模型'}'),
                const SizedBox(height: 6),
                Text('音频：$wavName'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('vad-pick-wav'),
                onPressed: _runningVad ? null : _chooseWav,
                icon: const Icon(Icons.audio_file_outlined, size: 18),
                label: const Text('选择 WAV'),
              ),
              FilledButton.icon(
                key: const Key('vad-run'),
                onPressed: model == null || _wavPath == null || _runningVad
                    ? null
                    : _runVad,
                icon: _runningVad
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(_runningVad ? '分析中…' : '开始分析'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _vadResult == null
                ? Center(
                    child: Text(
                      model == null
                          ? '先从左侧安装 629KB 的精选模型'
                          : '选择 16kHz 单声道 WAV 开始分析',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : _buildVadResult(_vadResult!),
          ),
        ],
      ),
    );
  }

  Widget _buildVadResult(VadInferenceResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${result.segments.length} 个片段 · 人声 ${result.speechDurationSeconds.toStringAsFixed(2)}s / '
          '音频 ${result.audioDurationSeconds.toStringAsFixed(2)}s · '
          '耗时 ${result.elapsed.inMilliseconds}ms · Runtime ${result.runtimeVersion}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: result.segments.length,
            itemBuilder: (BuildContext context, int index) {
              final VoiceSegment segment = result.segments[index];
              return ListTile(
                dense: true,
                leading: Text('${index + 1}'),
                title: Text(
                  '${segment.startSeconds.toStringAsFixed(2)}s — '
                  '${segment.endSeconds.toStringAsFixed(2)}s',
                ),
                trailing: Text(
                  '${segment.durationSeconds.toStringAsFixed(2)}s',
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
