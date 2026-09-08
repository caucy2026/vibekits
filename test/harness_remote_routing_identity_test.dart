import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import '../lib/features/dev_tools/domain/harness_remote_routing_identity.dart';

void main() {
  test('candidate is never callable before exact server confirmation', () {
    final identity = HarnessRemoteRoutingIdentity(random: Random(7));
    final (generation, candidate) = identity.beginRegistration();
    expect(candidate, matches(RegExp(r'^[1-9][0-9]{9}$')));
    expect(identity.routingId, isNull);
    expect(identity.callable, false);
    expect(identity.serverConfirmed(generation, '1234567890'), false);
    expect(identity.serverConfirmed(generation, candidate), true);
    expect(identity.routingId, candidate);
    expect(identity.callable, true);
  });

  test('conflict and offline invalidate late registration callbacks', () {
    final identity = HarnessRemoteRoutingIdentity();
    final (first, candidate) = identity.beginRegistration();
    expect(identity.serverRejected(first, conflict: true), true);
    expect(identity.state, HarnessRoutingRegistrationState.conflict);
    expect(identity.serverConfirmed(first, candidate), false);
    final (second, next) = identity.beginRegistration();
    identity.offline();
    expect(identity.serverConfirmed(second, next), false);
    expect(identity.callable, false);
  });

  test('persisted candidate is validated before it reaches rendezvous', () {
    final identity = HarnessRemoteRoutingIdentity();
    expect(
      () => identity.beginRegistration(persistedCandidate: 'VH-ABC'),
      throwsFormatException,
    );
    expect(
      () => identity.beginRegistration(persistedCandidate: '123 456789'),
      throwsFormatException,
    );
  });
}
