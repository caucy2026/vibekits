import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/app/app_theme.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/local_models/presentation/deepseek_agent_workspace.dart';

void main() {
  testWidgets('Harness 智能体页面截图', (WidgetTester tester) async {
    final GlobalKey repaintBoundaryKey = GlobalKey();
    final Directory outputDir = Directory(
      'docs${Platform.pathSeparator}acceptance${Platform.pathSeparator}screenshots',
    );
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

    await tester.pumpWidget(
      MaterialApp(
        title: 'vibekits snapshot',
        theme: VibekitsTheme.light(),
        home: Scaffold(
          body: RepaintBoundary(
            key: repaintBoundaryKey,
            child: SizedBox(
              width: 1280,
              height: 760,
              child: DeepSeekAgentWorkspace(
                initialWorkspace: Directory.current.path,
                checkEnvironment: () async => const HarnessEnvironmentReport(
                  ready: false,
                  nodeVersion: null,
                  npxVersion: null,
                  baseUrl: 'https://api.deepseek.com',
                  model: 'deepseek-v4-pro',
                  message: '环境未就绪（快照场景）',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(repaintBoundaryKey),
    );
    final ui.Image img = await boundary.toImage(pixelRatio: 1.0);
    final ByteData? bytes = await img.toByteData(
      format: ui.ImageByteFormat.png,
    );
    expect(bytes, isNotNull);

    final File output = File(
      '${outputDir.path}${Platform.pathSeparator}deepseek_workspace_snapshot.png',
    );
    await output.writeAsBytes(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );

    // 方便调用方快速确认截图已产出
    // ignore: avoid_print
    print('SNAPSHOT: ${output.absolute.path}');
    expect(output.existsSync(), isTrue);
  });
}
