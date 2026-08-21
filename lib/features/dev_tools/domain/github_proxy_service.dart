import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'git_repository_service.dart';

typedef GithubProxyProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
typedef GithubProxyCandidateProbe = Future<GithubProxyProbeResult> Function(
  String host,
  int port,
);

class GithubProxyProbeResult {
  const GithubProxyProbeResult({
    required this.listening,
    required this.httpsReachable,
    required this.gitReachable,
    required this.detail,
  });

  final bool listening;
  final bool httpsReachable;
  final bool gitReachable;
  final String detail;
}

class GithubProxyCandidate {
  const GithubProxyCandidate({
    required this.id,
    required this.host,
    required this.port,
    required this.processName,
    required this.processId,
    required this.discoveredAt,
    required this.listening,
    required this.httpsReachable,
    required this.gitReachable,
    required this.detail,
  });

  final String id;
  final String host;
  final int port;
  final String processName;
  final int processId;
  final DateTime discoveredAt;
  final bool listening;
  final bool httpsReachable;
  final bool gitReachable;
  final String detail;

  String get uri => 'http://$host:$port';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'host': host,
    'port': port,
    'processName': processName,
    'processId': processId,
    'uri': uri,
    'discoveredAt': discoveredAt.toUtc().toIso8601String(),
    'listening': listening,
    'httpsReachable': httpsReachable,
    'gitReachable': gitReachable,
    'detail': detail,
  };
}

