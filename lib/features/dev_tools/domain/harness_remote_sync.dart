/// Transport-independent cursor for the authoritative remote event stream.
/// Payloads stay in the official Harness model, not a second chat schema.
enum HarnessRemoteEventDecision { apply, duplicate, snapshotRequired }

class HarnessRemoteSyncCursor {
  String? _epoch;
  int _sequence = 0;
  bool _connected = false;
  bool _needsSnapshot = true;

  String? get epoch => _epoch;
  int get sequence => _sequence;
  bool get stale => !_connected || _needsSnapshot;

  void disconnected() {
    _connected = false;
  }

  /// Reconnection must reconcile with the authority before showing live state.
  void connected() {
    _connected = true;
    _needsSnapshot = true;
  }

  void acceptSnapshot({required String epoch, required int sequence}) {
    if (epoch.isEmpty || sequence < 0) {
      throw const FormatException('Invalid remote snapshot cursor');
    }
    if (!_connected) {
      throw StateError('Cannot apply snapshot while disconnected');
    }
    if (_epoch == epoch && sequence < _sequence) {
      throw StateError('Snapshot would roll back remote state');
    }
    _epoch = epoch;
    _sequence = sequence;
    _needsSnapshot = false;
  }

  HarnessRemoteEventDecision acceptEvent({
    required String epoch,
    required int sequence,
  }) {
    if (epoch.isEmpty || sequence <= 0) {
      throw const FormatException('Invalid remote event cursor');
    }
    if (stale || epoch != _epoch) {
      _needsSnapshot = true;
      return HarnessRemoteEventDecision.snapshotRequired;
    }
    if (sequence <= _sequence) return HarnessRemoteEventDecision.duplicate;
    if (sequence != _sequence + 1) {
      _needsSnapshot = true;
      return HarnessRemoteEventDecision.snapshotRequired;
    }
    _sequence = sequence;
    return HarnessRemoteEventDecision.apply;
  }

  /// Scoped batches can omit events outside a connection's authorization.
  /// The batch must name the exact cursor it was read from so omissions cannot
  /// conceal a dropped network batch. Only advance after applying its payloads.
  HarnessRemoteEventDecision acceptBatch({
    required String epoch,
    required int afterSequence,
    required int nextSequence,
    required List<int> visibleSequences,
  }) {
    if (afterSequence < 0 || nextSequence < afterSequence || epoch.isEmpty) {
      throw const FormatException('Invalid remote batch cursor');
    }
    var last = afterSequence;
    for (final sequence in visibleSequences) {
      if (sequence <= last || sequence > nextSequence) {
        throw const FormatException('Unordered remote batch');
      }
      last = sequence;
    }
    if (stale || epoch != _epoch) {
      _needsSnapshot = true;
      return HarnessRemoteEventDecision.snapshotRequired;
    }
    if (nextSequence <= _sequence) return HarnessRemoteEventDecision.duplicate;
    if (afterSequence != _sequence) {
      _needsSnapshot = true;
      return HarnessRemoteEventDecision.snapshotRequired;
    }
    _sequence = nextSequence;
    return HarnessRemoteEventDecision.apply;
  }
}
