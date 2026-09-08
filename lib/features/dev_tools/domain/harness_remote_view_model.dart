import 'dart:async';

import 'package:flutter/foundation.dart';

import 'harness_remote_connection.dart';
import 'harness_remote_sync.dart';
import 'harness_remote_workspace_client.dart';

/// Lifecycle projection only. Conversation payloads are still official DSH
/// envelopes and are handed to the official UI adapter, never rewritten here.
class HarnessRemoteViewModel extends ChangeNotifier {
  HarnessRemoteViewModel(this.client, {required this.applyOfficialEvents}) {
    _stateSubscription = client.connection.states.listen((state) {
      if (state != HarnessRemoteConnectionState.connected) {
        _cursor.disconnected();
        _live = false;
        if (!_disposed) notifyListeners();
      }
    });
  }
  final HarnessRemoteWorkspaceClient client;
  final Future<void> Function(List<Map<String, dynamic>>) applyOfficialEvents;
  final HarnessRemoteSyncCursor _cursor = HarnessRemoteSyncCursor();
  late final StreamSubscription<HarnessRemoteConnectionState>
  _stateSubscription;
  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  bool _live = false;
  Duration? _roundTrip;
  String? _error;
  List<Map<String, dynamic>> _workspaces = const [];
  bool get stale => _cursor.stale || !_live;
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
    final watch = Stopwatch()..start();
    try {
      final snapshot = _cursor.stale;
      final result = await client.readState(
        epoch: snapshot ? null : _cursor.epoch,
        sequence: snapshot ? null : _cursor.sequence,
      );
      if (_disposed) return;
      if (result['ok'] != true) throw StateError('REMOTE_STATE_UNAVAILABLE');
      if (result['snapshotRequired'] == true) {
        _cursor.connected();
        _live = false;
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
        _workspaces = List.unmodifiable(
          rows.map(
            (row) =>
                Map<String, dynamic>.unmodifiable(row as Map<String, dynamic>),
          ),
        );
        _cursor.acceptSnapshot(epoch: epoch, sequence: sequence);
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
          _live = false;
          return;
        }
        if (decision == HarnessRemoteEventDecision.apply) {
          await applyOfficialEvents(envelopes);
          if (_disposed) return;
          _cursor.acceptBatch(
            epoch: epoch,
            afterSequence: after,
            nextSequence: next,
            visibleSequences: sequences,
          );
        }
      }
      _live = result['live'] == true;
      _roundTrip = watch.elapsed;
      _error = null;
    } catch (_) {
      if (!_disposed) {
        _live = false;
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
    _timer?.cancel();
    unawaited(_stateSubscription.cancel());
    super.dispose();
  }
}
