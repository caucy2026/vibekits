import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/windows_test_node_service.dart';

typedef WindowsNodeInspector = Future<WindowsNodeInspection> Function();
typedef WindowsNodePlanner = WindowsNodeChangePlan Function(
  String inspectionId,
);

class WindowsTestNodeWorkspace extends StatefulWidget {
  const WindowsTestNodeWorkspace({super.key, this.inspect, this.createPlan});

  final WindowsNodeInspector? inspect;
  final WindowsNodePlanner? createPlan;

  @override
  State<WindowsTestNodeWorkspace> createState() =>
      _WindowsTestNodeWorkspaceState();
}

class _WindowsTestNodeWorkspaceState extends State<WindowsTestNodeWorkspace> {
  final WindowsTestNodeService _service = WindowsTestNodeService();
  WindowsNodeInspection? _inspection;
  WindowsNodeChangePlan? _plan;
  bool _running = false;
  String? _error;

  Future<void> _inspect() async {
    setState(() {
      _running = true;
      _error = null;
      _inspection = null;
      _plan = null;
    });
    try {
      final WindowsNodeInspection result =
          await (widget.inspect?.call() ?? _service.inspect());
      if (!mounted) return;
      setState(() {
        _inspection = result;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '体检失败：$error';
      });
    }
  }

  void _createPlan() {
    final WindowsNodeInspection? inspection = _inspection;
    if (inspection == null) return;
    try {
      setState(() {
        _plan =
            widget.createPlan?.call(inspection.id) ??
            _service.plan(inspection.id);
        _error = null;
      });
    } catch (error) {
      setState(() => _error = '计划失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final WindowsNodeInspection? inspection = _inspection;
    final WindowsNodeChangePlan? plan = _plan;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.laptop_windows_outlined, size: 21),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Windows 局域网测试节点',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                r'D:\KEMI-Test',
                style: TextStyle(fontSize: 11, color: context.vibe.success),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '普通权限先返回体检；系统修改只能交给签名窄权限 UAC helper，不接受任意管理员脚本。',
            style: TextStyle(fontSize: 11, color: context.vibe.muted),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('windows-node-inspect'),
                onPressed: _running ? null : _inspect,
                icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                label: Text(_running ? '体检中…' : '只读体检'),
              ),
              OutlinedButton.icon(
                key: const Key('windows-node-plan'),
                onPressed: _running || inspection == null ? null : _createPlan,
                icon: const Icon(Icons.rule_folder_outlined, size: 18),
                label: const Text('生成变更计划'),
              ),
              const Tooltip(
                message: '签名 UAC helper 尚未进入 Release，不能用 PowerShell 替代',
                child: OutlinedButton(
                  onPressed: null,
                  child: Text('执行计划（待签名 helper）'),
                ),
              ),
            ],
          ),
          if (_running) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Text(
              _error!,
              key: const Key('windows-node-error'),
              style: const TextStyle(color: VibekitsColors.danger),
            ),
          const SizedBox(height: 7),
          Expanded(
            child: inspection == null
                ? Center(
                    child: Text(
                      '体检覆盖 Windows、硬件、D 盘、网络、OpenSSH、防火墙、运行时、电源、目录、账户和公钥。',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : plan == null
                ? _checks(inspection)
                : _actions(plan),
          ),
        ],
      ),
    );
  }

  Widget _checks(WindowsNodeInspection inspection) => ListView.separated(
    key: const Key('windows-node-checks'),
    itemCount: inspection.checks.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (BuildContext context, int index) {
      final WindowsNodeCheck check = inspection.checks[index];
      final Color color = switch (check.status) {
        WindowsNodeCheckStatus.pass => context.vibe.success,
        WindowsNodeCheckStatus.warning => VibekitsColors.warning,
        WindowsNodeCheckStatus.blocked => VibekitsColors.danger,
        WindowsNodeCheckStatus.unknown => context.vibe.muted,
      };
      return ListTile(
        dense: true,
        leading: Icon(Icons.circle, size: 11, color: color),
        title: Text(check.label),
        subtitle: SelectableText(check.detail),
        trailing: check.requiresElevation
            ? const Tooltip(
                message: '需要 UAC 才能完成检查或修复',
                child: Icon(Icons.admin_panel_settings_outlined, size: 18),
              )
            : null,
      );
    },
  );

  Widget _actions(WindowsNodeChangePlan plan) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        plan.blockers.isEmpty
            ? '${plan.actions.length} 个幂等动作 · ${plan.requiresElevation ? '需要 UAC' : '普通权限'}'
            : '被 ${plan.blockers.length} 个门禁阻断：${plan.blockers.join('；')}',
        key: const Key('windows-node-plan-summary'),
        style: TextStyle(
          color: plan.blockers.isEmpty
              ? context.vibe.success
              : VibekitsColors.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: plan.actions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final WindowsNodePlanAction action = plan.actions[index];
            return ListTile(
              dense: true,
              title: SelectableText(action.id),
              subtitle: Text(
                '${action.currentValue} → ${action.targetValue}\n'
                '${action.reason} · 回滚：${action.rollback}',
              ),
            );
          },
        ),
      ),
    ],
  );
}
