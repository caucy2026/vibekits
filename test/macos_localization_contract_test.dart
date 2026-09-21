import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS bundle declares Simplified Chinese for native WebView menus', () {
    final String plist = File('macos/Runner/Info.plist').readAsStringSync();
    final String project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final File menu = File('macos/Runner/zh-Hans.lproj/MainMenu.strings');

    expect(plist, contains('<key>CFBundleLocalizations</key>'));
    expect(plist, contains('<string>zh-Hans</string>'));
    expect(project, contains('zh-Hans.lproj/MainMenu.strings'));
    expect(project, contains('/* zh-Hans */'));
    expect(menu.existsSync(), isTrue);
  });
}
