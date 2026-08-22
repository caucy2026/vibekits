import 'dart:convert';
import 'dart:io';

class MihomoProxyGroup {
  const MihomoProxyGroup({
    required this.name,
    required this.type,
    required this.selected,
    required this.nodes,
  });

  final String name;
  final String type;
  final String selected;
  final List<String> nodes;
}

class MihomoControllerSnapshot {
  const MihomoControllerSnapshot({
    required this.mode,
    required this.groups,
    required this.connectionCount,
    required this.downloadTotal,
    required this.uploadTotal,
  });

  final String mode;
  final List<MihomoProxyGroup> groups;
  final int connectionCount;
  final int downloadTotal;
  final int uploadTotal;
}

class MihomoControllerService {
  MihomoControllerService(this.endpoint, {this.secret = ''});

  final Uri endpoint;
  final String secret;

  Future<MihomoControllerSnapshot> snapshot() async {
    final Map<String, Object?> configs = await _json('GET', '/configs');
    final Map<String, Object?> proxies = await _json('GET', '/proxies');
    Map<String, Object?> connections = const <String, Object?>{};
    try {
      connections = await _json('GET', '/connections');
    } on Object {
      // Older Mihomo builds may disable the connections endpoint.
    }
    final List<MihomoProxyGroup> groups = <MihomoProxyGroup>[];
    final Object? proxyMap = proxies['proxies'];
    if (proxyMap is Map) {
      for (final MapEntry<Object?, Object?> entry in proxyMap.entries) {
        if (entry.value is! Map) continue;
        final Map value = entry.value! as Map;
        final List<String> nodes = (value['all'] as List? ?? const <Object>[])
            .map((Object? item) => '$item')
            .where((String item) => item.isNotEmpty)
            .toList(growable: false);
        if (nodes.isEmpty) continue;
        groups.add(
          MihomoProxyGroup(
            name: '${entry.key}',
            type: '${value['type'] ?? ''}',
            selected: '${value['now'] ?? ''}',
            nodes: nodes,
          ),
        );
      }
    }
    final List connectionsList =
        connections['connections'] as List? ?? const <Object>[];
    return MihomoControllerSnapshot(
      mode: '${configs['mode'] ?? 'rule'}'.toLowerCase(),
      groups: groups,
      connectionCount: connectionsList.length,
      downloadTotal: _integer(connections['downloadTotal']),
      uploadTotal: _integer(connections['uploadTotal']),
    );
  }

  Future<void> setMode(String mode) async {
    if (!const <String>{'rule', 'global', 'direct'}.contains(mode)) {
      throw const FormatException('代理模式无效');
    }
    await _json('PATCH', '/configs', body: <String, Object?>{'mode': mode});
  }

  Future<void> selectNode(String group, String node) async {
    if (group.isEmpty ||
        node.isEmpty ||
        group.length > 300 ||
        node.length > 300) {
      throw const FormatException('代理组或节点无效');
    }
    await _json(
      'PUT',
      '/proxies/${Uri.encodeComponent(group)}',
      body: <String, Object?>{'name': node},
    );
  }

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (!endpoint.isAbsolute ||
        endpoint.host != InternetAddress.loopbackIPv4.address &&
            endpoint.host != 'localhost') {
      throw const FormatException('Mihomo 控制端口只允许本机回环地址');
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final Uri uri = endpoint.replace(path: path);
      final HttpClientRequest request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 1));
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      final String text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Mihomo 控制接口失败（HTTP ${response.statusCode}）');
      }
      if (text.trim().isEmpty) return const <String, Object?>{};
      final Object? decoded = jsonDecode(text);
      return decoded is Map
          ? decoded.map((Object? key, Object? value) => MapEntry('$key', value))
          : const <String, Object?>{};
    } finally {
      client.close(force: true);
    }
  }

  static int _integer(Object? value) => value is num ? value.toInt() : 0;
}
