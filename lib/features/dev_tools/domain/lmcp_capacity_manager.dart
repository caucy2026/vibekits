import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'mcp_capability_models.dart';

class LmcpCapacityException implements Exception {
  const LmcpCapacityException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class LmcpCapacityLeaseManager {
  LmcpCapacityLeaseManager({
    required this.capacity,
    this.onChanged,
    DateTime Function()? now,
    Random? random,
  }) : assert(capacity > 0),
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final int capacity;
  final void Function()? onChanged;
  final DateTime Function() _now;
  final Random _random;
  final Map<String, _LmcpCapacityLease> _leases =
      <String, _LmcpCapacityLease>{};
  Timer? _expiryTimer;
  int _loadRevision = 1;
  bool _draining = false;

  int get activeLeaseCount {
    _removeExpired();
    return _leases.length;
  }

  McpNodeRuntime get runtime {
    _removeExpired();
    final int inFlight = _leases.values.fold<int>(
      0,
      (int total, _LmcpCapacityLease lease) => total + lease.slots,
    );
    final int available = (capacity - inFlight).clamp(0, capacity);
    final int oldest = _leases.isEmpty
        ? 0
        : _now()
              .difference(
                _leases.values
                    .map((_LmcpCapacityLease lease) => lease.createdAt)
                    .reduce(
                      (DateTime left, DateTime right) =>
                          left.isBefore(right) ? left : right,
                    ),
              )
              .inMilliseconds
              .clamp(0, 86400000);
    return McpNodeRuntime(
      state: _draining
          ? McpNodeState.draining
          : available == 0
          ? McpNodeState.saturated
          : inFlight == 0
          ? McpNodeState.idle
          : McpNodeState.busy,
      capacity: capacity,
      inFlight: inFlight,
      queueDepth: 0,
      availableSlots: available,
      loadRevision: _loadRevision,
      oldestTaskAgeMs: oldest,
      draining: _draining,
      acceptingReservations: !_draining,
    );
  }

  Map<String, Object?> status() => <String, Object?>{
    'runtime': runtime.toJson(),
    'activeLeaseCount': activeLeaseCount,
    'serviceTime': _now().toUtc().toIso8601String(),
  };

  Map<String, Object?> reserve({
    required String toolName,
    required String idempotencyKey,
    required String commanderId,
    required int requestedSlots,
    required int ttlSeconds,
    required String scopeDigest,
    required String callerInstanceId,
  }) {
    _removeExpired();
    if (_draining) {
      throw const LmcpCapacityException('NODE_DRAINING', '节点正在排空');
    }
    if (toolName.isEmpty ||
        idempotencyKey.isEmpty ||
        commanderId.isEmpty ||
        scopeDigest.isEmpty ||
        requestedSlots < 1 ||
        requestedSlots > capacity ||
        ttlSeconds < 10 ||
        ttlSeconds > 120) {
      throw const LmcpCapacityException('INVALID_ARGUMENTS', '租约参数无效');
    }
    if (callerInstanceId.isNotEmpty && callerInstanceId != commanderId) {
      throw const LmcpCapacityException(
        'LEASE_SCOPE_MISMATCH',
        'commanderId 与签名调用方身份不一致',
      );
    }
    final _LmcpCapacityLease? existing = _leases.values
        .where(
          (_LmcpCapacityLease lease) =>
              lease.commanderId == commanderId &&
              lease.idempotencyKey == idempotencyKey &&
              lease.toolName == toolName &&
              lease.scopeDigest == scopeDigest,
        )
        .firstOrNull;
    if (existing != null) return _leaseJson(existing);
    final McpNodeRuntime current = runtime;
    if (current.availableSlots < requestedSlots) {
      throw const LmcpCapacityException('CAPACITY_BUSY', '当前无可预约槽位');
    }
    final DateTime now = _now();
    final _LmcpCapacityLease lease = _LmcpCapacityLease(
      id: _randomId('lease'),
      token: _randomId('token'),
      toolName: toolName,
      idempotencyKey: idempotencyKey,
      commanderId: commanderId,
      scopeDigest: scopeDigest,
      slots: requestedSlots,
      createdAt: now,
      expiresAt: now.add(Duration(seconds: ttlSeconds)),
    );
    _leases[lease.id] = lease;
    _ensureExpiryTimer();
    _changed();
    return _leaseJson(lease);
  }

  Map<String, Object?> renew({
    required String leaseId,
    required String leaseToken,
    required int ttlSeconds,
    required String callerInstanceId,
  }) {
    final _LmcpCapacityLease lease = _require(
      leaseId,
      leaseToken,
      callerInstanceId,
    );
    if (ttlSeconds < 10 || ttlSeconds > 120) {
      throw const LmcpCapacityException(
        'INVALID_ARGUMENTS',
        'ttlSeconds 必须为 10∼120',
      );
    }
    lease.expiresAt = _now().add(Duration(seconds: ttlSeconds));
    _changed();
    return _leaseJson(lease);
  }

  Map<String, Object?> release({
    required String leaseId,
    required String leaseToken,
    required String callerInstanceId,
    required String reason,
  }) {
    final _LmcpCapacityLease? lease = _leases[leaseId];
    if (lease == null) {
      return <String, Object?>{'released': true, 'alreadyReleased': true};
    }
    _require(leaseId, leaseToken, callerInstanceId);
    _leases.remove(leaseId);
    if (_leases.isEmpty) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
    _changed();
    return <String, Object?>{
      'released': true,
      'leaseId': leaseId,
      'reason': reason.isEmpty ? 'completed' : reason,
      'loadRevision': _loadRevision,
    };
  }

  void validateScheduledCall({
    required String leaseId,
    required String leaseToken,
    required String toolName,
    required String idempotencyKey,
    required String callerInstanceId,
  }) {
    final _LmcpCapacityLease lease = _require(
      leaseId,
      leaseToken,
      callerInstanceId,
    );
    if (lease.toolName != toolName || lease.idempotencyKey != idempotencyKey) {
      throw const LmcpCapacityException('LEASE_SCOPE_MISMATCH', '租约的工具或幂等键不匹配');
    }
  }

  void setDraining(bool value) {
    if (_draining == value) return;
    _draining = value;
    _changed();
  }

  void dispose() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  _LmcpCapacityLease _require(
    String leaseId,
    String leaseToken,
    String callerInstanceId,
  ) {
    _removeExpired();
    final _LmcpCapacityLease? lease = _leases[leaseId];
    if (lease == null) {
      throw const LmcpCapacityException('LEASE_NOT_FOUND', '租约不存在或已过期');
    }
    if (lease.token != leaseToken ||
        (callerInstanceId.isNotEmpty &&
            lease.commanderId != callerInstanceId)) {
      throw const LmcpCapacityException('LEASE_SCOPE_MISMATCH', '租约身份或令牌不匹配');
    }
    return lease;
  }

  Map<String, Object?> _leaseJson(_LmcpCapacityLease lease) =>
      <String, Object?>{
        'leaseId': lease.id,
        'leaseToken': lease.token,
        'expiresAt': lease.expiresAt.toUtc().toIso8601String(),
        'slot': lease.slots,
        'loadRevision': _loadRevision,
      };

  void _removeExpired() {
    final DateTime now = _now();
    final int before = _leases.length;
    _leases.removeWhere(
      (_, _LmcpCapacityLease lease) => !lease.expiresAt.isAfter(now),
    );
    if (_leases.isEmpty) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
    if (_leases.length != before) _changed();
  }

  void _ensureExpiryTimer() {
    if (_expiryTimer?.isActive ?? false) return;
    _expiryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _removeExpired(),
    );
  }

  void _changed() {
    _loadRevision++;
    onChanged?.call();
  }

  String _randomId(String prefix) {
    final List<int> bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return '$prefix-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

class _LmcpCapacityLease {
  _LmcpCapacityLease({
    required this.id,
    required this.token,
    required this.toolName,
    required this.idempotencyKey,
    required this.commanderId,
    required this.scopeDigest,
    required this.slots,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final String toolName;
  final String idempotencyKey;
  final String commanderId;
  final String scopeDigest;
  final int slots;
  final DateTime createdAt;
  DateTime expiresAt;
}