class GithubProxyPlan {
  const GithubProxyPlan({
    required this.id,
    required this.candidateId,
    required this.proxyUri,
    required this.previousValue,
    required this.digest,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String candidateId;
  final String proxyUri;
  final String? previousValue;
  final String digest;
  final DateTime createdAt;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'planId': id,
    'candidateId': candidateId,
    'scope': '仅 GitHub Git',
    'key': GithubProxyService.githubProxyKey,
    'currentValue': previousValue ?? '未配置',
    'targetValue': proxyUri,
    'risk': 'writesData',
    'rollback': previousValue == null ? '删除新增配置' : '恢复原值',
    'digest': digest,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

class GithubProxyApplyResult {
  const GithubProxyApplyResult({
    required this.planId,
    required this.proxyUri,
    required this.verified,
    required this.rolledBack,
    required this.detail,
  });

  final String planId;
  final String proxyUri;
  final bool verified;
  final bool rolledBack;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'planId': planId,
    'scope': '仅 GitHub Git',
    'proxyUri': proxyUri,
    'verified': verified,
    'rolledBack': rolledBack,
    'detail': detail,
  };
}

class GithubProxyService {
  GithubProxyService({
    GithubProxyProcessRunner? processRunner,
    String? gitExecutable,
    DateTime Function()? clock,
    Random? random,
    this.candidateProbe,
  }) : _processRunner = processRunner ?? _runProcess,
       _usesBundledRunner = processRunner == null,
       _gitExecutable = gitExecutable ?? GitRepositoryService.bundledExecutable,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const String githubProxyKey = 'http.https://github.com.proxy';
  static const Duration _planLifetime = Duration(minutes: 10);

  final GithubProxyProcessRunner _processRunner;
  final bool _usesBundledRunner;
  final String _gitExecutable;
  final DateTime Function() _clock;
  final Random _random;
  final GithubProxyCandidateProbe? candidateProbe;
  final Map<String, GithubProxyCandidate> _candidates =
      <String, GithubProxyCandidate>{};
  final Map<String, GithubProxyPlan> _plans = <String, GithubProxyPlan>{};

  Future<List<GithubProxyCandidate>> discoverCandidates() async {
    if (!Platform.isWindows && _processRunner == _runProcess) {
      return const <GithubProxyCandidate>[];
    }
    const String script = r'''
$ErrorActionPreference='SilentlyContinue'
$supported=@('mihomo','verge-mihomo','clash-verge','clash-verge-service','clash','clash-meta')
$rows=@()
$seen=@{}
netstat.exe -ano -p tcp | ForEach-Object {
  $hostAddress=$null
  $port=0
  $ownerId=0
  if($_ -match '^\s*TCP\s+127\.0\.0\.1:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$'){
    $hostAddress='127.0.0.1';$port=[int]$Matches[1];$ownerId=[int]$Matches[2]
  }elseif($_ -match '^\s*TCP\s+\[::1\]:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$'){
    $hostAddress='::1';$port=[int]$Matches[1];$ownerId=[int]$Matches[2]
  }
  if($null -eq $hostAddress -or $port -lt 1 -or $ownerId -lt 1){return}
  $key="$hostAddress`:$port`:$ownerId"
  if($seen.ContainsKey($key)){return}
  $seen[$key]=$true
  $p=Get-Process -Id $ownerId -ErrorAction SilentlyContinue
  if($null -ne $p -and $supported -contains $p.ProcessName.ToLowerInvariant()) {
    $rows += [pscustomobject]@{host=$hostAddress;port=$port;processName=$p.ProcessName;processId=$p.Id}
  }
}
$rows | Sort-Object processId,port -Unique | ConvertTo-Json -Compress
''';
    final String encoded = base64.encode(Utf16LeEncoder.encode(script));
    final ProcessResult result = await _processRunner(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
    ).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw FormatException('代理监听发现失败：${_safeOutput(result.stderr)}');
    }
    final String output = '${result.stdout}'.trim();
    if (output.isEmpty) return const <GithubProxyCandidate>[];
    final Object? decoded = jsonDecode(output);
    final List<Object?> rows = decoded is List<Object?>
        ? decoded
        : <Object?>[decoded];
    final DateTime discoveredAt = _clock();
    final List<GithubProxyCandidate> found = <GithubProxyCandidate>[];
    for (final Object? row in rows) {
      if (row is! Map) continue;
      final String host = '${row['host']}';
      final int port = int.tryParse('${row['port']}') ?? 0;
      final int pid = int.tryParse('${row['processId']}') ?? 0;
      final String processName = '${row['processName']}';
      if (!_isLoopback(host) || port < 1 || port > 65535 || pid < 1) continue;
      final String id = sha256
          .convert(utf8.encode('$host:$port:$processName:$pid'))
          .toString()
          .substring(0, 24);
      final GithubProxyProbeResult probe =
          await (candidateProbe?.call(host, port) ??
              _probeCandidate(host, port));
      final GithubProxyCandidate candidate = GithubProxyCandidate(
        id: id,
        host: host,
        port: port,
        processName: processName,
        processId: pid,
        discoveredAt: discoveredAt,
        listening: probe.listening,
        httpsReachable: probe.httpsReachable,
        gitReachable: probe.gitReachable,
        detail: probe.detail,
      );
      _candidates[id] = candidate;
      found.add(candidate);
    }
    return List<GithubProxyCandidate>.unmodifiable(found);
  }

  Future<GithubProxyPlan> createPlan(String candidateId) async {
    _prune();
    final GithubProxyCandidate? candidate = _candidates[candidateId.trim()];
    if (candidate == null) {
      throw const FormatException('代理候选不存在，请重新检测监听端口');
    }
    if (!candidate.listening || !candidate.gitReachable) {
      throw FormatException('代理候选未通过真实 Git 验证：${candidate.detail}');
    }
    final String? previous = await _readCurrentValue();
    final DateTime createdAt = _clock();
    final String id = _randomId();
    final String payload =
        '$id|${candidate.id}|${candidate.uri}|${previous ?? ''}|${createdAt.toUtc().toIso8601String()}';
    final GithubProxyPlan plan = GithubProxyPlan(
      id: id,
      candidateId: candidate.id,
      proxyUri: candidate.uri,
      previousValue: previous,
      digest: sha256.convert(utf8.encode(payload)).toString(),
      createdAt: createdAt,
      expiresAt: createdAt.add(_planLifetime),
    );
    _plans[id] = plan;
    return plan;
  }

  Future<GithubProxyApplyResult> apply(
    String planId, {
    required String digest,
    String verificationRemote = 'https://github.com/git/git.git',
  }) async {
    final GithubProxyPlan plan = _requirePlan(planId, digest: digest);
    final GithubProxyCandidate? candidate = _candidates[plan.candidateId];
    if (candidate == null) throw const FormatException('代理候选已失效，请重新检测');
    final GithubProxyProbeResult currentProbe =
        await (candidateProbe?.call(candidate.host, candidate.port) ??
            _probeCandidate(candidate.host, candidate.port));
    if (!currentProbe.listening || !currentProbe.gitReachable) {
      throw FormatException('代理候选已失效：${currentProbe.detail}');
    }
    final String? current = await _readCurrentValue();
    if (current != plan.previousValue) {
      throw const FormatException('Git 代理状态已变化，旧计划拒绝执行');
    }
    await _git(<String>['config', '--global', githubProxyKey, plan.proxyUri]);
    try {
      await _git(<String>[
        'ls-remote',
        '--heads',
        verificationRemote,
      ], timeout: const Duration(seconds: 30));
      return GithubProxyApplyResult(
        planId: plan.id,
        proxyUri: plan.proxyUri,
        verified: true,
        rolledBack: false,
        detail: 'GitHub ls-remote 验证通过',
      );
    } on Object catch (error) {
      try {
        await _restoreValue(plan.previousValue);
      } on Object catch (rollbackError) {
        throw StateError(
          'GitHub 验证失败，且旧代理恢复失败：${_safeOutput(rollbackError)}；'
          '原验证错误：${_safeOutput(error)}',
        );
      }
      return GithubProxyApplyResult(
        planId: plan.id,
        proxyUri: plan.proxyUri,
        verified: false,
        rolledBack: true,
        detail: '验证失败并已恢复旧值：${_safeOutput(error)}',
      );
    }
  }

  Future<GithubProxyApplyResult> rollback(
    String planId, {
    required String digest,
  }) async {
    final GithubProxyPlan plan = _requirePlan(
      planId,
      digest: digest,
      allowExpired: true,
    );
    final String? current = await _readCurrentValue();
    if (current != plan.proxyUri) {
      throw const FormatException('当前 GitHub 代理已被其他操作修改，拒绝用旧计划覆盖');
    }
    await _restoreValue(plan.previousValue);
    return GithubProxyApplyResult(
      planId: plan.id,
      proxyUri: plan.proxyUri,
      verified: false,
      rolledBack: true,
      detail: plan.previousValue == null ? '已删除新增配置' : '已恢复原 GitHub 代理值',
    );
  }

  GithubProxyPlan _requirePlan(
    String id, {
    required String digest,
    bool allowExpired = false,
  }) {
    if (!allowExpired) _prune();
    final GithubProxyPlan? plan = _plans[id.trim()];
    if (plan == null) throw const FormatException('代理计划不存在或已过期，请重新预览');
    if (plan.digest != digest.trim()) {
      throw const FormatException('代理计划摘要不匹配，拒绝执行');
    }
    return plan;
  }

  Future<String?> _readCurrentValue() async {
    final ProcessResult result = await _processRunner(_gitExecutable, <String>[
      'config',
      '--global',
      '--get',
      githubProxyKey,
    ]).timeout(const Duration(seconds: 5));
    final String value = '${result.stdout}'.trim();
    return result.exitCode == 0 && value.isNotEmpty ? value : null;
  }

  Future<GithubProxyProbeResult> _probeCandidate(String host, int port) async {
    bool listening = false;
    bool httpsReachable = false;
    bool gitReachable = false;
    final List<String> details = <String>[];
    try {
      final Socket socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      listening = true;
      socket.destroy();
    } on Object catch (error) {
      details.add('监听失败：${_safeOutput(error)}');
    }
    if (listening) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..findProxy = (_) => 'PROXY $host:$port';
      try {
        final HttpClientRequest request = await client
            .headUrl(Uri.https('github.com', '/'))
            .timeout(const Duration(seconds: 10));
        request.followRedirects = false;
        final HttpClientResponse response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        httpsReachable = response.statusCode > 0 && response.statusCode < 500;
        await response.drain<void>();
        details.add('HTTPS=${response.statusCode}');
      } on Object catch (error) {
        details.add('HTTPS 失败：${_safeOutput(error)}');
      } finally {
        client.close(force: true);
      }
      try {
        final ProcessResult result = await _processRunner(
          _gitExecutable,
          <String>[
            ..._networkGitOptions(),
            '-c',
            '$githubProxyKey=http://$host:$port',
            'ls-remote',
            '--heads',
            'https://github.com/git/git.git',
          ],
        ).timeout(const Duration(seconds: 20));
        gitReachable = result.exitCode == 0;
        details.add(gitReachable ? 'Git ls-remote=通过' : 'Git ls-remote=失败');
      } on Object catch (error) {
        details.add('Git 失败：${_safeOutput(error)}');
      }
    }
    return GithubProxyProbeResult(
      listening: listening,
      httpsReachable: httpsReachable,
      gitReachable: gitReachable,
      detail: details.join('；'),
    );
  }

