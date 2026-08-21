import 'dart:convert';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

Future<void> main(List<String> args) async {
  final String root = Directory.current.absolute.path;
  final String target = args.isEmpty ? '192.168.3.63:5555' : args.first;
  final String apkPath = args.length > 1 ? File(args[1]).absolute.path : '';
  final String adb =
      '$root${Platform.pathSeparator}build${Platform.pathSeparator}windows'
      '${Platform.pathSeparator}x64${Platform.pathSeparator}runner'
      '${Platform.pathSeparator}Release${Platform.pathSeparator}tools'
      '${Platform.pathSeparator}adb${Platform.pathSeparator}adb.exe';
  if (!File(adb).existsSync()) throw StateError('缺少 Release 内置 ADB：$adb');

  final Directory evidence = Directory(
    '$root${Platform.pathSeparator}build${Platform.pathSeparator}acceptance'
    '${Platform.pathSeparator}adb-semantic',
  )..createSync(recursive: true);
  final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final File upload = File(
    '${evidence.path}${Platform.pathSeparator}upload-$suffix.txt',
  );
  final File download = File(
    '${evidence.path}${Platform.pathSeparator}download-$suffix.txt',
  );
  final File screenshot = File(
    '${evidence.path}${Platform.pathSeparator}screenshot-$suffix.png',
  );
  final String remote = '/sdcard/Download/vibekits-acceptance-$suffix.txt';
  final List<int> content = utf8.encode('VIBEKITS_ADB_SEMANTIC_$suffix');
  await upload.writeAsBytes(content, flush: true);

  final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
    adbExecutable: adb,
  );
  Future<Map<String, Object?>> invoke(
    String toolId,
    Map<String, Object?> arguments,
  ) async {
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: toolId,
      arguments: arguments,
      approve: (_) async => true,
    );
    if (!result.ok) throw StateError('$toolId 失败：${result.error}');
    return result.data!;
  }

  await invoke(VibekitsHarnessToolBridge.adbConnectId, <String, Object?>{
    'address': target,
  });
  final Map<String, Object?> devices = await invoke(
    VibekitsHarnessToolBridge.adbListDevicesId,
    const <String, Object?>{},
  );
  final Map<String, Object?> shell = await invoke(
    VibekitsHarnessToolBridge.adbShellId,
    <String, Object?>{
      'serial': target,
      'arguments': <String>['getprop', 'ro.product.model'],
    },
  );
  final Map<String, Object?> logcat = await invoke(
    VibekitsHarnessToolBridge.adbLogcatId,
    <String, Object?>{'serial': target, 'lines': 20},
  );
  await invoke(VibekitsHarnessToolBridge.adbPushFileId, <String, Object?>{
    'serial': target,
    'localPath': upload.path,
    'remotePath': remote,
  });
  await invoke(VibekitsHarnessToolBridge.adbPullFileId, <String, Object?>{
    'serial': target,
    'remotePath': remote,
    'localPath': download.path,
    'overwrite': true,
  });
  await invoke(VibekitsHarnessToolBridge.adbScreenshotId, <String, Object?>{
    'serial': target,
    'localPath': screenshot.path,
    'overwrite': true,
  });
  await invoke(VibekitsHarnessToolBridge.adbShellId, <String, Object?>{
    'serial': target,
    'arguments': <String>['rm', '-f', remote],
  });
  if (apkPath.isNotEmpty) {
    await invoke(VibekitsHarnessToolBridge.adbInstallApkId, <String, Object?>{
      'serial': target,
      'apkPath': apkPath,
      'replace': true,
    });
  }

  final List<int> pulled = await download.readAsBytes();
  if (!_sameBytes(content, pulled)) throw StateError('ADB 推送/拉取内容不一致');
  if (!await screenshot.exists() || await screenshot.length() < 64) {
    throw StateError('ADB 截图证据无效');
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'passed': true,
      'target': target,
      'devices': devices['devices'],
      'model': (shell['stdout'] ?? '').toString().trim(),
      'logcatBytes': utf8.encode('${logcat['stdout'] ?? ''}').length,
      'roundTripBytes': pulled.length,
      'screenshotPath': screenshot.path,
      'screenshotBytes': await screenshot.length(),
      'apkInstalled': apkPath.isNotEmpty,
      'evidenceSource': 'vibekits-harness-tool-bridge',
    }),
  );
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
