import 'dart:io';

import 'package:flutter/foundation.dart';

/// Legacy compatibility surface for builds that used an application-level
/// updater. VibeKits updates are owned exclusively by the KEMI App Center.
enum AppUpdatePhase { idle }

@immutable
class AppUpdateSnapshot {
  const AppUpdateSnapshot({this.phase = AppUpdatePhase.idle});

  final AppUpdatePhase phase;
}

/// Deliberately inert so startup and stale callers cannot show update prompts.
class AppUpdateService {
  AppUpdateService({
    HttpClient? client,
    String? apiRoot,
    String? platformOverride,
  }) : _client = client ?? HttpClient();

  static final AppUpdateService instance = AppUpdateService();
  static const String packageName = 'com.caucy.vibekits';

  final HttpClient _client;
  final ValueNotifier<AppUpdateSnapshot> snapshot =
      ValueNotifier<AppUpdateSnapshot>(const AppUpdateSnapshot());

  Future<void> start() async {}

  Future<void> check() async {}

  Future<void> downloadAndInstall() async {}

  void dispose() {
    _client.close(force: true);
    snapshot.dispose();
  }
}
