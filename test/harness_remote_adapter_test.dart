import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_event_log.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_sync.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_commands.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_execution.dart';

void main() {
  test('official WebSocket downlink retains task payload', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final adapter = HarnessOfficialRemoteAdapter(
      Uri.parse('http://127.0.0.1:${server.port}/?token=local-ui-secret'),
    );
    server.listen((request) async {
      if (request.uri.path == '/') {
        expect(request.uri.queryParameters['token'], 'local-ui-secret');
        request.response.cookies.add(Cookie('dsh_session', 'signed'));
        request.response.statusCode = HttpStatus.found;
        await request.response.close();
        return;
      }
      expect(request.uri.path, '/api/remote.mux');
      expect(request.uri.hasQuery, isFalse);
      expect(request.cookies.single.value, 'signed');
      final socket = await WebSocketTransformer.upgrade(request);
      final open = jsonDecode(await socket.first as String) as Map;
      expect(open['endpoint'], r'$events');
      socket.add(
        jsonEncode({
          'type': 'item',
          'streamId': open['streamId'],
          'value': {
            'type': 'emit',
            'event': 'api-session/status',
            'args': ['s', true],
          },
        }),
      );
      await socket.close();
    });
    try {
      final event = await adapter.events().first.timeout(
        const Duration(seconds: 5),
      );
      expect(event['method'], 'api-session/status');
      expect((event['payload'] as Map)['sessionId'], 's');
    } finally {
      await adapter.close();
      await server.close(force: true);
    }
  });
  test(
    'scoped execution reaches HTTP once and revoked callers cannot replay',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final adapter = HarnessOfficialRemoteAdapter(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final execution = HarnessRemoteExecution(
        adapter: adapter,
        workspaceForSession: (session) async => session == 's' ? 'w' : null,
      );
      var calls = 0;
      server.listen((request) async {
        calls++;
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'type': 'server-response',
            'rpcId': body['rpcId'],
            'result': {'ok': true, 'value': {}},
          }),
        );
        await request.response.close();
      });
      final command = HarnessRemoteCommand(
        id: 'cmd',
        workspaceId: 'w',
        sessionId: 's',
        operation: 'session.cancel',
        arguments: {'sessionId': 's'},
      );
      execution.grant(
        HarnessRemoteGrant(
          peerId: 'peer',
          workspaceIds: {'w'},
          operations: {'session.cancel'},
        ),
      );
      try {
        await execution.dispatch('peer', command);
        await execution.dispatch('peer', command);
        expect(calls, 1);
        await expectLater(
          execution.dispatch('unknown', command),
          throwsStateError,
        );
        execution.revoke('peer');
        await expectLater(
          execution.dispatch('peer', command),
          throwsStateError,
        );
        expect(calls, 1);
      } finally {
        await execution.close();
        await server.close(force: true);
      }
    },
  );
  test(
    'official HTTP carrier preserves envelope and rejects mismatched rpcId',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final adapter = HarnessOfficialRemoteAdapter(
        Uri.parse('http://127.0.0.1:${server.port}/?token=local-ui-secret'),
      );
      var mismatch = false;
      server.listen((request) async {
        if (request.uri.path == '/') {
          expect(request.uri.queryParameters['token'], 'local-ui-secret');
          request.response.cookies.add(Cookie('dsh_session', 'signed'));
          request.response.statusCode = HttpStatus.found;
          await request.response.close();
          return;
        }
        expect(request.uri.path, '/api/session/cancel');
        expect(request.uri.hasQuery, isFalse);
        expect(request.cookies.single.value, 'signed');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'type': 'server-response',
            'rpcId': mismatch ? 'wrong' : body['rpcId'],
            'result': {
              'ok': true,
              'value': {'items': []},
            },
          }),
        );
        await request.response.close();
      });
      final message = <String, dynamic>{
        'type': 'client-request',
        'rpcId': 'one',
        'method': 'session.cancel',
        'payload': {'sessionId': 'session'},
      };
      try {
        final result = await adapter.request(message);
        expect(result['rpcId'], 'one');
        mismatch = true;
        await expectLater(adapter.request(message), throwsFormatException);
      } finally {
        await adapter.close();
        await server.close(force: true);
      }
    },
  );

  test('rejects remote or credential-bearing execution endpoints', () {
    for (final url in [
      'https://127.0.0.1:1234',
      'http://192.168.3.63:1234',
      'http://user:secret@127.0.0.1:1234',
      'http://127.0.0.1:1234/api',
      'http://127.0.0.1:1234/#fragment',
    ]) {
      expect(
        () => HarnessOfficialRemoteAdapter(Uri.parse(url)),
        throwsArgumentError,
      );
    }
    for (final url in [
      'http://127.0.0.1:1234/?other=value',
      'http://127.0.0.1:1234/?token=',
    ]) {
      expect(
        () => HarnessOfficialRemoteAdapter(Uri.parse(url)),
        throwsFormatException,
      );
    }
  });

  test(
    'normalizes the official Harness localhost endpoint to IPv4 loopback',
    () {
      final adapter = HarnessOfficialRemoteAdapter(
        Uri.parse('http://localhost:55001/?token=local-ui-secret'),
      );
      expect(adapter.endpoint, Uri.parse('http://127.0.0.1:55001'));
    },
  );

  test('scoped batches advance over hidden events without leaking them', () {
    final log = HarnessRemoteEventLog(epoch: 'e');
    log.append('private', {'text': 'secret'});
    log.append('public', {'text': 'visible'});
    final batch = log.read(
      afterEpoch: 'e',
      afterSequence: 0,
      authorizedWorkspaces: {'public'},
    );
    expect((batch['events'] as List).length, 1);
    expect(jsonEncode(batch), isNot(contains('secret')));
    final cursor = HarnessRemoteSyncCursor()..connected();
    cursor.acceptSnapshot(epoch: 'e', sequence: 0);
    expect(
      cursor.acceptBatch(
        epoch: 'e',
        afterSequence: 0,
        nextSequence: 2,
        visibleSequences: [2],
      ),
      HarnessRemoteEventDecision.apply,
    );
    expect(cursor.sequence, 2);
  });

  test('journal eviction explicitly requests snapshot', () {
    final log = HarnessRemoteEventLog(epoch: 'e', maxEvents: 1);
    log.append('w', {'a': 1});
    log.append('w', {'a': 2});
    expect(
      log.read(
        afterEpoch: 'e',
        afterSequence: 0,
        authorizedWorkspaces: {'w'},
      )['snapshotRequired'],
      true,
    );
  });
}
