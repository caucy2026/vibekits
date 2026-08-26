import 'dart:async';
import 'dart:io';

import 'git_repository_service.dart';

enum DiagnosticStatus { ok, warning, failed }

class DiagnosticCheck {
  const DiagnosticCheck({
    required this.id,
    required this.label,
    required this.status,
    required this.detail,
    this.elapsed,
  });

  final String id;
  final String label;
  final DiagnosticStatus status;
  final String detail;
  final Duration? elapsed;
}

class GithubDiagnosticsReport {
  const GithubDiagnosticsReport({
    required this.checks,
    required this.recommendation,
  });

  final List<DiagnosticCheck> checks;
  final String recommendation;
}

abstract final class GithubDiagnosticsService {
  static Future<GithubDiagnosticsReport> run() async {
    final List<DiagnosticCheck> checks = await Future.wait(
      <Future<DiagnosticCheck>>[
        _credentials(),
        _dns(),
        _tcp('tcp443', 'GitHub TCP 443', 'github.com', 443),
        _tls(),
        _https(),
        _tcp('ssh22', 'SSH 端口 22', 'github.com', 22),
        _tcp('ssh443', 'SSH 备用端口 443', 'ssh.github.com', 443),
        _proxy(),
        _gitRoute(),
        Future<DiagnosticCheck>.value(_hosts()),
      ],
    );
    return GithubDiagnosticsReport(
      checks: checks,
      recommendation: recommendFor(checks),
    );
  }

  static String recommendFor(List<DiagnosticCheck> checks) {
    DiagnosticCheck? byId(String id) =>
        checks.where((DiagnosticCheck item) => item.id == id).firstOrNull;
    final DiagnosticCheck? https = byId('https');
    final DiagnosticCheck? credentials = byId('credentials');
    final DiagnosticCheck? gitRoute = byId('gitRoute');
    final DiagnosticCheck? ssh22 = byId('ssh22');
    final DiagnosticCheck? ssh443 = byId('ssh443');
    if (https?.status == DiagnosticStatus.failed) {
      return 'HTTPS 基础连接失败：先检查系统时间、代理、防火墙和 DNS；不要通过关闭 TLS 校验解决。';
    }
    if (gitRoute?.status == DiagnosticStatus.failed &&
        https?.status == DiagnosticStatus.ok) {
      return '浏览器 HTTPS 可达但内置 Git 路由失败；检查 Git host-scoped 代理、凭据和远端权限。';
    }
    if (ssh22?.status == DiagnosticStatus.failed &&
        ssh443?.status == DiagnosticStatus.ok) {
      return 'SSH 22 被阻断但 ssh.github.com:443 可用，可按 GitHub 官方文档显式配置 SSH over 443。';
    }
    if (credentials?.status != DiagnosticStatus.ok) {
      return '未确认 Git Credential Manager 账号；这与网络可达是两个独立状态，请先完成凭据登录。';
    }
    if (checks.any(
      (DiagnosticCheck item) =>
          item.id == 'hosts' && item.status == DiagnosticStatus.warning,
    )) {
      return 'hosts 中存在 GitHub 固定映射，可能已过期；请先备份并人工核对，不自动删除。';
    }
    if (checks.every(
      (DiagnosticCheck item) => item.status != DiagnosticStatus.failed,
    )) {
      return '基础链路正常；若下载仍慢，优先检查具体 Git 远端、代理策略和网络拥塞。';
    }
    return '按失败层级从 DNS → TLS → HTTPS → 代理/防火墙排查；本工具不会改 hosts 或安装证书。';
  }

