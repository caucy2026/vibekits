import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../../dev_tools/domain/deepseek_harness_service.dart';
import '../../dev_tools/domain/harness_tool_bridge.dart';
import '../domain/bundled_model_installer.dart';
import '../domain/curated_model.dart';
import '../domain/curated_model_bundle.dart';
import '../domain/image_preview.dart';
import '../domain/model_store.dart';
import '../domain/pp_ocr_v6.dart';
import '../domain/screenshot_capture.dart';
import '../domain/vad_inference.dart';
import 'deepseek_agent_workspace.dart';
import 'official_harness_workspace.dart';

Future<List<int>> loadBundledModelAsset(String path) async {
  final ByteData bundled = await rootBundle.load(path);
  return bundled.buffer.asUint8List(
    bundled.offsetInBytes,
    bundled.lengthInBytes,
  );
}

/// 模型目录默认位置（docs/02 §7）。
String defaultModelDirectory() {
  if (Platform.isMacOS) {
    final String home = Platform.environment['HOME'] ?? '.';
    return <String>[
      home,
      'Library',
      'Application Support',
      'Vibekits',
      'Models',
    ].join(Platform.pathSeparator);
  }
  final String base =
      Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['APPDATA'] ??
      '.';
  return '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Models';
}

String defaultToolDownloadDirectory() {
  final String base =
      Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['APPDATA'] ??
      Directory.current.path;
  return '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}downloads';
}

/// Harness 智能体工作台：开发智能体为主入口，OCR 为辅助能力。
class LocalModelsTab extends StatefulWidget {
  const LocalModelsTab({
    super.key,
    this.directory = '',
    this.toolDownloadDirectory = '',
    this.rustDeskExecutable = '',
    this.rustDeskWebClientUrl = '',
    this.initialImportPath,
    this.initialImagePath,
    this.ocrRunner = runPpOcr,
    this.modelLister = ModelStore.list,
    this.nativeDirectory,
    this.assetLoader = loadBundledModelAsset,
    this.ocrBundleInstaller = BundledModelInstaller.installPpOcrV6Tiny,
    this.screenshotCapture = SystemScreenshotCapture.captureRegion,
    this.initialLargeModelView = 'agent',
    this.onLargeModelViewChanged,
    this.initialHarnessWorkspace = '',
    this.onHarnessWorkspaceChanged,
    this.initialHarnessDebugDirectory = '',
    this.onHarnessDebugDirectoryChanged,
    this.harnessCheckEnvironment = DeepSeekHarnessService.checkEnvironment,
    this.harnessRunAgent = DeepSeekHarnessService.startAgent,
    this.harnessPickDirectory,
    this.harnessCredentialReader,
    this.remoteWorkspaceLauncher,
    this.externalHarnessPrompt = '',
    this.externalHarnessPromptSerial = 0,
  });

  final String directory;
  final String toolDownloadDirectory;
  final String rustDeskExecutable;
  final String rustDeskWebClientUrl;
  final String? initialImportPath;
  final String? initialImagePath;
  final Future<PpOcrResult> Function(PpOcrRequest request) ocrRunner;
  final Future<List<ModelInfo>> Function(String directory) modelLister;
  final String? nativeDirectory;
  final BundledModelAssetLoader assetLoader;
  final Future<List<ModelInfo>> Function(
    String directory,
    BundledModelAssetLoader loadAsset,
    BundledModelInstallProgress onProgress,
  )
  ocrBundleInstaller;
  final ScreenshotCapture screenshotCapture;
  final String initialLargeModelView;
  final Future<void> Function(String view)? onLargeModelViewChanged;
  final String initialHarnessWorkspace;
  final Future<void> Function(String workspace)? onHarnessWorkspaceChanged;
  final String initialHarnessDebugDirectory;
  final Future<void> Function(String directory)? onHarnessDebugDirectoryChanged;
  final HarnessEnvironmentChecker harnessCheckEnvironment;
  final HarnessAgentRunner harnessRunAgent;
  final AgentDirectoryPicker? harnessPickDirectory;
  final AgentCredentialReader? harnessCredentialReader;
  final HarnessRemoteWorkspaceLauncher? remoteWorkspaceLauncher;
  final String externalHarnessPrompt;
  final int externalHarnessPromptSerial;

  @override
  State<LocalModelsTab> createState() => _LocalModelsTabState();
}

