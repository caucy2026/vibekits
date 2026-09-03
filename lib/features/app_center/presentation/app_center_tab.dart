import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/app_center_service.dart';

class AppCenterTab extends StatefulWidget {
  const AppCenterTab({super.key, this.service});

  final AppCenterService? service;

  @override
  State<AppCenterTab> createState() => _AppCenterTabState();
}

class _AppCenterTabState extends State<AppCenterTab> {
  late final AppCenterService _service = widget.service ?? AppCenterService();
  late final bool _ownsService = widget.service == null;
  final TextEditingController _search = TextEditingController();
  AppCenterCatalog? _catalog;
  String? _category;
  String? _error;
  bool _loading = true;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int serial = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppCenterCatalog catalog = await _service.load(
        category: _category,
        keyword: _search.text,
      );
      if (!mounted || serial != _requestSerial) return;
      setState(() => _catalog = catalog);
    } on Object catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted && serial == _requestSerial) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String platform = switch (_service.platformName) {
      'windows' => 'Windows',
      'macos' => 'macOS',
      _ => '当前系统',
    };
    return ColoredBox(
      key: const Key('app-center-page'),
      color: context.vibe.canvas,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '$platform 应用',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('app-center-refresh'),
                      tooltip: '刷新应用列表',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '仅显示 KEMI 市场中已上架、允许展示且适用于 $platform 的应用。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('app-center-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: '搜索应用名称或简介',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
                if ((_catalog?.categories ?? const <AppCenterCategory>[])
                    .isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        ChoiceChip(
                          key: const Key('app-center-category-all'),
                          label: const Text('全部'),
                          selected: _category == null,
                          onSelected: (_) {
                            setState(() => _category = null);
                            unawaited(_load());
                          },
                        ),
                        const SizedBox(width: 8),
                        ..._catalog!.categories
                            .where((entry) => !entry.isExplore)
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(entry.name),
                                  selected: _category == entry.name,
                                  onSelected: (_) {
                                    setState(() => _category = entry.name);
                                    unawaited(_load());
                                  },
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _catalog == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _catalog == null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: '应用列表加载失败',
        message: _error!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新加载'),
        ),
      );
    }
    final List<AppCenterItem> apps = _catalog?.apps ?? const <AppCenterItem>[];
    if (apps.isEmpty) {
      return _MessageState(
        icon: Icons.apps_outlined,
        title: '暂无符合条件的应用',
        message: _search.text.trim().isEmpty ? '市场还没有上架当前系统应用。' : '换一个关键词再试试。',
      );
    }
    return Stack(
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final int columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 500
                ? 2
                : 1;
            return GridView.builder(
              key: const Key('app-center-grid'),
              padding: const EdgeInsets.all(22),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                mainAxisExtent: 226,
              ),
              itemCount: apps.length,
              itemBuilder: (_, index) => _AppCard(
                item: apps[index],
                onTap: () => _showDetails(apps[index]),
              ),
            );
          },
        ),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Future<void> _showDetails(AppCenterItem item) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AppDetailsDialog(service: _service, item: item),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.item, required this.onTap});

  final AppCenterItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: Key('app-center-item-${item.appId}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _AppIcon(item: item, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.name.isEmpty ? item.packageName : item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Text(
                item.shortDescription.isEmpty ? '暂无简介' : item.shortDescription,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: <Widget>[
                const Icon(Icons.star_rounded, size: 17, color: Colors.amber),
                const SizedBox(width: 3),
                Text(item.rating.toStringAsFixed(1)),
                const Spacer(),
                Flexible(
                  child: Text(
                    'v${item.versionName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.item, required this.size});

  final AppCenterItem item;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: size,
        height: size,
        child: item.iconUrl.startsWith('https://')
            ? Image.network(
                item.iconUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.apps_rounded),
              )
            : const Icon(Icons.apps_rounded),
      ),
    ),
  );
}

class _AppDetailsDialog extends StatefulWidget {
  const _AppDetailsDialog({required this.service, required this.item});

  final AppCenterService service;
  final AppCenterItem item;

  @override
  State<_AppDetailsDialog> createState() => _AppDetailsDialogState();
}

class _AppDetailsDialogState extends State<_AppDetailsDialog> {
  double? _progress;
  String? _message;

  Future<void> _install() async {
    setState(() {
      _progress = 0;
      _message = '正在下载并验证安装包…';
    });
    try {
      await widget.service.downloadAndOpen(
        widget.item,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) setState(() => _message = '校验通过，已交给系统打开');
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _progress = null;
          _message = '安装失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppCenterItem item = widget.item;
    return AlertDialog(
      key: const Key('app-center-details'),
      title: Row(
        children: <Widget>[
          _AppIcon(item: item, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.name.isEmpty ? item.packageName : item.name),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  Chip(label: Text(item.category)),
                  Chip(label: Text('版本 ${item.versionName}')),
                  Chip(label: Text('评分 ${item.rating.toStringAsFixed(1)}')),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                item.longDescription.isNotEmpty
                    ? item.longDescription
                    : item.shortDescription.isNotEmpty
                    ? item.shortDescription
                    : '暂无详细介绍',
              ),
              const SizedBox(height: 16),
              Text(
                '开发者包名：${item.packageName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '下载量：${item.downloadCount}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!item.hasVerifiedInstaller) ...<Widget>[
                const SizedBox(height: 12),
                const Text('该条目缺少完整的 HTTPS、文件大小或 SHA-256 信息，已禁止安装。'),
              ],
              if (_progress != null) ...<Widget>[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
              ],
              if (_message != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(_message!),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          key: const Key('app-center-install'),
          onPressed: item.hasVerifiedInstaller && _progress == null
              ? _install
              : null,
          icon: const Icon(Icons.download_rounded),
          label: const Text('下载并安装'),
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 44),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
        ],
      ),
    ),
  );
}
