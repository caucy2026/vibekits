import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/platform_storage_layout.dart';
import 'app/windows_file_associations.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformStorageLayout.initialize();
  final List<String> initialFilePaths = arguments
      .where((String argument) => File(argument).existsSync())
      .toList(growable: false);
  // File associations only exist on Windows. Avoid touching the executable
  // path and FFI-backed registration service during Android cold start.
  if (Platform.isWindows) {
    unawaited(WindowsFileAssociations.registerCurrentExecutable());
  }
  runApp(VibekitsApp(initialFilePaths: initialFilePaths));
}
