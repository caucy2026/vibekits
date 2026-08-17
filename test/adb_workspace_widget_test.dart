import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
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

    await tester.tap(find.widgetWithText(ListTile, 'ADB'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('ADB 设备'), findsOneWidget);
    expect(find.text('ADB 1.0.41'), findsOneWidget);
  });
}
