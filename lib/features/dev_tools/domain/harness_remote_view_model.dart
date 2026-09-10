import 'dart:async';

import 'package:flutter/foundation.dart';

import 'harness_remote_connection.dart';
import 'harness_remote_sync.dart';
import 'harness_remote_workspace_client.dart';

/// Lifecycle projection only. Conversation payloads are still official DSH
/// envelopes and are handed to the official UI adapter, never rewritten here.
class HarnessRemoteViewModel extends ChangeNotifier {
  HarnessRemoteViewModel(
    this.client, {
    required this.applyOfficialEvents,
    required this.restoreOfficialSnapshot,
  }) {
    _stateSubscription = client.connection.states.listen((state) {
      if (state != HarnessRemoteConnectionState.connected) {
        _generation++;
        _cursor.disconnected();
        _eventStreamLive = false;
        if (!_disposed) notifyListeners();
      }
    });
  }
  final HarnessRemoteWorkspaceClient client;
  final Future<void> Function(List<Map<String, dynamic>>) applyOfficialEvents;

  /// Reload official project/session projections and selected history before
  /// committing the cursor. A directory listing alone is not a restored UI.
  final Future<void> Function(List<Map<String, dynamic>>)
  restoreOfficialSnapshot;
  final HarnessRemoteSyncCursor _cursor = HarnessRemoteSyncCursor();
  late final StreamSubscription<HarnessRemoteConnectionState>
  _stateSubscription;
  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  bool _negotiated = false;
  DateTime? _lastHeartbeat;
  DateTime? _lastSnapshot;
  int _generation = 0;
  // `live` describes the optional official DSH event stream, not the
  // authenticated Harness transport. Snapshot polling is still current when
  // that upstream stream is unavailable.
  bool _eventStreamLive = false;
  Duration? _roundTrip;
  String? _error;
  List<Map<String, dynamic>> _workspaces = const [];
  bool get stale => _cursor.stale;
  bool get eventStreamLive => _eventStreamLive;
  Duration? get roundTrip => _roundTrip;
  String? get error => _error;
  List<Map<String, dynamic>> get workspaces => _workspaces;

  void start() {
    if (_disposed || _timer != null) return;
    _cursor.connected();
    unawaited(_poll());
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    if (_disposed ||
        _polling ||
        client.connection.state != HarnessRemoteConnectionState.connected) {
      return;
    }
    _polling = true;
    final generation = _generation;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        client.connection.state == HarnessRemoteConnectionState.connected;
    final watch = Stopwatch()..start();
    try {
      if (!_negotiated) {
        await client.negotiate();
        if (!current()) return;
        _negotiated = true;
        _lastHeartbeat = DateTime.now();
      } else if (_lastHeartbeat == null ||
          DateTime.now().difference(_lastHeartbeat!) >=
              const Duration(seconds: 5)) {
        _roundTrip = await client.heartbeat();
        if (!current()) return;
        _lastHeartbeat = DateTime.now();
      }
      final bool snapshot =
          _cursor.stale ||
          _lastSnapshot == null ||
          DateTime.now().difference(_lastSnapshot!) >=
              const Duration(seconds: 2);
      final result = await client.readState(
        epoch: snapshot ? null : _cursor.epoch,
        sequence: snapshot ? null : _cursor.sequence,
      );
      if (!current()) return;
      if (result['ok'] != true) throw StateError('REMOTE_STATE_UNAVAILABLE');
      if (result['snapshotRequired'] == true) {
        _cursor.connected();
        _eventStreamLive = false;
        return;
      }
      final epoch = result['epoch'];
      if (epoch is! String) throw const FormatException('Missing state epoch');
      if (snapshot) {
        final sequence = result['sequence'];
        final rows = result['workspaces'];
        if (sequence is! int ||
            rows is! List ||
            !rows.every((row) => row is Map<String, dynamic>)) {
          throw const FormatException('Invalid workspace snapshot');
        }
        final restored = List<Map<String, dynamic>>.unmodifiable(
          rows.map(
            (row) =>
                Map<String, dynamic>.unmodifiable(row as Map<String, dynamic>),
          ),
        );
        await restoreOfficialSnapshot(restored);
        if (!current()) return;
        _workspaces = restored;
        _cursor.acceptSnapshot(epoch: epoch, sequence: sequence);
        _lastSnapshot = DateTime.now();
      } else {
        final rows = result['events'];
        final after = result['afterSequence'];
        final next = result['nextSequence'];
        if (rows is! List || after is! int || next is! int) {
          throw const FormatException('Invalid remote event batch');
        }
        final sequences = <int>[];
        final envelopes = <Map<String, dynamic>>[];
        for (final row in rows) {
          if (row is! Map ||
              row['sequence'] is! int ||
              row['payload'] is! Map<String, dynamic>) {
            throw const FormatException('Invalid remote event');
          }
          sequences.add(row['sequence'] as int);
          envelopes.add(row['payload'] as Map<String, dynamic>);
        }
        // Validate on a temporary cursor. Commit only after UI application
        // succeeds; otherwise recovery must resnapshot, not silently skip.
        final trial = HarnessRemoteSyncCursor()..connected();
        trial.acceptSnapshot(epoch: _cursor.epoch!, sequence: _cursor.sequence);
        final decision = trial.acceptBatch(
          epoch: epoch,
          afterSequence: after,
          nextSequence: next,
          visibleSequences: sequences,
        );
        if (decision == HarnessRemoteEventDecision.snapshotRequired) {
          _cursor.connected();
          _eventStreamLive = false;
          return;
        }
        if (decision == HarnessRemoteEventDecision.apply) {
          await applyOfficialEvents(envelopes);
          if (!current()) return;
          _cursor.acceptBatch(
            epoch: epoch,
            afterSequence: after,
            nextSequence: next,
            visibleSequences: sequences,
          );
        }
      }
      _eventStreamLive = result['live'] == true;
      _roundTrip = watch.elapsed;
      _error = null;
    } catch (_) {
      if (!_disposed) {
        _negotiated = false;
        _lastHeartbeat = null;
        _eventStreamLive = false;
        _error = '远程状态同步中断，保留最后记录';
        _cursor.connected();
      }
    } finally {
      _polling = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_stateSubscription.cancel());
    super.dispose();
  }
}
