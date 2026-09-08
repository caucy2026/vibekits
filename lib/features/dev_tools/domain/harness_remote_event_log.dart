import 'dart:convert';

class HarnessRemoteEvent {
  const HarnessRemoteEvent({
    required this.epoch,
    required this.sequence,
    required this.workspaceId,
    required this.payloadJson,
  });
  final String epoch;
  final int sequence;
  final String workspaceId;
  final String payloadJson;

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'sequence': sequence,
    'workspaceId': workspaceId,
    'payload': jsonDecode(payloadJson),
  };
}

/// Bounded catch-up journal. Eviction is always observable as snapshotRequired;
/// it never pretends an incomplete history is complete. Durable history stays
/// with official DSH, and must be loaded when the cursor falls behind.
class HarnessRemoteEventLog {
  HarnessRemoteEventLog({
    required this.epoch,
    this.maxBytes = 16 * 1024 * 1024,
    this.maxEvents = 4096,
  }) {
    if (epoch.isEmpty || maxBytes <= 0 || maxEvents <= 0) {
      throw ArgumentError('Invalid remote event journal configuration');
    }
  }
  final String epoch;
  final int maxBytes;
  final int maxEvents;
  final List<(HarnessRemoteEvent, int)> _events = [];
  int _bytes = 0;
  int _sequence = 0;
  int get sequence => _sequence;

  HarnessRemoteEvent append(String workspaceId, Map<String, dynamic> envelope) {
    if (workspaceId.isEmpty) throw ArgumentError('Missing event scope');
    final encoded = jsonEncode(envelope);
    final length = utf8.encode(encoded).length;
    if (length > maxBytes) {
      // Invalidate every prior cursor even though the oversized frame cannot
      // be retained; the next read must explicitly request a fresh snapshot.
      _sequence++;
      _events.clear();
      _bytes = 0;
      throw StateError('REMOTE_EVENT_REQUIRES_SNAPSHOT');
    }
    final event = HarnessRemoteEvent(
      epoch: epoch,
      sequence: ++_sequence,
      workspaceId: workspaceId,
      payloadJson: encoded,
    );
    _events.add((event, length));
    _bytes += length;
    while (_events.length > maxEvents || _bytes > maxBytes) {
      _bytes -= _events.removeAt(0).$2;
    }
    return event;
  }

  /// Scope is the trusted connection grant. The cursor advances over hidden
  /// events too, so clients use nextSequence (not the visible event count).
  Map<String, Object?> read({
    required String afterEpoch,
    required int afterSequence,
    required Set<String> authorizedWorkspaces,
  }) {
    final oldest = _events.isEmpty ? _sequence + 1 : _events.first.$1.sequence;
    final needsSnapshot =
        afterEpoch != epoch ||
        afterSequence < oldest - 1 ||
        afterSequence < 0 ||
        afterSequence > _sequence;
    return {
      'epoch': epoch,
      'afterSequence': afterSequence,
      'nextSequence': _sequence,
      'snapshotRequired': needsSnapshot,
      'events': needsSnapshot
          ? <Object?>[]
          : [
              for (final entry in _events)
                if (entry.$1.sequence > afterSequence &&
                    authorizedWorkspaces.contains(entry.$1.workspaceId))
                  entry.$1.toJson(),
            ],
    };
  }
}
