import 'package:flutter/material.dart';

import '../features/archive/presentation/archive_tab.dart';
import '../features/cleaner/presentation/cleaner_tab.dart';
import '../features/documents/presentation/documents_tab.dart';
import '../features/dev_tools/presentation/dev_tools_tab.dart';
import '../features/local_models/presentation/local_models_tab.dart';
import 'app_shortcuts.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'supported_file_types.dart';

/// 应用主窗口：侧边导航 + 模块标题栏 + 内容区 + 状态栏。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.settingsController,
    this.initialFilePath,
  });

  final AppSettingsController settingsController;
  final String? initialFilePath;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const List<String> _tabTitles = <String>[
    '解压缩',
    'Windows 清理',
    '文档阅读',
    '开发工具',
    '本地模型',
  ];

  static const List<IconData> _tabIcons = <IconData>[
    Icons.folder_zip_outlined,
    Icons.cleaning_services_outlined,
    Icons.article_outlined,
    Icons.construction_outlined,
    Icons.memory_outlined,
  ];

  static const List<String> _tabDescriptions = <String>[
    '安全查看、创建与提取压缩文件',
    '扫描可清理空间并生成可核对报告',
    '快速查看文本、结构化数据与二进制文件',
    '常用编码、格式化和开发辅助能力',
    '管理离线模型、校验文件完整性',
  ];

  int _selectedIndex = 0;
  final ValueNotifier<int> _openRequest = ValueNotifier<int>(0);
  final ValueNotifier<int> _findRequest = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final AppSettings settings = widget.settingsController.value;
    final VibekitsFileKind startupKind = widget.initialFilePath == null
        ? VibekitsFileKind.unsupported
        : SupportedFileTypes.kindForPath(widget.initialFilePath!);
    _selectedIndex = switch (startupKind) {
      VibekitsFileKind.archive => 0,
      VibekitsFileKind.document => 2,
      VibekitsFileKind.unsupported =>
        settings.restoreLastTab ? settings.lastTab : 0,
    };
    widget.settingsController.addListener(_applySettings);
  }

  void _applySettings() {
    if (widget.initialFilePath != null) return;
    final AppSettings settings = widget.settingsController.value;
    if (settings.restoreLastTab && settings.lastTab != _selectedIndex) {
      setState(() => _selectedIndex = settings.lastTab);
    }
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_applySettings);
    _openRequest.dispose();
    _findRequest.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabTitles.length) {
      return;
    }
    setState(() => _selectedIndex = index);
    if (widget.settingsController.value.restoreLastTab) {
      widget.settingsController.update(
        widget.settingsController.value.copyWith(lastTab: index),
      );
    }
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => _SettingsDialog(
        initial: widget.settingsController.value,
        onSave: widget.settingsController.update,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = widget.settingsController.value;
    final List<Widget> tabPages = <Widget>[
      ArchiveTab(
        openRequest: _openRequest,
        initialPath:
            SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                VibekitsFileKind.archive
            ? widget.initialFilePath
            : null,
        maxEntries: settings.archiveMaxEntries,
        maxSingleExpandedBytes: settings.archiveMaxFileMb * 1024 * 1024,
      ),
      CleanerTab(
        initialWhitelist: settings.cleanupWhitelist,
        initialTargetIds: settings.cleanupScanTargets,
        onWhitelistChanged: (List<String> whitelist) =>
            widget.settingsController.update(
              widget.settingsController.value.copyWith(
                cleanupWhitelist: whitelist,
              ),
            ),
        onTargetIdsChanged: (List<String> targetIds) =>
            widget.settingsController.update(
              widget.settingsController.value.copyWith(
                cleanupScanTargets: targetIds,
              ),
            ),
      ),
      DocumentsTab(
        openRequest: _openRequest,
        findRequest: _findRequest,
        initialPath:
            SupportedFileTypes.kindForPath(widget.initialFilePath ?? '') ==
                VibekitsFileKind.document
            ? widget.initialFilePath
            : null,
      ),
      const DevToolsTab(),
      LocalModelsTab(
        key: ValueKey<String>(settings.modelDirectory),
        directory: settings.modelDirectory,
      ),
    ];
    final Map<ShortcutActivator, VoidCallback> shortcuts =
        AppShortcuts.forShell(
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
          onOpen: () {
            if (_selectedIndex == 0 || _selectedIndex == 2) {
              _openRequest.value++;
            }
          },
          onFind: () {
            if (_selectedIndex == 2) _findRequest.value++;
          },
        );

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool useSidebar = constraints.maxWidth >= 1180;
                if (!useSidebar) {
                  return Column(
                    children: <Widget>[
                      _buildTopBar(context, compact: true),
                      _buildCompactNavigation(context),
                      Expanded(child: _buildWorkspace(context, tabPages)),
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    _buildNavigation(context),
                    Expanded(child: _buildWorkspace(context, tabPages)),
                  ],
                );
              },
            ),
          ),
          endDrawer: _buildTaskPanel(context),
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, List<Widget> tabPages) {
    return Column(
      children: <Widget>[
        if (MediaQuery.sizeOf(context).width >= 1180) _buildTopBar(context),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Material(
              color: context.vibe.panelRaised,
              elevation: 2,
              shadowColor: context.vibe.glow,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.vibe.border),
              ),
              child: IndexedStack(index: _selectedIndex, children: tabPages),
            ),
          ),
        ),
        _buildStatusBar(context),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, {bool compact = false}) {
    return Container(
      height: compact ? 60 : 76,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      child: Row(
        children: <Widget>[
          if (compact) ...<Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'V',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _tabTitles[_selectedIndex],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    _tabDescriptions[_selectedIndex],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (!compact) ...<Widget>[
            _StatusPill(
              icon: Icons.shield_outlined,
              label: '本地运行',
              color: context.vibe.success,
            ),
            const SizedBox(width: 8),
          ],
          Builder(
            builder: (BuildContext drawerContext) => OutlinedButton.icon(
              onPressed: () => Scaffold.of(drawerContext).openEndDrawer(),
              icon: const Icon(Icons.task_alt_outlined, size: 17),
              label: const Text('任务 0'),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '设置 (Ctrl+,)',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactNavigation(BuildContext context) {
    return Container(
      key: const Key('primary-navigation-compact'),
      height: 58,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: context.vibe.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.vibe.border),
      ),
      child: Row(
        children: List<Widget>.generate(_tabTitles.length, (int index) {
          final bool selected = index == _selectedIndex;
          final Color color = selected
              ? Theme.of(context).colorScheme.primary
              : context.vibe.muted;
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              child: Material(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => _selectTab(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(_tabIcons[index], size: 18, color: color),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _tabTitles[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    return Container(
      key: const Key('primary-navigation'),
      width: 216,
      decoration: BoxDecoration(
        color: context.vibe.panel,
        border: Border(right: BorderSide(color: context.vibe.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: context.vibe.glow, blurRadius: 14),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'V',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Vibekits',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'LOCAL TOOLKIT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.vibe.muted,
                          letterSpacing: 1.1,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '工作台',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: context.vibe.muted, letterSpacing: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          ...List<Widget>.generate(_tabTitles.length, (int index) {
            final bool selected = index == _selectedIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _NavigationItem(
                key: ValueKey<String>('nav-${_tabTitles[index]}'),
                icon: _tabIcons[index],
                label: _tabTitles[index],
                shortcut: '${index + 1}',
                selected: selected,
                onTap: () => _selectTab(index),
              ),
            );
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.vibe.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.lock_outline, size: 16, color: context.vibe.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '数据默认留在本机',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'VIBEKITS  ·  v0.1.0',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: context.vibe.muted, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: 7, color: context.vibe.success),
          const SizedBox(width: 7),
          Text('系统就绪', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Tooltip(
            message: '资源监控将在后续里程碑接入',
            child: Text(
              'CPU --% · 内存 --',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskPanel(BuildContext context) {
    return Drawer(
      width: 360,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.task_alt_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text('后台任务', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '长时间任务会集中显示在这里',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Divider(color: context.vibe.border),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.inbox_outlined,
                        size: 36,
                        color: context.vibe.muted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '暂无任务',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '开始操作后，可在此查看进度',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? Theme.of(context).colorScheme.primary
        : context.vibe.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.26),
                    )
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 19, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).textTheme.bodyMedium?.color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  shortcut,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontFamily: 'Cascadia Mono',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial, required this.onSave});

  final AppSettings initial;
  final Future<void> Function(AppSettings) onSave;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late AppSettings _value = widget.initial;
  late final TextEditingController _modelDirectory = TextEditingController(
    text: _value.modelDirectory,
  );

  @override
  void dispose() {
    _modelDirectory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<ThemeMode>(
                key: const Key('theme-mode'),
                initialValue: _value.themeMode,
                decoration: const InputDecoration(labelText: '主题'),
                items: const <DropdownMenuItem<ThemeMode>>[
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
                onChanged: (ThemeMode? mode) {
                  if (mode != null) {
                    setState(() => _value = _value.copyWith(themeMode: mode));
                  }
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('恢复上次打开的标签页'),
                value: _value.restoreLastTab,
                onChanged: (bool enabled) => setState(
                  () => _value = _value.copyWith(restoreLastTab: enabled),
                ),
              ),
              DropdownButtonFormField<AppLogLevel>(
                initialValue: _value.logLevel,
                decoration: const InputDecoration(labelText: '日志级别'),
                items: AppLogLevel.values
                    .map(
                      (AppLogLevel level) => DropdownMenuItem<AppLogLevel>(
                        value: level,
                        child: Text(level.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (AppLogLevel? level) {
                  if (level != null) {
                    setState(() => _value = _value.copyWith(logLevel: level));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _value.cacheLimitMb.toString(),
                decoration: const InputDecoration(
                  labelText: '缓存上限（MB，64–8192）',
                ),
                keyboardType: TextInputType.number,
                onChanged: (String text) {
                  final int? number = int.tryParse(text);
                  if (number != null && number >= 64 && number <= 8192) {
                    _value = _value.copyWith(cacheLimitMb: number);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelDirectory,
                decoration: const InputDecoration(labelText: '模型目录（留空使用默认目录）'),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      initialValue: _value.archiveMaxEntries.toString(),
                      decoration: const InputDecoration(labelText: '解压最大条目数'),
                      keyboardType: TextInputType.number,
                      onChanged: (String text) {
                        final int? number = int.tryParse(text);
                        if (number != null &&
                            number >= 1000 &&
                            number <= 1000000) {
                          _value = _value.copyWith(archiveMaxEntries: number);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _value.archiveMaxFileMb.toString(),
                      decoration: const InputDecoration(labelText: '单文件上限（MB）'),
                      keyboardType: TextInputType.number,
                      onChanged: (String text) {
                        final int? number = int.tryParse(text);
                        if (number != null &&
                            number >= 64 &&
                            number <= 102400) {
                          _value = _value.copyWith(archiveMaxFileMb: number);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final NavigatorState navigator = Navigator.of(context);
            await widget.onSave(
              _value.copyWith(modelDirectory: _modelDirectory.text.trim()),
            );
            if (mounted) navigator.pop();
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
