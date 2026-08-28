import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_link_status.dart';

void main() {
  tearDown(() => RustDeskHarnessLinkStatusHub.disconnected());

  test('发现客户端不会误报已连接', () {
    RustDeskHarnessLinkStatusHub.clientFound();
    expect(RustDeskHarnessLinkStatusHub.latest.waiting, isTrue);
    expect(RustDeskHarnessLinkStatusHub.latest.connected, isFalse);
  });

  test('只有兼容握手才进入已连接', () {
    expect(
      RustDeskHarnessLinkStatusHub.acceptHandshake(<String, Object?>{
        'protocol': RustDeskHarnessLinkStatusHub.protocol,
        'versions': <int>[1],
        'peerId': 'kemi-host-01',
      }),
      isTrue,
    );
    expect(RustDeskHarnessLinkStatusHub.latest.connected, isTrue);
    expect(RustDeskHarnessLinkStatusHub.latest.protocolVersion, 1);
  });

  test('协议不兼容时拒绝连接', () {
    expect(
      RustDeskHarnessLinkStatusHub.acceptHandshake(<String, Object?>{
        'protocol': RustDeskHarnessLinkStatusHub.protocol,
        'versions': <int>[2],
        'peerId': 'kemi-host-02',
      }),
      isFalse,
    );
    expect(
      RustDeskHarnessLinkStatusHub.latest.phase,
      RustDeskHarnessLinkPhase.incompatible,
    );
  });

  test('心跳必须匹配握手 peer 和版本', () {
    RustDeskHarnessLinkStatusHub.acceptHandshake(<String, Object?>{
      'protocol': RustDeskHarnessLinkStatusHub.protocol,
      'versions': <int>[1],
      'peerId': 'kemi-host-03',
    });
    expect(
      RustDeskHarnessLinkStatusHub.acceptHeartbeat(
        peerId: 'another-host',
        version: 1,
      ),
      isFalse,
    );
    expect(
      RustDeskHarnessLinkStatusHub.acceptHeartbeat(
        peerId: 'kemi-host-03',
        version: 1,
      ),
      isTrue,
    );
  });
}
