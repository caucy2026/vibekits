import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/semantic_workflow_service.dart';

void main() {
  test('demonstration compiles tool calls into a parameterized semantic skill', () async {
    final Directory root = Directory(
      '${Directory.current.path}${Platform.pathSeparator}.runtime-cache'
      '${Platform.pathSeparator}test-semantic-${DateTime.now().microsecondsSinceEpoch}',
    );
    final SemanticWorkflowService service = SemanticWorkflowService(
      directory: root,
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final Map<String, Object?> started = await service.start(<String, Object?>{
      'name': '安装并检查测试包',
      'goal': '在指定 Android 设备安装 APK，并确认应用可启动',
      'successCriteria': <String>['安装返回成功', '目标进程处于运行状态'],
      'variables': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'deviceSerial',
          'description': 'ADB 设备序列号',
          'recordedValue': '192.168.3.53:5555',
        },
      ],
    });
    await service.capture(
      toolId: 'vibekits.adb.install_apk',
      toolName: '安装 APK',
      target: '192.168.3.53:5555',
      arguments: <String, Object?>{
        'serial': '192.168.3.53:5555',
        'apkPath': r'D:\packages\app.apk',
      },
      result: <String, Object?>{'installed': true},
      status: 'succeeded',
      startedAt: DateTime.now(),
    );
    final Map<String, Object?> stopped = await service.stop(
      const <String, Object?>{},
    );
    expect(stopped['stepCount'], 1);

    final Map<String, Object?> replay = await service.prepareReplay(
      <String, Object?>{
        'workflowId': started['workflowId'],
        'inputs': <String, Object?>{'deviceSerial': '192.168.3.99:5555'},
      },
    );
    final Map workflow = replay['workflow']! as Map;
    final Map step = (workflow['steps']! as List).single as Map;
    expect((step['arguments'] as Map)['serial'], '192.168.3.99:5555');
    expect(step['preferredTool'], 'vibekits.adb.install_apk');
    expect(
      (replay['executionContract'] as Map)['plannerInstruction'],
      contains('不要复现坐标'),
    );
  });

  test('replay rejects missing required semantic inputs', () async {
    final Directory root = Directory(
      '${Directory.current.path}${Platform.pathSeparator}.runtime-cache'
      '${Platform.pathSeparator}test-semantic-missing-${DateTime.now().microsecondsSinceEpoch}',
    );
    final SemanticWorkflowService service = SemanticWorkflowService(
      directory: root,
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final Map<String, Object?> started = await service.start(<String, Object?>{
      'name': '查询设备',
      'goal': '查询指定设备',
      'successCriteria': <String>['设备在线'],
      'variables': <Map<String, Object?>>[
        <String, Object?>{'name': 'serial', 'recordedValue': 'device-a'},
      ],
    });
    await service.capture(
      toolId: 'vibekits.adb.shell',
      toolName: 'ADB Shell',
      target: 'device-a',
      arguments: <String, Object?>{
        'serial': 'device-a',
        'command': 'get-state',
      },
      result: <String, Object?>{'state': 'device'},
      status: 'succeeded',
      startedAt: DateTime.now(),
    );
    await service.stop(const <String, Object?>{});

    expect(
      () => service.prepareReplay(<String, Object?>{
        'workflowId': started['workflowId'],
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
