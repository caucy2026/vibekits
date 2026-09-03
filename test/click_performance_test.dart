import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/app/app.dart';
import 'package:vibekits/app/app_settings.dart';
import 'package:vibekits/app/dropped_file_router.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/serial_port_service.dart';
import 'package:vibekits/features/dev_tools/domain/system_resource_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';
import 'package:vibekits/features/documents/presentation/documents_tab.dart';

void main() {
  // Debug widget tests include JIT compilation and host load. Keep a generous
  // regression ceiling here; release-profile latency is reported separately.
  const int debugFirstOpenCeilingMs = 2500;
  const int debugWarmOpenCeilingMs = 1000;

  Future<int> timedTap(
    WidgetTester tester,
    Finder finder, {
    int frames = 2,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    await tester.tap(finder);
    for (int index = 0; index < frames; index++) {
      await tester.pump();
    }
    stopwatch.stop();
    return stopwatch.elapsedMilliseconds;
  }

  void report(String kind, String id, int firstMs, int warmMs) {
    debugPrint(
      'CLICK_PERF|kind=$kind|id=$id|first_ms=$firstMs|warm_ms=$warmMs',
    );
  }

  testWidgets('七个一级工作区和设置窗口点击响应计时', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_click_main_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final AppSettingsController settings = AppSettingsController(
      store: AppSettingsStore(
        file: File('${sandbox.path}${Platform.pathSeparator}settings.json'),
      ),
    );
    settings.value = const AppSettings(
      lastTab: 4,
      lastWorkspaceId: 'dev-tools',
    );
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      VibekitsApp(
        settingsController: settings,
        droppedFiles: const Stream<List<String>>.empty(),
      ),
    );
    await tester.pump();

    const List<String> workspaces = <String>[
      '智能体（Harness）',
      '解压缩',
      '系统清理',
      '文档阅读',
      '开发工具',
      '应用中心',
      '关于我们',
    ];
    final Map<String, int> first = <String, int>{};
    for (final String name in workspaces) {
      first[name] = await timedTap(tester, find.byKey(Key('nav-$name')));
      expect(tester.takeException(), isNull, reason: '$name 首次打开不应异常');
    }
    for (final String name in workspaces) {
      final int warm = await timedTap(tester, find.byKey(Key('nav-$name')));
      report('workspace', name, first[name]!, warm);
      expect(
        first[name]!,
        lessThan(debugFirstOpenCeilingMs),
        reason: '$name 首次响应超时',
      );
      expect(warm, lessThan(debugWarmOpenCeilingMs), reason: '$name 再次响应超时');
      expect(tester.takeException(), isNull, reason: '$name 再次打开不应异常');
    }

    final int settingsMs = await timedTap(
      tester,
      find.byKey(const Key('app-settings-button')),
      frames: 1,
    );
    expect(find.text('设置'), findsOneWidget);
    report('dialog', '设置', settingsMs, settingsMs);
    expect(settingsMs, lessThan(debugWarmOpenCeilingMs));
    await tester.tap(find.text('取消'));
    await tester.pump();
    // Flush the debounced settings write before the test binding verifies
    // that no timers leaked from navigation.
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('全部开发工具入口首次和再次点击响应计时', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            serialPortLister: () async => const <SerialPortDescriptor>[],
            systemResourceInspector: (_) async =>
                SystemResourceService.parseWindowsJson(<String, Object?>{
                  'target': 'PERF-PC',
                  'cpuPercent': 10,
                  'logicalProcessors': 8,
                  'memoryTotalBytes': 8000000000,
                  'memoryAvailableBytes': 4000000000,
                  'gpuNames': <String>['TEST GPU'],
                  'storage': <Object?>[],
                  'processes': <Object?>[],
                }),
            adbLoadSnapshot: () async => const AdbSnapshot(
              installation: AdbInstallation(
                executable: 'bundled-adb',
                version: '1.0.41',
              ),
              devices: <AdbDevice>[],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );

    final Map<String, int> first = <String, int>{};
    for (final ToolSpec tool in devToolRegistry) {
      await tester.enterText(search, tool.name);
      await tester.pump();
      final Finder entry = find.byKey(Key('dev-tool-nav-${tool.id}'));
      expect(entry, findsOneWidget, reason: '${tool.name} 必须存在可点击入口');
      first[tool.id] = await timedTap(tester, entry);
      expect(tester.takeException(), isNull, reason: '${tool.name} 首次打开不应异常');
    }

    for (final ToolSpec tool in devToolRegistry) {
      await tester.enterText(search, tool.name);
      await tester.pump();
      final int warm = await timedTap(
        tester,
        find.byKey(Key('dev-tool-nav-${tool.id}')),
      );
      report('dev_tool', '${tool.id}:${tool.name}', first[tool.id]!, warm);
      expect(
        first[tool.id]!,
        lessThan(debugFirstOpenCeilingMs),
        reason: '${tool.name} 首次响应超时',
      );
      expect(
        warm,
        lessThan(debugWarmOpenCeilingMs),
        reason: '${tool.name} 再次响应超时',
      );
      expect(tester.takeException(), isNull, reason: '${tool.name} 再次打开不应异常');
    }

    final int activityMs = await timedTap(
      tester,
      find.byKey(const Key('current-tool-harness-activity')),
      frames: 1,
    );
    report('dialog', 'Harness调用记录', activityMs, activityMs);
    expect(activityMs, lessThan(debugWarmOpenCeilingMs));
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档窗口和支持格式窗口响应计时', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 760);
    addTearDown(tester.view.reset);
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_click_document_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File markdown = File(
      '${sandbox.path}${Platform.pathSeparator}performance.md',
    );
    markdown.writeAsStringSync('# 性能测试\n\n默认应立即显示 Markdown 预览。');

    final Stopwatch open = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsTab(
            initialPath: markdown.path,
            bytesReader: (_) async => markdown.readAsBytesSync(),
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
      await tester.pump(const Duration(milliseconds: 10));
    }
    open.stop();
    report('file_window', 'Markdown预览', open.elapsedMilliseconds, 0);
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.text('性能测试'), findsOneWidget);
    expect(open.elapsedMilliseconds, lessThan(1500));

    final int formatsMs = await timedTap(
      tester,
      find.byKey(const Key('document-supported-formats')),
      frames: 1,
    );
    report('dialog', '支持格式', formatsMs, formatsMs);
    expect(formatsMs, lessThan(500));
    expect(tester.takeException(), isNull);
  });

  test('拖入/系统打开文件分类耗时', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_route_perf_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Map<String, List<int>> fixtures = <String, List<int>>{
      'readme.md': '# hello'.codeUnits,
      'source.dart': 'void main() {}'.codeUnits,
      'data.json': '{"ok":true}'.codeUnits,
      'raw.bin': <int>[0, 1, 2, 3, 255],
      'archive.zip': <int>[0x50, 0x4b, 0x03, 0x04, 0, 0],
      'image.png': <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      'database.db': <int>[...('SQLite format 3\u0000'.codeUnits), 0, 0],
    };

    for (final MapEntry<String, List<int>> fixture in fixtures.entries) {
      final File file = File(
        '${sandbox.path}${Platform.pathSeparator}${fixture.key}',
      );
      await file.writeAsBytes(fixture.value);
      final Stopwatch stopwatch = Stopwatch()..start();
      final DroppedFileRoute route = await DroppedFileRouter.classify(
        file.path,
      );
      stopwatch.stop();
      debugPrint(
        'CLICK_PERF|kind=file_route|id=${fixture.key}|'
        'first_ms=${stopwatch.elapsedMilliseconds}|warm_ms=0|'
        'destination=${route.kind.name}',
      );
      expect(route.canOpen, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    }
  });
}