  static String redactProxy(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri != null && uri.hasAuthority && uri.userInfo.isNotEmpty) {
      return uri.replace(userInfo: '***').toString();
    }
    return value.replaceAll(RegExp(r'//[^/@\s]+@'), '//***@');
  }

  static Future<DiagnosticCheck> _credentials() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final ProcessResult result = await Process.run(
        GitRepositoryService.bundledExecutable,
        <String>['credential-manager', 'github', 'list'],
        runInShell: false,
      ).timeout(const Duration(seconds: 6));
      watch.stop();
      final String output = '${result.stdout}'.trim();
      if (result.exitCode != 0 || output.isEmpty) {
        return DiagnosticCheck(
          id: 'credentials',
          label: 'GitHub 凭据账号',
          status: DiagnosticStatus.warning,
          detail: 'Git Credential Manager 未报告账号；未读取 Token',
          elapsed: watch.elapsed,
        );
      }
      final List<String> labels = output
          .split(RegExp(r'[\r\n]+'))
          .map(_redactCredentialLine)
          .where((String line) => line.isNotEmpty)
          .take(10)
          .toList(growable: false);
      return DiagnosticCheck(
        id: 'credentials',
        label: 'GitHub 凭据账号',
        status: labels.isEmpty ? DiagnosticStatus.warning : DiagnosticStatus.ok,
        detail: labels.isEmpty ? '存在凭据记录但未取得账号标签' : labels.join('\n'),
        elapsed: watch.elapsed,
      );
    } on Object catch (error) {
      return DiagnosticCheck(
        id: 'credentials',
        label: 'GitHub 凭据账号',
        status: DiagnosticStatus.warning,
        detail: '无法读取账号标签：${error.runtimeType}；未读取 Token',
        elapsed: watch.elapsed,
      );
    }
  }

  static String _redactCredentialLine(String value) => value
      .replaceAll(
        RegExp(r'(password|token|secret)\s*[:=]\s*\S+', caseSensitive: false),
        r'$1=***',
      )
      .replaceAll(RegExp(r'https?://[^/@\s]+@'), 'https://***@')
      .trim();

  static Future<DiagnosticCheck> _dns() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final List<InternetAddress> addresses = await InternetAddress.lookup(
        'github.com',
      ).timeout(const Duration(seconds: 5));
      watch.stop();
      return DiagnosticCheck(
        id: 'dns',
        label: 'DNS',
        status: addresses.isEmpty
            ? DiagnosticStatus.failed
            : DiagnosticStatus.ok,
        detail: addresses
            .take(4)
            .map((InternetAddress item) => item.address)
            .join(', '),
        elapsed: watch.elapsed,
      );
    } catch (error) {
      return DiagnosticCheck(
        id: 'dns',
        label: 'DNS',
        status: DiagnosticStatus.failed,
        detail: '$error',
        elapsed: watch.elapsed,
      );
    }
  }

  static Future<DiagnosticCheck> _tls() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final SecureSocket socket = await SecureSocket.connect(
        'github.com',
        443,
        timeout: const Duration(seconds: 6),
      );
      final X509Certificate? certificate = socket.peerCertificate;
      await socket.close();
      watch.stop();
      return DiagnosticCheck(
        id: 'tls',
        label: 'TLS 证书',
        status: DiagnosticStatus.ok,
        detail: certificate == null
            ? '系统校验通过'
            : '${certificate.subject} · 到期 ${certificate.endValidity.toLocal()}',
        elapsed: watch.elapsed,
      );
    } catch (error) {
      return DiagnosticCheck(
        id: 'tls',
        label: 'TLS 证书',
        status: DiagnosticStatus.failed,
        detail: '$error',
        elapsed: watch.elapsed,
      );
    }
  }

  static Future<DiagnosticCheck> _https() async {
    final Stopwatch watch = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final HttpClientRequest request = await client.openUrl(
        'HEAD',
        Uri.parse('https://github.com/'),
      );
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      watch.stop();
      return DiagnosticCheck(
        id: 'https',
        label: 'GitHub HTTPS',
        status: response.statusCode < 500
            ? DiagnosticStatus.ok
            : DiagnosticStatus.warning,
        detail: 'HTTP ${response.statusCode}',
        elapsed: watch.elapsed,
      );
    } catch (error) {
      return DiagnosticCheck(
        id: 'https',
        label: 'GitHub HTTPS',
        status: DiagnosticStatus.failed,
        detail: '$error',
        elapsed: watch.elapsed,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<DiagnosticCheck> _tcp(
    String id,
    String label,
    String host,
    int port,
  ) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Socket socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();
      watch.stop();
      return DiagnosticCheck(
        id: id,
        label: label,
        status: DiagnosticStatus.ok,
        detail: '$host:$port 可达',
        elapsed: watch.elapsed,
      );
    } catch (error) {
      return DiagnosticCheck(
        id: id,
        label: label,
        status: DiagnosticStatus.failed,
        detail: '$error',
        elapsed: watch.elapsed,
      );
    }
  }

  static Future<DiagnosticCheck> _proxy() async {
    final List<String> values = <String>[];
    for (final String name in <String>[
      'HTTPS_PROXY',
      'HTTP_PROXY',
      'ALL_PROXY',
      'https_proxy',
      'http_proxy',
    ]) {
      final String? value = Platform.environment[name];
      if (value != null && value.isNotEmpty) {
        values.add('$name=${redactProxy(value)}');
      }
    }
    try {
      for (final String key in <String>['http.proxy', 'https.proxy']) {
        final ProcessResult result = await Process.run(
          GitRepositoryService.bundledExecutable,
          <String>['config', '--global', '--get', key],
          runInShell: false,
        ).timeout(const Duration(seconds: 3));
        final String value = '${result.stdout}'.trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          values.add('git $key=${redactProxy(value)}');
        }
      }
    } on Object {
      // Git is optional for the proxy inventory.
    }
    if (Platform.isWindows) {
      try {
        final ProcessResult winInet = await Process.run('reg.exe', <String>[
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
          '/v',
          'ProxyEnable',
        ], runInShell: false).timeout(const Duration(seconds: 3));
        final String output = '${winInet.stdout}'.trim();
        values.add(output.contains('0x1') ? 'WinINet=已启用' : 'WinINet=未启用');
      } on Object {
        values.add('WinINet=无法读取');
      }
      try {
        final ProcessResult winHttp = await Process.run('netsh.exe', <String>[
          'winhttp',
          'show',
          'proxy',
        ], runInShell: false).timeout(const Duration(seconds: 3));
        final String output = '${winHttp.stdout}'
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim();
        values.add(
          'WinHTTP=${redactProxy(output.length > 300 ? output.substring(0, 300) : output)}',
        );
      } on Object {
        values.add('WinHTTP=无法读取');
      }
    }
    return DiagnosticCheck(
      id: 'proxy',
      label: '代理配置',
      status: values.isEmpty ? DiagnosticStatus.ok : DiagnosticStatus.warning,
      detail: values.isEmpty ? '未发现环境变量或全局 Git 代理' : values.join('\n'),
    );
  }

  static Future<DiagnosticCheck> _gitRoute() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final ProcessResult result = await Process.run(
        GitRepositoryService.bundledExecutable,
        <String>['ls-remote', 'https://github.com/git/git.git', 'HEAD'],
        runInShell: false,
      ).timeout(const Duration(seconds: 15));
      watch.stop();
      final String output = '${result.stdout}'.trim();
      return DiagnosticCheck(
        id: 'gitRoute',
        label: '内置 Git 路由',
        status: result.exitCode == 0 && output.isNotEmpty
            ? DiagnosticStatus.ok
            : DiagnosticStatus.failed,
        detail: result.exitCode == 0
            ? 'MinGit ls-remote HEAD 成功'
            : '失败：${_redactCredentialLine('${result.stderr}')}',
        elapsed: watch.elapsed,
      );
    } on Object catch (error) {
      return DiagnosticCheck(
        id: 'gitRoute',
        label: '内置 Git 路由',
        status: DiagnosticStatus.failed,
        detail: '失败：${error.runtimeType}',
        elapsed: watch.elapsed,
      );
    }
  }

  static DiagnosticCheck _hosts() {
    final String path = Platform.isWindows
        ? r'C:\Windows\System32\drivers\etc\hosts'
        : '/etc/hosts';
    try {
      final List<String> matches = File(path)
          .readAsLinesSync()
          .where(
            (String line) =>
                !line.trimLeft().startsWith('#') &&
                line.toLowerCase().contains('github'),
          )
          .take(20)
          .toList();
      return DiagnosticCheck(
        id: 'hosts',
        label: 'hosts 固定映射',
        status: matches.isEmpty
            ? DiagnosticStatus.ok
            : DiagnosticStatus.warning,
        detail: matches.isEmpty ? '未发现 GitHub 固定映射' : matches.join('\n'),
      );
    } catch (error) {
      return DiagnosticCheck(
        id: 'hosts',
        label: 'hosts 固定映射',
        status: DiagnosticStatus.warning,
        detail: '无法读取：$error',
      );
    }
  }
}
