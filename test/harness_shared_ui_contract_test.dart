import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows and macOS use one Harness interaction entry', () {
    final String source = File(
      'lib/features/local_models/presentation/local_models_tab.dart',
    ).readAsStringSync();

    expect(source, contains('DeepSeekAgentWorkspace('));
    expect(source, isNot(contains('OfficialHarnessWorkspace(')));
    expect(source, isNot(contains('Platform.isWindows')));
  });

  test('shared Harness entry receives platform services as adapters', () {
    final String source = File(
      'lib/features/local_models/presentation/deepseek_agent_workspace.dart',
    ).readAsStringSync();

    expect(source, contains('HarnessRemoteWorkspaceLauncher?'));
    expect(source, contains('HarnessScreenshotOcrRunner?'));
    expect(source, contains('String downloadDirectory'));
    expect(source, contains('VibekitsHarnessToolBridge('));
  });
}
