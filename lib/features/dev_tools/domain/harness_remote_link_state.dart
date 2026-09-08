/// Shared connection state for desktop and Android controllers. Task phase is
/// deliberately absent: losing a connection must never mark remote work idle.
enum HarnessRemoteLinkPhase {
  disconnected,
  resolving,
  connecting,
  awaitingApproval,
  authenticating,
  synchronizing,
  connected,
  reconnecting,
  failed,
}

class HarnessRemoteLinkState {
  int _generation = 0;
  HarnessRemoteLinkPhase _phase = HarnessRemoteLinkPhase.disconnected;
  String? _peerId;
  String? _failure;
  bool _hasSnapshot = false;

  int get generation => _generation;
  HarnessRemoteLinkPhase get phase => _phase;
  String? get peerId => _peerId;
  String? get failure => _failure;
  bool get stale => _hasSnapshot && _phase != HarnessRemoteLinkPhase.connected;
  bool get canSubmit => _phase == HarnessRemoteLinkPhase.connected;

  int begin(String peerId) {
    if (peerId.trim().isEmpty) throw ArgumentError('Missing remote identity');
    if (_peerId != peerId) _hasSnapshot = false;
    _peerId = peerId;
    _failure = null;
    _phase = HarnessRemoteLinkPhase.resolving;
    return ++_generation;
  }

  bool resolved(int attempt) => _move(attempt, {
    HarnessRemoteLinkPhase.resolving,
  }, HarnessRemoteLinkPhase.connecting);

  bool transportConnected(int attempt, {required bool paired}) => _move(
    attempt,
    {HarnessRemoteLinkPhase.connecting},
    paired
        ? HarnessRemoteLinkPhase.authenticating
        : HarnessRemoteLinkPhase.awaitingApproval,
  );

  bool approved(int attempt) => _move(attempt, {
    HarnessRemoteLinkPhase.awaitingApproval,
  }, HarnessRemoteLinkPhase.authenticating);

  bool authenticated(int attempt) => _move(attempt, {
    HarnessRemoteLinkPhase.authenticating,
  }, HarnessRemoteLinkPhase.synchronizing);

  bool snapshotApplied(int attempt) {
    final moved = _move(attempt, {
      HarnessRemoteLinkPhase.synchronizing,
    }, HarnessRemoteLinkPhase.connected);
    if (moved) _hasSnapshot = true;
    return moved;
  }

  /// Invalidate ALL callbacks belonging to the lost connection immediately.
  /// The caller schedules retry; this model never opens a socket implicitly.
  int? connectionLost(int attempt) {
    if (attempt != _generation ||
        const {
          HarnessRemoteLinkPhase.disconnected,
          HarnessRemoteLinkPhase.failed,
          HarnessRemoteLinkPhase.reconnecting,
        }.contains(_phase)) {
      return null;
    }
    _phase = HarnessRemoteLinkPhase.reconnecting;
    return ++_generation;
  }

  bool retry(int attempt) => _move(attempt, {
    HarnessRemoteLinkPhase.reconnecting,
  }, HarnessRemoteLinkPhase.resolving);

  bool fail(int attempt, String safeCode) {
    if (attempt != _generation || _phase == HarnessRemoteLinkPhase.disconnected) {
      return false;
    }
    _failure = safeCode;
    _phase = HarnessRemoteLinkPhase.failed;
    ++_generation;
    return true;
  }

  void disconnect() {
    ++_generation;
    _failure = null;
    _phase = HarnessRemoteLinkPhase.disconnected;
  }

  bool _move(
    int attempt,
    Set<HarnessRemoteLinkPhase> from,
    HarnessRemoteLinkPhase to,
  ) {
    if (attempt != _generation || !from.contains(_phase)) return false;
    _phase = to;
    return true;
  }
}
