import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/presentation/adb_workspace.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('ADB 工作区显示绝对路径和三种设备状态', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const AdbSnapshot snapshot = AdbSnapshot(
      installation: AdbInstallation(
        executable: r'D:\Android\platform-tools\adb.exe',
        version: '1.0.41',
      ),
      devices: <AdbDevice>[
        AdbDevice(
          serial: 'usb-ok',
          state: AdbDeviceState.device,
          model: 'Pixel_9',
        ),
        AdbDevice(serial: 'usb-denied', state: AdbDeviceState.unauthorized),
        AdbDevice(serial: 'usb-offline', state: AdbDeviceState.offline),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdbWorkspace(loadSnapshot: () async => snapshot)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ADB 1.0.41'), findsOneWidget);
    expect(find.text(r'D:\Android\platform-tools\adb.exe'), findsOneWidget);
    expect(find.byKey(const Key('adb-device-usb-ok')), findsOneWidget);
    expect(find.byKey(const Key('adb-device-usb-denied')), findsOneWidget);
    expect(find.byKey(const Key('adb-device-usb-offline')), findsOneWidget);
    expect(find.text('可用'), findsOneWidget);
    expect(find.text('未授权'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
    expect(find.textContaining('设备已授权'), findsOneWidget);

    await tester.tap(find.byKey(const Key('adb-device-usb-denied')));
    await tester.pump();
    expect(find.textContaining('确认 USB 调试授权'), findsOneWidget);
  });

  testWidgets('开发工具左侧可一次进入 ADB 工作区', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const AdbSnapshot snapshot = AdbSnapshot(
      installation: AdbInstallation(
        executable: r'D:\Android\platform-tools\adb.exe',
        version: '1.0.41',
      ),
      devices: <AdbDevice>[],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(adbLoadSnapshot: () async => snapshot),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ListTile, '安卓调试（ADB）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('ADB 设备'), findsOneWidget);
    expect(find.text('ADB 1.0.41'), findsOneWidget);
  });

  testWidgets('选中设备后可以执行命令并在终端显示真实结果', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const AdbSnapshot snapshot = AdbSnapshot(
      installation: AdbInstallation(
        executable: r'D:\Android\platform-tools\adb.exe',
        version: '1.0.41',
      ),
      devices: <AdbDevice>[
        AdbDevice(
          serial: '192.168.3.63:5555',
          state: AdbDeviceState.device,
          model: 'huanglong',
        ),
      ],
    );
    String? executable;
    List<String>? arguments;
    List<String>? commandHistory;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdbWorkspace(
            loadSnapshot: () async => snapshot,
            runCommand: (String path, List<String> values) async {
              executable = path;
              arguments = values;
              return const AdbCommandResult(
                exitCode: 0,
                stdout: 'huanglong\r\n',
                stderr: '',
              );
            },
            onCommandHistoryChanged: (List<String> values) async {
              commandHistory = values;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adb-command-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('adb-command-input')),
      'getprop ro.product.model',
    );
    await tester.tap(find.byKey(const Key('adb-command-run')));
    await tester.pumpAndSettle();

    expect(executable, r'D:\Android\platform-tools\adb.exe');
    expect(arguments, <String>[
      '-s',
      '192.168.3.63:5555',
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    expect(commandHistory, <String>['shell getprop ro.product.model']);
    expect(find.textContaining(r'$ adb -s 192.168.3.63:5555'), findsOneWidget);
    expect(find.textContaining('huanglong'), findsWidgets);
  });

  testWidgets('无线地址会复用且历史保存失败不影响连接', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const AdbSnapshot snapshot = AdbSnapshot(
      installation: AdbInstallation(
        executable: r'D:\Android\platform-tools\adb.exe',
        version: '1.0.41',
      ),
      devices: <AdbDevice>[],
    );
    String? connectedAddress;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdbWorkspace(
            loadSnapshot: () async => snapshot,
            initialRecentAddresses: const <String>['192.168.3.62:5555'],
            connectDevice: (_, String address) async {
              connectedAddress = address;
              return 'connected to 192.168.3.63:5555';
            },
            onRecentAddressesChanged: (_) async {
              throw StateError('settings unavailable');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('adb-wireless-address')),
      '192.168.3.63',
    );
    await tester.tap(find.byKey(const Key('adb-connect')));
    await tester.pumpAndSettle();

    expect(connectedAddress, '192.168.3.63');
    expect(
      find.textContaining('connected to 192.168.3.63:5555'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('adb-error')), findsNothing);
  });

  testWidgets('ADB 工作区展示 Harness 调用记录并支持删除和清空', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<HarnessToolActivity> entries = <HarnessToolActivity>[
      HarnessToolActivity(
        id: 'one',
        toolId: 'vibekits.adb.list_devices',
        toolName: '列出 ADB 设备',
        target: '',
        argumentsSummary: '{}',
        resultSummary: 'huanglong',
        status: HarnessToolActivityStatus.succeeded,
        startedAt: DateTime(2026, 8, 18, 17, 0),
        elapsedMs: 120,
      ),
      HarnessToolActivity(
        id: 'two',
        toolId: 'vibekits.adb.command',
        toolName: '执行 ADB 命令',
        target: '192.168.3.63:5555',
        argumentsSummary:
            '{"arguments":["shell","getprop","ro.product.model"]}',
        resultSummary: 'huanglong',
        status: HarnessToolActivityStatus.succeeded,
        startedAt: DateTime(2026, 8, 18, 17, 1),
        elapsedMs: 86,
      ),
    ];
    const AdbSnapshot snapshot = AdbSnapshot(
      installation: AdbInstallation(
        executable: r'D:\Android\platform-tools\adb.exe',
        version: '1.0.41',
      ),
      devices: <AdbDevice>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdbWorkspace(
            loadSnapshot: () async => snapshot,
            loadHarnessActivity: (_) async => List.of(entries),
            deleteHarnessActivity: (String id) async {
              entries.removeWhere((HarnessToolActivity item) => item.id == id);
            },
            clearHarnessActivity: (_) async => entries.clear(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adb-harness-activity')));
    await tester.pumpAndSettle();

    expect(find.text('Harness 调用记录'), findsOneWidget);
    expect(find.textContaining('192.168.3.63:5555'), findsOneWidget);
    await tester.tap(find.byKey(const Key('adb-harness-delete-one')));
    await tester.pumpAndSettle();
    expect(entries, hasLength(1));
    await tester.tap(find.byKey(const Key('adb-harness-clear')));
    await tester.pumpAndSettle();
    expect(entries, isEmpty);
    expect(find.text('暂无 Harness ADB 调用'), findsOneWidget);
  });
}
