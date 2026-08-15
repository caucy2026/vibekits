import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'main_shell.dart';

/// Vibekits 应用根组件。
class VibekitsApp extends StatelessWidget {
  const VibekitsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibekits',
      debugShowCheckedModeBanner: false,
      theme: VibekitsTheme.light(),
      home: const MainShell(),
    );
  }
}
