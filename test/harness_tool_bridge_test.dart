import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vibekits/features/dev_tools/domain/adb_server_endpoint.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_work_status.dart';
import 'package:vibekits/features/dev_tools/domain/remote_connection_record.dart';
import 'package:vibekits/features/dev_tools/domain/remote_connection_status.dart';
import 'package:vibekits/features/dev_tools/domain/remote_database_service.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';
import 'package:vibekits/features/dev_tools/domain/sftp_service.dart';
import 'package:vibekits/features/dev_tools/domain/sqlite_database_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';
import 'package:vibekits/features/dev_tools/domain/windows_node_device_service.dart';

void main() {
  test('Harness 可见参数和结果摘要保留工程细节且脱敏凭据', () {
    final String summary = HarnessToolActivityStore.summarizeForDisplay(
      <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
        'apiKey': 'must-not-leak',
        'nested': <String, Object?>{
          'password': 'also-secret',
          'result': 'KEMI-E668',
        },
      },
    );

    expect(summary, contains('192.168.3.63:5555'));
    expect(summary, contains('ro.product.model'));
    expect(summary, contains('KEMI-E668'));
    expect(summary, contains('<已隐藏>'));
    expect(summary, isNot(contains('must-not-leak')));
    expect(summary, isNot(contains('also-secret')));
  });

  test('Harness 编排中的工具结束后回到 reasoning 而不是误报 ready', () async {
    final Completer<void> release = Completer<void>();
    const String workspaceRef = 'test-agent-orchestrated-workspace';
    final HarnessWorkspaceStatusContext context =
        HarnessWorkStatusHub.activateWorkspace(
          workspaceRef: workspaceRef,
          workspaceLabel: '编排项目',
          sessionRef: 'test-session',
        );
    addTearDown(() => HarnessWorkStatusHub.clearWorkspace(context));
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      agentOrchestrated: true,
      handlers: <String, HarnessToolHandler>{
        'vibekits.file_hash': (_) async {
          await release.future;
          return <String, Object?>{'digest': 'test'};
        },
      },
    );

    final Future<HarnessToolCallResult> pending = bridge.invoke(
      toolId: 'vibekits.file_hash',
      arguments: const <String, Object?>{'input': '/tmp/test'},
      approve: (_) async => true,
    );
    await Future<void>.delayed(Duration.zero);
    HarnessTaskSnapshot task = HarnessWorkStatusHub.registryLatest.tasks
        .lastWhere(
          (HarnessTaskSnapshot value) => value.key.workspaceRef == workspaceRef,
        );
    expect(task.phase, HarnessWorkPhase.toolRunning);
    expect(task.busy, isTrue);

    release.complete();
    expect((await pending).ok, isTrue);
    task = HarnessWorkStatusHub.registryLatest.tasks.lastWhere(
      (HarnessTaskSnapshot value) => value.key.workspaceRef == workspaceRef,
    );
    expect(task.phase, HarnessWorkPhase.reasoning);
    expect(task.busy, isTrue);
    expect(task.message, contains('继续分析'));
  });

  test('Harness 结束后的迟到工具结果不得覆盖 ready 终态', () async {
    final Completer<void> release = Completer<void>();
    bool agentActive = true;
    const String workspaceRef = 'test-agent-late-tool-workspace';
    final HarnessWorkspaceStatusContext context =
        HarnessWorkStatusHub.activateWorkspace(
          workspaceRef: workspaceRef,
          workspaceLabel: '迟到工具项目',
          sessionRef: 'late-tool-session',
        );
    addTearDown(() => HarnessWorkStatusHub.clearWorkspace(context));
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      agentOrchestrated: true,
      agentActive: () => agentActive,
      handlers: <String, HarnessToolHandler>{
        'vibekits.file_hash': (_) async {
          await release.future;
          return <String, Object?>{'digest': 'late'};
        },
      },
    );

    final Future<HarnessToolCallResult> pending = bridge.invoke(
      toolId: 'vibekits.file_hash',
      arguments: const <String, Object?>{'input': '/tmp/late'},
      approve: (_) async => true,
    );
    await Future<void>.delayed(Duration.zero);
    agentActive = false;
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.ready,
      message: 'Harness 任务完成，工作区就绪',
    );
    final int terminalSequence =
        HarnessWorkStatusHub.registryLatest.streamSequence;

    release.complete();
    expect((await pending).ok, isTrue);
    final HarnessTaskSnapshot task = HarnessWorkStatusHub.registryLatest.tasks
        .lastWhere(
          (HarnessTaskSnapshot value) => value.key.workspaceRef == workspaceRef,
        );
    expect(task.phase, HarnessWorkPhase.ready);
    expect(task.message, contains('工作区就绪'));
    expect(
      HarnessWorkStatusHub.registryLatest.streamSequence,
      terminalSequence,
    );
  });

  test('Harness 停止时清理并验证任务启动的 Android 应用', () async {
    final List<List<String>> adbCalls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      agentOrchestrated: true,
      agentActive: () => true,
      adbExecutable: '/test/adb',
      adbRunner: (String executable, List<String> arguments) async {
        adbCalls.add(List<String>.of(arguments));
        if (arguments.contains('pidof')) {
          return const AdbCommandResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const AdbCommandResult(exitCode: 0, stdout: 'ok', stderr: '');
      },
    );

    final HarnessToolCallResult launched = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbShellId,
      arguments: const <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>[
          'am',
          'start',
          '--display',
          '0',
          '-n',
          'com.kemi.whackamole/.MainActivity',
        ],
      },
      approve: (_) async => true,
    );
    expect(launched.ok, isTrue);
    expect(launched.data?['agentOwnedActivity'], isA<Map<String, Object?>>());

    final List<Map<String, Object?>> cleaned = await bridge
        .stopAgentOwnedActivities();

    expect(cleaned, hasLength(1));
    expect(cleaned.single['package'], 'com.kemi.whackamole');
    expect(cleaned.single['stopped'], isTrue);
    expect(cleaned.single['verified'], isTrue);
    expect(
      adbCalls.any(
        (List<String> call) =>
            call.join(' ') ==
            '-s 192.168.3.63:5555 shell am force-stop com.kemi.whackamole',
      ),
      isTrue,
    );
    expect(
      adbCalls.any(
        (List<String> call) =>
            call.join(' ') ==
            '-s 192.168.3.63:5555 shell pidof com.kemi.whackamole',
      ),
      isTrue,
    );
  });

  test('Harness 可查看并经写权限审批人工评价 MCP 全局信誉', () async {
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      mcpReputationLoader: () async => <String, Object?>{
        'tierOrder': <String>['app', 'local', 'lan'],
        'entries': <Object?>[],
      },
      mcpReputationRater:
          (String tier, String instanceId, String toolName, int rating) async =>
              <String, Object?>{
                'tier': tier,
                'instanceId': '*',
                'toolName': toolName,
                'manualRating': rating,
                'scope': 'global-tool-type',
              },
    );

    final HarnessToolCallResult listed = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.mcpReputationListId,
      arguments: const <String, Object?>{},
      approve: (_) async {
        approvals++;
        return true;
      },
    );
    expect(listed.ok, isTrue);
    expect(approvals, 0);

    final HarnessToolCallResult rated = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.mcpReputationRateId,
      arguments: const <String, Object?>{
        'tier': 'lan',
        'instanceId': 'kemi-device-a',
        'toolName': 'kemi.files.send',
        'rating': 0,
      },
      approve: (HarnessToolApprovalRequest request) async {
        approvals++;
        expect(request.tool.risk, HarnessToolRisk.writesData);
        expect(request.target, contains('kemi.files.send'));
        return true;
      },
    );
    expect(rated.ok, isTrue);
    expect(approvals, 1);
    expect(rated.data?['manualRating'], 0);
    expect(rated.data?['scope'], 'global-tool-type');
  });

  test('Harness 可读取完整 MCP 目录并经审批调用局域网工具', () async {
    int approvals = 0;
    Map<String, Object?>? routedArguments;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      mcpCatalogLoader: () async => <String, Object?>{
        'tiers': <String, Object?>{
          'lan': <Object?>[
            <String, Object?>{
              'instanceId': 'org.kemi.send:TEST',
              'callable': true,
              'tools': <Object?>[
                <String, Object?>{'name': 'kemi.files.send'},
              ],
            },
          ],
        },
      },
      mcpToolInvoker:
          (
            String instanceId,
            String toolName,
            Map<String, Object?> arguments,
          ) async {
            expect(instanceId, 'org.kemi.send:TEST');
            expect(toolName, 'kemi.files.send');
            routedArguments = arguments;
            return <String, Object?>{
              'instanceId': instanceId,
              'tool': toolName,
              'ok': true,
            };
          },
    );

    final HarnessToolCallResult catalog = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.mcpCatalogListId,
      arguments: const <String, Object?>{},
      approve: (_) async {
        approvals++;
        return true;
      },
    );
    expect(catalog.ok, isTrue);
    expect(approvals, 0);

    final HarnessToolCallResult call = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.mcpToolCallId,
      arguments: const <String, Object?>{
        'instanceId': 'org.kemi.send:TEST',
        'toolName': 'kemi.files.send',
        'arguments': <String, Object?>{
          'sourcePath': '/tmp/harmless.txt',
          'targetDeviceId': 'receiver',
        },
      },
      approve: (HarnessToolApprovalRequest request) async {
        approvals++;
        expect(request.tool.risk, HarnessToolRisk.controlsDevice);
        expect(request.target, contains('org.kemi.send:TEST'));
        return true;
      },
    );
    expect(call.ok, isTrue);
    expect(approvals, 1);
    expect(routedArguments?['sourcePath'], '/tmp/harmless.txt');
  });

  test('Harness 自动 MCP 工具透传调度参数并返回业务终态', () async {
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      mcpAutoInvoker:
          (
            toolName,
            taskId,
            idempotencyKey,
            scopeDigest,
            arguments,
            requestedSlots,
            ttlSeconds,
          ) async {
            expect(toolName, 'kemi.benchmark.run');
            expect(taskId, 'stability-62');
            expect(idempotencyKey, 'stability-62-run-1');
            expect(scopeDigest, 'sha256:read-only-benchmark');
            expect(arguments, const <String, Object?>{'mode': 'quick'});
            expect(requestedSlots, 1);
            expect(ttlSeconds, 45);
            return <String, Object?>{
              'ok': true,
              'selected': const <String, Object?>{
                'instanceId': 'com.newlink.kemiscrollbench:41B8C7FDF4',
              },
              'result': const <String, Object?>{
                'structuredContent': <String, Object?>{
                  'final': true,
                  'grade': 'S',
                },
              },
            };
          },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.mcpAutoCallId,
      arguments: const <String, Object?>{
        'toolName': 'kemi.benchmark.run',
        'taskId': 'stability-62',
        'idempotencyKey': 'stability-62-run-1',
        'scopeDigest': 'sha256:read-only-benchmark',
        'arguments': <String, Object?>{'mode': 'quick'},
      },
      approve: (_) async {
        approvals++;
        return true;
      },
    );

    expect(approvals, 1);
    expect(result.ok, isTrue);
    expect(
      ((result.data?['result'] as Map)['structuredContent'] as Map)['grade'],
      'S',
    );
  });

  test('移动端保留完整工具目录并明确桌面节点边界', () {
    expect(
      VibekitsHarnessToolBridge.requiresDesktopNode(
        VibekitsHarnessToolBridge.adbCommandId,
      ),
      isTrue,
    );
    expect(
      VibekitsHarnessToolBridge.requiresDesktopNode(
        VibekitsHarnessToolBridge.serialTransactId,
      ),
      isTrue,
    );
    expect(
      VibekitsHarnessToolBridge.requiresDesktopNode(
        VibekitsHarnessToolBridge.fileDiffId,
      ),
      isFalse,
    );
    expect(
      VibekitsHarnessToolBridge.requiresDesktopNode(
        VibekitsHarnessToolBridge.remoteSshExecId,
      ),
      isFalse,
    );
    expect(
      VibekitsHarnessToolBridge.requiresDesktopNode(
        VibekitsHarnessToolBridge.remoteDatabaseQueryId,
      ),
      isFalse,
    );
  });

  test('导出版本化可执行工具目录且不暴露未接工具', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Map<String, Object?> catalog = bridge.exportCatalog();
    expect(catalog['protocol'], VibekitsHarnessToolBridge.protocolVersion);
    final List<dynamic> tools = catalog['tools']! as List<dynamic>;
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.sha256'),
      isTrue,
    );
    final dynamic jsonQuery = tools.firstWhere(
      (dynamic tool) => tool['id'] == 'vibekits.json_query',
    );
    expect(jsonQuery['description'], contains('本地优先'));
    expect(jsonQuery['description'], contains('适合：'));
    expect(
      tools.any(
        (dynamic tool) => tool['id'] == 'vibekits.code_structure_search',
      ),
      isTrue,
    );
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.safe_benchmark'),
      isTrue,
    );
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.database_manager'),
      isFalse,
    );
    expect(
      tools.any(
        (dynamic tool) =>
            tool['id'] == VibekitsHarnessToolBridge.adbListDevicesId,
      ),
      isTrue,
    );
    for (final String id in <String>[
      VibekitsHarnessToolBridge.adbCommandId,
      VibekitsHarnessToolBridge.serialListPortsId,
      VibekitsHarnessToolBridge.serialTransactId,
      VibekitsHarnessToolBridge.sqliteInspectId,
      VibekitsHarnessToolBridge.sqliteQueryId,
      VibekitsHarnessToolBridge.gitInspectId,
      VibekitsHarnessToolBridge.gitListRemoteRefsId,
      VibekitsHarnessToolBridge.gitReadRemoteFileId,
      VibekitsHarnessToolBridge.gitCloneMinimalId,
      VibekitsHarnessToolBridge.gitCompareRefsId,
      VibekitsHarnessToolBridge.gitCreateLocalBranchId,
      VibekitsHarnessToolBridge.gitBackupPreviewId,
      VibekitsHarnessToolBridge.gitBackupCommitId,
      VibekitsHarnessToolBridge.gitBackupPushId,
      VibekitsHarnessToolBridge.gitVerifyRemoteRefId,
      VibekitsHarnessToolBridge.fileSearchId,
      VibekitsHarnessToolBridge.apiRequestId,
      VibekitsHarnessToolBridge.networkDownloadId,
      VibekitsHarnessToolBridge.githubDiagnosticsId,
      VibekitsHarnessToolBridge.githubProxyCandidatesId,
      VibekitsHarnessToolBridge.githubProxyPlanId,
      VibekitsHarnessToolBridge.githubProxyApplyId,
      VibekitsHarnessToolBridge.githubProxyRollbackId,
      VibekitsHarnessToolBridge.windowsNodeInspectId,
      VibekitsHarnessToolBridge.windowsNodeHelperStatusId,
      VibekitsHarnessToolBridge.windowsNodePlanId,
      VibekitsHarnessToolBridge.windowsNodeListDevicesId,
      VibekitsHarnessToolBridge.windowsNodeExportOnboardingId,
      VibekitsHarnessToolBridge.programmerCalculatorId,
      VibekitsHarnessToolBridge.remoteListProfilesId,
      VibekitsHarnessToolBridge.remoteSshExecId,
      VibekitsHarnessToolBridge.remoteSftpListId,
      VibekitsHarnessToolBridge.remoteSftpUploadId,
      VibekitsHarnessToolBridge.remoteSftpDownloadId,
      VibekitsHarnessToolBridge.remoteDatabaseListProfilesId,
      VibekitsHarnessToolBridge.remoteDatabaseInspectId,
      VibekitsHarnessToolBridge.remoteDatabaseQueryId,
      VibekitsHarnessToolBridge.duplicateScanId,
      VibekitsHarnessToolBridge.fileDiffId,
      VibekitsHarnessToolBridge.systemDriveAnalyzeId,
      VibekitsHarnessToolBridge.systemDriveAnalyzeStartId,
      VibekitsHarnessToolBridge.systemDriveAnalyzeStatusId,
      VibekitsHarnessToolBridge.systemDriveAnalyzeCancelId,
      VibekitsHarnessToolBridge.audioInspectId,
      VibekitsHarnessToolBridge.audioPcmToWavId,
      VibekitsHarnessToolBridge.audioPlayId,
      VibekitsHarnessToolBridge.audioPauseId,
      VibekitsHarnessToolBridge.audioStopId,
      VibekitsHarnessToolBridge.audioGenerateToneId,
      VibekitsHarnessToolBridge.systemResourcesId,
      VibekitsHarnessToolBridge.harnessDiagnosticsId,
    ]) {
      expect(tools.any((dynamic tool) => tool['id'] == id), isTrue, reason: id);
    }
    final Set<String> fullIds = bridge.fullCatalog
        .map((HarnessToolDefinition tool) => tool.id)
        .toSet();
    for (final String id in <String>[
      VibekitsHarnessToolBridge.windowsNodeApplyId,
      VibekitsHarnessToolBridge.windowsNodeVerifyId,
      VibekitsHarnessToolBridge.windowsNodeEnrollDeviceId,
      VibekitsHarnessToolBridge.windowsNodeRevokeDeviceId,
      VibekitsHarnessToolBridge.windowsNodeRollbackId,
      VibekitsHarnessToolBridge.windowsNodeEnsureClientIdentityId,
    ]) {
      expect(fullIds, contains(id));
      expect(tools.any((dynamic tool) => tool['id'] == id), isFalse);
    }
  });

  test('开发工具左侧每个入口都有至少一个 Harness 可执行适配器', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Set<String> declared = bridge.fullCatalog
        .map((HarnessToolDefinition tool) => tool.id)
        .toSet();
    final Set<String> executable = bridge.executableCatalog
        .map((HarnessToolDefinition tool) => tool.id)
        .toSet();
    for (final ToolSpec workspace in devToolRegistry) {
      final Set<String> toolIds = harnessToolIdsFor(workspace);
      expect(
        toolIds.every(declared.contains),
        isTrue,
        reason: '${workspace.id} 存在未进入 Harness 完整目录的声明',
      );
      expect(
        toolIds.any(executable.contains),
        isTrue,
        reason: '${workspace.id} 没有当前环境可执行的 Harness 适配器',
      );
    }
  });

  test('每个独立开发工具都有完整重复使用合同', () {
    for (final ToolSpec workspace in devToolRegistry) {
      expect(
        devToolUsageContracts.containsKey(workspace.id),
        isTrue,
        reason: '${workspace.id} 缺少重复使用、多目标与秘密处理合同',
      );
    }
  });

  test('智能体能力自检保证所有公开工具都有本地执行器', () async {
    final Directory runtime = Directory.systemTemp.createTempSync(
      'vibekits_capability_runtime_',
    );
    addTearDown(() => runtime.deleteSync(recursive: true));
    final File adb = File('${runtime.path}${Platform.pathSeparator}adb')
      ..writeAsStringSync('test adb runtime');
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: adb.path,
    );
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.capabilityCheckId,
      arguments: const <String, Object?>{},
      approve: (_) async {
        approvals += 1;
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(result.data?['ready'], isTrue);
    expect(result.data?['missingHandlers'], isEmpty);
    expect(result.data?['missingRuntimes'], isEmpty);
    expect(result.data?['executableTools'], greaterThan(50));
    expect(result.data?['unavailableTools'], isNotEmpty);
    final Map<String, Object?> productHierarchy =
        (result.data?['productHierarchy'] as Map).cast<String, Object?>();
    expect(productHierarchy['topLevelPageCount'], 5);
    expect(productHierarchy['topLevelPages'], hasLength(5));
    expect(
      productHierarchy['developerCapabilityEntries'],
      allDevToolRegistry.length,
    );
    expect(
      productHierarchy['independentDeveloperWorkspaces'],
      devToolRegistry.length,
    );
    final Map<String, Object?> platform = (result.data?['platform'] as Map)
        .cast<String, Object?>();
    final Map<String, Object?> storage = (platform['storageLocations'] as Map)
        .cast<String, Object?>();
    final Map<String, Object?> cleanup = (platform['cleanup'] as Map)
        .cast<String, Object?>();
    expect(storage['settings'], isNotEmpty);
    expect(storage['credentials'], isNotEmpty);
    expect(cleanup['platform'], Platform.operatingSystem);
    expect(cleanup['scanScope'], isNotEmpty);
    expect(approvals, 0);
  });

  test('智能体能力自检不会把缺少 ADB 的安装包报告为 ready', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable:
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'definitely-missing-vibekits-adb',
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.capabilityCheckId,
      arguments: const <String, Object?>{},
      approve: (_) async => true,
    );

    expect(result.ok, isTrue);
    expect(result.data?['ready'], isFalse);
    expect(
      result.data?['missingRuntimes'],
      contains(
        isA<Map<String, Object?>>().having(
          (Map<String, Object?> value) => value['id'],
          'id',
          'android-platform-tools-adb',
        ),
      ),
    );
  });

  test('Harness 可列出节点设备并导出不含秘密的 onboarding', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vk_harness_node_devices_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      windowsNodeDeviceService: WindowsNodeDeviceService(directory: directory),
    );
    int approvals = 0;
    Future<bool> approve(HarnessToolApprovalRequest _) async {
      approvals++;
      return true;
    }

    final HarnessToolCallResult listed = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.windowsNodeListDevicesId,
      arguments: const <String, Object?>{},
      approve: approve,
    );
    expect(listed.ok, isTrue);
    expect(listed.data!['devices'], isEmpty);

    final HarnessToolCallResult onboarding = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.windowsNodeExportOnboardingId,
      arguments: const <String, Object?>{
        'host': '192.168.3.10',
        'port': 22,
        'hostKeyFingerprint': 'SHA256:verified-host-key',
        'allowedCidr': '192.168.3.0/24',
      },
      approve: approve,
    );
    expect(onboarding.ok, isTrue);
    expect(
      onboarding.data!['sshConfig'],
      contains('StrictHostKeyChecking yes'),
    );
    expect(
      onboarding.data.toString().toLowerCase(),
      isNot(contains('privatekey')),
    );
    expect(approvals, 0, reason: '两个工具都只读且不导出秘密');
  });

  test('只读文本工具无需审批并返回结构化结果', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.sha256',
      arguments: <String, Object?>{'input': 'abc'},
      approve: (_) async {
        approvals++;
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(approvals, 0);
    expect(
      result.data?['output'],
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test(
    'Harness 真实调用本机资源探针并返回采样汇总',
    () async {
      final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
      int approvals = 0;
      final HarnessToolCallResult result = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.systemResourcesId,
        arguments: const <String, Object?>{'samples': 1},
        approve: (_) async {
          approvals += 1;
          return true;
        },
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(result.data!['platform'], 'windows');
      expect((result.data!['summary']! as Map)['samples'], 1);
      expect(result.data!['series'], isNotEmpty);
      expect(approvals, 0, reason: '资源探针是只读工具');
    },
    skip: !Platform.isWindows,
    // A cold Windows runner can spend the service's full 12-second bounded
    // probe budget starting PowerShell/WMI before Flutter test overhead. Keep
    // the product timeout strict while giving CI enough orchestration margin.
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('新增微工具由能力清单自动进入 Harness 并可直接调用', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.json_query',
      arguments: <String, Object?>{
        'input': '{"items":[{"id":7}]}',
        'params': '.items[0].id',
      },
      approve: (_) async {
        approvals++;
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.data?['output'], '7');
    expect(approvals, 0);
  });

  test('Harness 自动调用代码结构搜索和安全性能基准', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits_harness_structure_',
    );
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}agent.dart',
    ).writeAsString('class ToolAgent {}\n');
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;

    final HarnessToolCallResult structure = await bridge.invoke(
      toolId: 'vibekits.code_structure_search',
      arguments: <String, Object?>{
        'input': root.path,
        'params': 'class|ToolAgent',
      },
      approve: (_) async {
        approvals++;
        return true;
      },
    );
    final HarnessToolCallResult benchmark = await bridge.invoke(
      toolId: 'vibekits.safe_benchmark',
      arguments: <String, Object?>{
        'input': '{"ok":true}',
        'params': 'json_parse|5',
      },
      approve: (_) async {
        approvals++;
        return true;
      },
    );

    expect(structure.ok, isTrue);
    expect(structure.data?['output'], contains('ToolAgent'));
    expect(benchmark.ok, isTrue);
    expect(benchmark.data?['output'], contains('"iterations": 5'));
    expect(approvals, 0);
  });

  test('Harness 工具完成后写入对应工具审计记录', () async {
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      activityRecorder:
          ({
            required String toolId,
            required String toolName,
            required String target,
            required Map<String, Object?> arguments,
            required Object? result,
            required HarnessToolActivityStatus status,
            required DateTime startedAt,
          }) async {
            records.add(<String, Object?>{
              'toolId': toolId,
              'toolName': toolName,
              'arguments': arguments,
              'result': result,
              'status': status,
            });
          },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.sha256',
      arguments: <String, Object?>{'input': 'abc'},
      approve: (_) async => true,
    );

    expect(result.ok, isTrue);
    expect(records, hasLength(1));
    expect(records.single['toolId'], 'vibekits.sha256');
    expect(records.single['status'], HarnessToolActivityStatus.succeeded);
  });

  test('ADB 连接先展示规范化目标并取得一次性批准', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: 'C:\\tools\\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        if (arguments.first == 'devices') {
          return const AdbCommandResult(
            exitCode: 0,
            stdout:
                'List of devices attached\n'
                '192.168.3.63:5555 device product:p model:m device:d transport_id:1\n',
            stderr: '',
          );
        }
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'connected to 192.168.3.63:5555',
          stderr: '',
        );
      },
    );
    HarnessToolApprovalRequest? approval;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbConnectId,
      arguments: <String, Object?>{'address': '192.168.3.63'},
      approve: (HarnessToolApprovalRequest request) async {
        approval = request;
        return true;
      },
    );
    expect(approval?.tool.risk, HarnessToolRisk.controlsDevice);
    expect(approval?.target, '192.168.3.63:5555');
    expect(calls, <List<String>>[
      <String>['connect', '192.168.3.63:5555'],
      <String>['devices', '-l'],
    ]);
    expect(result.ok, isTrue);
    expect(result.data?['verified'], isTrue);
  });

  test('拒绝高风险工具后不执行处理器', () async {
    int calls = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        'vibekits.batch_rename': (_) async {
          calls++;
          return <String, Object?>{};
        },
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.batch_rename',
      arguments: <String, Object?>{'input': 'D:\\project'},
      approve: (_) async => false,
    );
    expect(result.cancelled, isTrue);
    expect(calls, 0);
  });

  test('ADB 命令经过设备审批并使用固定可执行文件', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: r'C:\tools\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'Pixel_8',
          stderr: '',
        );
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbCommandId,
      arguments: <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
      },
      approve: (HarnessToolApprovalRequest request) async {
        expect(request.target, '192.168.3.63:5555');
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(calls.single, <String>[
      '-s',
      '192.168.3.63:5555',
      'shell',
      'getprop',
      'ro.product.model',
    ]);
  });

  test('Android Shell 自动拆分模型生成的多属性 getprop', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: '/tools/adb/adb',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(List<String>.of(arguments));
        return AdbCommandResult(
          exitCode: 0,
          stdout: arguments.last == 'ro.product.model'
              ? 'huanglong\n'
              : 'newlink\n',
          stderr: '',
        );
      },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbShellId,
      arguments: <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>[
          'getprop',
          'ro.product.model',
          'ro.product.manufacturer',
          'ro.build.version.release',
        ],
      },
      approve: (_) async => true,
    );

    expect(result.ok, isTrue);
    expect(result.data?['expandedGetprop'], isTrue);
    expect(result.data?['properties'], <String, String>{
      'ro.product.model': 'huanglong',
      'ro.product.manufacturer': 'newlink',
      'ro.build.version.release': 'newlink',
    });
    expect(calls, hasLength(3));
    expect(calls.first, <String>[
      '-s',
      '192.168.3.63:5555',
      'shell',
      'getprop',
      'ro.product.model',
    ]);
  });

  test('Android Shell 安全规范化 dumpsys grep 管道并在本地过滤', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: '/tools/adb/adb',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(List<String>.of(arguments));
        return const AdbCommandResult(
          exitCode: 0,
          stdout:
              'DisplayDeviceInfo{"Built-in Screen"}\n'
              '  mDisplayId=0\n'
              'unrelated-value\n',
          stderr: '',
        );
      },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbShellId,
      arguments: <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>[
          'dumpsys',
          'display',
          '|',
          'grep',
          '-E',
          r'DisplayDeviceInfo|mDisplayId|DisplayDeviceInfo\("Built-in size',
        ],
      },
      approve: (_) async => true,
    );

    expect(result.ok, isTrue);
    expect(result.data?['pipelineNormalized'], isTrue);
    expect(result.data?['stdout'], contains('DisplayDeviceInfo'));
    expect(result.data?['stdout'], contains('mDisplayId=0'));
    expect(result.data?['stdout'], isNot(contains('unrelated-value')));
    expect(calls, <List<String>>[
      <String>['-s', '192.168.3.63:5555', 'shell', 'dumpsys', 'display'],
    ]);
  });

  test('Harness 对远端 ADB 的注入 runner 也统一添加 server 前缀', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: r'C:\tools\adb.exe',
      adbEndpoint: AdbServerEndpoint.rustDesk(
        host: '127.0.0.1',
        port: 15037,
        peerId: 'peer-remote',
        sessionId: 'session-remote',
        leaseId: 'lease-remote',
      ),
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'Pixel_9',
          stderr: '',
        );
      },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbCommandId,
      arguments: <String, Object?>{
        'serial': 'remote-usb',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
      },
      approve: (_) async => true,
    );

    expect(calls.single, <String>[
      '-H',
      '127.0.0.1',
      '-P',
      '15037',
      '-s',
      'remote-usb',
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    expect(result.data?['adbServer'], <String, Object?>{
      'kind': 'rustDesk',
      'displayName': 'KEMI 远程办公 · peer-remote',
      'host': '127.0.0.1',
      'port': 15037,
      'peerId': 'peer-remote',
      'sessionId': 'session-remote',
    });
  });

  test('Harness 默认跟随 ADB 工作区发布的远端 server endpoint', () async {
    final AdbServerEndpoint endpoint = AdbServerEndpoint.rustDesk(
      host: '127.0.0.1',
      port: 16037,
      peerId: 'peer-shared',
      leaseId: 'lease-shared',
    );
    AdbServerEndpointHub.publish(endpoint);
    addTearDown(() => AdbServerEndpointHub.clearLease(endpoint.leaseId));
    final List<String> captured = <String>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: r'C:\tools\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        captured.addAll(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'Pixel shared',
          stderr: '',
        );
      },
    );

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbCommandId,
      arguments: <String, Object?>{
        'serial': 'remote-usb',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
      },
      approve: (_) async => true,
    );

    expect(result.ok, isTrue);
    expect(captured.take(4).toList(), <String>[
      '-H',
      '127.0.0.1',
      '-P',
      '16037',
    ]);
    expect(result.data?['adbServer'], endpoint.toAuditFields());
  });

  test('Harness 通过六个语义 ADB 工具完成常用工作流', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_adb_semantic_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final File apk = File('${sandbox.path}${Platform.pathSeparator}demo.apk');
    final File upload = File(
      '${sandbox.path}${Platform.pathSeparator}upload.txt',
    );
    await apk.writeAsBytes(<int>[1, 2, 3]);
    await upload.writeAsString('VIBE');
    final String download =
        '${sandbox.path}${Platform.pathSeparator}download.txt';
    final String screenshot =
        '${sandbox.path}${Platform.pathSeparator}screen.png';
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: r'C:\tools\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(List<String>.of(arguments));
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'Success',
          stderr: '',
        );
      },
    );
    const String serial = '192.168.3.63:5555';
    Future<HarnessToolCallResult> invoke(
      String toolId,
      Map<String, Object?> arguments,
    ) => bridge.invoke(
      toolId: toolId,
      arguments: <String, Object?>{'serial': serial, ...arguments},
      approve: (HarnessToolApprovalRequest request) async {
        expect(request.target, serial);
        return true;
      },
    );

    final List<HarnessToolCallResult> results = <HarnessToolCallResult>[
      await invoke(VibekitsHarnessToolBridge.adbShellId, <String, Object?>{
        'arguments': <String>['getprop', 'ro.product.model'],
      }),
      await invoke(VibekitsHarnessToolBridge.adbLogcatId, <String, Object?>{
        'lines': 120,
        'tag': 'VIBE_TAG',
      }),
      await invoke(VibekitsHarnessToolBridge.adbInstallApkId, <String, Object?>{
        'apkPath': apk.path,
        'replace': true,
        'allowDowngrade': true,
      }),
      await invoke(VibekitsHarnessToolBridge.adbPushFileId, <String, Object?>{
        'localPath': upload.path,
        'remotePath': '/sdcard/Download/upload.txt',
      }),
      await invoke(VibekitsHarnessToolBridge.adbPullFileId, <String, Object?>{
        'remotePath': '/sdcard/Download/result.txt',
        'localPath': download,
      }),
      await invoke(VibekitsHarnessToolBridge.adbScreenshotId, <String, Object?>{
        'localPath': screenshot,
      }),
    ];

    expect(results.every((HarnessToolCallResult result) => result.ok), isTrue);
    expect(calls, hasLength(8));
    expect(calls[0], <String>[
      '-s',
      serial,
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    expect(calls[1], <String>[
      '-s',
      serial,
      'logcat',
      '-d',
      '-t',
      '120',
      'VIBE_TAG:D',
      '*:S',
    ]);
    expect(calls[2], <String>['-s', serial, 'install', '-r', '-d', apk.path]);
    expect(calls[3], <String>[
      '-s',
      serial,
      'push',
      upload.path,
      '/sdcard/Download/upload.txt',
    ]);
    expect(calls[4], <String>[
      '-s',
      serial,
      'pull',
      '/sdcard/Download/result.txt',
      download,
    ]);
    expect(calls[5].sublist(0, 5), <String>[
      '-s',
      serial,
      'shell',
      'screencap',
      '-p',
    ]);
    expect(calls[6][2], 'pull');
    expect(calls[7].sublist(2, 5), <String>['shell', 'rm', '-f']);
  });

  test('SQLite 检查和查询通过桥接完成闭环', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_sqlite_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final String path = '${sandbox.path}${Platform.pathSeparator}sample.db';
    final Database database = sqlite3.open(path);
    database.execute('CREATE TABLE users(id INTEGER, name TEXT)');
    database.execute("INSERT INTO users VALUES (1, 'Ada')");
    database.close();
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();

    final HarnessToolCallResult inspect = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.sqliteInspectId,
      arguments: <String, Object?>{'path': path},
      approve: (_) async => true,
    );
    final HarnessToolCallResult query = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.sqliteQueryId,
      arguments: <String, Object?>{
        'path': path,
        'sql': 'SELECT name FROM users',
      },
      approve: (_) async => true,
    );

    expect(inspect.ok, isTrue);
    expect(inspect.data?['objects'].toString(), contains('users'));
    expect(query.ok, isTrue);
    expect(query.data?['rows'], <List<String>>[
      <String>['Ada'],
    ]);
  });

  test('文件搜索通过桥接返回结构化匹配', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_search_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    await File(
      '${sandbox.path}${Platform.pathSeparator}hello.dart',
    ).writeAsString('void main() {}');
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.fileSearchId,
          arguments: <String, Object?>{'root': sandbox.path, 'query': 'hello'},
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect(result.data?['matches'].toString(), contains('hello.dart'));
  });

  test('HTTP 工具经审批访问本地服务并回传响应', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"bridge":"ok"}');
      await request.response.close();
    });
    final Uri target = Uri.parse('http://127.0.0.1:${server.port}/health');
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.apiRequestId,
          arguments: <String, Object?>{
            'method': 'GET',
            'url': target.toString(),
          },
          approve: (HarnessToolApprovalRequest request) async {
            expect(request.target, target.toString());
            return true;
          },
        );
    expect(result.ok, isTrue);
    expect(result.data?['statusCode'], 200);
    expect(result.data?['body'], '{"bridge":"ok"}');
  });

  test('程序员计算器通过桥接返回多进制结果', () async {
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.programmerCalculatorId,
          arguments: <String, Object?>{
            'expression': '(0xFF << 2) | 3',
            'width': 16,
          },
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect(result.data?['hexadecimal'], '0x03FF');
    expect(result.data?['decimal'], '1023');
  });

  test('Harness 通过已保存会话闭环调用 SSH 与 SFTP 且不暴露凭据', () async {
    const RemoteConnectionRecord profile = RemoteConnectionRecord(
      id: 'server_1',
      name: '测试服务器',
      mode: RemoteSessionMode.ssh,
      host: 'server.example.com',
      user: 'dev',
      port: 22,
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: 'SHA256:TrustedHostKey0123456789+/',
    );
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_remote_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final File upload = await File(
      '${sandbox.path}${Platform.pathSeparator}upload.txt',
    ).writeAsString('UPLOAD_OK');
    final String download =
        '${sandbox.path}${Platform.pathSeparator}download.txt';
    final List<String> transfers = <String>[];
    final List<Map<String, Object?>> activities = <Map<String, Object?>>[];
    int approvals = 0;
    RemoteConnectionStatusRegistry.connected(
      token: 'test-active-session',
      profileId: profile.id,
      kind: 'ssh',
    );
    addTearDown(RemoteConnectionStatusRegistry.clearForTests);
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      activityRecorder:
          ({
            required String toolId,
            required String toolName,
            required String target,
            required Map<String, Object?> arguments,
            required Object? result,
            required HarnessToolActivityStatus status,
            required DateTime startedAt,
          }) async {
            activities.add(<String, Object?>{
              'toolId': toolId,
              'target': target,
              'arguments': arguments,
              'result': result,
              'status': status.name,
            });
          },
      remoteProfileLoader: () async => const <RemoteConnectionRecord>[profile],
      credentialReader: (String key) async {
        expect(key, profile.credentialKey);
        return 'vault-secret';
      },
      remoteCommandRunner:
          (
            RemoteConnectionProfile connection,
            String command,
            String? secret,
            RemoteHostKeyVerifier verifier,
          ) async {
            expect(connection.host, profile.host);
            expect(secret, 'vault-secret');
            expect(command, 'printf HARNESS_SSH_OK');
            expect(
              await verifier(profile.hostKeyType!, profile.hostKeyFingerprint!),
              isTrue,
            );
            return const RemoteCommandResult(
              exitCode: 0,
              stdout: 'HARNESS_SSH_OK',
              stderr: '',
            );
          },
      remoteFileConnector:
          (
            RemoteConnectionProfile connection,
            String? secret,
            RemoteHostKeyVerifier verifier,
          ) async => _FakeHarnessRemoteFileClient(transfers),
    );

    Future<bool> approve(HarnessToolApprovalRequest request) async {
      approvals += 1;
      expect(request.target, contains('server_1'));
      return true;
    }

    final HarnessToolCallResult profiles = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteListProfilesId,
      arguments: const <String, Object?>{},
      approve: approve,
    );
    final HarnessToolCallResult command = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSshExecId,
      arguments: const <String, Object?>{
        'profileId': 'server_1',
        'command': 'printf HARNESS_SSH_OK',
      },
      approve: approve,
    );
    final HarnessToolCallResult listing = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSftpListId,
      arguments: const <String, Object?>{
        'profileId': 'server_1',
        'remotePath': '/tmp',
      },
      approve: approve,
    );
    final HarnessToolCallResult uploaded = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSftpUploadId,
      arguments: <String, Object?>{
        'profileId': 'server_1',
        'localPath': upload.path,
        'remotePath': '/tmp/upload.txt',
      },
      approve: approve,
    );
    final HarnessToolCallResult downloaded = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteSftpDownloadId,
      arguments: <String, Object?>{
        'profileId': 'server_1',
        'remotePath': '/tmp/remote.txt',
        'localPath': download,
      },
      approve: approve,
    );

    expect(profiles.ok, isTrue);
    expect(profiles.data.toString(), contains('online'));
    expect(profiles.data.toString(), contains('activeConnections: 1'));
    expect(profiles.data.toString(), isNot(contains('vault-secret')));
    expect(command.data?['stdout'], 'HARNESS_SSH_OK');
    expect(listing.data.toString(), contains('remote.txt'));
    expect(uploaded.ok, isTrue);
    expect(downloaded.ok, isTrue);
    expect(await File(download).readAsString(), 'REMOTE_OK');
    expect(transfers, <String>['upload:/tmp/upload.txt', 'download:$download']);
    expect(approvals, 3);
    expect(activities, hasLength(5));
    expect(
      activities.map((Map<String, Object?> item) => item['toolId']),
      containsAll(<String>[
        VibekitsHarnessToolBridge.remoteSshExecId,
        VibekitsHarnessToolBridge.remoteSftpListId,
        VibekitsHarnessToolBridge.remoteSftpUploadId,
        VibekitsHarnessToolBridge.remoteSftpDownloadId,
      ]),
    );
    expect(activities.toString(), isNot(contains('vault-secret')));
  });

  test('Harness 可打开一次认证后自动联动 SFTP 的交互工作流', () async {
    RemoteWorkspaceIntent? opened;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      remoteWorkspaceLauncher: (RemoteWorkspaceIntent intent) async {
        opened = intent;
      },
    );
    expect(
      bridge.executableCatalog.any(
        (HarnessToolDefinition tool) =>
            tool.id == VibekitsHarnessToolBridge.remoteOpenInteractiveId,
      ),
      isTrue,
    );
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteOpenInteractiveId,
      arguments: const <String, Object?>{
        'host': '192.168.3.20',
        'user': 'root',
        'openSftp': true,
      },
      approve: (_) async {
        approvals += 1;
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.data?['state'], 'awaiting_user_authentication');
    expect(opened?.host, '192.168.3.20');
    expect(opened?.user, 'root');
    expect(opened?.openSftpAfterConnect, isTrue);
    expect(approvals, 0);
  });

  test('Harness 截图 OCR 通过界面工作流返回本机识别结果', () async {
    int runs = 0;
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      screenshotOcrRunner: () async {
        runs += 1;
        return <String, Object?>{
          'text': 'Build succeeded',
          'lineCount': 1,
          'runtime': 'PP-OCRv6 tiny',
        };
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.screenshotOcrId,
      arguments: const <String, Object?>{},
      approve: (_) async {
        approvals += 1;
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.data?['text'], 'Build succeeded');
    expect(runs, 1);
    expect(approvals, 1);
  });

  test('Harness 通过已保存会话只读检查和查询远程数据库', () async {
    const RemoteDatabaseProfile profile = RemoteDatabaseProfile(
      id: 'postgres-42',
      name: '开发库',
      host: 'db.example.com',
      port: 5432,
      database: 'app',
      username: 'developer',
      useTls: true,
    );
    int approvals = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      remoteDatabaseProfileLoader: () async => <RemoteDatabaseProfile>[profile],
      credentialReader: (String key) async {
        expect(key, profile.id);
        return 'database-secret';
      },
      remoteDatabaseInspector:
          (RemoteDatabaseProfile value, String password) async {
            expect(value.id, profile.id);
            expect(password, 'database-secret');
            return const RemoteDatabaseSnapshot(
              profile: profile,
              serverVersion: 'PostgreSQL 17',
              objects: <RemoteDatabaseObject>[
                RemoteDatabaseObject(schema: 'public', name: 'users'),
              ],
            );
          },
      remoteDatabaseQuerier:
          (RemoteDatabaseProfile value, String password, String sql) async {
            expect(password, 'database-secret');
            expect(
              RemoteDatabaseService.validateReadOnlySql(sql, value.engine),
              'SELECT 1',
            );
            return const SqliteResultPage(
              columns: <String>['value'],
              rows: <List<String>>[
                <String>['1'],
              ],
              offset: 0,
              hasMore: false,
              label: '远程 SQL 查询',
            );
          },
    );

    Future<bool> approve(HarnessToolApprovalRequest request) async {
      approvals += 1;
      expect(request.target, profile.id);
      return true;
    }

    final HarnessToolCallResult profiles = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteDatabaseListProfilesId,
      arguments: const <String, Object?>{},
      approve: approve,
    );
    final HarnessToolCallResult inspected = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteDatabaseInspectId,
      arguments: const <String, Object?>{'profileId': 'postgres-42'},
      approve: approve,
    );
    final HarnessToolCallResult queried = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.remoteDatabaseQueryId,
      arguments: const <String, Object?>{
        'profileId': 'postgres-42',
        'sql': 'SELECT 1',
      },
      approve: approve,
    );

    expect(profiles.data.toString(), contains('db.example.com'));
    expect(profiles.data.toString(), isNot(contains('database-secret')));
    expect(inspected.data.toString(), contains('users'));
    expect(queried.data?['rows'], <List<String>>[
      <String>['1'],
    ]);
    expect(approvals, 2);
  });

  test('Harness 比较两个真实文件且审计日志不记录文件正文', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_diff_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final File left = await File(
      '${sandbox.path}${Platform.pathSeparator}before.txt',
    ).writeAsString('private-left-line\nshared\n');
    final File right = await File(
      '${sandbox.path}${Platform.pathSeparator}after.txt',
    ).writeAsString('private-right-line\nshared\n');
    Object? auditResult;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      activityRecorder:
          ({
            required String toolId,
            required String toolName,
            required String target,
            required Map<String, Object?> arguments,
            required Object? result,
            required HarnessToolActivityStatus status,
            required DateTime startedAt,
          }) async {
            expect(toolId, VibekitsHarnessToolBridge.fileDiffId);
            auditResult = result;
          },
    );
    int approvals = 0;

    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.fileDiffId,
      arguments: <String, Object?>{
        'leftPath': left.path,
        'rightPath': right.path,
      },
      approve: (HarnessToolApprovalRequest request) async {
        approvals += 1;
        return true;
      },
    );

    expect(result.ok, isTrue);
    expect(result.data?['addedLines'], 1);
    expect(result.data?['removedLines'], 1);
    expect(result.data?['unifiedDiff'], contains('+private-right-line'));
    expect(approvals, 0);
    expect(auditResult.toString(), contains('addedLines: 1'));
    expect(auditResult.toString(), isNot(contains('private-left-line')));
    expect(auditResult.toString(), isNot(contains('private-right-line')));
  });

  test('Harness 在后台线程完成文件哈希和重复文件扫描', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_files_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final File first = await File(
      '${sandbox.path}${Platform.pathSeparator}first.bin',
    ).writeAsString('same-content');
    await File(
      '${sandbox.path}${Platform.pathSeparator}second.bin',
    ).writeAsString('same-content');
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;
    Future<bool> approve(HarnessToolApprovalRequest request) async {
      approvals += 1;
      return true;
    }

    final HarnessToolCallResult hash = await bridge.invoke(
      toolId: 'vibekits.file_hash',
      arguments: <String, Object?>{'input': first.path, 'params': 'sha256'},
      approve: approve,
    );
    final HarnessToolCallResult duplicates = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.duplicateScanId,
      arguments: <String, Object?>{'root': sandbox.path, 'minimumSize': 1},
      approve: approve,
    );
    final HarnessToolCallResult drive = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.systemDriveAnalyzeId,
      arguments: <String, Object?>{'root': sandbox.path},
      approve: approve,
    );

    expect(hash.ok, isTrue);
    expect(hash.data?['digest'], hasLength(64));
    expect(duplicates.data?['duplicateFiles'], 1);
    expect(duplicates.data?['reclaimableBytes'], 12);
    expect(drive.ok, isTrue);
    expect(drive.data?['totalBytes'], greaterThan(0));
    expect(drive.data?['entries'].toString(), contains('first.bin'));
    expect(drive.data?['storagePressure'], isA<Map<String, Object?>>());
    expect(drive.data?['systemBaseline'].toString(), contains('20–40 GiB'));
    expect(drive.data?['priorities'], isA<List<Object?>>());
    expect(approvals, 0);
  });

  test('Harness 通过任务 ID 等待长时间磁盘分析且不会重复启动', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_drive_task_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    await File(
      '${sandbox.path}${Platform.pathSeparator}sample.bin',
    ).writeAsBytes(List<int>.filled(4096, 7));
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    Future<bool> approve(HarnessToolApprovalRequest request) async => true;

    final HarnessToolCallResult started = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.systemDriveAnalyzeStartId,
      arguments: <String, Object?>{'root': sandbox.path, 'maxResults': 20},
      approve: approve,
    );
    expect(started.ok, isTrue);
    final String taskId = started.data!['taskId']! as String;
    expect(taskId, startsWith('drive-'));

    Map<String, Object?> status = <String, Object?>{};
    for (int attempt = 0; attempt < 100; attempt += 1) {
      final HarnessToolCallResult polled = await bridge.invoke(
        toolId: VibekitsHarnessToolBridge.systemDriveAnalyzeStatusId,
        arguments: <String, Object?>{'taskId': taskId},
        approve: approve,
      );
      expect(polled.ok, isTrue);
      status = polled.data!;
      if (status['running'] == false) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(status['phase'], 'completed');
    expect(status['result'], isA<Map<String, Object?>>());
    expect(status['result'].toString(), contains('sample.bin'));
  });
}

class _FakeHarnessRemoteFileClient implements RemoteFileClient {
  _FakeHarnessRemoteFileClient(this.transfers);

  final List<String> transfers;

  @override
  Future<String> absolute(String path) async => path;

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async =>
      const <RemoteFileEntry>[
        RemoteFileEntry(
          name: 'remote.txt',
          path: '/tmp/remote.txt',
          isDirectory: false,
          size: 9,
        ),
      ];

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    final int size = await File(localPath).length();
    transfers.add('upload:$remotePath');
    onProgress(size, size);
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    required int total,
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    transfers.add('download:$localPath');
    await File(localPath).writeAsString('REMOTE_OK');
    onProgress(total, total);
  }

  @override
  Future<void> close() async {}
}
