import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_session_store.dart';

void main() {
  test(
    'deletes exact session data and removes official index references',
    () async {
      final Directory home = await Directory.systemTemp.createTemp(
        'vibekits-harness-delete-',
      );
      addTearDown(() => home.delete(recursive: true));
      const String deleted = 'session-11111111-1111-1111-1111-111111111111';
      const String kept = 'session-22222222-2222-2222-2222-222222222222';
      final Directory session = Directory(
        '${home.path}/sessions/work/$deleted',
      );
      await session.create(recursive: true);
      await File('${session.path}/session.jsonl.zstd').writeAsString('private');
      final Directory stores = Directory('${home.path}/storages');
      await stores.create(recursive: true);
      await File('${stores.path}/workspace.json').writeAsString(
        jsonEncode({
          'global': {
            'archivedSessionIds': [deleted, kept],
          },
          'tables': {
            'workspaces': {
              'w': {
                'sessionIds': [deleted, kept],
              },
            },
          },
        }),
      );
      await File('${stores.path}/session_projcache.json').writeAsString(
        jsonEncode({
          'tables': {
            'sessions': {deleted: {}, kept: {}},
          },
        }),
      );

      await HarnessSessionStore(home: home).deleteSession(deleted);

      expect(await session.exists(), isFalse);
      expect(await session.parent.exists(), isFalse);
      final dynamic workspace = jsonDecode(
        await File('${stores.path}/workspace.json').readAsString(),
      );
      expect(workspace['global']['archivedSessionIds'], [kept]);
      expect(workspace['tables']['workspaces']['w']['sessionIds'], [kept]);
      final dynamic cache = jsonDecode(
        await File('${stores.path}/session_projcache.json').readAsString(),
      );
      expect(cache['tables']['sessions'].keys, [kept]);
    },
  );

  test('rejects a path-like session id', () async {
    final Directory home = await Directory.systemTemp.createTemp(
      'vibekits-harness-delete-',
    );
    addTearDown(() => home.delete(recursive: true));
    expect(
      () => HarnessSessionStore(home: home).deleteSession('../sessions'),
      throwsFormatException,
    );
  });

  test('removes only legacy native probe workspaces', () async {
    final Directory home = await Directory.systemTemp.createTemp(
      'vibekits-harness-probe-cleanup-',
    );
    addTearDown(() => home.delete(recursive: true));
    final Directory probe = Directory(
      '${home.path}/sessions/--C-Users-test-AppData-Local-Temp-vibekits_harness_native_411a3ec8--',
    );
    final Directory userWorkspace = Directory(
      '${home.path}/sessions/--D-vibecode-vibekits--',
    );
    await probe.create(recursive: true);
    await File('${probe.path}/probe.txt').writeAsString('temporary');
    await userWorkspace.create(recursive: true);
    await File('${userWorkspace.path}/keep.txt').writeAsString('user');

    final int removed = await HarnessSessionStore(home: home)
        .deleteLegacyNativeProbeSessions();

    expect(removed, 1);
    expect(await probe.exists(), isFalse);
    expect(await userWorkspace.exists(), isTrue);
  });
}
