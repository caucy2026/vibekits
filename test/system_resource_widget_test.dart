import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/system_resource_service.dart';
import 'package:vibekits/features/dev_tools/presentation/system_resource_workspace.dart';

void main() {
  testWidgets('资源诊断先显示界面再异步呈现完整快照', (WidgetTester tester) async {
    final SystemResourceSnapshot fixture =
        SystemResourceService.parseWindowsJson(<String, Object?>{
          'target': 'TEST-PC',
          'cpuPercent': 25,
          'logicalProcessors': 8,
          'memoryTotalBytes': 8 * 1024 * 1024 * 1024,
          'memoryAvailableBytes': 4 * 1024 * 1024 * 1024,
          'gpuNames': <String>['Fixture GPU'],
          'gpuPercent': 30,
          'storage': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'C:',
              'totalBytes': 1000000000,
              'freeBytes': 500000000,
            },
          ],
          'processes': <Map<String, Object?>>[
            <String, Object?>{
              'pid': 7,
              'name': 'fixture.exe',
              'cpuPercent': 12,
              'memoryBytes': 1000000,
            },
          ],
        });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SystemResourceWorkspace(
            inspector: (String? serial) async => fixture,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('system-resource-refresh')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST-PC'), findsOneWidget);
    expect(find.text('Fixture GPU'), findsOneWidget);
  });
}
