import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_store_app.dart';

void main() {
  test(
    'Mac App Store build uses the isolated target and prunes private assets',
    () async {
      final String buildScript = await File(
        'tool/build_macos_app_store.sh',
      ).readAsString();
      final String project = await File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsString();
      final String appDelegate = await File(
        'macos/Runner/AppDelegate.swift',
      ).readAsString();
      final String entitlements = await File(
        'macos/Runner/ReleaseAppStore.entitlements',
      ).readAsString();
      final String infoPlist = await File(
        'macos/Runner/InfoAppStore.plist',
      ).readAsString();
      final String uploadOptions = await File(
        'macos/ExportOptionsAppStoreUpload.plist',
      ).readAsString();
      final String pubspec = await File('pubspec.yaml').readAsString();

      expect(buildScript, contains('--target=lib/main_app_store.dart'));
      expect(buildScript, contains('FLUTTER_TARGET=lib/main_app_store.dart'));
      expect(
        buildScript,
        contains(
          "SWIFT_ACTIVE_COMPILATION_CONDITIONS='\$(inherited) VIBEKITS_APP_STORE'",
        ),
      );
      expect(buildScript, contains('VIBEKITS_APP_STORE_DISPLAY_VERSION'));
      expect(
        buildScript,
        contains('VIBEKITS_INFO_PLIST=Runner/InfoAppStore.plist'),
      );
      expect(buildScript, contains('assets/harness'));
      expect(buildScript, contains('forbidden_framework'));
      expect(buildScript, contains('setRemoteLoginEnabled'));
      expect(project, contains('STORE_ASSETS='));
      expect(project, contains('assets/cleaner'));
      expect(project, contains('assets/harness'));
      expect(project, contains('test_data'));
      expect(project, contains('/usr/bin/codesign --force --sign'));
      expect(project, contains(r'$EXPANDED_CODE_SIGN_IDENTITY'));
      expect(appDelegate, contains('#if !VIBEKITS_APP_STORE'));
      expect(appDelegate, contains('setRemoteLoginEnabled'));
      expect(
        entitlements,
        isNot(contains('com.apple.security.network.client')),
      );
      expect(infoPlist, contains('<string>zip</string>'));
      expect(infoPlist, isNot(contains('<string>rar</string>')));
      expect(infoPlist, isNot(contains('<string>7z</string>')));
      expect(infoPlist, isNot(contains('<string>onnx</string>')));
      expect(uploadOptions, contains('<string>upload</string>'));
      expect(uploadOptions, contains('<string>app-store-connect</string>'));
      expect(pubspec, isNot(contains('\n  webview_flutter:')));
      expect(pubspec, isNot(contains('\n  audioplayers:')));
      expect(pubspec, isNot(contains('\n  sherpa_onnx:')));
      expect(pubspec, isNot(contains('\n  libserialport_plus:')));
      expect(pubspec, isNot(contains('\n  sqlite3:')));
    },
  );

  testWidgets('Mac App Store target exposes only its three offline pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VibekitsAppStoreApp());
    await tester.pump();

    expect(find.text('解压缩'), findsWidgets);
    expect(find.text('文档阅读'), findsWidgets);
    expect(find.text('关于 Vibekits'), findsOneWidget);
    expect(find.text('应用中心'), findsNothing);
    expect(find.textContaining('Harness'), findsNothing);
    expect(find.textContaining('MCP'), findsNothing);
    expect(find.textContaining('RAR'), findsNothing);
    expect(find.textContaining('7z'), findsNothing);
    expect(find.textContaining('登录'), findsNothing);
    expect(find.textContaining('账号'), findsNothing);
    expect(find.textContaining('注册'), findsNothing);

    await tester.tap(find.byKey(const Key('app-store-nav-2')));
    await tester.pump();
    expect(find.byKey(const Key('app-store-about-page')), findsOneWidget);
    expect(find.textContaining('文件只在本机处理'), findsOneWidget);
  });
}