class _LocalModelsTabState extends State<LocalModelsTab> {
  late final String _directory = widget.directory.trim().isEmpty
      ? defaultModelDirectory()
      : widget.directory.trim();
  late final String _downloadDirectory =
      widget.toolDownloadDirectory.trim().isEmpty
      ? defaultToolDownloadDirectory()
      : widget.toolDownloadDirectory.trim();
  late String _harnessDebugDirectory =
      widget.initialHarnessDebugDirectory.trim().isEmpty
      ? DeepSeekHarnessService.defaultDebugDirectory()
      : widget.initialHarnessDebugDirectory.trim();
  List<ModelInfo> _models = const <ModelInfo>[];
  bool _modelsLoaded = false;
  bool _modelsLoading = false;
  String _message = '';
  String? _wavPath;
  VadInferenceResult? _vadResult;
  bool _runningVad = false;
  late _ModelWorkspace _workspace;
  String? _imagePath;
  PpOcrResult? _ocrResult;
  bool _runningOcr = false;
  bool _capturingScreenshot = false;
  bool _agentOpened = false;
  bool _agentRunning = false;
  bool _autoOcrStarted = false;
  Uint8List? _portablePreview;
  bool _loadingPortablePreview = false;
  bool _portablePreviewAttempted = false;
  String? _portablePreviewError;
  String? _downloadingId;
  double? _downloadProgress;
  HttpClient? _downloadClient;

