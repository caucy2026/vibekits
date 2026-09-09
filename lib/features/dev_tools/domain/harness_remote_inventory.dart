import 'dart:math';

import 'harness_official_remote_adapter.dart';

/// Reads the authoritative official workspace registry. No local project names
/// or caller-provided paths are used to decide ownership of remote sessions.
class HarnessRemoteInventory {
  HarnessRemoteInventory(this.adapter);
  final HarnessRemoteApiAdapter adapter;
  final Random _random = Random.secure();

  Future<List<Map<String, dynamic>>> _workspaces() async {
    final id = List.generate(
      24,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final response = await adapter.request({
      'type': 'client-request',
      'rpcId': id,
      'method': 'workspace.list',
      'payload': <String, Object?>{},
    });
    final result = response['result'];
    if (result is! Map || result['ok'] != true) {
      throw StateError('REMOTE_INVENTORY_UNAVAILABLE');
    }
    final value = result['value'];
    if (value is! Map || value['items'] is! List) {
      throw const FormatException('Unsupported official workspace inventory');
    }
    final rows = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final row in value['items'] as List) {
      if (row is! Map<String, dynamic> ||
          row['workspaceId'] is! String ||
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

  Future<List<Map<String, dynamic>>> visibleWorkspaces(
    Set<String> authorizedWorkspaceIds,
  ) async => [
    for (final row in await _workspaces())
      if (authorizedWorkspaceIds.contains(row['workspaceId'])) row,
  ];
}
