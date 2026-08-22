import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'platform_credential_store.dart';
import 'system_proxy_service.dart';

typedef MihomoCredentialReader = Future<String?> Function(String key);
typedef MihomoCredentialWriter = Future<void> Function(
  String key,
  String value,
);
typedef MihomoCredentialDeleter = Future<void> Function(String key);
typedef MihomoProxyResolver = Future<String?> Function();

class MihomoConfigSummary {
  const MihomoConfigSummary({
    required this.mixedPort,
    required this.controller,
    required this.mode,
    required this.proxyCount,
    required this.secret,
  });

  final int mixedPort;
  final Uri? controller;
  final String mode;
  final int proxyCount;
  final String secret;

  static MihomoConfigSummary parse(String yaml) {
    String? value(String key) {
      final RegExpMatch? match = RegExp(
        '^${RegExp.escape(key)}\\s*:\\s*(.*?)\\s*\$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(yaml);
      return match?.group(1)?.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
    }

    final int port =
        int.tryParse(value('mixed-port') ?? '') ??
        int.tryParse(value('port') ?? '') ??
        7890;
    final String controllerValue = value('external-controller') ?? '';
    final Uri? controller = controllerValue.isEmpty
        ? null
        : Uri.tryParse(
            controllerValue.contains('://')
                ? controllerValue
                : 'http://$controllerValue',
          );
    int proxyCount = 0;
    bool inProxies = false;
    for (final String line in const LineSplitter().convert(yaml)) {
      if (RegExp(r'^proxies\s*:', caseSensitive: false).hasMatch(line)) {
        inProxies = true;
        continue;
      }
      if (inProxies && line.isNotEmpty && !RegExp(r'^\s').hasMatch(line)) {
        inProxies = false;
      }
      if (inProxies && RegExp(r'^\s+-\s+').hasMatch(line)) {
        proxyCount++;
      }
    }
    return MihomoConfigSummary(
      mixedPort: port.clamp(1, 65535),
      controller: controller,
      mode: (value('mode') ?? 'rule').toLowerCase(),
      proxyCount: proxyCount,
      secret: value('secret') ?? '',
    );
  }
}

class MihomoManagedConfig {
  const MihomoManagedConfig({required this.path, required this.summary});

  final String path;
  final MihomoConfigSummary summary;
}

class MihomoProfile {
  const MihomoProfile({
    required this.id,
    required this.name,
    required this.path,
    required this.sourceHost,
    required this.updatedAt,
    required this.summary,
    required this.subscription,
  });

  final String id;
  final String name;
  final String path;
  final String sourceHost;
  final DateTime updatedAt;
  final MihomoConfigSummary summary;
  final bool subscription;

  String get credentialKey => 'mihomo-subscription-$id';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'path': path,
    'sourceHost': sourceHost,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'subscription': subscription,
  };
}

class MihomoProfileState {
  const MihomoProfileState({required this.profiles, this.activeId});

  final List<MihomoProfile> profiles;
  final String? activeId;
}

class MihomoProfileService {
  MihomoProfileService({
    required this.dataDirectory,
    this.credentialReader = PlatformCredentialStore.read,
    this.credentialWriter = PlatformCredentialStore.write,
    this.credentialDeleter = PlatformCredentialStore.delete,
    this.proxyResolver = _defaultProxyResolver,
  });

  static const int _maxConfigBytes = 32 * 1024 * 1024;
  final String dataDirectory;
  final MihomoCredentialReader credentialReader;
  final MihomoCredentialWriter credentialWriter;
  final MihomoCredentialDeleter credentialDeleter;
  final MihomoProxyResolver proxyResolver;

  Directory get _profilesDirectory =>
      Directory('$dataDirectory${Platform.pathSeparator}profiles');
  File get _manifest =>
      File('$dataDirectory${Platform.pathSeparator}profiles.json');
  File get _activityLog =>
      File('$dataDirectory${Platform.pathSeparator}subscription.log');

  Future<List<String>> readActivityLog({int limit = 100}) async {
    if (!await _activityLog.exists()) return const <String>[];
    final List<String> lines = await _activityLog.readAsLines();
    return lines.skip((lines.length - limit).clamp(0, lines.length)).toList();
  }

