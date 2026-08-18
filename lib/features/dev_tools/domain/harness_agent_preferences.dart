import 'dart:convert';
import 'dart:io';

enum HarnessAgentPermissionMode { requestApproval, assisted, fullAccess }

typedef HarnessAgentPermissionLoader =
    Future<HarnessAgentPermissionMode> Function();
typedef HarnessAgentPermissionSaver = Future<void> Function(
  HarnessAgentPermissionMode mode,
);

abstract final class HarnessAgentPreferencesStore {
  static HarnessAgentPermissionMode? _cached;

  static Future<HarnessAgentPermissionMode> loadPermissionMode() async {
    if (_cached case final HarnessAgentPermissionMode value) return value;
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return _cached = HarnessAgentPermissionMode.assisted;
    }
    try {
      final File file = _file();
      if (!await file.exists()) {
        return _cached = HarnessAgentPermissionMode.assisted;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      final String name = decoded is Map
          ? '${decoded['permissionMode'] ?? ''}'
          : '';
      return _cached = HarnessAgentPermissionMode.values.firstWhere(
        (HarnessAgentPermissionMode mode) => mode.name == name,
        orElse: () => HarnessAgentPermissionMode.assisted,
      );
    } on Object {
      return _cached = HarnessAgentPermissionMode.assisted;
    }
  }

  static Future<void> savePermissionMode(
    HarnessAgentPermissionMode mode,
  ) async {
    _cached = mode;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    final File file = _file();
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{'version': 1, 'permissionMode': mode.name}),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static File _file() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return File(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
      '${Platform.pathSeparator}agent_preferences.json',
    );
  }
}
