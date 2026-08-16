import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/github_diagnostics.dart';

void main() {
  test('代理凭据在展示前脱敏', () {
    expect(
      GithubDiagnosticsService.redactProxy('http://user:secret@proxy:8080'),
      'http://***@proxy:8080',
    );
    expect(
      GithubDiagnosticsService.redactProxy('socks5://token@proxy:1080'),
      'socks5://***@proxy:1080',
    );
  });

  test('SSH 22 阻断但 443 可用时给出官方备用端口方向', () {
    final String recommendation = GithubDiagnosticsService.recommendFor(
      const <DiagnosticCheck>[
        DiagnosticCheck(
          id: 'https',
          label: 'HTTPS',
          status: DiagnosticStatus.ok,
          detail: 'ok',
        ),
        DiagnosticCheck(
          id: 'ssh22',
          label: 'SSH 22',
          status: DiagnosticStatus.failed,
          detail: 'blocked',
        ),
        DiagnosticCheck(
          id: 'ssh443',
          label: 'SSH 443',
          status: DiagnosticStatus.ok,
          detail: 'ok',
        ),
      ],
    );
    expect(recommendation, contains('SSH over 443'));
  });

  test('HTTPS 失败时不建议关闭 TLS', () {
    final String recommendation = GithubDiagnosticsService.recommendFor(
      const <DiagnosticCheck>[
        DiagnosticCheck(
          id: 'https',
          label: 'HTTPS',
          status: DiagnosticStatus.failed,
          detail: 'certificate error',
        ),
      ],
    );
    expect(recommendation, contains('不要通过关闭 TLS'));
  });
}
