import 'package:flutter/material.dart';

import 'app_store_shell.dart';
import 'app_theme.dart';

/// Offline-only application used by the Mac App Store target.
class VibekitsAppStoreApp extends StatelessWidget {
  const VibekitsAppStoreApp({
    super.key,
    this.initialFilePaths = const <String>[],
  });

  final List<String> initialFilePaths;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vibekits',
    debugShowCheckedModeBanner: false,
    theme: VibekitsTheme.light(),
    darkTheme: VibekitsTheme.dark(),
    themeMode: ThemeMode.system,
    home: AppStoreShell(initialFilePaths: initialFilePaths),
  );
}
