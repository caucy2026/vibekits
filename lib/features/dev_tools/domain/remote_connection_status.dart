class RemoteConnectionStatus {
  const RemoteConnectionStatus({
    required this.profileId,
    required this.activeConnections,
    required this.kinds,
    required this.connectedSinceEpochMs,
  });

  final String profileId;
  final int activeConnections;
  final List<String> kinds;
  final int connectedSinceEpochMs;

  bool get online => activeConnections > 0;
}

/// Process-local live state shared by the remote workspace and Harness bridge.
/// It deliberately contains no host, username, command, path or credential.
abstract final class RemoteConnectionStatusRegistry {
  static final Map<String, _ActiveRemoteConnection> _active =
      <String, _ActiveRemoteConnection>{};

  static void connected({
    required String token,
    required String profileId,
    required String kind,
  }) {
    _active[token] = _ActiveRemoteConnection(
      profileId: profileId,
      kind: kind,
      connectedSinceEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static void disconnected(String token) => _active.remove(token);

  static RemoteConnectionStatus statusFor(String profileId) {
    final List<_ActiveRemoteConnection> matches = _active.values
        .where((_ActiveRemoteConnection item) => item.profileId == profileId)
        .toList(growable: false);
    return RemoteConnectionStatus(
      profileId: profileId,
      activeConnections: matches.length,
      kinds:
          matches
              .map((_ActiveRemoteConnection item) => item.kind)
              .toSet()
              .toList()
            ..sort(),
      connectedSinceEpochMs: matches.isEmpty
          ? 0
          : matches
                .map(
                  (_ActiveRemoteConnection item) => item.connectedSinceEpochMs,
                )
                .reduce((int a, int b) => a < b ? a : b),
    );
  }

  static void clearForTests() => _active.clear();
}

class _ActiveRemoteConnection {
  const _ActiveRemoteConnection({
    required this.profileId,
    required this.kind,
    required this.connectedSinceEpochMs,
  });

  final String profileId;
  final String kind;
  final int connectedSinceEpochMs;
}
