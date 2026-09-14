import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_version.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_exposure_server.dart';

void main() {
  test('UI, package metadata and LMCP publish one application version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec,
      contains('version: ${AppVersion.semantic}+${AppVersion.build}'),
    );
    expect(VibekitsLmcpExposureServer.currentAppVersion, AppVersion.semantic);
    expect(
      VibekitsLmcpProtocol.currentCatalogRevision,
      '${AppVersion.build}',
    );
  });
}
