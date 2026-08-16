import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/github_diagnostics.dart';

typedef GithubDiagnosticsRunner = Future<GithubDiagnosticsReport> Function();

class GithubDiagnosticsWorkspace extends StatefulWidget {
  const GithubDiagnosticsWorkspace({super.key, this.runDiagnostics});

  final GithubDiagnosticsRunner? runDiagnostics;

  @override
  State<GithubDiagnosticsWorkspace> createState() =>
      _GithubDiagnosticsWorkspaceState();
}

class _GithubDiagnosticsWorkspaceState
    extends State<GithubDiagnosticsWorkspace> {
  GithubDiagnosticsReport? _report;
  String? _error;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final GithubDiagnosticsReport report =
          await (widget.runDiagnostics != null
              ? widget.runDiagnostics!()
              : GithubDiagnosticsService.run());
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '诊断失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final GithubDiagnosticsReport? report = _report;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const Icon(Icons.monitor_heart_outlined, size: 21),
              const Text(
                'GitHub 网络诊断',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              _DiagnosticBadge(text: '只读 · 可审计', color: context.vibe.success),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '分层检查 DNS、TLS、HTTPS、代理、hosts 和 SSH 22/443；不改 hosts、不安装证书、不关闭 TLS。',
            style: TextStyle(fontSize: 12, color: context.vibe.muted),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('github-diagnostics-run'),
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_running ? '诊断中…' : '开始诊断'),
            ),
          ),
          if (_running) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const Key('github-diagnostics-error'),
                style: const TextStyle(color: VibekitsColors.danger),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: report == null
                ? Center(
                    child: Text(
                      '一次诊断只读取当前网络和配置状态。',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: report.checks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (BuildContext context, int index) {
                      final DiagnosticCheck check = report.checks[index];
                      final Color color = switch (check.status) {
                        DiagnosticStatus.ok => context.vibe.success,
                        DiagnosticStatus.warning => VibekitsColors.warning,
                        DiagnosticStatus.failed => VibekitsColors.danger,
                      };
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              check.status == DiagnosticStatus.ok
                                  ? Icons.check_circle_outline
                                  : check.status == DiagnosticStatus.warning
                                  ? Icons.info_outline
                                  : Icons.error_outline,
                              size: 18,
                              color: color,
                            ),
                            const SizedBox(width: 9),
                            SizedBox(
                              width: 150,
                              child: Text(
                                '${check.label}${check.elapsed == null ? '' : ' · ${check.elapsed!.inMilliseconds} ms'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                check.detail,
                                style: const TextStyle(
                                  fontFamily: 'Cascadia Mono',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (report != null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              key: const Key('github-diagnostics-recommendation'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(report.recommendation),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagnosticBadge extends StatelessWidget {
  const _DiagnosticBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