  Future<MihomoProfileState> load() async {
    if (!await _manifest.exists()) {
      return const MihomoProfileState(profiles: <MihomoProfile>[]);
    }
    try {
      final Object? decoded = jsonDecode(await _manifest.readAsString());
      if (decoded is! Map) throw const FormatException('订阅清单格式错误');
      final List<MihomoProfile> profiles = <MihomoProfile>[];
      for (final Object? raw
          in (decoded['profiles'] as List? ?? const <Object>[])) {
        if (raw is! Map) continue;
        final String id = '${raw['id'] ?? ''}';
        final String path = '${raw['path'] ?? ''}';
        final File file = File(path);
        if (!RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(id) ||
            !file.isAbsolute ||
            !await file.exists()) {
          continue;
        }
        final String yaml = await _readConfig(file);
        profiles.add(
          MihomoProfile(
            id: id,
            name: '${raw['name'] ?? '未命名配置'}'.trim(),
            path: file.path,
            sourceHost: '${raw['sourceHost'] ?? ''}',
            updatedAt:
                DateTime.tryParse('${raw['updatedAt'] ?? ''}')?.toLocal() ??
                (await file.lastModified()).toLocal(),
            summary: MihomoConfigSummary.parse(yaml),
            subscription: raw['subscription'] == true,
          ),
        );
      }
      final String? activeId = decoded['activeId'] is String
          ? decoded['activeId']! as String
          : null;
      return MihomoProfileState(
        profiles: profiles,
        activeId: profiles.any((MihomoProfile item) => item.id == activeId)
            ? activeId
            : profiles.firstOrNull?.id,
      );
    } on Object {
      return const MihomoProfileState(profiles: <MihomoProfile>[]);
    }
  }

  Future<MihomoProfile> importConfig({
    required String sourcePath,
    String? displayName,
  }) async {
    final File source = File(sourcePath.trim());
    if (!source.isAbsolute || !await source.exists()) {
      throw const FormatException('请选择存在的 Clash YAML 配置');
    }
    final String yaml = await _readConfig(source);
    final String id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await _profilesDirectory.create(recursive: true);
    final File target = File(
      '${_profilesDirectory.path}${Platform.pathSeparator}$id.yaml',
    );
    await _atomicWrite(target, yaml);
    final MihomoProfile profile = MihomoProfile(
      id: id,
      name: _safeName(displayName ?? _basename(source.path)),
      path: target.path,
      sourceHost: '本地文件',
      updatedAt: DateTime.now(),
      summary: MihomoConfigSummary.parse(yaml),
      subscription: false,
    );
    await _upsert(profile, makeActive: true);
    await _log('导入成功 name=${profile.name} source=local');
    return profile;
  }

