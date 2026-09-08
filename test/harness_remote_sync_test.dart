import 'package:flutter_test/flutter_test.dart';
import '../lib/features/dev_tools/domain/harness_remote_sync.dart';

void main() {
  late HarnessRemoteSyncCursor cursor;
  setUp(() {
    cursor = HarnessRemoteSyncCursor()..connected();
    cursor.acceptSnapshot(epoch: 'boot-a', sequence: 10);
  });

  test('applies consecutive events and ignores redelivery', () {
    expect(
      cursor.acceptEvent(epoch: 'boot-a', sequence: 11),
      HarnessRemoteEventDecision.apply,
    );
    expect(
      cursor.acceptEvent(epoch: 'boot-a', sequence: 11),
      HarnessRemoteEventDecision.duplicate,
    );
    expect(cursor.sequence, 11);
    expect(cursor.stale, isFalse);
  });

  test('gap blocks later events until authoritative snapshot', () {
    expect(
      cursor.acceptEvent(epoch: 'boot-a', sequence: 12),
      HarnessRemoteEventDecision.snapshotRequired,
    );
    expect(
      cursor.acceptEvent(epoch: 'boot-a', sequence: 11),
      HarnessRemoteEventDecision.snapshotRequired,
    );
    expect(cursor.sequence, 10);
    expect(cursor.stale, isTrue);
    cursor.acceptSnapshot(epoch: 'boot-a', sequence: 12);
    expect(cursor.stale, isFalse);
  });

  test('restart requires snapshot and allows new epoch numbering', () {
    expect(
      cursor.acceptEvent(epoch: 'boot-b', sequence: 1),
      HarnessRemoteEventDecision.snapshotRequired,
    );
    cursor.acceptSnapshot(epoch: 'boot-b', sequence: 0);
    expect(
      cursor.acceptEvent(epoch: 'boot-b', sequence: 1),
      HarnessRemoteEventDecision.apply,
    );
  });

  test('disconnect preserves history and reconnect remains stale', () {
    cursor.disconnected();
    expect(cursor.sequence, 10);
    expect(cursor.stale, isTrue);
    expect(
      () => cursor.acceptSnapshot(epoch: 'boot-a', sequence: 10),
      throwsStateError,
    );
    cursor.connected();
    expect(cursor.stale, isTrue);
    cursor.acceptSnapshot(epoch: 'boot-a', sequence: 10);
    expect(cursor.stale, isFalse);
  });

  test('rejects rollback and malformed cursors', () {
    expect(
      () => cursor.acceptSnapshot(epoch: 'boot-a', sequence: 9),
      throwsStateError,
    );
    expect(
      () => cursor.acceptEvent(epoch: '', sequence: 11),
      throwsFormatException,
    );
    expect(
      () => cursor.acceptEvent(epoch: 'boot-a', sequence: 0),
      throwsFormatException,
    );
    expect(cursor.sequence, 10);
  });
}
