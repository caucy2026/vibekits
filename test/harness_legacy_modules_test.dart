import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_legacy_modules.dart';

void main() {
  test('accepts only announced local console origin', () {
    final expected = Uri.parse('http://127.0.0.1:1234');
    expect(
      harnessAnnouncedUrl(
        'dsh web: http://127.0.0.1:1234/?token=abc\n',
        expected,
      )?.queryParameters['token'],
      'abc',
    );
    expect(
      harnessAnnouncedUrl(
        'dsh web: http://evil.example:1234/?token=abc',
        expected,
      ),
      isNull,
    );
    expect(
      harnessAnnouncedUrl(
        'dsh web: http://127.0.0.1:9999/?token=abc',
        expected,
      ),
      isNull,
    );
  });
  test(
    'detaches linked module root without touching signed app contents',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'harness-linked-root-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final home = Directory('${temp.path}/home');
      final bundle = Directory('${temp.path}/app/node_modules');
      await bundle.create(recursive: true);
      final marker = File('${bundle.path}/untouched');
      await marker.writeAsString('signed');
      await Directory('${home.path}/profiles').create(recursive: true);
      await Link('${home.path}/profiles/node_modules').create(bundle.path);
      final moved = await migrateHarnessLegacyModules(
        home,
        '${bundle.path}/dsh/lib/bin.js',
      );
      expect(moved, hasLength(1));
      expect(await Link(moved.single).target(), bundle.path);
      expect(await marker.readAsString(), 'signed');
      expect(
        await FileSystemEntity.type(
          '${home.path}/profiles/node_modules',
          followLinks: false,
        ),
        FileSystemEntityType.directory,
      );
    },
  );
  test(
    'backs up copied runtime, preserves links, proxies and user packages',
    () async {
      final temp = await Directory.systemTemp.createTemp('harness-migration-');
      addTearDown(() => temp.delete(recursive: true));
      final home = Directory('${temp.path}/home');
      final bundle = '${temp.path}/runtime/node_modules';
      final modules = '${home.path}/profiles/node_modules';
      for (final name in ['@deepseek-ai/dsh', 'proxy', 'linked']) {
        await Directory('$bundle/$name').create(recursive: true);
      }
      for (final name in ['@deepseek-ai/dsh', 'proxy', 'custom-plugin']) {
        final file = File('$modules/$name/package.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          name == 'proxy'
              ? '{"name":"proxy","dsh":{"moduleFallback":{"targets":{}}}}'
              : '{"name":"$name"}',
        );
      }
      await Link('$modules/linked').create('$bundle/linked');
      await Directory('$bundle/incomplete').create(recursive: true);
      await Directory('$bundle/malformed').create(recursive: true);
      await Directory('$modules/incomplete').create(recursive: true);
      await Directory('$modules/malformed').create(recursive: true);
      await File('$modules/malformed/package.json').writeAsString('{broken');
      final session = File('${home.path}/sessions/keep.json');
      await session.parent.create(recursive: true);
      await session.writeAsString('chat history');
      final moved = await migrateHarnessLegacyModules(
        home,
        '$bundle/@deepseek-ai/dsh/lib/bin.js',
      );
      expect(moved, hasLength(3));
      expect(
        moved.any(
          (String path) =>
              path.endsWith('@deepseek-ai/dsh') &&
              File('$path/package.json').existsSync(),
        ),
        isTrue,
      );
      expect(await Directory('$modules/@deepseek-ai/dsh').exists(), isFalse);
      expect(await Directory('$modules/incomplete').exists(), isFalse);
      expect(await Directory('$modules/malformed').exists(), isFalse);
      expect(
        await File('$modules/custom-plugin/package.json').exists(),
        isTrue,
      );
      expect(await File('$modules/proxy/package.json').exists(), isTrue);
      expect(await Link('$modules/linked').exists(), isTrue);
      expect(await session.readAsString(), 'chat history');
      expect(
        await migrateHarnessLegacyModules(
          home,
          '$bundle/@deepseek-ai/dsh/lib/bin.js',
        ),
        isEmpty,
      );
    },
  );
  test('shows root error rather than Node version', () {
    expect(
      harnessStartupDiagnostic('stack\nError: bad module\nNode.js v22.19.0'),
      'Error: bad module',
    );
    expect(harnessStartupDiagnostic(''), '');
  });
}
