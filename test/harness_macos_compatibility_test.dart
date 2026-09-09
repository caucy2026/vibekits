import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  const String compatibilityIndex = '/runtime/dist-macos12/index.html';

  test('legacy WebKit macOS versions select the compatibility frontend', () {
    for (final String version in <String>[
      'Version 12.0 (Build 21A344)',
      'Version 12.6.4 (Build 21G526)',
      'Version 13.0 (Build 22A380)',
      'Version 13.7.8 (Build 22H730)',
      'macOS 14.0',
      'macOS 14.3.1',
    ]) {
      expect(
        harnessLegacyWebKitDistIndex(
          isMacOS: true,
          operatingSystemVersion: version,
          compatibilityIndexPath: compatibilityIndex,
        ),
        compatibilityIndex,
        reason: version,
      );
    }
  });

  test('Safari 17.4-era and unknown macOS versions retain official frontend', () {
    for (final String version in <String>[
      'Version 11.7.10 (Build 20G1427)',
      'macOS 14',
      'macOS 14.4',
      'macOS 14.7.6',
      'macOS 15.0',
      'macOS 26.0',
      'Darwin Kernel Version 25.0.0',
    ]) {
      expect(
        harnessLegacyWebKitDistIndex(
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
      harnessLegacyWebKitDistIndex(
        isMacOS: false,
        operatingSystemVersion: 'Version 12.6.4',
        compatibilityIndexPath: compatibilityIndex,
      ),
      isNull,
    );
  });

  test('macOS 12 client bundles are isolated from official bundles', () {
    final Directory package = Directory(
      'native/harness/macos/runtime/node_modules/@deepseek-ai/'
      'dsh-client-ui-model-selection/lib',
    );
    final File official = File('${package.path}/client.js');
    final File compatibility = File('${package.path}/client.macos12.js');
    final String moduleHost = File(
      'native/harness/macos/runtime/node_modules/@deepseek-ai/'
      'dsh-client-modules/lib/index.js',
    ).readAsStringSync();

    expect(official.existsSync(), isTrue);
    expect(compatibility.existsSync(), isTrue);
    expect(compatibility.readAsStringSync(), isNot(official.readAsStringSync()));
    expect(moduleHost, contains('process.env.VIBEKITS_DSH_WEB_DIST_INDEX'));
    expect(moduleHost, contains('.replace(/\\.js\$/, ".macos12.js")'));
  });

  test('macOS 12 connection bundle uses the legacy WebKit RPC transport', () {
    final Directory package = Directory(
      'native/harness/macos/runtime/node_modules/@deepseek-ai/'
      'dsh-client-connection/lib',
    );
    final String official = File('${package.path}/client.js').readAsStringSync();
    final String compatibility = File(
      '${package.path}/client.macos12.js',
    ).readAsStringSync();

    expect(official, contains('globalThis.fetch'));
    expect(official, isNot(contains('XMLHttpRequest')));
    expect(compatibility, contains('XMLHttpRequest'));
    expect(compatibility, contains('Harness RPC network request failed'));
  });

  test('macOS 12 gateway bundle polyfills composed abort signals', () {
    final Directory package = Directory(
      'native/harness/macos/runtime/node_modules/@deepseek-ai/'
      'dsh-api-gateway/lib',
    );
    final String official = File('${package.path}/client.js').readAsStringSync();
    final String compatibility = File(
      '${package.path}/client.macos12.js',
    ).readAsStringSync();

    expect(official, contains('AbortSignal.any'));
    expect(official, isNot(contains('macos12AbortSignalAny')));
    expect(compatibility, isNot(contains('AbortSignal.any')));
    expect(compatibility, contains('AbortController'));
  });
}
