import 'harness_official_remote_adapter.dart';

/// Reads the authoritative official workspace registry. No local project names
/// or caller-provided paths are used to decide ownership of remote sessions.
class HarnessRemoteInventory {
  HarnessRemoteInventory(this.adapter);
  final HarnessRemoteApiAdapter adapter;
  Future<List<Map<String, dynamic>>> _workspaces() async {
    final items = await adapter.workspaceSnapshot();
    final rows = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final row in items) {
      if (row['workspaceId'] is! String ||
          row['title'] is! String ||
          row['sessionIds'] is! List ||
          !(row['sessionIds'] as List).every((id) => id is String) ||
          !ids.add(row['workspaceId'] as String)) {
        throw const FormatException('Invalid official workspace inventory');
      }
      rows.add(row);
    }
    return rows;
  }

  Future<String?> workspaceForSession(String sessionId) async {
    final matches = (await _workspaces())
        .where((row) => (row['sessionIds'] as List).contains(sessionId))
        .toList();
    // Ambiguous ownership must fail closed, not take the first project.
    if (matches.length != 1) return null;
    return matches.single['workspaceId'] as String;
  }

  /// Resolve persisted user-visible path scopes into this DSH generation's
  /// opaque Workspace IDs. IDs are also accepted for forward compatibility.
  Future<Set<String>> resolveWorkspaceScopes(Set<String> scopes) async => {
    for (final row in await _workspaces())
      if (scopes.contains(row['workspaceId']) || scopes.contains(row['path']))
        row['workspaceId'] as String,
  };

  Future<List<Map<String, dynamic>>> visibleWorkspaces(
    Set<String> authorizedWorkspaceIds,
  ) async => [
    for (final row in await _workspaces())
      if (authorizedWorkspaceIds.contains(row['workspaceId'])) row,
  ];
}
