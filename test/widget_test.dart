import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/app/app.dart';
import 'package:vibekits/app/app_settings.dart';
import 'package:vibekits/app/dropped_file_router.dart';
import 'package:vibekits/app/main_shell.dart';
import 'package:vibekits/features/documents/domain/format_router.dart';
import 'package:vibekits/features/documents/presentation/documents_tab.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/local_models/domain/model_store.dart';
import 'package:vibekits/features/local_models/domain/pp_ocr_v6.dart';
import 'package:vibekits/features/local_models/presentation/local_models_tab.dart';

void main() {
  testWidgets('启动后显示五个 Tab 与第一个页面', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    for (final String title in <String>[
      'Harness（智能体）',
      '解压缩',
      '系统清理',
      '文档阅读',
      '开发工具',
    ]) {
      // 激活 Tab 的标题会同时出现在标签栏和页面标题中，因此至少存在一个。
      expect(find.text(title), findsWidgets);
    }

    // 默认展示 Harness 智能体工作台。
    expect(find.text('Harness 智能体'), findsOneWidget);
    expect(find.byKey(const Key('agent-composer')), findsOneWidget);
    // 其余页面处于离屏状态。
    expect(find.text('开始扫描'), findsNothing);
  });

  testWidgets('点击 Tab 切换页面', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    await tester.tap(find.text('系统清理'));
    await tester.pumpAndSettle();

    expect(find.text('开始扫描'), findsOneWidget);
    expect(find.text('打开压缩包'), findsNothing);
  });

  testWidgets('启动恢复上次一级工作区', (WidgetTester tester) async {
    final AppSettingsController settings = AppSettingsController();
    settings.value = const AppSettings(
      lastTab: 3,
      lastWorkspaceId: 'documents',
    );
    addTearDown(settings.dispose);

    await tester.pumpWidget(VibekitsApp(settingsController: settings));
    await tester.pumpAndSettle();

    expect(find.text('文档阅读'), findsWidgets);
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byKey(const Key('agent-composer')), findsNothing);
  });

  testWidgets('启动恢复 Harness 内部 OCR 子页', (WidgetTester tester) async {
    final AppSettingsController settings = AppSettingsController();
    settings.value = const AppSettings(
      lastWorkspaceId: 'large-model',
      lastLargeModelView: 'ocr',
    );
    addTearDown(settings.dispose);

    await tester.pumpWidget(VibekitsApp(settingsController: settings));
    await tester.pumpAndSettle();

    expect(find.text('Harness（智能体）'), findsWidgets);
    expect(find.byKey(const Key('ocr-screenshot')), findsOneWidget);
    expect(find.byKey(const Key('agent-composer')), findsNothing);
  });

  testWidgets('Ctrl+数字键切换 Tab', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    Future<void> pressCtrlWithKey(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await pressCtrlWithKey(LogicalKeyboardKey.digit4);
    expect(find.text('打开文件'), findsOneWidget);
    await pressCtrlWithKey(LogicalKeyboardKey.keyF);
    expect(find.byType(TextField), findsOneWidget);

    await pressCtrlWithKey(LogicalKeyboardKey.digit5);
    expect(
      find.byKey(const Key('programmer-calculator-input')),
      findsOneWidget,
    );

    await pressCtrlWithKey(LogicalKeyboardKey.digit2);
    expect(find.text('打开压缩包'), findsOneWidget);
  });

  testWidgets('Ctrl+, 打开设置对话框', (WidgetTester tester) async {
    await tester.pumpWidget(const VibekitsApp());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('宽窗口使用侧边工作台导航', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VibekitsApp());

    expect(find.byKey(const Key('primary-navigation')), findsOneWidget);
    expect(find.byKey(const Key('primary-navigation-compact')), findsNothing);
    expect(find.text('LOCAL TOOLKIT'), findsOneWidget);
    expect(find.textContaining('v1.9.0-dev.17+27'), findsWidgets);
    expect(find.text('任务 0'), findsNothing);
  });

  testWidgets('1024 宽窗口自动使用紧凑顶部导航', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 700);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VibekitsApp());

    expect(find.byKey(const Key('primary-navigation')), findsNothing);
    expect(find.byKey(const Key('primary-navigation-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最小窗口逐项切换五个工作区不溢出', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const VibekitsApp());

    for (final String title in <String>[
      'Harness（智能体）',
      '系统清理',
      '文档阅读',
      '开发工具',
      '解压缩',
    ]) {
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$title 在最小窗口应可操作');
    }
  });

  testWidgets('深色主题可渲染完整主界面', (WidgetTester tester) async {
    final AppSettingsController settings = AppSettingsController();
    settings.value = const AppSettings(themeMode: ThemeMode.dark);
    addTearDown(settings.dispose);

    await tester.pumpWidget(VibekitsApp(settingsController: settings));

    final BuildContext context = tester.element(find.byType(MainShell));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(find.text('系统就绪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统打开文档时自动路由到文档模块', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_open');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File source = File(
      '${sandbox.path}${Platform.pathSeparator}startup.dart',
    )..writeAsStringSync('void startupRouteWorks() {}');

    await tester.pumpWidget(VibekitsApp(initialFilePath: source.path));
    await tester.pumpAndSettle();

    expect(find.text('文档阅读'), findsWidgets);
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      source.path,
    );
    expect(find.text('打开压缩包'), findsNothing);
  });

  testWidgets('Markdown 默认渲染可读预览且可切换源码', (WidgetTester tester) async {
    final Uint8List source = Uint8List.fromList(
      utf8.encode('# 使用说明\n\n拖入文件后自动处理。\n\n```dart\nvoid main() {}\n```'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsTab(
            initialPath: 'readme.md',
            bytesReader: (_) async => source,
          ),
        ),
      ),
    );
    for (
      int attempt = 0;
      attempt < 100 &&
          find.byKey(const Key('markdown-preview')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    final List<String> loadErrors = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text widget) => widget.data)
        .whereType<String>()
        .where((String value) => value.contains('打开失败'))
        .toList();
    expect(loadErrors, isEmpty);
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.text('使用说明'), findsOneWidget);
    expect(find.text('拖入文件后自动处理。'), findsOneWidget);

    await tester.tap(find.text('源码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markdown-preview')), findsNothing);
    expect(find.textContaining('# 使用说明'), findsOneWidget);
  });

  testWidgets('拖入文件后自动选择文档工具并立即打开', (WidgetTester tester) async {
    final StreamController<List<String>> drops =
        StreamController<List<String>>.broadcast();
    addTearDown(() async {
      await drops.close();
    });
    final File source = File('pubspec.yaml').absolute;

    await tester.pumpWidget(
      VibekitsApp(
        droppedFiles: drops.stream,
        dropClassifier: (String path) async => DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.document,
          detail: '按扩展名交给文档阅读处理',
        ),
      ),
    );
    drops.add(<String>[source.path]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('文档阅读'), findsWidgets);
    expect(find.textContaining('按扩展名交给文档阅读处理：pubspec.yaml'), findsOneWidget);
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      source.path,
    );
    final Key? firstRequestKey = tester
        .widget<DocumentsTab>(find.byType(DocumentsTab))
        .key;
    drops.add(<String>[source.path]);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).key,
      isNot(firstRequestKey),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('系统传入多个文件时逐项路由而不是只处理第一个', (WidgetTester tester) async {
    final List<String> paths = <String>['first.md', 'second.unknown'];
    await tester.pumpWidget(
      VibekitsApp(
        initialFilePaths: paths,
        dropClassifier: (String path) async => DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.document,
          detail: '已自动识别',
          documentMode: path.endsWith('.md')
              ? DocViewMode.markdown
              : DocViewMode.text,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drop-batch-button')), findsOneWidget);
    expect(find.textContaining('已逐项识别 2 个项目'), findsOneWidget);
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      'first.md',
    );
  });

  testWidgets('拖入 ONNX 自动切换模型仓库并提交导入', (WidgetTester tester) async {
    final StreamController<List<String>> drops =
        StreamController<List<String>>.broadcast();
    addTearDown(drops.close);
    const String modelPath = 'D:\\models\\tiny.onnx';
    await tester.pumpWidget(
      VibekitsApp(
        droppedFiles: drops.stream,
        dropClassifier: (String path) async => const DroppedFileRoute(
          path: modelPath,
          kind: DroppedFileRouteKind.model,
          detail: '已识别为本地模型',
        ),
      ),
    );
    drops.add(const <String>[modelPath]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Harness（智能体）'), findsWidgets);
    expect(
      tester
          .widget<LocalModelsTab>(find.byType(LocalModelsTab))
          .initialImportPath,
      modelPath,
    );
    expect(find.textContaining('已识别为本地模型'), findsOneWidget);
  });

  testWidgets('多文件拖入逐项识别且未知文件自动选择查看方式', (WidgetTester tester) async {
    final StreamController<List<String>> drops =
        StreamController<List<String>>.broadcast();
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_batch',
    );
    final File text = File('${sandbox.path}/notes.unknown')
      ..writeAsStringSync('automatic text route');
    final File binary = File('${sandbox.path}/payload.unknown')
      ..writeAsBytesSync(<int>[0x00, 0x01, 0x02, 0xff]);
    addTearDown(() async {
      await drops.close();
      sandbox.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      VibekitsApp(
        droppedFiles: drops.stream,
        dropClassifier: (String path) async {
          if (path == sandbox.path) {
            return DroppedFileRoute(
              path: path,
              kind: DroppedFileRouteKind.rejected,
              detail: '这是文件夹；请在对应工具中选择该目录',
            );
          }
          return DroppedFileRoute(
            path: path,
            kind: DroppedFileRouteKind.document,
            detail: path == text.path
                ? '未知扩展名，已按内容自动选择文本查看'
                : '未知扩展名，已按内容自动选择 Hex 查看',
            documentMode: path == text.path
                ? DocViewMode.text
                : DocViewMode.hex,
          );
        },
      ),
    );
    drops.add(<String>[text.path, binary.path, sandbox.path]);
    for (
      int attempt = 0;
      attempt < 100 &&
          find.byKey(const Key('drop-batch-button')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.byKey(const Key('drop-batch-button')), findsOneWidget);
    expect(find.textContaining('已逐项识别 3 个项目'), findsOneWidget);
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      text.path,
    );

    await tester.tap(find.byKey(const Key('drop-batch-button')));
    await tester.pumpAndSettle();
    expect(find.text('本次拖入 · 3 项'), findsOneWidget);
    expect(find.text('notes.unknown'), findsOneWidget);
    expect(find.text('payload.unknown'), findsOneWidget);
    expect(find.textContaining('这是文件夹'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'payload.unknown'));
    await tester.pump();
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialPath,
      binary.path,
    );
    expect(
      tester.widget<DocumentsTab>(find.byType(DocumentsTab)).initialMode,
      DocViewMode.hex,
    );
  });

  testWidgets('Harness 页只保留智能体与截图 OCR', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_models_ui',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: LocalModelsTab(
          directory: sandbox.path,
          harnessCheckEnvironment: () async => const HarnessEnvironmentReport(
            ready: false,
            nodeVersion: null,
            npxVersion: null,
            message: '测试环境未配置 Node.js',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('截图 OCR'), findsOneWidget);
    expect(find.text('Harness 智能体'), findsOneWidget);
    expect(find.text('精选小模型'), findsNothing);
    expect(find.text('语音片段检测'), findsNothing);
    expect(find.byKey(const Key('agent-composer')), findsOneWidget);
    await tester.tap(find.text('截图 OCR'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ocr-screenshot')), findsOneWidget);
    expect(find.byKey(const Key('ocr-pick-image')), findsOneWidget);
    expect(find.byKey(const Key('ocr-run')), findsOneWidget);
    await tester.tap(find.text('Harness 智能体'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-composer')), findsOneWidget);
    expect(find.byKey(const Key('agent-pick-workspace')), findsOneWidget);
  });

  testWidgets('智能体切换到 OCR 再返回时保留当前会话', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_agent_keepalive',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final _PersistentAgentHandle handle = _PersistentAgentHandle();
    addTearDown(handle.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LocalModelsTab(
          directory: sandbox.path,
          initialHarnessWorkspace: sandbox.path,
          modelLister: (_) async => const <ModelInfo>[],
          harnessCheckEnvironment: () async => const HarnessEnvironmentReport(
            ready: true,
            nodeVersion: 'v24.18.0',
            npxVersion: '11.16.0',
            message: '运行环境已就绪',
          ),
          harnessRunAgent: (_) async => handle,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harness 智能体'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-composer')), '审查项目');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    handle.add('会话结果会保留');
    await tester.pump();
    await handle.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图 OCR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harness 智能体'));
    await tester.pumpAndSettle();
    expect(find.text('会话结果会保留'), findsOneWidget);
  });

  testWidgets('拖入图片直接进入本地 OCR 工作区并显示预览', (WidgetTester tester) async {
    final StreamController<List<String>> drops =
        StreamController<List<String>>.broadcast();
    addTearDown(drops.close);
    final String imagePath = File(
      'test_data${Platform.pathSeparator}images${Platform.pathSeparator}'
      'general_ocr_002.png',
    ).absolute.path;
    await tester.pumpWidget(
      VibekitsApp(
        droppedFiles: drops.stream,
        dropClassifier: (String path) async => DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.image,
          detail: '已识别为图片，自动预览并准备文字识别',
        ),
      ),
    );
    drops.add(<String>[imagePath]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Harness（智能体）'), findsWidgets);
    expect(find.byKey(const Key('ocr-image-preview')), findsOneWidget);
    expect(
      tester
          .widget<LocalModelsTab>(find.byType(LocalModelsTab))
          .initialImagePath,
      imagePath,
    );
  });

  testWidgets('拖入图片在模型已安装时自动识别并显示可复制结果', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_ocr_ui');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String imagePath = File(
      'test_data${Platform.pathSeparator}images${Platform.pathSeparator}'
      'general_ocr_002.png',
    ).absolute.path;
    int requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalModelsTab(
          directory: sandbox.path,
          initialImagePath: imagePath,
          modelLister: (_) async => const <ModelInfo>[
            ModelInfo(
              fileName: 'ppocrv6_tiny_det.onnx',
              capability: 'OCR',
              size: 1,
              sha256: 'det',
              integrity: ModelIntegrity.verified,
            ),
            ModelInfo(
              fileName: 'ppocrv6_tiny_rec.onnx',
              capability: 'OCR',
              size: 1,
              sha256: 'rec',
              integrity: ModelIntegrity.verified,
            ),
            ModelInfo(
              fileName: 'ppocrv6_tiny_rec.yml',
              capability: 'OCR',
              size: 1,
              sha256: 'config',
              integrity: ModelIntegrity.verified,
            ),
          ],
          ocrRunner: (PpOcrRequest request) async {
            requests++;
            expect(request.imagePath, imagePath);
            return const PpOcrResult(
              lines: <OcrTextLine>[
                OcrTextLine(
                  text: '自动识别成功',
                  confidence: 0.99,
                  bounds: OcrRect(left: 1, top: 2, right: 20, bottom: 10),
                ),
              ],
              imageWidth: 100,
              imageHeight: 50,
              elapsed: Duration(milliseconds: 8),
              runtime: 'test runtime',
            );
          },
        ),
      ),
    );
    for (
      int attempt = 0;
      attempt < 100 && find.text('自动识别成功').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(requests, 1);
    expect(find.text('自动识别成功'), findsOneWidget);
    expect(find.byTooltip('复制文字'), findsOneWidget);
    expect(find.textContaining('8ms'), findsOneWidget);
  });

  testWidgets('截图完成后自动调用 OCR，无需再次点击识别', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_screenshot_ocr',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final String imagePath = File(
      'test_data${Platform.pathSeparator}images${Platform.pathSeparator}'
      'general_ocr_002.png',
    ).absolute.path;
    int requests = 0;
    String? screenshotDirectory;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalModelsTab(
          directory: sandbox.path,
          initialHarnessDebugDirectory:
              '${sandbox.path}${Platform.pathSeparator}debug',
          screenshotCapture: (String directory) async {
            screenshotDirectory = directory;
            return imagePath;
          },
          modelLister: (_) async => const <ModelInfo>[
            ModelInfo(
              fileName: 'ppocrv6_tiny_det.onnx',
              capability: 'OCR',
              size: 1,
              sha256: 'det',
              integrity: ModelIntegrity.verified,
            ),
            ModelInfo(
              fileName: 'ppocrv6_tiny_rec.onnx',
              capability: 'OCR',
              size: 1,
              sha256: 'rec',
              integrity: ModelIntegrity.verified,
            ),
            ModelInfo(
              fileName: 'ppocrv6_tiny_rec.yml',
              capability: 'OCR',
              size: 1,
              sha256: 'config',
              integrity: ModelIntegrity.verified,
            ),
          ],
          ocrRunner: (PpOcrRequest request) async {
            requests++;
            return const PpOcrResult(
              lines: <OcrTextLine>[
                OcrTextLine(
                  text: '截图自动识别成功',
                  confidence: 0.98,
                  bounds: OcrRect(left: 0, top: 0, right: 30, bottom: 10),
                ),
              ],
              imageWidth: 100,
              imageHeight: 50,
              elapsed: Duration(milliseconds: 5),
              runtime: 'test runtime',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('截图 OCR'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ocr-screenshot')));
    await tester.pumpAndSettle();
    for (int attempt = 0; attempt < 20 && requests == 0; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(
      screenshotDirectory,
      '${sandbox.path}${Platform.pathSeparator}debug'
      '${Platform.pathSeparator}screenshots',
    );
    expect(find.text('截图自动识别成功'), findsOneWidget);
    expect(find.byKey(const Key('ocr-image-preview')), findsOneWidget);
  });
}

class _PersistentAgentHandle implements HarnessAgentHandle {
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exitCode = Completer<int>();
  bool _running = true;

  void add(String value) => _output.add(value);

  Future<void> complete() async {
    if (!_running) return;
    _running = false;
    _exitCode.complete(0);
  }

  Future<void> dispose() => _output.close();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<String> get output => _output.stream;

  @override
  bool get running => _running;

  @override
  Future<void> stop() => complete();
}
