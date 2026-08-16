import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/supported_file_types.dart';
import 'app/windows_file_associations.dart';

void main(List<String> arguments) {
  final String? initialFilePath = arguments
      .where((String argument) => File(argument).existsSync())
      .where(
        (String argument) =>
            SupportedFileTypes.kindForPath(argument) !=
            VibekitsFileKind.unsupported,
      )
      .firstOrNull;
  unawaited(WindowsFileAssociations.registerCurrentExecutable());
  runApp(VibekitsApp(initialFilePath: initialFilePath));
}
