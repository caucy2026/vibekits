import 'dart:math';

enum HarnessRoutingRegistrationState {
  unregistered,
  registering,
  registered,
  conflict,
  rejected,
}

/// Rendezvous/relay routing identity. This is deliberately separate from the
/// VH certificate label: users enter [routingId], while pairing pins the full
/// end-to-end certificate fingerprint.
class HarnessRemoteRoutingIdentity {
  HarnessRemoteRoutingIdentity({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  int _generation = 0;
  String? _candidate;
  String? _registeredId;
  HarnessRoutingRegistrationState _state =
      HarnessRoutingRegistrationState.unregistered;

  HarnessRoutingRegistrationState get state => _state;
  String? get routingId => _registeredId;
  bool get callable =>
      _state == HarnessRoutingRegistrationState.registered &&
      _registeredId != null;

  /// Uses the standard ten-digit RustDesk-compatible range. The server remains
  /// authoritative: generation is never displayed as a callable ID.
  (int, String) beginRegistration({String? persistedCandidate}) {
    final candidate =
        persistedCandidate ??
        (1000000000 + _random.nextInt(1000000000)).toString();
    if (!RegExp(r'^[1-9][0-9]{9}$').hasMatch(candidate)) {
      throw const FormatException('Invalid Harness routing ID candidate');
    }
    _candidate = candidate;
    _registeredId = null;
    _state = HarnessRoutingRegistrationState.registering;
    return (++_generation, candidate);
  }

  bool serverConfirmed(int generation, String id) {
    if (generation != _generation ||
        _state != HarnessRoutingRegistrationState.registering ||
        id != _candidate) {
      return false;
    }
    _registeredId = id;
    _state = HarnessRoutingRegistrationState.registered;
    return true;
  }

  bool serverRejected(int generation, {required bool conflict}) {
    if (generation != _generation ||
        _state != HarnessRoutingRegistrationState.registering) {
      return false;
    }
    _registeredId = null;
    _state = conflict
        ? HarnessRoutingRegistrationState.conflict
        : HarnessRoutingRegistrationState.rejected;
    ++_generation;
    return true;
  }

  void offline() {
    ++_generation;
    _registeredId = null;
    _state = HarnessRoutingRegistrationState.unregistered;
  }
}
