import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/app_center/domain/runtime_component_verifier.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('component-verifier-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Map<String, Object?> manifest() => {
    'schema_version': 1,
    'host_package_name': 'com.caucy.vibekits',
    'component_id': 'network_proxy',
    'standalone': false,
    'os_type': Platform.operatingSystem,
    'architecture': RuntimeComponentVerifier.architecture,
    'version_code': 1,
    'files': {'mihomo/mihomo${Platform.isWindows ? '.exe' : ''}': '0' * 64},
  };
  Future<void> write(Map<String, Object?> value) => File(
    '${root.path}/component-manifest.json',
  ).writeAsString(jsonEncode(value));
  test('reject a component without a release manifest', () async {
    await expectLater(
      RuntimeComponentVerifier.verify(root, 'network_proxy'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'reason',
          contains('缺少发布清单'),
        ),
      ),
    );
  });
  test('reject a component for another host before native execution', () async {
    await write({...manifest(), 'host_package_name': 'another.app'});
    await expectLater(
      RuntimeComponentVerifier.verify(root, 'network_proxy'),
      throwsFormatException,
    );
  });
  test('reject a mismatched architecture and version', () async {
    await write({...manifest(), 'architecture': 'unsupported-cpu'});
    await expectLater(
      RuntimeComponentVerifier.verify(root, 'network_proxy'),
      throwsFormatException,
    );
    await write(manifest());
    await expectLater(
      RuntimeComponentVerifier.verify(root, 'network_proxy', versionCode: 2),
      throwsFormatException,
    );
  });
  test(
    'reject missing payload files even with a valid manifest identity',
    () async {
      await write(manifest());
      await expectLater(
        RuntimeComponentVerifier.verify(root, 'network_proxy'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('文件不完整'),
          ),
        ),
      );
    },
  );
}
