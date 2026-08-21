import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/github_proxy_service.dart';

void main() {
  test('普通权限候选发现使用 netstat 并识别 Verge Mihomo 真实进程名', () async {
    String? script;
    final GithubProxyService service = GithubProxyService(
      processRunner: (String executable, List<String> arguments) async {
        final List<int> bytes = base64.decode(arguments.last);
        script = String.fromCharCodes(<int>[
          for (int index = 0; index + 1 < bytes.length; index += 2)
            bytes[index] | (bytes[index + 1] << 8),
        ]);
        return ProcessResult(1, 0, '[]', '');
      },
      gitExecutable: 'git.exe',
    );

    expect(await service.discoverCandidates(), isEmpty);
    expect(script, contains('netstat.exe -ano -p tcp'));
    expect(script, contains('verge-mihomo'));
    expect(script, isNot(contains('Get-NetTCPConnection')));
  });

  test('发现真实非 7890 回环端口并只生成 GitHub host-scoped 计划', () async {
    String? configured;
    final List<List<String>> calls = <List<String>>[];
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      calls.add(<String>[executable, ...arguments]);
      if (executable == 'powershell.exe') {
        return ProcessResult(
          1,
          0,
          '{"host":"127.0.0.1","port":7897,"processName":"mihomo","processId":42}',
          '',
        );
      }
      if (arguments.contains('--get')) {
        return configured == null
            ? ProcessResult(2, 1, '', '')
            : ProcessResult(2, 0, '$configured\n', '');
      }
      if (arguments.contains('--unset-all')) {
        configured = null;
        return ProcessResult(3, 0, '', '');
      }
      if (arguments.length >= 4 && arguments[0] == 'config') {
        configured = arguments.last;
        return ProcessResult(4, 0, '', '');
      }
      if (arguments.first == 'ls-remote') {
        return ProcessResult(5, 0, 'abc\tHEAD\n', '');
      }
      return ProcessResult(6, 1, '', 'unexpected');
    }

    final GithubProxyService service = GithubProxyService(
      processRunner: runner,
      gitExecutable: 'git.exe',
      clock: () => DateTime(2026, 8, 21),
      random: Random(1),
      candidateProbe: (_, _) async => const GithubProxyProbeResult(
        listening: true,
        httpsReachable: true,
        gitReachable: true,
        detail: 'HTTPS=200；Git ls-remote=通过',
      ),
    );
    final List<GithubProxyCandidate> candidates = await service
        .discoverCandidates();
    expect(candidates, hasLength(1));
    expect(candidates.single.port, 7897);
    expect(candidates.single.gitReachable, isTrue);
    final GithubProxyPlan plan = await service.createPlan(candidates.single.id);
    expect(plan.proxyUri, 'http://127.0.0.1:7897');
    expect(plan.toJson()['key'], GithubProxyService.githubProxyKey);

    final GithubProxyApplyResult applied = await service.apply(
      plan.id,
      digest: plan.digest,
    );
    expect(applied.verified, isTrue);
    expect(configured, 'http://127.0.0.1:7897');
    expect(
      calls.any(
        (List<String> call) =>
            call.contains('http.https://github.com.proxy') &&
            !call.contains('http.proxy'),
      ),
      isTrue,
    );
  });

  test('Git 验证失败自动恢复代理旧值', () async {
    String? configured = 'http://127.0.0.1:7000';
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      if (executable == 'powershell.exe') {
        return ProcessResult(
          1,
          0,
          '{"host":"127.0.0.1","port":7897,"processName":"clash-verge","processId":9}',
          '',
        );
      }
      if (arguments.contains('--get')) {
        return ProcessResult(2, 0, '$configured\n', '');
      }
      if (arguments.first == 'ls-remote') {
        return ProcessResult(3, 1, '', 'timeout');
      }
      if (arguments.contains('--unset-all')) {
        configured = null;
      } else if (arguments.first == 'config') {
        configured = arguments.last;
      }
      return ProcessResult(4, 0, '', '');
    }

    final GithubProxyService service = GithubProxyService(
      processRunner: runner,
      gitExecutable: 'git.exe',
      clock: () => DateTime(2026, 8, 21),
      random: Random(2),
      candidateProbe: (_, _) async => const GithubProxyProbeResult(
        listening: true,
        httpsReachable: true,
        gitReachable: true,
        detail: 'HTTPS=200；Git ls-remote=通过',
      ),
    );
    final GithubProxyCandidate candidate =
        (await service.discoverCandidates()).single;
    final GithubProxyPlan plan = await service.createPlan(candidate.id);
    final GithubProxyApplyResult result = await service.apply(
      plan.id,
      digest: plan.digest,
    );
    expect(result.verified, isFalse);
    expect(result.rolledBack, isTrue);
    expect(configured, 'http://127.0.0.1:7000');
  });

  test('未通过真实 Git 探测的候选不能生成修复计划', () async {
    final GithubProxyService service = GithubProxyService(
      processRunner: (_, _) async => ProcessResult(
        1,
        0,
        '{"host":"127.0.0.1","port":7899,"processName":"mihomo","processId":42}',
        '',
      ),
      gitExecutable: 'git.exe',
      candidateProbe: (_, _) async => const GithubProxyProbeResult(
        listening: true,
        httpsReachable: false,
        gitReachable: false,
        detail: 'Git ls-remote=失败',
      ),
    );
    final GithubProxyCandidate candidate =
        (await service.discoverCandidates()).single;
    await expectLater(
      service.createPlan(candidate.id),
      throwsA(isA<FormatException>()),
    );
  });

  test('摘要篡改和过期计划回滚不能覆盖后来修改的代理值', () async {
    String? configured = 'http://127.0.0.1:7000';
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      if (executable == 'powershell.exe') {
        return ProcessResult(
          1,
          0,
          '{"host":"127.0.0.1","port":7897,"processName":"mihomo","processId":42}',
          '',
        );
      }
      if (arguments.contains('--get')) {
        return configured == null
            ? ProcessResult(2, 1, '', '')
            : ProcessResult(2, 0, '$configured\n', '');
      }
      if (arguments.contains('--unset-all')) {
        configured = null;
      } else if (arguments.first == 'config') {
        configured = arguments.last;
      }
      if (arguments.first == 'ls-remote') {
        return ProcessResult(3, 0, 'abc\tHEAD\n', '');
      }
      return ProcessResult(4, 0, '', '');
    }

    final GithubProxyService service = GithubProxyService(
      processRunner: runner,
      gitExecutable: 'git.exe',
      clock: () => DateTime(2026, 8, 21),
      random: Random(3),
      candidateProbe: (_, _) async => const GithubProxyProbeResult(
        listening: true,
        httpsReachable: true,
        gitReachable: true,
        detail: '通过',
      ),
    );
    final GithubProxyCandidate candidate =
        (await service.discoverCandidates()).single;
    final GithubProxyPlan plan = await service.createPlan(candidate.id);
    await expectLater(
      service.apply(plan.id, digest: '${plan.digest}tampered'),
      throwsA(isA<FormatException>()),
    );
    final GithubProxyApplyResult applied = await service.apply(
      plan.id,
      digest: plan.digest,
    );
    expect(applied.verified, isTrue);
    configured = 'http://127.0.0.1:7999';
    await expectLater(
      service.rollback(plan.id, digest: plan.digest),
      throwsA(isA<FormatException>()),
    );
    expect(configured, 'http://127.0.0.1:7999');
  });
}
