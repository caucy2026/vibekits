import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/app_version.dart';
import '../../../app/app_update_service.dart';
import '../domain/marketing_cache_service.dart';

class AboutTab extends StatefulWidget {
  const AboutTab({super.key, this.active = true, this.marketingService});

  final bool active;
  final MarketingCacheService? marketingService;

  @override
  State<AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<AboutTab> {
  late final MarketingCacheService _service =
      widget.marketingService ?? MarketingCacheService.instance;
  Timer? _timer;
  int _index = 0;

  static const List<_Capability> _capabilities = <_Capability>[
    _Capability(
      Icons.auto_awesome_outlined,
      '智能体与扩展',
      '官方 Harness 工作区、会话、权限、Skills、设置与插件清单。',
    ),
    _Capability(Icons.hub_outlined, 'MCP 协同', '本机与局域网能力发现、证书校验、授权、调度和结果验真。'),
    _Capability(
      Icons.folder_zip_outlined,
      '压缩文件',
      '安全查看、创建与提取压缩包，提供路径和容量边界检查。',
    ),
    _Capability(
      Icons.cleaning_services_outlined,
      '系统清理',
      '扫描可清理空间，先生成可核对计划，再执行受控清理。',
    ),
    _Capability(Icons.article_outlined, '文档阅读', '查看文本、结构化数据与受支持的二进制文档内容。'),
    _Capability(
      Icons.construction_outlined,
      '开发工具',
      'ADB、网络、数据库、串口、音频及格式转换等工程工具。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _service.snapshot.addListener(_changed);
    unawaited(_service.loadCached());
    _resetTimer();
  }

  @override
  void didUpdateWidget(covariant AboutTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _resetTimer();
  }

  void _changed() {
    if (!mounted) return;
    final int count = _service.snapshot.value.images.length;
    setState(() => _index = count == 0 ? 0 : _index.clamp(0, count - 1));
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.active && _service.snapshot.value.images.length > 1) {
      _timer = Timer(const Duration(seconds: 5), _advance);
    }
  }

  void _advance() {
    final int count = _service.snapshot.value.images.length;
    if (!mounted || count < 2) return;
    setState(() => _index = (_index + 1) % count);
    _resetTimer();
  }

  void _select(int index) {
    setState(() => _index = index);
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.snapshot.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
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
                _identity(context),
                const SizedBox(height: 14),
                _updateCard(context),
                const SizedBox(height: 22),
                ValueListenableBuilder<MarketingCacheSnapshot>(
                  valueListenable: _service.snapshot,
                  builder: (context, MarketingCacheSnapshot value, child) =>
                      _marketing(context, value),
                ),
                const SizedBox(height: 24),
                Text('当前版本能力', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '以下项目来自当前应用导航和已交付工具，不包含规划中或未经验证的能力。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (_, BoxConstraints constraints) {
                    final double width = constraints.maxWidth >= 760
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _capabilities
                          .map(
                            (item) => SizedBox(
                              width: width,
                              child: _CapabilityCard(item),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _privacy(context),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _identity(BuildContext context) => Row(
    children: <Widget>[
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
          key: const Key('about-product-icon'),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
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

  Widget _updateCard(
    BuildContext context,
  ) => ValueListenableBuilder<AppUpdateSnapshot>(
    valueListenable: AppUpdateService.instance.snapshot,
    builder: (context, value, child) {
      final bool busy =
          value.phase == AppUpdatePhase.checking ||
          value.phase == AppUpdatePhase.downloading;
      final bool available = value.phase == AppUpdatePhase.available;
      return Card(
        key: const Key('about-update-card'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              if (busy)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  available ? Icons.system_update_alt : Icons.verified_outlined,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      available ? '可更新到 ${value.versionName}' : '应用更新',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.message.isEmpty
                          ? '启动时自动检查，也可随时手动检查。'
                          : value.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (available && value.releaseNotes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        value.releaseNotes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                key: Key(
                  available ? 'about-install-update' : 'about-check-update',
                ),
                onPressed: busy
                    ? null
                    : available
                    ? AppUpdateService.instance.downloadAndInstall
                    : AppUpdateService.instance.check,
                child: Text(available ? '下载并安装' : '检查更新'),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _marketing(BuildContext context, MarketingCacheSnapshot value) {
    if (!value.hasImages) {
      if (value.state == MarketingCacheState.loading ||
          value.state == MarketingCacheState.syncing) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            key: const Key('about-marketing-loading'),
            decoration: _decoration(context),
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('正在准备系列产品内容…'),
              ],
            ),
          ),
        );
      }
      return _offline(context);
    }
    final List<MarketingCachedImage> images = value.images;
    final int selected = _index.clamp(0, images.length - 1);
    final MarketingCachedImage image = images[selected];
    return Column(
      children: <Widget>[
        Semantics(
          button: images.length > 1,
          label: '第 ${selected + 1} / ${images.length} 张系列产品图：${image.name}',
          child: InkWell(
            key: const Key('about-marketing-carousel'),
            onTap: images.length > 1 ? _advance : null,
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Image.file(
                    File(image.path),
                    key: ValueKey<String>(image.path),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value.version.isEmpty ? '系列产品资源' : '系列产品资源 ${value.version}',
                key: const Key('about-marketing-version'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (value.state == MarketingCacheState.syncing)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (images.length > 1)
              Wrap(
                key: const Key('about-marketing-indicators'),
                spacing: 6,
                children: List<Widget>.generate(
                  images.length,
                  (int index) => InkWell(
                    key: Key('about-marketing-indicator-$index'),
                    onTap: () => _select(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Semantics(
                      button: true,
                      selected: index == selected,
                      label: '显示第 ${index + 1} 张系列产品图',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == selected ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: index == selected
                              ? Theme.of(context).colorScheme.primary
                              : context.vibe.border,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _offline(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: Container(
      key: const Key('about-local-product-panel'),
      padding: const EdgeInsets.all(28),
      decoration: _decoration(context),
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
          const Text(
            '统一使用本机工具和经过授权的局域网 MCP，保留调用过程、结果证据与停止控制。当前网络不可用，已安全显示内置产品信息。',
          ),
        ],
      ),
    ),
  );

  BoxDecoration _decoration(BuildContext context) => BoxDecoration(
    gradient: LinearGradient(
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
  );

  Widget _privacy(BuildContext context) => Container(
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
            '隐私与联网：文件默认在本机处理。应用启动后低优先级检查已授权的同系列产品图片；只显示通过 HTTPS、大小、MD5、格式和解码校验的本地缓存，失败时继续使用上次完整缓存或内置内容。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard(this.item);
  final _Capability item;

  @override
  Widget build(BuildContext context) => Card(
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

class _Capability {
  const _Capability(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}
