import 'dart:io';

import 'package:flutter/services.dart';

/// Binds a child process tree to the desktop App lifetime on Windows.
///
/// The native runner owns a Windows Job Object with
/// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. This is the last-resort cleanup when
/// Windows closes the Flutter engine before Dart can await widget disposal.
abstract final class PlatformProcessLifecycle {
  static const MethodChannel _channel = MethodChannel(
    'vibekits/process_lifecycle',
  );

  static Future<void> bindProcessTree(int processId) async {
    if (!Platform.isWindows) return;
    final bool? bound;
    try {
      bound = await _channel.invokeMethod<bool>(
        'bindProcessTree',
        <String, Object>{'pid': processId},
      );
    } on MissingPluginException {
      if (Platform.environment['FLUTTER_TEST'] == 'true') return;
      rethrow;
    }
    if (bound != true) {
      throw StateError('无法将子进程绑定到 App 生命周期');
    }
  }

  static Future<void> releaseProcessTree(int processId) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('releaseProcessTree', <String, Object>{
        'pid': processId,
      });
    } on MissingPluginException {
      // The Flutter engine may already be gone during application shutdown.
    } on PlatformException {
      // The process is already gone; the runner will close remaining jobs.
    }
  }
}
