import 'dart:convert';
import 'dart:io';

import 'tool_result.dart';

/// 网络开发工具（docs/06 §6.4，DEV-005/006）。
///
/// 仅由用户主动触发联网；提供超时与取消语义。
abstract final class NetworkTools {
  static ToolResult urlParse(String input) {
    final Uri? uri = Uri.tryParse(input.trim());
    if (uri == null) {
      return const ToolFailure('URL 解析失败：不是合法的 URL');
    }
    return ToolSuccess(
      'scheme: ${uri.scheme}\n'
      'host: ${uri.host}\n'
      'port: ${uri.hasPort ? uri.port : '-'}\n'
      'path: ${uri.path}\n'
      'query: ${uri.query}\n'
      'fragment: ${uri.fragment}',
    );
  }

  static ToolResult cidrCalc(String input) {
    final List<String> parts = input.trim().split('/');
    if (parts.length != 2) {
      return const ToolFailure('CIDR 格式应为 a.b.c.d/prefix');
    }
    final InternetAddress? address = InternetAddress.tryParse(parts[0]);
    final int? prefix = int.tryParse(parts[1]);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return const ToolFailure('仅支持 IPv4 地址');
    }
    if (prefix == null || prefix < 0 || prefix > 32) {
      return const ToolFailure('前缀必须是 0～32');
    }
    final List<int> raw = address.rawAddress; // 4 字节
    final int ip = (raw[0] << 24) | (raw[1] << 16) | (raw[2] << 8) | raw[3];
    final int mask = prefix == 0
        ? 0
        : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final int network = ip & mask;
    final int broadcast = network | (~mask & 0xFFFFFFFF);
    final int count = prefix >= 31
        ? (prefix == 32 ? 1 : 2)
        : (1 << (32 - prefix));

    String fmt(int value) => <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ].map((int v) => v.toString()).join('.');
    return ToolSuccess(
      '网络地址: ${fmt(network)}/$prefix\n'
      '广播地址: ${fmt(broadcast)}\n'
      '可用数量: $count',
    );
  }

  static Future<ToolResult> dnsLookup(String host) async {
    final String target = host.trim();
    if (target.isEmpty) {
      return const ToolFailure('域名不能为空');
    }
    try {
      final List<InternetAddress> results = await InternetAddress.lookup(
        target,
      );
      if (results.isEmpty) {
        return const ToolSuccess('无解析结果');
      }
      return ToolSuccess(
        results
            .map((InternetAddress a) => '${a.type.name}  ${a.address}')
            .join('\n'),
      );
    } catch (e) {
      return ToolFailure('DNS 查询失败：$e');
    }
  }

  static Future<ToolResult> tcpPort(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final Socket socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return ToolSuccess('$host:$port 可连接');
    } catch (e) {
      return ToolFailure('$host:$port 连接失败：$e');
    }
  }

  static Future<ToolResult> httpRequest(
    String method,
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return const ToolFailure('URL 非法');
    }
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest request = await client.openUrl(method, uri);
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final StringBuffer headers = StringBuffer();
      response.headers.forEach((String name, List<String> values) {
        headers.writeln('  $name: ${values.join(', ')}');
      });
      return ToolSuccess(
        '状态: ${response.statusCode} ${response.reasonPhrase}\n'
        '响应头:\n$headers'
        '\n响应体:\n$body',
      );
    } catch (e) {
      return ToolFailure('HTTP 请求失败：$e');
    } finally {
      client.close(force: true);
    }
  }
}
