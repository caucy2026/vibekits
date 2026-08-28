import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Harness Web clipboard supports rich editor and mainstream shortcuts', () {
    final String source = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('[contenteditable]:not([contenteditable="false"])'),
    );
    expect(source, contains("document.execCommand('insertText'"));
    expect(source, contains('LogicalKeyboardKey.keyC'));
    expect(source, contains('LogicalKeyboardKey.keyV'));
    expect(source, contains('LogicalKeyboardKey.insert'));
    expect(source, contains('_copyFromFocusedWebSelection'));
    expect(source, contains('_pasteIntoFocusedWebField'));
  });
}