  Future<MihomoProfile> addSubscription({
    required String name,
    required String url,
  }) async {
    final Uri uri = _validatedSubscriptionUri(url);
    final String id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final String yaml = await _download(uri);
    await _profilesDirectory.create(recursive: true);
    final File target = File(
      '${_profilesDirectory.path}${Platform.pathSeparator}$id.yaml',
    );
    await _atomicWrite(target, yaml);
    final MihomoProfile profile = MihomoProfile(
      id: id,
      name: _safeName(name.trim().isEmpty ? uri.host : name),
      path: target.path,
      sourceHost: uri.host,
      updatedAt: DateTime.now(),
      summary: MihomoConfigSummary.parse(yaml),
      subscription: true,
    );
    try {
      await credentialWriter(profile.credentialKey, uri.toString());
      await _upsert(profile, makeActive: true);
      await _log(
        '订阅成功 host=${uri.host} bytes=${utf8.encode(yaml).length} '
        'nodes=${profile.summary.proxyCount}',
      );
      return profile;
    } on Object catch (error) {
      await _log(
        '订阅失败 host=${uri.host} stage=credential '
        'error=${_safeError(error, uri)}',
      );
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  Future<MihomoProfile> update(MihomoProfile profile) async {
    if (!profile.subscription) throw StateError('本地配置不能在线更新');
    final String? secretUrl = await credentialReader(profile.credentialKey);
    if (secretUrl == null || secretUrl.trim().isEmpty) {
      throw StateError('订阅凭据已丢失，请删除后重新添加');
    }
    final Uri uri = _validatedSubscriptionUri(secretUrl);
    final String yaml = await _download(uri);
    final File target = File(profile.path);
    await _atomicWrite(target, yaml);
    final MihomoProfile updated = MihomoProfile(
      id: profile.id,
      name: profile.name,
      path: profile.path,
      sourceHost: uri.host,
      updatedAt: DateTime.now(),
      summary: MihomoConfigSummary.parse(yaml),
      subscription: true,
    );
    await _upsert(updated, makeActive: true);
    await _log(
      '更新成功 host=${uri.host} bytes=${utf8.encode(yaml).length} '
      'nodes=${updated.summary.proxyCount}',
    );
    return updated;
  }

  Future<void> select(String id) async {
    final MihomoProfileState state = await load();
    if (!state.profiles.any((MihomoProfile item) => item.id == id)) return;
    await _save(state.profiles, id);
  }

  Future<void> delete(MihomoProfile profile) async {
    final MihomoProfileState state = await load();
    final List<MihomoProfile> remaining = state.profiles
        .where((MihomoProfile item) => item.id != profile.id)
        .toList(growable: false);
    if (profile.subscription) await credentialDeleter(profile.credentialKey);
    final File file = File(profile.path);
    if (await file.exists()) await file.delete();
    await _save(
      remaining,
      state.activeId == profile.id ? remaining.firstOrNull?.id : state.activeId,
    );
  }

  Future<MihomoManagedConfig> prepareManagedConfig(
    MihomoProfile profile,
  ) async {
    String yaml = await _readConfig(File(profile.path));
    // Clash Verge treats a subscription as a profile and owns all local
    // inbound/control settings. Never trust or reuse ports supplied by a
    // remote profile: they may conflict with another Clash instance.
    yaml = yaml.replaceAll(
      RegExp(
        r'^(mixed-port|port|socks-port|allow-lan|external-controller)\s*:.*(?:\r?\n|$)',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );
    final int mixedPort = await _freeLoopbackPort();
    int controllerPort = await _freeLoopbackPort();
    while (controllerPort == mixedPort) {
      controllerPort = await _freeLoopbackPort();
    }
    yaml =
        '$yaml${yaml.endsWith('\n') ? '' : '\n'}'
        'mixed-port: $mixedPort\n'
        'allow-lan: false\n'
        'external-controller: 127.0.0.1:$controllerPort\n';
    final MihomoConfigSummary summary = MihomoConfigSummary.parse(yaml);
    final File runtime = File(
      '$dataDirectory${Platform.pathSeparator}active-runtime.yaml',
    );
    await _atomicWrite(runtime, yaml);
    return MihomoManagedConfig(path: runtime.path, summary: summary);
  }

  static Future<int> _freeLoopbackPort() async {
    final ServerSocket socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _upsert(
    MihomoProfile profile, {
    required bool makeActive,
  }) async {
    final MihomoProfileState state = await load();
    final List<MihomoProfile> profiles = <MihomoProfile>[
      ...state.profiles.where((MihomoProfile item) => item.id != profile.id),
      profile,
    ];
    await _save(profiles, makeActive ? profile.id : state.activeId);
  }

  Future<void> _save(List<MihomoProfile> profiles, String? activeId) async {
    await Directory(dataDirectory).create(recursive: true);
    final String payload = jsonEncode(<String, Object?>{
      'activeId': activeId,
      'profiles': profiles.map((MihomoProfile item) => item.toJson()).toList(),
    });
    await _atomicWrite(_manifest, payload);
  }

  Future<String> _download(Uri uri) async {
    String? proxy;
    if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
      try {
        proxy = await proxyResolver();
      } on Object {
        proxy = null;
      }
    }
    await _log(
      '开始订阅 host=${uri.host} route=${proxy == null ? 'direct' : 'system-proxy'}',
    );
    try {
      return await _downloadOnce(uri, proxy: proxy);
    } on Object catch (firstError) {
      if (proxy != null) {
        await _log(
          '代理下载失败，回退直连 host=${uri.host} '
          'error=${_safeError(firstError, uri)}',
        );
        try {
          return await _downloadOnce(uri);
        } on Object catch (directError) {
          final String safe = _safeError(directError, uri);
          await _log('订阅失败 host=${uri.host} stage=direct error=$safe');
          throw StateError('订阅下载失败：$safe');
        }
      }
      final String safe = _safeError(firstError, uri);
      await _log('订阅失败 host=${uri.host} stage=download error=$safe');
      throw StateError('订阅下载失败：$safe');
    }
  }

  Future<String> _downloadOnce(Uri uri, {String? proxy}) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
    try {
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/yaml, text/plain, */*',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'clash-verge/v2.4.3');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('订阅更新失败（HTTP ${response.statusCode}）');
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      int total = 0;
      await for (final List<int> chunk in response.timeout(
        const Duration(seconds: 20),
      )) {
        total += chunk.length;
        if (total > _maxConfigBytes) throw StateError('订阅配置超过 32 MiB');
        bytes.add(chunk);
      }
      final String yaml = utf8.decode(bytes.takeBytes(), allowMalformed: false);
      _validateConfig(yaml);
      return yaml;
    } finally {
      client.close(force: true);
    }
  }

  static Uri _validatedSubscriptionUri(String value) {
    if (value.trim().length > 1200) {
      throw const FormatException('订阅地址过长（最多 1200 字符）');
    }
    final Uri uri = Uri.parse(value.trim());
    final bool loopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (!uri.isAbsolute ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
      throw const FormatException('订阅必须使用 HTTPS；本机调试允许 HTTP loopback');
    }
    return uri;
  }

  static Future<String> _readConfig(File file) async {
    final int length = await file.length();
    if (length <= 0 || length > _maxConfigBytes) {
      throw const FormatException('Clash 配置必须在 1 B～32 MiB 之间');
    }
    final String yaml = await file.readAsString();
    _validateConfig(yaml);
    return yaml;
  }

  static void _validateConfig(String yaml) {
    if (RegExp(r'^\s*<(!doctype|html)', caseSensitive: false).hasMatch(yaml)) {
      throw const FormatException('订阅服务器返回了网页，不是 Clash 配置');
    }
    if (!RegExp(
      r'^\s*(mixed-port|port|socks-port|proxies|proxy-providers|rules)\s*:',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(yaml)) {
      throw const FormatException('订阅内容不是可识别的 Clash YAML');
    }
  }

  Future<void> _log(String message) async {
    await Directory(dataDirectory).create(recursive: true);
    if (await _activityLog.exists() &&
        await _activityLog.length() > 512 * 1024) {
      await _activityLog.delete();
    }
    await _activityLog.writeAsString(
      '[${DateTime.now().toIso8601String()}] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static String _safeError(Object error, Uri uri) => '$error'
      .replaceAll(uri.toString(), '${uri.scheme}://${uri.host}/…')
      .replaceAll(
        RegExp(r'([?&](token|key|auth)=)[^&\s]+', caseSensitive: false),
        r'$1***',
      );

  static Future<String?> _defaultProxyResolver() async {
    if (!Platform.isWindows) return null;
    final SystemProxySnapshot snapshot = await SystemProxyService().inspect();
    if (!snapshot.enabled || snapshot.server?.trim().isEmpty != false) {
      return null;
    }
    final String raw = snapshot.server!.trim();
    final Map<String, String> byScheme = <String, String>{};
    for (final String part in raw.split(';')) {
      final int separator = part.indexOf('=');
      if (separator > 0) {
        byScheme[part.substring(0, separator).trim().toLowerCase()] = part
            .substring(separator + 1)
            .trim();
      }
    }
    final String candidate = byScheme['https'] ?? byScheme['http'] ?? raw;
    return RegExp(r'^[^\s:;]+:\d{1,5}$').hasMatch(candidate) ? candidate : null;
  }

  static Future<void> _atomicWrite(File target, String value) async {
    await target.parent.create(recursive: true);
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  static String _safeName(String value) {
    final String safe = value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    return safe.isEmpty ? '未命名配置' : safe.substring(0, safe.length.clamp(0, 80));
  }

  static String _basename(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceFirst(RegExp(r'\.ya?ml\$', caseSensitive: false), '');
}
