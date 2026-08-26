import 'dart:async';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/platform_credential_store.dart';

const String _target = '192.168.3.63:5555';

Future<void> main(List<String> arguments) async {
  final String root = Directory.current.absolute.path;
  final String adb = arguments.isEmpty
      ? '$root${Platform.pathSeparator}build${Platform.pathSeparator}windows'
            '${Platform.pathSeparator}x64${Platform.pathSeparator}runner'
            '${Platform.pathSeparator}Release${Platform.pathSeparator}tools'
            '${Platform.pathSeparator}adb${Platform.pathSeparator}adb.exe'
      : File(arguments.first).absolute.path;
  if (!File(adb).existsSync()) {
    stderr.writeln('HARNESS_ADB_MISSING=$adb');
    exitCode = 2;
    return;
  }
  final String apiKey =
      await PlatformCredentialStore.read('deepseek-api-key') ?? '';
  if (apiKey.trim().isEmpty) {
    stderr.writeln('HARNESS_ADB_NO_SAVED_KEY');
    exitCode = 3;
    return;
  }

  final HarnessAgentHandle handle = await DeepSeekHarnessService.startAgent(
    HarnessAgentRequest(
      workspace: root,
      prompt:
          '必须调用 Vibekits ADB 工具完成验证，不要猜测。先列出设备，'
          '然后对 $_target 分别读取 ro.product.model、'
          'ro.build.version.release、ro.product.manufacturer。'
          '最后只输出一行：VIBEKITS_HARNESS_ADB_OK model=<值> android=<值> manufacturer=<值>',
      apiKey: apiKey,
      model: DeepSeekHarnessService.defaultModel,
      toolBridge: VibekitsHarnessToolBridge(adbExecutable: adb),
      approveTool: _approveReadOnlyDeviceCheck,
    ),
  );
  final StringBuffer output = StringBuffer();
  final StreamSubscription<String> subscription = handle.output.listen((
    String chunk,
  ) {
    stdout.write(chunk);
    output.write(chunk);
  });
  try {
    final int code = await handle.exitCode.timeout(
      const Duration(seconds: 120),
      onTimeout: () async {
        await handle.stop();
        return 124;
      },
    );
    final String text = output.toString();
    stdout.writeln('\nHARNESS_ADB_EXIT=$code');
    if (code != 0 ||
        !text.contains('VIBEKITS_HARNESS_ADB_OK') ||
        !text.toLowerCase().contains('huanglong') ||
        !text.contains('12') ||
        !text.contains('HL2.0')) {
      exitCode = 4;
      return;
    }
    stdout.writeln('HARNESS_ADB_SMOKE_PASSED');
  } finally {
    await subscription.cancel();
    if (handle.running) await handle.stop();
  }
}

Future<bool> _approveReadOnlyDeviceCheck(
  HarnessToolApprovalRequest request,
) async {
  if (request.tool.id != VibekitsHarnessToolBridge.adbCommandId ||
      request.target != _target) {
    return false;
  }
  final Object? raw = request.arguments['arguments'];
  if (raw is! List || raw.length != 3) return false;
  final List<String> command = raw.map((Object? value) => '$value').toList();
  return command[0] == 'shell' &&
      command[1] == 'getprop' &&
      const <String>{
        'ro.product.model',
        'ro.build.version.release',
        'ro.product.manufacturer',
      }.contains(command[2]);
}
