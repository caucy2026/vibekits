import 'dart:async';

import 'platform_credential_store.dart';

typedef ClusterTaskSettingReader = Future<String?> Function(String key);
typedef ClusterTaskSettingWriter =
    Future<void> Function(String key, String value);

/// Local configuration for the cluster task device agent.
///
/// This class deliberately owns no network client and has no dependency on the
/// Harness runtime. Until a server URL, trusted hosts and signing key are all
/// configured, the switch remains on in a harmless waiting state and no
/// network activity is started.
final class ClusterTaskSettings {
  ClusterTaskSettings({
    ClusterTaskSettingReader? read,
    ClusterTaskSettingWriter? write,
  }) : _read = read ?? PlatformCredentialStore.read,
       _write = write ?? PlatformCredentialStore.write;

  static const String _enabledKey = 'cluster-task-v1-enabled';
  static const String _serverUrlKey = 'cluster-task-v1-server-url';
  static const String _trustedHostsKey = 'cluster-task-v1-trusted-hosts';
  static const String _signingKeyKey = 'cluster-task-v1-signing-public-key';
  static final StreamController<ClusterTaskConfiguration> _changes =
      StreamController<ClusterTaskConfiguration>.broadcast();
  static ClusterTaskConfiguration _latest = const ClusterTaskConfiguration();

  final ClusterTaskSettingReader _read;
  final ClusterTaskSettingWriter _write;

  static ClusterTaskConfiguration get latest => _latest;
  static Stream<ClusterTaskConfiguration> get changes => _changes.stream;

  Future<ClusterTaskConfiguration> load() async {
    final storedEnabled = (await _read(_enabledKey))?.trim().toLowerCase();
    final configuration = ClusterTaskConfiguration(
      enabled: storedEnabled == null ? true : storedEnabled == 'true',
      serverUrl: (await _read(_serverUrlKey))?.trim() ?? '',
      trustedHosts: _splitHosts(await _read(_trustedHostsKey)),
      signingPublicKey: (await _read(_signingKeyKey))?.trim() ?? '',
    );
    return _publish(configuration);
  }

  Future<ClusterTaskConfiguration> saveConfiguration({
    required String serverUrl,
    required Iterable<String> trustedHosts,
    required String signingPublicKey,
  }) async {
    final normalizedUrl = serverUrl.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (normalizedUrl.isNotEmpty &&
        (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
      throw const FormatException('集群任务服务必须使用有效的 HTTPS 地址');
    }
    final hosts =
        trustedHosts
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    await _write(_serverUrlKey, normalizedUrl);
    await _write(_trustedHostsKey, hosts.join(','));
    await _write(_signingKeyKey, signingPublicKey.trim());
    final configuration = ClusterTaskConfiguration(
      enabled: _latest.enabled,
      serverUrl: normalizedUrl,
      trustedHosts: hosts,
      signingPublicKey: signingPublicKey.trim(),
    );
    return _publish(configuration);
  }

  Future<ClusterTaskConfiguration> saveEnabled(bool value) async {
    var configuration = _latest;
    if (configuration.serverUrl.isEmpty &&
        configuration.trustedHosts.isEmpty &&
        configuration.signingPublicKey.isEmpty) {
      configuration = await load();
    }
    await _write(_enabledKey, value ? 'true' : 'false');
    return _publish(configuration.copyWith(enabled: value));
  }

  static List<String> _splitHosts(String? value) =>
      (value ?? '')
          .split(',')
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  static ClusterTaskConfiguration _publish(
    ClusterTaskConfiguration configuration,
  ) {
    _latest = configuration;
    _changes.add(configuration);
    return configuration;
  }
}

final class ClusterTaskConfiguration {
  const ClusterTaskConfiguration({
    this.enabled = true,
    this.serverUrl = '',
    this.trustedHosts = const <String>[],
    this.signingPublicKey = '',
  });

  final bool enabled;
  final String serverUrl;
  final List<String> trustedHosts;
  final String signingPublicKey;

  bool get configured {
    final uri = Uri.tryParse(serverUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        trustedHosts.isNotEmpty &&
        signingPublicKey.isNotEmpty;
  }

  String get phase => !configured
      ? enabled
            ? 'waiting_configuration'
            : 'disabled'
      : enabled
      ? 'enabled'
      : 'disabled';

  ClusterTaskConfiguration copyWith({bool? enabled}) =>
      ClusterTaskConfiguration(
        enabled: enabled ?? this.enabled,
        serverUrl: serverUrl,
        trustedHosts: trustedHosts,
        signingPublicKey: signingPublicKey,
      );

  Map<String, Object?> toSafeJson() => <String, Object?>{
    'enabled': enabled,
    'configured': configured,
    'phase': phase,
    'serverOrigin': _safeOrigin(serverUrl),
    'trustedHosts': trustedHosts,
    'hasSigningPublicKey': signingPublicKey.isNotEmpty,
  };

  static String _safeOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
}
