import 'dart:async';

import 'lmcp_inbound_call_hub.dart';

enum RemoteSimulationActivityDirection { outgoing, incoming }

enum RemoteSimulationActivityPhase { running, succeeded, failed }

final class RemoteSimulationActivityEntry {
  const RemoteSimulationActivityEntry({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.action,
    required this.detail,
    required this.startedAt,
    required this.updatedAt,
    required this.phase,
  });

  final String id;
  final RemoteSimulationActivityDirection direction;
  final String peerId;
  final String action;
  final String detail;
  final DateTime startedAt;
  final DateTime updatedAt;
  final RemoteSimulationActivityPhase phase;

  RemoteSimulationActivityEntry copyWith({
    String? detail,
    DateTime? updatedAt,
    RemoteSimulationActivityPhase? phase,
  }) => RemoteSimulationActivityEntry(
    id: id,
    direction: direction,
    peerId: peerId,
    action: action,
    detail: detail ?? this.detail,
    startedAt: startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    phase: phase ?? this.phase,
  );
}

final class RemoteSimulationActivityHandle {
  const RemoteSimulationActivityHandle._(this._hub, this.id);

  final RemoteSimulationActivityHub _hub;
  final String id;

  void succeed([String detail = '操作完成']) =>
      _hub._finish(id, RemoteSimulationActivityPhase.succeeded, detail);

  void fail(Object error) =>
      _hub._finish(id, RemoteSimulationActivityPhase.failed, '$error');
}

/// Lightweight, process-local audit trail for remote simulation.
///
/// It is deliberately independent from Harness startup and transport state.
/// Only actual simulator actions publish here, so an unused feature has no
/// timers, file I/O, network work, or impact on the agent workspace.
final class RemoteSimulationActivityHub {
  RemoteSimulationActivityHub({this.capacity = 200, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static final RemoteSimulationActivityHub instance =
      RemoteSimulationActivityHub();

  final int capacity;
  final DateTime Function() _clock;
  final StreamController<List<RemoteSimulationActivityEntry>> _changes =
      StreamController<List<RemoteSimulationActivityEntry>>.broadcast(
        sync: true,
      );
  final List<RemoteSimulationActivityEntry> _entries =
      <RemoteSimulationActivityEntry>[];
  int _sequence = 0;

  Stream<List<RemoteSimulationActivityEntry>> get changes => _changes.stream;

  List<RemoteSimulationActivityEntry> get entries =>
      List<RemoteSimulationActivityEntry>.unmodifiable(_entries);

  RemoteSimulationActivityHandle begin({
    required RemoteSimulationActivityDirection direction,
    required String peerId,
    required String action,
    Map<String, Object?> arguments = const <String, Object?>{},
    String detail = '',
  }) {
    final DateTime now = _clock();
    final String id = '${now.microsecondsSinceEpoch}-${_sequence++}';
    final String safeDetail = detail.trim().isNotEmpty
        ? _bounded(detail, 600)
        : arguments.isEmpty
        ? '正在执行'
        : redactLmcpArguments(arguments);
    _entries.insert(
      0,
      RemoteSimulationActivityEntry(
        id: id,
        direction: direction,
        peerId: _bounded(peerId.trim(), 80),
        action: _bounded(action.trim().isEmpty ? '远程操作' : action, 160),
        detail: safeDetail,
        startedAt: now,
        updatedAt: now,
        phase: RemoteSimulationActivityPhase.running,
      ),
    );
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
    _emit();
    return RemoteSimulationActivityHandle._(this, id);
  }

  void clear() {
    _entries.clear();
    _emit();
  }

  void _finish(String id, RemoteSimulationActivityPhase phase, String detail) {
    final int index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final RemoteSimulationActivityEntry current = _entries[index];
    final String outcome = detail.trim().isEmpty ? '操作完成' : detail.trim();
    final String combined = current.detail == '正在执行'
        ? outcome
        : '${current.detail}\n$outcome';
    _entries[index] = _entries[index].copyWith(
      updatedAt: _clock(),
      phase: phase,
      detail: _bounded(combined, 600),
    );
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(entries);
  }

  static String _bounded(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
