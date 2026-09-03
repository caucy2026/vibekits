import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/app_version.dart';

/// Product identity and capability page.
///
/// VibeKits does not currently operate a dedicated marketing-resource
/// endpoint. This page is therefore deliberately local-only: it never blocks
/// startup, never borrows another product's feed, and remains complete while
/// offline.
class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  static const List<_CapabilityGroup> _capabilities = <_CapabilityGroup>[
    _CapabilityGroup(
      icon: Icons.auto_awesome_outlined,
      title: '智能体与扩展',
      description: '官方 Harness 工作区、会话、权限、Skills、设置与插件清单。',
    ),
    _CapabilityGroup(
      icon: Icons.hub_outlined,
      title: 'MCP 协同',
      description: '本机与局域网能力发现、证书校验、授权、调度和结果验真。',
    ),
    _CapabilityGroup(
      icon: Icons.folder_zip_outlined,
      title: '压缩文件',
      description: '安全查看、创建与提取压缩包，提供路径和容量边界检查。',
    ),
    _CapabilityGroup(
      icon: Icons.cleaning_services_outlined,
      title: '系统清理',
      description: '扫描可清理空间，先生成可核对计划，再执行受控清理。',
    ),
    _CapabilityGroup(
      icon: Icons.article_outlined,
      title: '文档阅读',
      description: '查看文本、结构化数据与受支持的二进制文档内容。',
    ),
    _CapabilityGroup(
      icon: Icons.construction_outlined,
      title: '开发工具',
      description: 'ADB、网络、数据库、串口、音频及格式转换等工程工具。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('about-us-page'),
      color: context.vibe.canvas,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildIdentity(context),
                  const SizedBox(height: 22),
                  _buildProductPanel(context),
                  const SizedBox(height: 24),
                  Text('当前版本能力', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    '以下项目来自当前应用导航和已交付工具，不包含规划中或未经验证的能力。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final int columns = constraints.maxWidth >= 760
                              ? 2
                              : 1;
                          final double width = columns == 2
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _capabilities
                                .map(
                                  (_CapabilityGroup item) => SizedBox(
                                    width: width,
                                    child: _CapabilityCard(item: item),
                                  ),
                                )
                                .toList(growable: false),
                          );
                        },
                  ),
                  const SizedBox(height: 24),
                  _buildPrivacyNote(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
            key: const Key('about-product-icon'),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              color: Theme.of(context).colorScheme.primary,
              child: Text(
                'V',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Vibekits',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 3),
              Text(
                '本地优先的智能体与工程工具箱',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 5),
              Text(
                AppVersion.display,
                key: const Key('about-app-version'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductPanel(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        key: const Key('about-local-product-panel'),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
              context.vibe.panelRaised,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.vibe.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.handyman_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('让智能体调用真实工程能力', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                '统一使用本机工具和经过授权的局域网 MCP，保留调用过程、结果证据与停止控制。核心产品信息随安装包提供，无网络时仍可完整查看。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.vibe.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, size: 20, color: context.vibe.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '隐私与联网：文件默认在本机处理。需要网络、远端设备或外部 MCP 的能力会遵循对应授权和风险提示；本页面自身不请求在线宣传资源。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.item});

  final _CapabilityGroup item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              item.icon,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityGroup {
  const _CapabilityGroup({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}
