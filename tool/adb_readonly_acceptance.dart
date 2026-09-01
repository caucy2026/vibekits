import 'dart:convert';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: adb_readonly_acceptance.dart <adb> <serial>');
    exitCode = 2;
    return;
  }
  final String adb = File(arguments[0]).absolute.path;
  final String serial = arguments[1].trim();
  final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
    adbExecutable: adb,
  );

  Future<Map<String, Object?>> invoke(
    String toolId,
    Map<String, Object?> toolArguments,
  ) async {
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: toolId,
      arguments: toolArguments,
      approve: (HarnessToolApprovalRequest request) async =>
          request.tool.id == VibekitsHarnessToolBridge.adbShellId,
    );
    if (!result.ok) throw StateError('$toolId failed: ${result.error}');
    return result.data!;
  }

  final Map<String, Object?> capabilities = await invoke(
    VibekitsHarnessToolBridge.capabilityCheckId,
    const <String, Object?>{},
  );
  final Map<String, Object?> properties = await invoke(
    VibekitsHarnessToolBridge.adbShellId,
    <String, Object?>{
      'serial': serial,
      'arguments': const <String>[
        'getprop',
        'ro.product.model',
        'ro.product.manufacturer',
        'ro.board.platform',
        'ro.build.version.release',
        'ro.build.version.sdk',
        'ro.product.cpu.abi',
      ],
    },
  );
  final Map<String, Object?> displays = await invoke(
    VibekitsHarnessToolBridge.adbShellId,
    <String, Object?>{
      'serial': serial,
      'arguments': const <String>['dumpsys', 'display', 'displays'],
    },
  );

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'passed': true,
      'serial': serial,
      'capabilityReady': capabilities['ready'],
      'missingRuntimes': capabilities['missingRuntimes'],
      'expandedGetprop': properties['expandedGetprop'],
      'properties': properties['properties'],
      'displayEvidence': '${displays['stdout'] ?? ''}'
          .split('\n')
          .where(
            (String line) =>
                line.contains('mViewports=') || line.contains('Display Id='),
          )
          .take(4)
          .toList(),
      'evidenceSource': 'vibekits-harness-tool-bridge',
    }),
  );
}