  Future<void> _restoreValue(String? value) async {
    if (value == null || value.isEmpty) {
      await _git(<String>[
        'config',
        '--global',
        '--unset-all',
        githubProxyKey,
      ], allowMissing: true);
    } else {
      await _git(<String>['config', '--global', githubProxyKey, value]);
    }
  }

  Future<String> _git(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    bool allowMissing = false,
  }) async {
    final bool networkCommand = arguments.contains('ls-remote');
    final ProcessResult result = await _processRunner(_gitExecutable, <String>[
      if (networkCommand) ..._networkGitOptions(),
      ...arguments,
    ]).timeout(timeout);
    if (result.exitCode != 0 && !allowMissing) {
      throw FormatException(_safeOutput(result.stderr));
    }
    return '${result.stdout}';
  }

  void _prune() {
    final DateTime now = _clock();
    _plans.removeWhere(
      (String _, GithubProxyPlan plan) => !plan.expiresAt.isAfter(now),
    );
  }

  List<String> _networkGitOptions() {
    if (!_usesBundledRunner || !Platform.isWindows) return const <String>[];
    final String runtimeRoot = File(_gitExecutable).parent.parent.path;
    return <String>[
      '--exec-path=$runtimeRoot${Platform.pathSeparator}mingw64'
          '${Platform.pathSeparator}bin',
      '-c',
      'http.sslBackend=openssl',
    ];
  }

  String _randomId() =>
      base64UrlEncode(List<int>.generate(24, (_) => _random.nextInt(256)))
          .replaceAll('=', '');

  static bool _isLoopback(String host) => host == '127.0.0.1' || host == '::1';

  static String _safeOutput(Object? value) => '$value'
      .replaceAll(RegExp(r'https?://[^/@\s]+@'), 'https://***@')
      .replaceAll(
        RegExp(r'(token|password|secret)=\S+', caseSensitive: false),
        r'$1=***',
      )
      .trim();

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);
}

abstract final class Utf16LeEncoder {
  static List<int> encode(String input) {
    final List<int> bytes = <int>[];
    for (final int unit in input.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add((unit >> 8) & 0xff);
    }
    return bytes;
  }
}
