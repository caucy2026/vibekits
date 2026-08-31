import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';
import 'package:vibekits/features/local_models/presentation/mcp_exposure_consent_dialog.dart';

void main() {
  testWidgets('从关闭切到打开前展示工具清单和明确风险并允许取消', (WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => FilledButton(
            onPressed: () async {
              result = await showMcpExposureConsentDialog(
                context: context,
                deviceName: 'VibeKits@test-ABC',
                certificateFingerprint: 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                tools: const <McpToolInterface>[
                  McpToolInterface(
                    name: 'vibekits.files.search',
                    title: '搜索文件',
                    description: '读取文件名，不修改文件。',
                    inputSchema: <String, Object?>{'type': 'object'},
                  ),
                ],
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('允许打开 MCP 权限？'), findsOneWidget);
    expect(find.textContaining('发送文件'), findsOneWidget);
    expect(find.text('vibekits.files.search'), findsOneWidget);
    expect(find.text('允许并打开 MCP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mcp-exposure-deny')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
