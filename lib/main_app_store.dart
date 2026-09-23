import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app_crash_log.dart';
import 'app/app_store_app.dart';
import 'app/platform_storage_layout.dart';

/// Dedicated Mac App Store entry point.
///
/// This target intentionally imports only the offline archive/document product.
/// The direct-distribution entry point remains [main.dart] and keeps the full
/// Harness, MCP, application-center, update and engineering-tool experience.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformStorageLayout.initialize();

  final void Function(FlutterErrorDetails)? defaultHandler =
      FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AppCrashLog.recordSync(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'flutter-framework',
    );
    defaultHandler?.call(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    AppCrashLog.recordSync(error, stackTrace, source: 'platform-dispatcher');
    return true;
  };

  final List<String> initialFilePaths = arguments
      .where((String argument) => File(argument).existsSync())
      .toList(growable: false);
  runApp(VibekitsAppStoreApp(initialFilePaths: initialFilePaths));
}
