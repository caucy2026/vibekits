import 'dart:async';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/platform_credential_store.dart';

Future<void> main() async {
  final String apiKey =
      await PlatformCredentialStore.read('deepseek-api-key') ?? '';
  if (apiKey.trim().isEmpty) {
    stderr.writeln('HARNESS_SMOKE_NO_SAVED_KEY');
    exitCode = 2;
    return;
  }
  final HarnessEnvironmentReport environment =
      await DeepSeekHarnessService.checkEnvironment();
  stdout.writeln('ENV_READY=${environment.ready} ${environment.message}');
  if (!environment.ready) {
    exitCode = 3;
    return;
  }
  final HarnessAgentHandle handle = await DeepSeekHarnessService.startAgent(
    HarnessAgentRequest(
      workspace: Directory.current.path,
      prompt: '只回复 VIBEKITS_HARNESS_OK，不要调用工具。',
      apiKey: apiKey,
      model: DeepSeekHarnessService.defaultModel,
    ),
  );
  final StringBuffer output = StringBuffer();
  final StreamSubscription<String> subscription = handle.output.listen(
    output.write,
  );
  try {
    final int code = await handle.exitCode.timeout(
      const Duration(seconds: 120),
      onTimeout: () async {
        await handle.stop();
        return 124;
      },
    );
    stdout.writeln('HARNESS_EXIT=$code');
    stdout.writeln(output.toString().trim());
    if (code != 0 || !output.toString().contains('VIBEKITS_HARNESS_OK')) {
      exitCode = 4;
    }
  } finally {
    await subscription.cancel();
    if (handle.running) await handle.stop();
  }
}
