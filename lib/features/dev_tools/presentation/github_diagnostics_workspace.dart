import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/github_diagnostics.dart';
import '../domain/github_proxy_service.dart';

typedef GithubDiagnosticsRunner = Future<GithubDiagnosticsReport> Function();

class GithubDiagnosticsWorkspace extends StatefulWidget {
  const GithubDiagnosticsWorkspace({
    super.key,
    this.runDiagnostics,
    this.proxyService,
  });

  final GithubDiagnosticsRunner? runDiagnostics;
  final GithubProxyService? proxyService;

  @override
  State<GithubDiagnosticsWorkspace> createState() =>
      _GithubDiagnosticsWorkspaceState();
}

class _GithubDiagnosticsWorkspaceState
    extends State<GithubDiagnosticsWorkspace> {
  GithubDiagnosticsReport? _report;
  late final GithubProxyService _proxyService;
  List<GithubProxyCandidate> _proxyCandidates = const <GithubProxyCandidate>[];
  GithubProxyCandidate? _selectedProxy;
  GithubProxyPlan? _proxyPlan;
  GithubProxyApplyResult? _proxyResult;
  String? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _proxyService = widget.proxyService ?? GithubProxyService();
  }

  Future<void> _discoverProxyCandidates() async {
    setState(() {
      _running = true;
      _error = null;
      _proxyCandidates = const <GithubProxyCandidate>[];
      _selectedProxy = null;
      _proxyPlan = null;
      _proxyResult = null;
    });
    try {
      final List<GithubProxyCandidate> candidates = await _proxyService
          .discoverCandidates();
      if (!mounted) return;
      setState(() {
        _proxyCandidates = candidates;
        _selectedProxy = candidates.firstOrNull;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '代理发现失败：$error';
      });
    }
  }

  Future<void> _previewProxyPlan() async {
    final GithubProxyCandidate? candidate = _selectedProxy;
    if (candidate == null) return;
    setState(() {
      _running = true;
      _error = null;
      _proxyPlan = null;
      _proxyResult = null;
    });
    try {
      final GithubProxyPlan plan = await _proxyService.createPlan(candidate.id);
      if (!mounted) return;
      setState(() {
        _proxyPlan = plan;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '修复预览失败：$error';
      });
    }
  }

  Future<void> _applyProxyPlan() async {
    final GithubProxyPlan? plan = _proxyPlan;
    if (plan == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('仅修复 GitHub Git 代理？'),
        content: SelectableText(
          '${GithubProxyService.githubProxyKey}\n'
          '${plan.previousValue ?? '未配置'} → ${plan.proxyUri}\n\n'
          '应用后会执行真实 ls-remote；失败自动恢复旧值，不修改系统代理。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('github-proxy-confirm-apply'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('应用并验证'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final GithubProxyApplyResult result = await _proxyService.apply(plan.id);
      if (!mounted) return;
      setState(() {
        _proxyResult = result;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '应用失败，旧值已自动恢复：$error';
      });
    }
  }

  Future<void> _rollbackProxyPlan() async {
    final GithubProxyPlan? plan = _proxyPlan;
    if (plan == null) return;
    setState(() => _running = true);
    try {
      final GithubProxyApplyResult result = await _proxyService.rollback(
        plan.id,
      );
      if (!mounted) return;
      setState(() {
        _proxyResult = result;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '恢复失败：$error';
      });
    }
  }

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
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('github-diagnostics-run'),
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(_running ? '诊断中…' : '开始诊断'),
              ),
              OutlinedButton.icon(
                key: const Key('github-proxy-discover'),
                onPressed: _running ? null : _discoverProxyCandidates,
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('检测代理候选'),
              ),
              if (_selectedProxy != null)
                OutlinedButton.icon(
                  key: const Key('github-proxy-preview'),
                  onPressed: _running ? null : _previewProxyPlan,
                  icon: const Icon(Icons.rule_outlined, size: 18),
                  label: const Text('修复预览'),
                ),
              if (_proxyPlan != null)
                FilledButton.icon(
                  key: const Key('github-proxy-apply'),
                  onPressed: _running ? null : _applyProxyPlan,
                  icon: const Icon(Icons.route_outlined, size: 18),
                  label: const Text('仅修复 GitHub Git'),
                ),
              if (_proxyPlan != null)
                TextButton(
                  key: const Key('github-proxy-rollback'),
                  onPressed: _running ? null : _rollbackProxyPlan,
                  child: const Text('恢复旧值'),
                ),
            ],
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
          if (_proxyCandidates.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _proxyCandidates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int index) {
                  final GithubProxyCandidate candidate =
                      _proxyCandidates[index];
                  return Tooltip(
                    message: candidate.detail,
                    child: ChoiceChip(
                      label: Text(
                        '${candidate.gitReachable ? '✓' : '×'} '
                        '${candidate.processName} · ${candidate.uri}',
                      ),
                      selected: candidate.id == _selectedProxy?.id,
                      onSelected: _running
                          ? null
                          : (_) => setState(() {
                              _selectedProxy = candidate;
                              _proxyPlan = null;
                              _proxyResult = null;
                            }),
                    ),
                  );
                },
              ),
            ),
          if (_proxyPlan != null)
            Text(
              '仅 GitHub Git：${_proxyPlan!.previousValue ?? '未配置'} → ${_proxyPlan!.proxyUri} · 可回滚',
              key: const Key('github-proxy-plan-summary'),
              style: const TextStyle(fontSize: 11),
            ),
          if (_proxyResult != null)
            Text(
              _proxyResult!.detail,
              key: const Key('github-proxy-result'),
              style: TextStyle(
                color: _proxyResult!.verified
                    ? context.vibe.success
                    : _proxyResult!.rolledBack
                    ? VibekitsColors.warning
                    : VibekitsColors.danger,
              ),
            ),
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
