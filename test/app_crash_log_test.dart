import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_crash_log.dart';
import 'package:vibekits/app/platform_storage_layout.dart';

void main() {
  test('未捕获异常写入有界脱敏日志且记录器自身不抛错', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-crash-log-',
    );
    addTearDown(() => root.delete(recursive: true));
    await PlatformStorageLayout.initialize(
      operatingSystem: 'windows',
      environment: <String, String>{'LOCALAPPDATA': root.path},
      executablePath: '${root.path}${Platform.pathSeparator}vibekits.exe',
      roots: PlatformStorageRoots(
        applicationSupport: '${root.path}${Platform.pathSeparator}support',
        applicationCache: '${root.path}${Platform.pathSeparator}cache',
        temporary: '${root.path}${Platform.pathSeparator}temp',
        documents: '${root.path}${Platform.pathSeparator}documents',
      ),
    );

    AppCrashLog.recordSync(
      StateError('authorization=Bearer-secret'),
      StackTrace.fromString('frame access_token=raw-token'),
      source: 'test-source',
    );

    final String contents = await AppCrashLog.file.readAsString();
    expect(contents, contains('test-source'));
    expect(contents, contains('authorization=<redacted>'));
    expect(contents, contains('access_token=<redacted>'));
    expect(contents, isNot(contains('Bearer-secret')));
    expect(contents, isNot(contains('raw-token')));
  });
}
