import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_work_status.dart';

void main() {
  test('旧 publish/latest/changes API 保持兼容并同步 registry', () async {
    final int beforeSequence =
        HarnessWorkStatusHub.registryLatest.streamSequence;
    final Future<HarnessWorkSnapshot> changed =
        HarnessWorkStatusHub.changes.first;
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.runningTool,
      message: '正在执行 ADB',
      toolId: 'vibekits.adb.command',
      toolName: 'ADB 命令',
      target:
          '/Users/private/project https://example.test/a?token=raw '
          'token=secret-value authorization: bearer-value',
    );

    final HarnessWorkSnapshot snapshot = await changed;
    expect(snapshot.phase, HarnessWorkPhase.runningTool);
    expect(snapshot.busy, isTrue);
    expect(snapshot.target, isNot(contains('/Users/private')));
    expect(snapshot.target, isNot(contains('example.test')));
    expect(snapshot.target, isNot(contains('secret-value')));
    expect(snapshot.target, isNot(contains('bearer-value')));
    expect(snapshot.toJson()['toolId'], 'vibekits.adb.command');
    expect(HarnessWorkStatusHub.latest, same(snapshot));
    expect(
      HarnessWorkStatusHub.registryLatest.streamSequence,
      greaterThan(beforeSequence),
    );
    expect(
      HarnessWorkStatusHub.registryLatest.tasks.first.phase,
      HarnessWorkPhase.toolRunning,
    );
  });

  test('工作区上下文把兼容工具状态登记为真实项目且不生成全局行', () {
    final HarnessWorkspaceStatusContext context =
        HarnessWorkStatusHub.activateWorkspace(
          workspaceRef: '/Volumes/private/repository/vibekits',
          workspaceLabel: 'vibekits',
          sessionRef: 'vibekits-harness-test',
        );
    try {
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.starting,
        message: '正在启动本地 Harness',
      );
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.ready,
        message: 'Harness 已就绪',
      );
      HarnessWorkStatusHub.publish(
        phase: HarnessWorkPhase.toolRunning,
        message: '正在执行 MCP 目录刷新',
        toolId: 'vibekits.mcp.catalog_list',
        toolName: 'MCP 目录刷新',
      );

      final HarnessTaskSnapshot task =
          HarnessWorkStatusHub.registryLatest.tasks.first;
      expect(task.workspaceLabel, 'vibekits');
      expect(task.workspaceRef, startsWith('workspace-'));
      expect(task.workspaceRef, isNot(contains('/Volumes/private')));
      expect(task.sessionRef, 'vibekits-harness-test');
      expect(task.phase, HarnessWorkPhase.toolRunning);
      expect(task.toolId, 'vibekits.mcp.catalog_list');
      expect(task.workspaceRef, isNot('legacy-workspace'));
    } finally {
      HarnessWorkStatusHub.clearWorkspace(context);
    }
  });

  test('DSH 工作区清单逐项目同步、重命名并移除过期项目', () {
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry();
    registry.syncWorkspaceInventory(const <HarnessWorkspaceSummary>[
      HarnessWorkspaceSummary(
        workspaceRef: 'dsh-workspace:rustdesk',
        label: 'rustdesk',
        active: true,
      ),
      HarnessWorkspaceSummary(
        workspaceRef: 'dsh-workspace:vibekits',
        label: 'vibekits',
      ),
    ]);
    expect(registry.latest.tasks, hasLength(2));
    expect(
      registry.latest.tasks
          .firstWhere(
            (HarnessTaskSnapshot task) => task.workspaceLabel == 'rustdesk',
          )
          .phase,
      HarnessWorkPhase.ready,
    );

    registry.syncWorkspaceInventory(const <HarnessWorkspaceSummary>[
      HarnessWorkspaceSummary(
        workspaceRef: 'dsh-workspace:vibekits-new',
        label: 'vibekits-new',
        active: true,
      ),
    ]);
    expect(registry.latest.tasks, hasLength(1));
    expect(registry.latest.tasks.single.workspaceLabel, 'vibekits-new');
    expect(registry.latest.tasks.single.phase, HarnessWorkPhase.ready);
  });

  test('并行任务使用全局 sequence 和各自 task revision', () {
    final _MutableClock clock = _MutableClock();
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry(
      clock: clock.now,
    );

    final HarnessTaskSnapshot first = registry.beginTask(
      workspaceRef: 'workspace-a',
      sessionRef: 'session-a',
      taskId: 'task-a',
      phase: HarnessWorkPhase.queued,
      message: '任务 A 已排队',
    );
    clock.tick();
    final HarnessTaskSnapshot second = registry.beginTask(
      workspaceRef: 'workspace-b',
      sessionRef: 'session-b',
      taskId: 'task-b',
      phase: HarnessWorkPhase.waitingApproval,
      message: '任务 B 等待批准',
    );
    clock.tick();
    final HarnessTaskSnapshot updated = registry.updateTask(
      key: first.key,
      phase: HarnessWorkPhase.planning,
      message: '任务 A 规划中',
    );

    expect(first.streamSequence, 1);
    expect(second.streamSequence, 2);
    expect(updated.streamSequence, 3);
    expect(first.taskRevision, 1);
    expect(second.taskRevision, 1);
    expect(updated.taskRevision, 2);
    expect(registry.latest.aggregate.taskCount, 2);
    expect(registry.latest.aggregate.busyCount, 2);
    expect(registry.latest.aggregate.waitingApprovalCount, 1);
    expect(registry.latest.tasks.first.taskId, 'task-a');
  });

  test('完整阶段链合法且终态不能回到运行态', () {
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry();
    HarnessTaskSnapshot task = registry.beginTask(
      workspaceRef: 'workspace',
      sessionRef: 'session',
      taskId: 'strict-task',
      phase: HarnessWorkPhase.starting,
    );
    for (final HarnessWorkPhase phase in <HarnessWorkPhase>[
      HarnessWorkPhase.ready,
      HarnessWorkPhase.queued,
      HarnessWorkPhase.planning,
      HarnessWorkPhase.reasoning,
      HarnessWorkPhase.waitingApproval,
      HarnessWorkPhase.invokingTool,
      HarnessWorkPhase.toolRunning,
      HarnessWorkPhase.synthesizing,
    ]) {
      task = registry.updateTask(key: task.key, phase: phase);
    }
    task = registry.finishTask(
      key: task.key,
      phase: HarnessWorkPhase.completed,
      message: '完成',
    );

    expect(task.taskRevision, 10);
    expect(task.terminal, isTrue);
    expect(
      () =>
          registry.updateTask(key: task.key, phase: HarnessWorkPhase.reasoning),
      throwsStateError,
    );
    expect(
      () => registry.beginTask(
        workspaceRef: 'workspace',
        sessionRef: 'session',
        taskId: 'strict-task',
      ),
      throwsStateError,
    );
    expect(
      () => registry.finishTask(key: task.key, phase: HarnessWorkPhase.ready),
      throwsArgumentError,
    );
  });

  test('非法阶段跳转不改变 sequence 或 revision', () {
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry();
    final HarnessTaskSnapshot task = registry.beginTask(
      workspaceRef: 'workspace',
      sessionRef: 'session',
      taskId: 'invalid-transition',
      phase: HarnessWorkPhase.starting,
    );

    expect(
      () => registry.updateTask(
        key: task.key,
        phase: HarnessWorkPhase.toolRunning,
      ),
      throwsStateError,
    );
    expect(registry.streamSequence, 1);
    expect(registry.latest.tasks.single.taskRevision, 1);
  });

  test('应用重启把旧运行任务标记 interrupted 并延续全局序号', () {
    final HarnessTaskStateRegistry before = HarnessTaskStateRegistry();
    final HarnessTaskSnapshot failed = before.beginTask(
      workspaceRef: 'workspace',
      sessionRef: 'session',
      taskId: 'failed-task',
    );
    before.finishTask(
      key: failed.key,
      phase: HarnessWorkPhase.failed,
      message: '失败',
    );
    before.beginTask(
      workspaceRef: 'workspace',
      sessionRef: 'session',
      taskId: 'active-task',
      phase: HarnessWorkPhase.toolRunning,
    );
    final int previousSequence = before.streamSequence;

    final HarnessTaskStateRegistry after = HarnessTaskStateRegistry();
    after.restoreAfterRestart(
      before.latest.tasks,
      afterStreamSequence: previousSequence,
    );

    final Map<String, HarnessTaskSnapshot> tasks =
        <String, HarnessTaskSnapshot>{
          for (final HarnessTaskSnapshot task in after.latest.tasks)
            task.taskId: task,
        };
    expect(after.streamSequence, greaterThan(previousSequence));
    expect(tasks['active-task']!.phase, HarnessWorkPhase.interrupted);
    expect(tasks['active-task']!.taskRevision, 2);
    expect(tasks['failed-task']!.phase, HarnessWorkPhase.failed);
    expect(tasks['failed-task']!.taskRevision, 2);
  });

  test('公开字段脱敏、引用去路径化并满足单任务 4 KiB 上限', () {
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry();
    final HarnessTaskSnapshot task = registry.beginTask(
      deviceRef: '/private/device/id',
      workspaceRef: r'C:\customers\secret-project',
      workspaceLabel: '客户 /Users/alice/project token=workspace-secret',
      sessionRef: '/private/session/one',
      taskId: 'public-task',
      phase: HarnessWorkPhase.toolRunning,
      message:
          '读取 /Users/alice/project/private.txt '
          'Authorization: Bearer message-secret ${'进度' * 300}',
      toolId: 'vibekits.git.read_remote_file',
      toolName: '读取远端文件',
      target:
          'https://user:pass@example.test/repo?api_key=url-secret '
          r'C:\customers\secret-project\private.txt '
          '--password cli-secret',
      progress: const HarnessWorkProgress(
        current: 12,
        total: 10,
        unit: 'files',
      ),
    );
    final String encoded = jsonEncode(task.toJson());

    expect(task.deviceRef, startsWith('device-'));
    expect(task.workspaceRef, startsWith('workspace-'));
    expect(task.sessionRef, startsWith('session-'));
    expect(encoded, isNot(contains('alice')));
    expect(encoded, isNot(contains('example.test')));
    expect(encoded, isNot(contains('message-secret')));
    expect(encoded, isNot(contains('url-secret')));
    expect(encoded, isNot(contains('cli-secret')));
    expect(task.progress!.current, 10);
    expect(
      utf8.encode(encoded).length,
      lessThanOrEqualTo(HarnessTaskStateRegistry.maxTaskSnapshotBytes),
    );
  });

  test('设备快照超限时保留聚合和最新任务而不是无界增长', () {
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry(
      maxSnapshotBytes: HarnessTaskStateRegistry.maxTaskSnapshotBytes,
    );
    for (int index = 0; index < 20; index += 1) {
      registry.beginTask(
        workspaceRef: 'workspace-$index',
        workspaceLabel: '工作区 ${'名' * 100}',
        sessionRef: 'session-$index',
        taskId: 'task-$index',
        phase: HarnessWorkPhase.reasoning,
        message: '正在推理 ${'状态' * 100}',
        target: 'Android 设备 ${'目标' * 100}',
      );
    }

    expect(registry.latest.aggregate.taskCount, 20);
    expect(registry.latest.aggregate.busyCount, 20);
    expect(registry.latest.tasks, isNotEmpty);
    expect(registry.latest.tasks.first.taskId, 'task-19');
    expect(registry.latest.tasks.length, lessThan(20));
    expect(
      registry.latest.encodedByteLength,
      lessThanOrEqualTo(HarnessTaskStateRegistry.maxTaskSnapshotBytes),
    );
  });

  test('registry change stream 发布最新完整快照', () async {
    final HarnessTaskStateRegistry registry = HarnessTaskStateRegistry();
    final Future<HarnessWorkRegistrySnapshot> changed = registry.changes.first;
    registry.beginTask(
      workspaceRef: 'workspace',
      sessionRef: 'session',
      taskId: 'stream-task',
    );

    final HarnessWorkRegistrySnapshot snapshot = await changed;
    expect(snapshot.streamSequence, 1);
    expect(snapshot.tasks.single.taskId, 'stream-task');
    expect(snapshot.toJson()['schema'], HarnessWorkRegistrySnapshot.schema);
  });
}

class _MutableClock {
  DateTime _value = DateTime.utc(2026, 8, 30, 1);

  DateTime now() => _value;

  void tick() {
    _value = _value.add(const Duration(seconds: 1));
  }
}
