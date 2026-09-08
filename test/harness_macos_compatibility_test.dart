import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  const String compatibilityIndex = '/runtime/dist-macos12/index.html';

  test('macOS 12 selects the compatibility Harness frontend', () {
    expect(
      harnessMacos12WebDistIndex(
        isMacOS: true,
        operatingSystemVersion: 'Version 12.6.4 (Build 21G526)',
        compatibilityIndexPath: compatibilityIndex,
      ),
      compatibilityIndex,
    );
  });

  test('newer and unknown macOS versions retain the official frontend', () {
    for (final String version in <String>[
      'Version 13.7.8 (Build 22H730)',
      'macOS 14.7.6',
      'Darwin Kernel Version 25.0.0',
    ]) {
      expect(
        harnessMacos12WebDistIndex(
          isMacOS: true,
          operatingSystemVersion: version,
          compatibilityIndexPath: compatibilityIndex,
        ),
        isNull,
        reason: version,
      );
    }
  });

  test('non-macOS platforms retain the official frontend', () {
    expect(
      harnessMacos12WebDistIndex(
        isMacOS: false,
        operatingSystemVersion: 'Version 12.6.4',
        compatibilityIndexPath: compatibilityIndex,
      ),
      isNull,
    );
  });
}
