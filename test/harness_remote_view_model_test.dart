import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/features/dev_tools/domain/harness_remote_connection.dart';
import '../lib/features/dev_tools/domain/harness_remote_workspace_client.dart';
import '../lib/features/dev_tools/domain/harness_remote_view_model.dart';

class _Channel implements HarnessRemoteChannel {
  final incoming = StreamController<String>();
  @override
  String get authenticatedPeerId => 'peer';
  @override
  Stream<String> get frames => incoming.stream;
  @override
  Future<void> send(String frame) async {
    final request = jsonDecode(frame) as Map;
    final payload = request['payload'] as Map;
    final response = switch (payload['kind']) {
      'hello' => {
        'ok': true,
        'protocol': 'vibekits.harness.remote',
        'version': 1,
        'connectionId': 'connection',
        'authenticatedControllerId': 'VH-CONTROLLER',
        'capabilities': ['read-state', 'heartbeat'],
      },
      'heartbeat' => {
        'ok': true,
        'connectionId': 'connection',
        'serverTimeUtc': '2026-09-08T00:00:00Z',
      },
      _ => {
        'ok': true,
        'live': true,
        'epoch': 'epoch',
        'sequence': 0,
        'workspaces': [
          {
            'workspaceId': 'w',
            'title': 'project',
            'sessionIds': ['s'],
          },
        ],
      },
    };
    incoming.add(
      jsonEncode({
        'protocol': 'vibekits.harness.remote',
        'version': 1,
        'type': 'response',
        'requestId': request['requestId'],
        'payload': response,
      }),
    );
  }

  @override
  Future<void> close() async {
    unawaited(incoming.close());
  }
}

void main() {
  test(
    'does not become live until official history restoration completes',
    () async {
      final connection = HarnessRemoteConnection(_Channel());
      final entered = Completer<void>();
      final restore = Completer<void>();
      final applied = Completer<void>();
      final model = HarnessRemoteViewModel(
        HarnessRemoteWorkspaceClient(connection),
        applyOfficialEvents: (_) async {},
        restoreOfficialSnapshot: (rows) async {
          expect(rows.single['workspaceId'], 'w');
          entered.complete();
          await restore.future;
        },
      );
      model.addListener(() {
        if (!model.stale && !applied.isCompleted) applied.complete();
      });
      try {
        model.start();
        await entered.future;
        expect(model.stale, true);
        expect(model.workspaces, isEmpty);
        restore.complete();
        await applied.future.timeout(const Duration(seconds: 2));
        expect(model.workspaces.single['title'], 'project');
      } finally {
        model.dispose();
        await connection.close();
      }
    },
  );

  test(
    'disconnect during history restore cannot resurrect a live snapshot',
    () async {
      final connection = HarnessRemoteConnection(_Channel());
      final entered = Completer<void>();
      final restore = Completer<void>();
      final model = HarnessRemoteViewModel(
        HarnessRemoteWorkspaceClient(connection),
        applyOfficialEvents: (_) async {},
        restoreOfficialSnapshot: (_) async {
          entered.complete();
          await restore.future;
        },
      );
      try {
        model.start();
        await entered.future;
        await connection.close();
        restore.complete();
        await Future<void>.delayed(Duration.zero);
        expect(model.stale, true);
        expect(model.workspaces, isEmpty);
      } finally {
        model.dispose();
      }
    },
  );
}
