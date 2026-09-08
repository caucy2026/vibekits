import 'harness_official_remote_adapter.dart';
import 'harness_remote_commands.dart';

/// Server-owned grant. Neither identity nor scope is read from wire payloads.
class HarnessRemoteGrant {
  HarnessRemoteGrant({
    required this.peerId,
    required Set<String> workspaceIds,
    required Set<String> operations,
  }) : workspaceIds = Set.unmodifiable(workspaceIds),
       operations = Set.unmodifiable(operations);
  final String peerId;
  final Set<String> workspaceIds;
  final Set<String> operations;
}

/// Scoped command execution over the official API, shared by all carriers.
/// Scope resolution must query the execution host, not trust a caller's label.
class HarnessRemoteExecution {
  HarnessRemoteExecution({
    required this.adapter,
    required this.workspaceForSession,
  }) {
    _gate = HarnessRemoteCommandGate(authorize: _authorize, execute: _execute);
  }

  final HarnessOfficialRemoteAdapter adapter;
  final Future<String?> Function(String sessionId) workspaceForSession;
  late final HarnessRemoteCommandGate _gate;
  final Map<String, HarnessRemoteGrant> _grants = {};
  int _authorizationRevision = 0;
  bool _closed = false;

  Set<String> visibleWorkspaceIds(String peerId) {
    final grant = _grants[peerId];
    if (_closed || grant == null) return const {};
    return grant.workspaceIds;
  }

  // This first adapter intentionally excludes settings/credentials/host paths.
  // Additional official operations require explicit scope mapping, never a
  // blanket proxy which would turn loopback trust into remote administrator.
  static const sessionOperations = {
    'session.history',
    'session.models',
    'session.selectModel',
    'session.rename',
    'session.prompt',
    'session.updateQueue',
    'session.cancel',
  };

  void grant(HarnessRemoteGrant grant) {
    if (_closed || grant.peerId.isEmpty) {
      throw StateError('REMOTE_GRANT_INVALID');
    }
    _grants[grant.peerId] = grant;
    _authorizationRevision++;
  }

  void revoke(String peerId) {
    _grants.remove(peerId);
    _authorizationRevision++;
  }

  Future<bool> _authorize(String peerId, HarnessRemoteCommand command) async {
    final revision = _authorizationRevision;
    final grant = _grants[peerId];
    if (_closed ||
        grant == null ||
        !sessionOperations.contains(command.operation) ||
        !grant.operations.contains(command.operation) ||
        !grant.workspaceIds.contains(command.workspaceId)) {
      return false;
    }
    final payload = command.arguments;
    if (payload['sessionId'] != command.sessionId) return false;
    final workspace = await workspaceForSession(command.sessionId);
    // A revoke during lookup must win over the in-flight authorization.
    return !_closed &&
        revision == _authorizationRevision &&
        workspace == command.workspaceId;
  }

  Future<Map<String, dynamic>> dispatch(
    String authenticatedPeerId,
    HarnessRemoteCommand command,
  ) => _gate.dispatch(authenticatedPeerId, command);

  Future<Map<String, Object?>> _execute(HarnessRemoteCommand command) async {
    final reply = await adapter.request({
      'type': 'client-request',
      'rpcId': command.id,
      'method': command.operation,
      'payload': command.arguments,
    });
    // Preserve the official result, including accepted vs actual completion.
    // In particular session.cancel acknowledgement is not an idle event.
    return reply;
  }

  Future<void> close() async {
    _closed = true;
    _grants.clear();
    _authorizationRevision++;
    await adapter.close();
  }
}
