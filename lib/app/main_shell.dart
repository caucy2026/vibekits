import 'package:flutter/material.dart';

import '../features/archive/presentation/archive_tab.dart';
import '../features/cleaner/presentation/cleaner_tab.dart';
import '../features/documents/presentation/documents_tab.dart';
import '../features/dev_tools/presentation/dev_tools_tab.dart';
import '../features/local_models/presentation/local_models_tab.dart';
import 'app_shortcuts.dart';
import 'app_theme.dart';

/// 应用主窗口：顶栏 + 五 Tab 导航 + 内容区 + 状态栏。
///
/// 布局与行为对应 docs/01_WINDOWS_UI_LAYOUT.md 第 2 节。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

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

  static const List<Widget> _tabPages = <Widget>[
    ArchiveTab(),
    CleanerTab(),
    DocumentsTab(),
    DevToolsTab(),
    LocalModelsTab(),
  ];

  int _selectedIndex = 0;

  void _selectTab(int index) {
    if (index < 0 || index >= _tabTitles.length) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('设置'),
          content: const SizedBox(
            width: 360,
            child: Text(
              '设置页将在后续里程碑接入：主题、语言、最近文件、日志级别、'
              '缓存上限、模型目录和解压安全限制。\n\n当前版本：0.1.0（骨架）。',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<ShortcutActivator, VoidCallback> shortcuts =
        AppShortcuts.forShell(
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
        );

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: <Widget>[
              _buildTopBar(context),
              _buildTabBar(context),
              Expanded(
                child: IndexedStack(index: _selectedIndex, children: _tabPages),
              ),
              _buildStatusBar(context),
            ],
          ),
          endDrawer: _buildTaskPanel(context),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 56,
      color: VibekitsColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Icon(Icons.widgets_outlined, size: 20, color: VibekitsColors.primary),
          const SizedBox(width: 8),
          const Text(
            'Vibekits',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: VibekitsColors.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => Scaffold.of(context).openEndDrawer(),
            icon: const Icon(Icons.assignment_outlined, size: 16),
            label: const Text('后台任务 0'),
            style: TextButton.styleFrom(
              foregroundColor: VibekitsColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: VibekitsColors.textSecondary,
          ),
          const SizedBox(width: 4),
          const Text(
            '本地模式',
            style: TextStyle(fontSize: 12, color: VibekitsColors.textSecondary),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '设置 (Ctrl+,)',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            color: VibekitsColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      height: 68,
      color: VibekitsColors.surface,
      child: Row(
        children: List<Widget>.generate(_tabTitles.length, (int index) {
          final bool selected = index == _selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () => _selectTab(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        _tabIcons[index],
                        size: 20,
                        color: selected
                            ? VibekitsColors.primary
                            : VibekitsColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _tabTitles[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? VibekitsColors.primary
                                : VibekitsColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 3,
                    width: 48,
                    decoration: BoxDecoration(
                      color: selected
                          ? VibekitsColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 28,
      color: VibekitsColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          const Text(
            '就绪',
            style: TextStyle(fontSize: 12, color: VibekitsColors.textSecondary),
          ),
          const Spacer(),
          const Tooltip(
            message: '资源监控将在后续里程碑接入',
            child: Text(
              'CPU --% · 内存 --',
              style: TextStyle(
                fontSize: 12,
                color: VibekitsColors.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'v0.1.0',
            style: TextStyle(fontSize: 12, color: VibekitsColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskPanel(BuildContext context) {
    return const Drawer(
      width: 360,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '后台任务',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: VibekitsColors.textPrimary,
                ),
              ),
              SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: Text(
                    '暂无任务',
                    style: TextStyle(
                      fontSize: 12,
                      color: VibekitsColors.textSecondary,
                    ),
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
