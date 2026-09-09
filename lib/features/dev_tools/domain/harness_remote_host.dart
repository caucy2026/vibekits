import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'harness_official_remote_adapter.dart';
import 'harness_remote_execution.dart';
import 'harness_remote_inventory.dart';
import 'harness_remote_event_log.dart';
import 'harness_remote_server_connection.dart';
import 'harness_remote_tls_channel.dart';
import 'harness_remote_ledger.dart';
import 'harness_work_status.dart';

/// Explicitly enabled remote host, independent from desktop-sharing identity.
/// Constructing a host does not listen or grant access. UI pairing must supply
/// the dedicated TLS identity and approved certificate-to-peer mapping.
class HarnessRemoteHost {
  HarnessRemoteHost({
    Uri? officialEndpoint,
    HarnessRemoteApiAdapter? adapter,
    required this.ledger,
    HarnessWorkRegistrySnapshot Function()? workSnapshot,
  }) : _workSnapshot =
           workSnapshot ?? (() => HarnessWorkStatusHub.registryLatest) {
    if ((officialEndpoint == null) == (adapter == null)) {
      throw ArgumentError('Provide exactly one remote API adapter');
    }
    _adapter = adapter ?? HarnessOfficialRemoteAdapter(officialEndpoint!);
    inventory = HarnessRemoteInventory(_adapter);
    execution = HarnessRemoteExecution(
      adapter: _adapter,
      workspaceForSession: inventory.workspaceForSession,
      ledger: ledger,
    );
  }
  late final HarnessRemoteApiAdapter _adapter;
  final HarnessRemoteLedger ledger;
  final HarnessWorkRegistrySnapshot Function() _workSnapshot;
  late final HarnessRemoteInventory inventory;
  late final HarnessRemoteExecution execution;
  SecureServerSocket? _listener;
  StreamSubscription<SecureSocket>? _subscription;
  final Map<String, String> _approved = {};
  final Map<HarnessRemoteServerConnection, String> _connections = {};
  HarnessRemoteEventLog _journal = _newJournal();
  static HarnessRemoteEventLog _newJournal() => HarnessRemoteEventLog(
    epoch: List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
  );
  bool _eventsLive = false;
  bool _closed = false;
  bool _starting = false;
  final Completer<void> _shutdown = Completer<void>();
  int? get port => _listener?.port;

  void approveCertificate(String sha256, HarnessRemoteGrant grant) {
    if (_closed || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Invalid approved certificate');
    }
    final existing = _approved[sha256];
    if (existing != null && existing != grant.peerId) {
      throw StateError('REMOTE_CERTIFICATE_IDENTITY_CONFLICT');
    }
    execution.grant(grant);
    _approved[sha256] = grant.peerId;
  }

  Future<void> revoke(String peerId) async {
    execution.revoke(peerId);
    _approved.removeWhere((_, value) => value == peerId);
    final connections = _connections.entries
        .where((entry) => entry.value == peerId)
        .map((entry) => entry.key)
        .toList();
    for (final connection in connections) {
      _connections.remove(connection);
      await connection.close();
    }
  }

