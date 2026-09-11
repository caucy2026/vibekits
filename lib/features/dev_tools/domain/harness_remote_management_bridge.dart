/// App-level bridge between the Advanced settings page and the currently
/// running Harness backend.
///
/// Remote configuration must not own, cover, rebuild, or navigate the Harness
/// WebView. The workspace registers only these bounded lifecycle callbacks;
/// the settings page invokes them without reaching into WebView state.
class HarnessRemoteManagementBridge {
  HarnessRemoteManagementBridge._();

  static Object? _owner;
  static Future<void> Function()? _startHost;
  static Future<void> Function()? _stopHost;
  static Set<String> Function()? _localWorkspaceIds;

  static void bind({
    required Object owner,
    required Future<void> Function() startHost,
    required Future<void> Function() stopHost,
    required Set<String> Function() localWorkspaceIds,
  }) {
    _owner = owner;
    _startHost = startHost;
    _stopHost = stopHost;
    _localWorkspaceIds = localWorkspaceIds;
  }

  static void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _startHost = null;
    _stopHost = null;
    _localWorkspaceIds = null;
  }

  static Future<void> startHost() async {
    final callback = _startHost;
    if (callback == null) {
      throw StateError('HARNESS_BACKEND_NOT_READY');
    }
    await callback();
  }

  static Future<void> stopHost() async {
    final callback = _stopHost;
    if (callback != null) await callback();
  }

  static Set<String> localWorkspaceIds() =>
      _localWorkspaceIds?.call() ?? const <String>{};
}
