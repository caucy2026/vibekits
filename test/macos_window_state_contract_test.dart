import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS main window restores and persists the user frame', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    expect(source, contains('setFrameAutosaveName'));
    expect(source, contains('setFrameUsingName'));
    expect(source, contains('force: false'));
  });
}
