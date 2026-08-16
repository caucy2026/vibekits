import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_settings.dart';
import 'main_shell.dart';

/// Vibekits 应用根组件。
class VibekitsApp extends StatefulWidget {
  const VibekitsApp({super.key, this.settingsController, this.initialFilePath});

  final AppSettingsController? settingsController;
  final String? initialFilePath;

  @override
  State<VibekitsApp> createState() => _VibekitsAppState();
}

class _VibekitsAppState extends State<VibekitsApp> {
  late final AppSettingsController _settings =
      widget.settingsController ?? AppSettingsController();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
    if (widget.settingsController == null) _settings.load();
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    if (widget.settingsController == null) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibekits',
      debugShowCheckedModeBanner: false,
      theme: VibekitsTheme.light(),
      darkTheme: VibekitsTheme.dark(),
      themeMode: _settings.value.themeMode,
      home: MainShell(
        settingsController: _settings,
        initialFilePath: widget.initialFilePath,
      ),
    );
  }
}
