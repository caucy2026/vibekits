import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test(
    'Harness edits only its bound workspace with explicit approval',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'vibekits-harness-workspace-',
      );
      addTearDown(() => root.delete(recursive: true));
      final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
        workspaceRoot: root.path,
      );
      int approvals = 0;
      Future<bool> approve(HarnessToolApprovalRequest request) async {
        approvals++;
        expect(request.tool.risk, HarnessToolRisk.writesData);
        return true;
      }

      expect(
        bridge.executableCatalog.map((HarnessToolDefinition item) => item.id),
        containsAll(<String>[
          VibekitsHarnessToolBridge.workspaceListFilesId,
          VibekitsHarnessToolBridge.workspaceReadTextId,
          VibekitsHarnessToolBridge.workspaceWriteTextId,
        ]),
      );

      final HarnessToolCallResult written = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.workspaceWriteTextId,
        arguments: <String, Object?>{
          'path': 'game/index.html',
          'content': '<!doctype html><title>PAD game</title>',
        },
        approve: approve,
      );
      expect(written.ok, isTrue);
      expect(approvals, 1);
      expect(
        await File('${root.path}/game/index.html').readAsString(),
        contains('PAD game'),
      );

      final HarnessToolCallResult listed = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.workspaceListFilesId,
        arguments: const <String, Object?>{'path': '.', 'maxDepth': 3},
        approve: (_) async => false,
      );
      expect(listed.ok, isTrue);
      expect('${listed.data}', contains('game/index.html'));

      final HarnessToolCallResult read = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.workspaceReadTextId,
        arguments: const <String, Object?>{'path': 'game/index.html'},
        approve: (_) async => false,
      );
      expect(read.ok, isTrue);
      expect(read.data?['content'], contains('PAD game'));

      final HarnessToolCallResult refusedOverwrite = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.workspaceWriteTextId,
        arguments: const <String, Object?>{
          'path': 'game/index.html',
          'content': 'changed',
        },
        approve: approve,
      );
      expect(refusedOverwrite.ok, isFalse);

      final HarnessToolCallResult traversal = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.workspaceReadTextId,
        arguments: const <String, Object?>{'path': '../outside.txt'},
        approve: (_) async => false,
      );
      expect(traversal.ok, isFalse);
      expect('${traversal.error}', contains('..'));
    },
  );

  test('workspace file tools are absent without a bound Harness workspace', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Iterable<String> ids = bridge.executableCatalog.map(
      (HarnessToolDefinition item) => item.id,
    );
    expect(
      ids,
      isNot(contains(VibekitsHarnessToolBridge.workspaceListFilesId)),
    );
    expect(ids, isNot(contains(VibekitsHarnessToolBridge.workspaceReadTextId)));
    expect(
      ids,
      isNot(contains(VibekitsHarnessToolBridge.workspaceWriteTextId)),
    );
  });
}
