import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/windows_file_associations.dart';

void main(List<String> arguments) {
  final List<String> initialFilePaths = arguments
      .where((String argument) => File(argument).existsSync())
      .toList(growable: false);
  unawaited(WindowsFileAssociations.registerCurrentExecutable());
  runApp(VibekitsApp(initialFilePaths: initialFilePaths));
}
