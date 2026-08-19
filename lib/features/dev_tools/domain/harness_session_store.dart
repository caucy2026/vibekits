import 'dart:convert';
import 'dart:io';

/// Removes one official Harness session after its server has been stopped.
///
/// The operation is deliberately scoped to the exact session id and the two
/// official indexes that reference it. Callers must obtain user confirmation.
class HarnessSessionStore {
  HarnessSessionStore({Directory? home}) : home = home ?? _defaultHarnessHome();

  final Directory home;

  static final RegExp _sessionIdPattern = RegExp(
    r'^session-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  Future<void> deleteSession(String sessionId) async {
    if (!_sessionIdPattern.hasMatch(sessionId)) {
      throw const FormatException('Harness 会话 ID 无效');
    }

    final Directory sessionsRoot = Directory(
      '${home.path}${Platform.pathSeparator}sessions',
    );
    if (await sessionsRoot.exists()) {
      await for (final FileSystemEntity workspace in sessionsRoot.list()) {
        if (workspace is! Directory) continue;
        final Directory candidate = Directory(
          '${workspace.path}${Platform.pathSeparator}$sessionId',
        );
        if (await candidate.exists()) {
          await candidate.delete(recursive: true);
        }
      }
    }

    await _editJsonStore('workspace.json', (Map<String, dynamic> root) {
      final Map<String, dynamic>? global = _map(root['global']);
      _removeFromList(global?['archivedSessionIds'], sessionId);
      final Map<String, dynamic>? tables = _map(root['tables']);
      final Map<String, dynamic>? workspaces = _map(tables?['workspaces']);
      for (final dynamic value in workspaces?.values ?? const <dynamic>[]) {
        _removeFromList(_map(value)?['sessionIds'], sessionId);
      }
    });
    await _editJsonStore('session_projcache.json', (Map<String, dynamic> root) {
      final Map<String, dynamic>? tables = _map(root['tables']);
      _map(tables?['sessions'])?.remove(sessionId);
    });
  }

  Future<void> _editJsonStore(
    String name,
    void Function(Map<String, dynamic> root) edit,
  ) async {
    final File file = File(
      '${home.path}${Platform.pathSeparator}storages${Platform.pathSeparator}$name',
    );
    if (!await file.exists()) return;
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$name 格式无效');
    }
    edit(decoded);
    final File temporary = File('${file.path}.vibekits.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(decoded),
      flush: true,
    );
    await file.delete();
    await temporary.rename(file.path);
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static void _removeFromList(Object? value, String sessionId) {
    if (value is List<dynamic>) value.removeWhere((item) => item == sessionId);
  }

  static Directory _defaultHarnessHome() {
    final String base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return Directory(
      Platform.isWindows
          ? '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness'
          : '$base${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Harness',
    );
  }
}
