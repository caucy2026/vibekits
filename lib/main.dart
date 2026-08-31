import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import 'app/app.dart';
import 'app/app_crash_log.dart';
import 'app/platform_storage_layout.dart';
import 'app/windows_file_associations.dart';
import 'features/dev_tools/domain/harness_tool_bridge.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final String? webviewDebugPort = _webviewDebugPort(arguments);
  if (Platform.isWindows && webviewDebugPort != null) {
    await WebviewController.initializeEnvironment(
      additionalArguments: '--remote-debugging-port=$webviewDebugPort',
    );
  }
  await PlatformStorageLayout.initialize();
  final void Function(FlutterErrorDetails)? defaultFlutterErrorHandler =
      FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AppCrashLog.recordSync(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'flutter-framework',
    );
    defaultFlutterErrorHandler?.call(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    AppCrashLog.recordSync(error, stackTrace, source: 'platform-dispatcher');
    return true;
  };
  final List<String> initialFilePaths = arguments
      .where((String argument) => File(argument).existsSync())
      .toList(growable: false);
  final String? initialWorkspaceId = arguments.contains('--open-harness')
      ? 'large-model'
      : null;
  final bool approveAdbSerialStress = arguments.contains(
    '--harness-stress-approve-adb-serial',
  );
  final bool approveDownloadInstallTest = arguments.contains(
    '--harness-test-approve-download-install',
  );
  final Set<String> preapprovedExternalToolIds = <String>{
    if (approveDownloadInstallTest) ...const <String>{
      VibekitsHarnessToolBridge.networkDownloadId,
      VibekitsHarnessToolBridge.adbConnectId,
      VibekitsHarnessToolBridge.adbInstallApkId,
      VibekitsHarnessToolBridge.adbShellId,
    },
    if (approveAdbSerialStress) ...const <String>{
      VibekitsHarnessToolBridge.adbConnectId,
      VibekitsHarnessToolBridge.adbShellId,
      VibekitsHarnessToolBridge.adbLogcatId,
      VibekitsHarnessToolBridge.adbInstallApkId,
      VibekitsHarnessToolBridge.adbSessionOpenId,
      VibekitsHarnessToolBridge.adbSessionStatusId,
      VibekitsHarnessToolBridge.adbSessionCloseId,
      VibekitsHarnessToolBridge.serialSessionOpenId,
      VibekitsHarnessToolBridge.serialSessionReadId,
      VibekitsHarnessToolBridge.serialSessionWriteId,
      VibekitsHarnessToolBridge.serialSessionCloseId,
    },
  };
  // File associations only exist on Windows. Avoid touching the executable
  // path and FFI-backed registration service during Android cold start.
  if (Platform.isWindows) {
    unawaited(WindowsFileAssociations.registerCurrentExecutable());
  }
  runApp(
    VibekitsApp(
      initialFilePaths: initialFilePaths,
      initialWorkspaceId: initialWorkspaceId,
      preapprovedExternalToolIds: preapprovedExternalToolIds,
    ),
  );
}

String? _webviewDebugPort(List<String> arguments) {
  const String prefix = '--webview-debug-port=';
  for (final String argument in arguments) {
    if (!argument.startsWith(prefix)) {
      continue;
    }
    final String value = argument.substring(prefix.length);
    final int? port = int.tryParse(value);
    if (port != null && port >= 1024 && port <= 65535) {
      return '$port';
    }
  }
  return null;
}
