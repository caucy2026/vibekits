import 'dart:async';

import 'package:flutter/material.dart';

import '../../dev_tools/domain/harness_remote_controller_runtime.dart';
import '../../dev_tools/domain/harness_simulator_controller.dart';
import '../../dev_tools/domain/harness_simulator_target_runtime.dart';
import '../../dev_tools/domain/rustdesk_harness_link_status.dart';

bool isHarnessConnectionLive({
  required bool remoteControllerConnected,
  required bool remoteLinkConnected,
  required bool simulatorControllerConnected,
  required bool simulatorTargetConnected,
}) =>
    remoteControllerConnected ||
    remoteLinkConnected ||
    simulatorControllerConnected ||
    simulatorTargetConnected;

/// The Harness tab light reflects an authenticated remote or simulator link.
class HarnessConnectionBadge extends StatefulWidget {
  const HarnessConnectionBadge({
    super.key,
    required this.running,
    required this.child,
  });

  final bool running;
  final Widget child;

  @override
  State<HarnessConnectionBadge> createState() => _HarnessConnectionBadgeState();
}

class _HarnessConnectionBadgeState extends State<HarnessConnectionBadge> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  ChangeNotifier? _remoteModel;

  @override
  void initState() {
    super.initState();
    _bindRemoteModel();
    _subscriptions.addAll([
      HarnessRemoteControllerRuntime.instance.changes.listen((_) {
        _bindRemoteModel();
        _refresh();
      }),
      RustDeskHarnessLinkStatusHub.changes.listen((_) => _refresh()),
      HarnessSimulatorController.shared.changes.listen((_) => _refresh()),
      HarnessSimulatorTargetRuntime.shared.changes.listen((_) => _refresh()),
    ]);
  }

  void _bindRemoteModel() {
    final next = HarnessRemoteControllerRuntime.instance.session?.model;
    if (identical(next, _remoteModel)) return;
    _remoteModel?.removeListener(_refresh);
    _remoteModel = next;
    _remoteModel?.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _remoteModel?.removeListener(_refresh);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteSession = HarnessRemoteControllerRuntime.instance.session;
    final connected = isHarnessConnectionLive(
      remoteControllerConnected:
          remoteSession != null && !remoteSession.model.stale,
      remoteLinkConnected: RustDeskHarnessLinkStatusHub.latest.connected,
      simulatorControllerConnected:
          HarnessSimulatorController.shared.status()['connected'] == true,
      simulatorTargetConnected:
          HarnessSimulatorTargetRuntime.shared.latest.phase ==
          HarnessSimulatorTargetPhase.connected,
    );
    return Badge(
      isLabelVisible: widget.running || connected,
      smallSize: 7,
      backgroundColor: connected ? Colors.green : null,
      child: widget.child,
    );
  }
}