  @override
  void initState() {
    super.initState();
    _imagePath = widget.initialImagePath;
    _workspace =
        widget.initialImagePath != null || widget.initialImportPath != null
        ? _ModelWorkspace.ocr
        : widget.initialLargeModelView == 'ocr'
        ? _ModelWorkspace.ocr
        : _ModelWorkspace.agent;
    _agentOpened = _workspace == _ModelWorkspace.agent;
    if (!Platform.isAndroid && !Platform.isIOS) {
      unawaited(_initializeHarnessDebugDirectory());
    }
    if (_workspace == _ModelWorkspace.ocr) unawaited(_refresh());
    final String? path = widget.initialImportPath;
    if (path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _importPath(path));
    }
  }

  @override
  void didUpdateWidget(covariant LocalModelsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalHarnessPromptSerial !=
        oldWidget.externalHarnessPromptSerial) {
      setState(() {
        _workspace = _ModelWorkspace.agent;
        _agentOpened = true;
      });
      final Future<void>? update = widget.onLargeModelViewChanged?.call(
        'agent',
      );
      if (update != null) unawaited(update);
    }
  }

  Future<void> _initializeHarnessDebugDirectory() async {
    try {
      await DeepSeekHarnessService.prepareDebugDirectory(
        _harnessDebugDirectory,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _message = '默认调试目录不可写，请在 Harness 模型设置中选择其他目录';
      });
    }
  }

  Future<void> _refresh() async {
    if (_modelsLoading) return;
    _modelsLoading = true;
    try {
      final List<ModelInfo> models = await widget.modelLister(_directory);
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelsLoaded = true;
      });
      if (_imagePath != null && !_autoOcrStarted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!_ocrBundleInstalled) await _downloadOcrBundle();
          if (mounted && _ocrBundleInstalled && !_autoOcrStarted) {
            _autoOcrStarted = true;
            await _runOcr();
          }
        });
      }
    } finally {
      _modelsLoading = false;
    }
  }

  bool get _ocrBundleInstalled => ppOcrV6TinyBundle.artifacts.every(
    (CuratedModelArtifact artifact) => _models.any(
      (ModelInfo model) =>
          model.fileName == artifact.fileName &&
          model.integrity == ModelIntegrity.verified,
    ),
  );

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
    final bool retainDownload = model.bundleAssetPath == null;
    final Directory staging = retainDownload
        ? Directory(_downloadDirectory)
        : Directory.systemTemp.createTempSync('vibekits_model');
    await staging.create(recursive: true);
    final File downloaded = File(
      '${staging.path}${Platform.pathSeparator}${model.fileName}.part',
    );
    HttpClient? client;
    setState(() {
      _downloadingId = model.id;
      _downloadProgress = null;
      _message = model.bundleAssetPath == null
          ? '正在下载 ${model.name}…'
          : '正在安装内置 ${model.name}…';
    });
    try {
      if (model.bundleAssetPath != null) {
        final List<int> bundled = await widget.assetLoader(
          model.bundleAssetPath!,
        );
        await downloaded.writeAsBytes(bundled, flush: true);
        if (mounted) setState(() => _downloadProgress = 1);
      } else {
        client = HttpClient();
        _downloadClient = client;
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
      }
      final String digest =
          (await crypto.sha256.bind(downloaded.openRead()).first).toString();
      if (digest != model.sha256) {
        throw const FormatException('模型 SHA-256 校验失败，文件不会安装');
      }
      File installSource = downloaded;
      if (retainDownload) {
        final File retained = File(
          '${staging.path}${Platform.pathSeparator}${model.fileName}',
        );
        if (await retained.exists()) await retained.delete();
        installSource = await downloaded.rename(retained.path);
      }
      final ModelInfo installed = await ModelStore.import(
        installSource.path,
        _directory,
      );
      if (!mounted) return;
      setState(() => _message = '已安装 ${installed.fileName}，校验通过');
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = '模型安装失败：$error');
    } finally {
      client?.close(force: true);
      _downloadClient = null;
      if (!retainDownload && staging.existsSync()) {
        staging.deleteSync(recursive: true);
      } else if (downloaded.existsSync()) {
        downloaded.deleteSync();
      }
      if (mounted) {
        setState(() {
          _downloadingId = null;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _downloadOcrBundle() async {
    if (_downloadingId != null) return;
    setState(() {
      _downloadingId = ppOcrV6TinyBundle.id;
      _downloadProgress = 0;
      _message = '正在安装 PP-OCRv6 tiny（3 个经过校验的文件）…';
    });
    try {
      await widget.ocrBundleInstaller(_directory, widget.assetLoader, (
        double progress,
      ) {
        if (mounted) setState(() => _downloadProgress = progress);
      });
      if (!mounted) return;
      setState(() => _message = 'PP-OCRv6 tiny 已安装并完成逐文件校验');
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = 'OCR 模型安装失败：$error');
    } finally {
      _downloadClient = null;
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

  Future<void> _chooseImage() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: '图片',
          extensions: <String>[
            'png',
            'jpg',
            'jpeg',
            'webp',
            'bmp',
            'gif',
            'tif',
            'tiff',
            'ico',
            'cur',
            'tga',
            'psd',
            'exr',
            'pnm',
            'pbm',
            'pgm',
            'ppm',
            'pvr',
          ],
        ),
      ],
    );
    if (file == null || !mounted) return;
    setState(() {
      _imagePath = file.path;
      _ocrResult = null;
      _autoOcrStarted = true;
      _portablePreview = null;
      _portablePreviewAttempted = false;
      _portablePreviewError = null;
    });
    if (!_ocrBundleInstalled) await _downloadOcrBundle();
    if (_ocrBundleInstalled) await _runOcr();
  }

  Future<void> _captureScreenshot() async {
    if (_capturingScreenshot || _runningOcr) return;
    setState(() {
      _capturingScreenshot = true;
      _message = '框选屏幕区域，完成后会立即识别…';
    });
    try {
      final HarnessDebugPaths debug =
          await DeepSeekHarnessService.prepareDebugDirectory(
            _harnessDebugDirectory,
          );
      final String? path = await widget.screenshotCapture(
        debug.screenshots.path,
      );
      if (!mounted) return;
      if (path == null) {
        setState(() => _message = '已取消截图');
        return;
      }
      setState(() {
        _imagePath = path;
        _ocrResult = null;
        _autoOcrStarted = true;
        _portablePreview = null;
        _portablePreviewAttempted = false;
        _portablePreviewError = null;
      });
      if (_ocrBundleInstalled) {
        await _runOcr();
      } else {
        await _downloadOcrBundle();
        if (_ocrBundleInstalled) await _runOcr();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '截图失败：$error');
    } finally {
      if (mounted) setState(() => _capturingScreenshot = false);
    }
  }

  Future<Map<String, Object?>> _captureScreenshotForHarness() async {
    if (_capturingScreenshot || _runningOcr) {
      throw StateError('截图 OCR 正在运行，请等待当前任务完成');
    }
    setState(() {
      _workspace = _ModelWorkspace.ocr;
      _ocrResult = null;
      _imagePath = null;
    });
    await widget.onLargeModelViewChanged?.call('ocr');
    await _captureScreenshot();
    final PpOcrResult? result = _ocrResult;
    final String? imagePath = _imagePath;
    if (result == null || imagePath == null) {
      throw StateError(_message.isEmpty ? '截图 OCR 未完成' : _message);
    }
    return <String, Object?>{
      'imagePath': imagePath,
      'text': result.text,
      'lineCount': result.lines.length,
      'width': result.imageWidth,
      'height': result.imageHeight,
      'elapsedMs': result.elapsed.inMilliseconds,
      'runtime': result.runtime,
      'lines': <Map<String, Object?>>[
        for (final OcrTextLine line in result.lines)
          <String, Object?>{
            'text': line.text,
            'confidence': line.confidence,
            'bounds': <String, int>{
              'left': line.bounds.left,
              'top': line.bounds.top,
              'right': line.bounds.right,
              'bottom': line.bounds.bottom,
            },
          },
      ],
    };
  }

  Future<void> _runOcr() async {
    final String? imagePath = _imagePath;
    if (!_ocrBundleInstalled || imagePath == null || _runningOcr) return;
    setState(() {
      _runningOcr = true;
      _ocrResult = null;
      _message = '正在本机 CPU 识别文字，图片不会上传…';
    });
    try {
      final String separator = Platform.pathSeparator;
      final PpOcrResult result = await widget.ocrRunner(
        PpOcrRequest(
          imagePath: imagePath,
          detectionModelPath: '$_directory${separator}ppocrv6_tiny_det.onnx',
          recognitionModelPath: '$_directory${separator}ppocrv6_tiny_rec.onnx',
          recognitionConfigPath: '$_directory${separator}ppocrv6_tiny_rec.yml',
          nativeDirectory:
              widget.nativeDirectory ??
              File(Platform.resolvedExecutable).parent.path,
        ),
      );
      if (!mounted) return;
      setState(() {
        _ocrResult = result;
        _message = result.lines.isEmpty
            ? '识别完成，没有发现清晰文字'
            : '识别完成：${result.lines.length} 行文字';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '文字识别失败：$error');
    } finally {
      if (mounted) setState(() => _runningOcr = false);
    }
  }

  Future<void> _copyOcrText() async {
    final String text = _ocrResult?.text ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _message = '识别文字已复制');
  }

  void _loadPortablePreview() {
    final String? path = _imagePath;
    if (path == null || _portablePreviewAttempted) return;
    _portablePreviewAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _loadingPortablePreview = true);
      try {
        final Uint8List bytes = await buildPortableImagePreview(path);
        if (mounted && _imagePath == path) {
          setState(() {
            _portablePreview = bytes;
            _portablePreviewError = null;
          });
        }
      } catch (error) {
        if (mounted && _imagePath == path) {
          setState(() {
            _portablePreviewError = '$error';
            _message = '图片预览失败：$error';
          });
        }
      } finally {
        if (mounted) setState(() => _loadingPortablePreview = false);
      }
    });
  }

  Future<void> _saveOcrText() async {
    final String text = _ocrResult?.text ?? '';
    if (text.isEmpty) return;
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: '${_imageBaseName()}.txt',
    );
    if (location == null) return;
    await File(location.path).writeAsString(text, flush: true);
    if (mounted) setState(() => _message = '识别文字已保存到 ${location.path}');
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

  Future<void> _showModelManager() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('本地模型管理'),
        content: SizedBox(width: 620, height: 500, child: _buildModelPanel()),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('导入模型'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
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
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              SegmentedButton<_ModelWorkspace>(
                key: const Key('model-workspace-tabs'),
                showSelectedIcon: false,
                segments: <ButtonSegment<_ModelWorkspace>>[
                  ButtonSegment<_ModelWorkspace>(
                    value: _ModelWorkspace.agent,
                    icon: const Icon(Icons.terminal, size: 17),
                    label: Badge(
                      isLabelVisible: _agentRunning,
                      smallSize: 7,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 3),
                        child: Text('Harness 智能体'),
                      ),
                    ),
                  ),
                  const ButtonSegment<_ModelWorkspace>(
                    value: _ModelWorkspace.ocr,
                    icon: Icon(Icons.document_scanner_outlined, size: 17),
                    label: Text('截图 OCR'),
                  ),
                ],
                selected: <_ModelWorkspace>{_workspace},
                onSelectionChanged: (Set<_ModelWorkspace> selected) {
                  setState(() {
                    _workspace = selected.first;
                    if (_workspace == _ModelWorkspace.agent) {
                      _agentOpened = true;
                    }
                  });
                  widget.onLargeModelViewChanged?.call(
                    _workspace == _ModelWorkspace.agent ? 'agent' : 'ocr',
                  );
                  if (_workspace == _ModelWorkspace.ocr && !_modelsLoaded) {
                    unawaited(_refresh());
                  }
                },
              ),
              const Spacer(),
              if (_workspace == _ModelWorkspace.ocr)
                TextButton(
                  key: const Key('ocr-install'),
                  onPressed: _ocrBundleInstalled || _downloadingId != null
                      ? null
                      : _downloadOcrBundle,
                  child: Text(_ocrBundleInstalled ? '已安装' : '安装模型'),
                ),
              if (_workspace == _ModelWorkspace.ocr)
                IconButton(
                  tooltip: '管理本地模型',
                  onPressed: _showModelManager,
                  icon: const Icon(Icons.settings_outlined, size: 19),
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
          child: IndexedStack(
            index: _workspace == _ModelWorkspace.ocr ? 0 : 1,
            children: <Widget>[
              _buildOcrWorkspace(),
              if (_agentOpened)
                if (Platform.isWindows &&
                    Platform.environment['FLUTTER_TEST'] != 'true')
                  OfficialHarnessWorkspace(
                    initialWorkspace: widget.initialHarnessWorkspace,
                    initialDebugDirectory: _harnessDebugDirectory,
                    onRunningChanged: (bool running) {
                      if (mounted) setState(() => _agentRunning = running);
                    },
                    credentialReader: widget.harnessCredentialReader,
                    remoteWorkspaceLauncher: widget.remoteWorkspaceLauncher,
                    screenshotOcrRunner: _captureScreenshotForHarness,
                    externalPrompt: widget.externalHarnessPrompt,
                    externalPromptSerial: widget.externalHarnessPromptSerial,
                    rustDeskExecutable: widget.rustDeskExecutable,
                    rustDeskWebClientUrl: widget.rustDeskWebClientUrl,
                  )
                else
                  DeepSeekAgentWorkspace(
                    initialWorkspace: widget.initialHarnessWorkspace,
                    onWorkspaceChanged: widget.onHarnessWorkspaceChanged,
                    initialDebugDirectory: _harnessDebugDirectory,
                    onDebugDirectoryChanged: (String directory) async {
                      if (mounted) {
                        setState(() => _harnessDebugDirectory = directory);
                      }
                      await widget.onHarnessDebugDirectoryChanged?.call(
                        directory,
                      );
                    },
                    onRunningChanged: (bool running) {
                      if (mounted) setState(() => _agentRunning = running);
                    },
                    checkEnvironment: widget.harnessCheckEnvironment,
                    runAgent: widget.harnessRunAgent,
                    pickDirectory: widget.harnessPickDirectory,
                    credentialReader: widget.harnessCredentialReader,
                    externalPrompt: widget.externalHarnessPrompt,
                    externalPromptSerial: widget.externalHarnessPromptSerial,
                  )
              else
                const SizedBox.shrink(),
            ],
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
          height: 190,
          child: ListView.builder(
            itemCount: curatedModels.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) return _buildOcrBundleTile();
              final CuratedModel model = curatedModels[index - 1];
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

  Widget _buildOcrBundleTile() {
    final bool downloading = _downloadingId == ppOcrV6TinyBundle.id;
    return ListTile(
      dense: true,
      title: Text(ppOcrV6TinyBundle.name, style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        '${_formatSize(ppOcrV6TinyBundle.downloadBytes)} · '
        '${ppOcrV6TinyBundle.license} · 多语言 OCR',
        style: TextStyle(fontSize: 10, color: context.vibe.muted),
      ),
      trailing: downloading
          ? SizedBox(
              width: 86,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: LinearProgressIndicator(value: _downloadProgress),
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
              key: const Key('ocr-install'),
              onPressed: _ocrBundleInstalled || _downloadingId != null
                  ? null
                  : _downloadOcrBundle,
              child: Text(_ocrBundleInstalled ? '已安装' : '安装'),
            ),
    );
  }

  // VAD 运行时仍保留给已安装用户，入口将在统一音频工具落地后迁入。
  // ignore: unused_element
  Widget _buildWorkspace() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_ModelWorkspace>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<_ModelWorkspace>>[
                ButtonSegment<_ModelWorkspace>(
                  value: _ModelWorkspace.ocr,
                  icon: Icon(Icons.document_scanner_outlined, size: 17),
                  label: Text('文字识别'),
                ),
                ButtonSegment<_ModelWorkspace>(
                  value: _ModelWorkspace.vad,
                  icon: Icon(Icons.graphic_eq, size: 17),
                  label: Text('语音片段检测'),
                ),
              ],
              selected: <_ModelWorkspace>{_workspace},
              onSelectionChanged: (Set<_ModelWorkspace> selected) {
                setState(() => _workspace = selected.first);
              },
            ),
          ),
        ),
        Expanded(
          child: _workspace == _ModelWorkspace.ocr
              ? _buildOcrWorkspace()
              : _buildVadWorkspace(),
        ),
      ],
    );
  }

  Widget _buildOcrWorkspace() {
    final String imageName = _imagePath == null ? '尚未选择图片' : _imageBaseName();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.document_scanner_outlined, size: 21),
              const SizedBox(width: 8),
              const Text(
                '图片文字识别',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '本机 CPU · 不上传',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: context.vibe.panelRaised,
                      border: Border.all(color: context.vibe.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _imagePath == null
                        ? Center(
                            child: Text(
                              '拖入图片即可自动预览并识别',
                              style: TextStyle(color: context.vibe.muted),
                            ),
                          )
                        : _portablePreview != null
                        ? Image.memory(
                            _portablePreview!,
                            key: const Key('ocr-portable-image-preview'),
                            fit: BoxFit.contain,
                          )
                        : Image.file(
                            File(_imagePath!),
                            key: const Key('ocr-image-preview'),
                            fit: BoxFit.contain,
                            errorBuilder:
                                (
                                  BuildContext context,
                                  Object error,
                                  StackTrace? stackTrace,
                                ) {
                                  _loadPortablePreview();
                                  return Center(
                                    child: _loadingPortablePreview
                                        ? const CircularProgressIndicator()
                                        : Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Text(
                                              _portablePreviewError == null
                                                  ? '正在转换此图片的预览…'
                                                  : '当前系统与内置解码器无法安全预览此格式。\n'
                                                        '仍可保留文件并使用 Hex/哈希工具检查。\n\n'
                                                        '$_portablePreviewError',
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                  );
                                },
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.vibe.panelRaised,
                      border: Border.all(color: context.vibe.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _runningOcr
                        ? const Center(child: CircularProgressIndicator())
                        : _ocrResult == null
                        ? Center(
                            child: Text(
                              _ocrBundleInstalled
                                  ? '识别结果会显示在这里'
                                  : '首次识别会自动准备内置 PP-OCRv6 tiny',
                              style: TextStyle(color: context.vibe.muted),
                            ),
                          )
                        : SelectableText(
                            _ocrResult!.text.isEmpty
                                ? '没有识别到文字'
                                : _ocrResult!.text,
                            key: const Key('ocr-result'),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  imageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.vibe.muted),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('ocr-screenshot'),
                onPressed: _capturingScreenshot || _runningOcr
                    ? null
                    : _captureScreenshot,
                icon: const Icon(Icons.crop_free, size: 18),
                label: Text(_capturingScreenshot ? '等待截图…' : '截图识别'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('ocr-pick-image'),
                onPressed: _runningOcr ? null : _chooseImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('选择图片'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('ocr-run'),
                onPressed:
                    !_ocrBundleInstalled || _imagePath == null || _runningOcr
                    ? null
                    : _runOcr,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(_runningOcr ? '识别中…' : '识别文字'),
              ),
              if ((_ocrResult?.text.isNotEmpty ?? false)) ...<Widget>[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '复制文字',
                  onPressed: _copyOcrText,
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: '保存为 TXT',
                  onPressed: _saveOcrText,
                  icon: const Icon(Icons.save_alt_outlined),
                ),
              ],
            ],
          ),
          if (_ocrResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${_ocrResult!.lines.length} 行 · '
                '${_ocrResult!.elapsed.inMilliseconds}ms · '
                '${_ocrResult!.runtime}',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ),
        ],
      ),
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

  String _imageBaseName() {
    final String name = (_imagePath ?? 'ocr')
        .replaceAll('\\', '/')
        .split('/')
        .last;
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
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

enum _ModelWorkspace { ocr, agent, vad }
