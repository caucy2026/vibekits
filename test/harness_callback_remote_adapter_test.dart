import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_callback_remote_adapter.dart';

void main() {
  test(
    'mobile callback adapter preserves official envelopes and live events',
    () async {
      final adapter = HarnessCallbackRemoteAdapter((method, payload) async {
        expect(method, 'workspace.list');
        expect(payload, isEmpty);
        return const <String, Object?>{
          'ok': true,
          'value': <String, Object?>{'items': <Object?>[]},
        };
      });
      var connected = false;
      final event = Completer<Map<String, dynamic>>();
      final subscription = adapter
          .events(onConnected: () => connected = true)
          .listen(event.complete);
      await Future<void>.delayed(Duration.zero);
      expect(connected, isTrue);
      final response = await adapter.request(const <String, dynamic>{
        'type': 'client-request',
        'rpcId': 'rpc-1',
        'method': 'workspace.list',
        'payload': <String, dynamic>{},
      });
      expect(response['type'], 'server-response');
      expect(response['rpcId'], 'rpc-1');
      expect((response['result'] as Map)['ok'], isTrue);
      adapter.publish(const <String, dynamic>{
        'type': 'server-request',
        'rpcId': 'event-1',
        'payload': <String, dynamic>{'sessionId': 's'},
      });
      expect((await event.future)['rpcId'], 'event-1');
      await subscription.cancel();
      await adapter.close();
      await expectLater(
        adapter.request(const <String, dynamic>{
          'type': 'client-request',
          'rpcId': 'rpc-2',
          'method': 'workspace.list',
          'payload': <String, dynamic>{},
        }),
        throwsStateError,
      );
    },
  );
}
