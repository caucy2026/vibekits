import 'package:flutter_test/flutter_test.dart';
import '../lib/features/dev_tools/domain/harness_remote_link_state.dart';

void main() {
  test('first pairing needs approval, authentication and applied snapshot', () {
    final state = HarnessRemoteLinkState();
    final attempt = state.begin('VH-A');
    expect(state.snapshotApplied(attempt), false);
    expect(state.resolved(attempt), true);
    expect(state.transportConnected(attempt, paired: false), true);
    expect(state.authenticated(attempt), false);
    expect(state.approved(attempt), true);
    expect(state.canSubmit, false);
    expect(state.authenticated(attempt), true);
    expect(state.canSubmit, false);
    expect(state.snapshotApplied(attempt), true);
    expect(state.canSubmit, true);
  });

  test('disconnect invalidates late callbacks, including successful sync', () {
    final state = HarnessRemoteLinkState();
    final attempt = state.begin('VH-A');
    state.resolved(attempt);
    state.transportConnected(attempt, paired: true);
    state.authenticated(attempt);
    state.disconnect();
    expect(state.snapshotApplied(attempt), false);
    expect(state.connectionLost(attempt), isNull);
    expect(state.fail(attempt, 'late error'), false);
    expect(state.phase, HarnessRemoteLinkPhase.disconnected);
  });

  test(
    'reconnect retains stale content but requires fresh identity and sync',
    () {
      final state = HarnessRemoteLinkState();
      final first = state.begin('VH-A');
      state.resolved(first);
      state.transportConnected(first, paired: true);
      state.authenticated(first);
      state.snapshotApplied(first);
      final next = state.connectionLost(first)!;
      expect(state.stale, true);
      expect(state.canSubmit, false);
      expect(state.snapshotApplied(first), false);
      state.retry(next);
      state.resolved(next);
      state.transportConnected(next, paired: true);
      state.authenticated(next);
      expect(state.stale, true);
      state.snapshotApplied(next);
      expect(state.stale, false);
      expect(state.canSubmit, true);
    },
  );

  test(
    'switching device and authorization failure reject previous callbacks',
    () {
      final state = HarnessRemoteLinkState();
      final first = state.begin('VH-A');
      final second = state.begin('VH-B');
      expect(state.resolved(first), false);
      expect(state.peerId, 'VH-B');
      expect(state.fail(second, 'PERMISSION_DENIED'), true);
      expect(state.resolved(second), false);
      expect(state.canSubmit, false);
      expect(state.failure, 'PERMISSION_DENIED');
    },
  );
}
