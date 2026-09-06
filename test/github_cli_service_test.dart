import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/github_cli_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test('executes argv directly with non-interactive environment', () async {
    late List<String> capturedArguments;
    late Map<String, String> capturedEnvironment;
    final GithubCliService service = GithubCliService(
      executable: Platform.resolvedExecutable,
      runner:
          (
            String executable,
            List<String> arguments, {
            required String? workingDirectory,
            required Map<String, String> environment,
            required Duration timeout,
          }) async {
            capturedArguments = arguments;
            capturedEnvironment = environment;
            return ProcessResult(12, 0, '{"number":7}', '');
          },
    );

    final Map<String, Object?> result = await service.execute(const <String>[
      'pr',
      'view',
      '7',
      '--json',
      'number',
    ]);

    expect(result['ok'], isTrue);
    expect(capturedArguments, <String>['pr', 'view', '7', '--json', 'number']);
    expect(capturedEnvironment['GH_PROMPT_DISABLED'], '1');
    expect(capturedEnvironment['GH_NO_UPDATE_NOTIFIER'], '1');
    expect(capturedEnvironment['DO_NOT_TRACK'], '1');
  });

  test('blocks token reads and token input', () async {
    final GithubCliService service = GithubCliService(
      executable: Platform.resolvedExecutable,
    );
    expect(
      () => service.execute(const <String>['auth', 'token']),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.execute(const <String>['auth', 'login', '--with-token']),
      throwsA(isA<FormatException>()),
    );
  });

  test('redacts GitHub tokens from process output', () async {
    final GithubCliService service = GithubCliService(
      executable: Platform.resolvedExecutable,
      runner:
          (
            String executable,
            List<String> arguments, {
            required String? workingDirectory,
            required Map<String, String> environment,
            required Duration timeout,
          }) async => ProcessResult(
            12,
            1,
            'github_pat_abcdefghijklmnopqrstuvwxyz0123456789',
            'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
          ),
    );
    final Map<String, Object?> result = await service.execute(const <String>[
      'api',
      'user',
    ]);
    expect(result['stdout'], '[REDACTED_GITHUB_TOKEN]');
    expect(result['stderr'], '[REDACTED_GITHUB_TOKEN]');
  });

  test('bridge exports GitHub CLI tools with schemas and remote risk', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Map<String, HarnessToolDefinition> catalog =
        <String, HarnessToolDefinition>{
          for (final HarnessToolDefinition tool in bridge.executableCatalog)
            tool.id: tool,
        };
    expect(
      catalog[VibekitsHarnessToolBridge.githubCliInspectId]?.risk,
      HarnessToolRisk.readOnly,
    );
    expect(
      catalog[VibekitsHarnessToolBridge.githubCliAuthStatusId]?.risk,
      HarnessToolRisk.readOnly,
    );
    expect(
      catalog[VibekitsHarnessToolBridge.githubCliExecuteId]?.risk,
      HarnessToolRisk.controlsDevice,
    );
    expect(
      catalog[VibekitsHarnessToolBridge.githubCliExecuteId]?.inputSchema,
      containsPair('additionalProperties', false),
    );
  });
}
