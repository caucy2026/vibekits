import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_capacity_manager.dart';

void main() {
  test('one slot is atomically granted to only one of 100 commanders', () {
    final LmcpCapacityLeaseManager manager = LmcpCapacityLeaseManager(
      capacity: 1,
    );
    addTearDown(manager.dispose);

    int granted = 0;
    int busy = 0;
    for (int index = 0; index < 100; index++) {
      try {
        manager.reserve(
          toolName: 'kemi.benchmark.run',
          idempotencyKey: 'task-$index',
          commanderId: 'commander-$index',
          requestedSlots: 1,
          ttlSeconds: 45,
          scopeDigest: 'scope-$index',
          callerInstanceId: 'commander-$index',
        );
        granted++;
      } on LmcpCapacityException catch (error) {
        expect(error.code, 'CAPACITY_BUSY');
        busy++;
      }
    }
    expect(granted, 1);
    expect(busy, 99);
    expect(manager.runtime.availableSlots, 0);
  });

  test('reserve is idempotent and release never exposes token in status', () {
    final LmcpCapacityLeaseManager manager = LmcpCapacityLeaseManager(
      capacity: 2,
    );
    addTearDown(manager.dispose);
    Map<String, Object?> reserve() => manager.reserve(
      toolName: 'kemi.files.send',
      idempotencyKey: 'send-001',
      commanderId: 'com.vibekits.desktop:ABC',
      requestedSlots: 1,
      ttlSeconds: 45,
      scopeDigest: 'sha256:scope',
      callerInstanceId: 'com.vibekits.desktop:ABC',
    );

    final Map<String, Object?> first = reserve();
    final Map<String, Object?> second = reserve();
    expect(second['leaseId'], first['leaseId']);
    expect(second['leaseToken'], first['leaseToken']);
    expect(manager.activeLeaseCount, 1);
    expect(
      manager.status().toString(),
      isNot(contains('${first['leaseToken']}')),
    );

    manager.validateScheduledCall(
      leaseId: '${first['leaseId']}',
      leaseToken: '${first['leaseToken']}',
      toolName: 'kemi.files.send',
      idempotencyKey: 'send-001',
      callerInstanceId: 'com.vibekits.desktop:ABC',
    );
    manager.release(
      leaseId: '${first['leaseId']}',
      leaseToken: '${first['leaseToken']}',
      callerInstanceId: 'com.vibekits.desktop:ABC',
      reason: 'completed',
    );
    expect(manager.runtime.availableSlots, 2);
  });

  test('wrong caller or token cannot use a lease', () {
    final LmcpCapacityLeaseManager manager = LmcpCapacityLeaseManager(
      capacity: 1,
    );
    addTearDown(manager.dispose);
    final Map<String, Object?> lease = manager.reserve(
      toolName: 'tool.run',
      idempotencyKey: 'idempotent',
      commanderId: 'caller-a',
      requestedSlots: 1,
      ttlSeconds: 45,
      scopeDigest: 'scope',
      callerInstanceId: 'caller-a',
    );

    expect(
      () => manager.validateScheduledCall(
        leaseId: '${lease['leaseId']}',
        leaseToken: 'wrong',
        toolName: 'tool.run',
        idempotencyKey: 'idempotent',
        callerInstanceId: 'caller-b',
      ),
      throwsA(
        isA<LmcpCapacityException>().having(
          (LmcpCapacityException error) => error.code,
          'code',
          'LEASE_SCOPE_MISMATCH',
        ),
      ),
    );
  });
}