  Future<void> start({
    required InternetAddress bindAddress,
    required int port,
    required SecurityContext identity,
  }) async {
    if (_closed || _listener != null || _starting) {
      throw StateError('REMOTE_HOST_ALREADY_STARTED_OR_CLOSED');
    }
    _starting = true;
    try {
      final listener = await SecureServerSocket.bind(
        bindAddress,
        port,
        identity,
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      if (_closed) {
        await listener.close();
        return;
      }
      _listener = listener;
      _subscription = listener.listen(
        (socket) {
          if (_closed || _connections.length >= 16) {
            socket.destroy();
            return;
          }
          try {
            final channel = HarnessRemoteTlsChannel.accept(socket, _approved);
            final connection = HarnessRemoteServerConnection(
              channel: channel,
              execution: execution,
              readState: _readState,
            );
            _connections[connection] = channel.authenticatedPeerId;
            unawaited(
              connection.done.whenComplete(() {
                _connections.remove(connection);
              }),
            );
          } catch (_) {
            socket.destroy();
          }
        },
        onError: (Object error) {
          // Individual failed TLS handshakes do not disable other controllers.
        },
      );
      unawaited(_pumpEvents());
    } finally {
      _starting = false;
    }
  }

  Future<void> _pumpEvents() async {
    var failures = 0;
    while (!_closed) {
      try {
        await for (final event in _adapter.events(
          onConnected: () {
            // No replay contract exists on the official WebSocket. Every new
            // stream starts a new epoch, forcing clients to reload history.
            _journal = _newJournal();
            _eventsLive = true;
          },
        )) {
          if (_closed) break;
          final payload = event['payload'] as Map;
          final sessionId = payload['sessionId'];
          if (sessionId is! String) continue;
          final workspaceId = await inventory.workspaceForSession(sessionId);
          if (_closed) break;
          if (workspaceId == null) continue;
          _journal.append(workspaceId, event);
          failures = 0;
        }
      } catch (_) {
        // Keep errors out of the wire; stale is observable through readState.
      } finally {
        _eventsLive = false;
      }
      if (_closed) break;
      failures = min(failures + 1, 5);
      await Future.any([
        _shutdown.future,
        Future<void>.delayed(Duration(milliseconds: 250 * (1 << failures))),
      ]);
    }
  }

  Future<Map<String, Object?>> _readState(
    String peerId,
    Map<String, dynamic> request,
  ) async {
    final scope = execution.visibleWorkspaceIds(peerId);
    if (scope.isEmpty) throw StateError('REMOTE_PERMISSION_DENIED');
    final afterEpoch = request['epoch'];
    final afterSequence = request['sequence'];
    if (afterEpoch is String && afterSequence is int) {
      return {
        'ok': true,
        'live': _eventsLive,
        ..._journal.read(
          afterEpoch: afterEpoch,
          afterSequence: afterSequence,
          authorizedWorkspaces: scope,
        ),
      };
    }
    // Capture cursor BEFORE inventory: clients may replay duplicate updates,
    // but must not skip changes that arrived while inventory was loading.
    final sequence = _journal.sequence;
    final epoch = _journal.epoch;
    final rows = await inventory.visibleWorkspaces(scope);
    final work = _workSnapshot();
    final currentScope = execution.visibleWorkspaceIds(peerId);
    if (currentScope.isEmpty) throw StateError('REMOTE_PERMISSION_DENIED');
    if (_journal.epoch != epoch) {
      return {'ok': true, 'live': false, 'snapshotRequired': true};
    }
    return {
      'ok': true,
      'epoch': epoch,
      'sequence': sequence,
      'live': _eventsLive,
      'workspaces': [
        for (final row in rows)
          if (currentScope.contains(row['workspaceId']))
            _withWorkState(row, work),
      ],
    };
  }

  Map<String, dynamic> _withWorkState(
    Map<String, dynamic> workspace,
    HarnessWorkRegistrySnapshot snapshot,
  ) {
    final String workspaceId = workspace['workspaceId'] as String;
    final String title = workspace['title'] as String;
    final matches =
        snapshot.tasks
            .where(
              (task) =>
                  task.workspaceRef == workspaceId ||
                  task.workspaceLabel == title,
            )
            .toList()
          ..sort((a, b) => b.streamSequence.compareTo(a.streamSequence));
    final latest = matches.isEmpty ? null : matches.first;
    final busy = matches.where((task) => task.busy).toList();
    return <String, dynamic>{
      ...workspace,
      'phase': busy.isNotEmpty
          ? busy.first.phase.wireName
          : latest?.phase.wireName ?? HarnessWorkPhase.ready.wireName,
      'busyTaskCount': busy.length,
      if (latest != null) ...{
        'statusMessage': latest.message,
        'statusUpdatedAt': latest.updatedAt.toUtc().toIso8601String(),
      },
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _shutdown.complete();
    _approved.clear();
    await _subscription?.cancel();
    await _listener?.close();
    _listener = null;
    final connections = _connections.keys.toList();
    _connections.clear();
    await Future.wait(connections.map((connection) => connection.close()));
    await execution.close();
    await ledger.close();
  }
}
