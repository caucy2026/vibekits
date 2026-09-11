import 'dart:async';

import 'harness_remote_controller_session.dart';

/// Process-wide owner for the controller-side Harness connection.
///
/// The Advanced settings page only configures or starts a connection. Closing
/// that page must not tear down the P2P/relay tunnel: the main Harness surface
/// consumes the same session until the user explicitly disconnects it.
final class HarnessRemoteControllerRuntime {
  HarnessRemoteControllerRuntime._();

  static final HarnessRemoteControllerRuntime instance =
      HarnessRemoteControllerRuntime._();

  final StreamController<HarnessRemoteControllerSession?> _changes =
      StreamController<HarnessRemoteControllerSession?>.broadcast(sync: true);
  HarnessRemoteControllerSession? _session;

  HarnessRemoteControllerSession? get session => _session;
  Stream<HarnessRemoteControllerSession?> get changes => _changes.stream;

  Future<void> adopt(HarnessRemoteControllerSession session) async {
    if (identical(_session, session)) return;
    final previous = _session;
    _session = session;
    _changes.add(session);
    await previous?.close();
  }

  Future<void> close() async {
    final previous = _session;
    if (previous == null) return;
    _session = null;
    _changes.add(null);
    await previous.close();
  }
}
