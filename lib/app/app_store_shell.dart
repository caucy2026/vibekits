import 'package:flutter/material.dart';

import '../features/about/presentation/app_store_about_tab.dart';
import '../features/archive/presentation/archive_tab.dart';
import '../features/documents/domain/format_router.dart';
import '../features/documents/presentation/documents_tab.dart';
import 'app_theme.dart';

/// Reviewable Mac App Store surface: three visible, offline capabilities only.
class AppStoreShell extends StatefulWidget {
  const AppStoreShell({super.key, this.initialFilePaths = const <String>[]});

  final List<String> initialFilePaths;

  @override
  State<AppStoreShell> createState() => _AppStoreShellState();
}

class _AppStoreShellState extends State<AppStoreShell> {
  static const List<String> _storeArchiveExtensions = <String>[
    'zip',
    'tar',
    'gz',
    'tgz',
    'bz2',
    'tbz2',
    'xz',
    'txz',
  ];
  static const List<String> _titles = <String>['解压缩', '文档阅读', '关于 Vibekits'];
  static const List<IconData> _icons = <IconData>[
    Icons.folder_zip_outlined,
    Icons.article_outlined,
    Icons.info_outline_rounded,
  ];

  int _selectedIndex = 0;

  String? get _initialPath =>
      widget.initialFilePaths.isEmpty ? null : widget.initialFilePaths.first;

  bool get _initialFileIsArchive {
    final String? path = _initialPath;
    if (path == null) return false;
    final int separator = path.lastIndexOf('.');
    if (separator < 0) return false;
    final String extension = path.substring(separator + 1).toLowerCase();
    return _storeArchiveExtensions.contains(extension);
  }

  @override
  void initState() {
    super.initState();
    if (_initialPath != null && !_initialFileIsArchive) _selectedIndex = 1;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      ArchiveTab(
        initialPath: _initialFileIsArchive ? _initialPath : null,
        acceptedExtensions: _storeArchiveExtensions,
        externalBackendsEnabled: false,
      ),
      DocumentsTab(
        initialPath: _initialFileIsArchive ? null : _initialPath,
        initialMode: _initialFileIsArchive || _initialPath == null
            ? null
            : documentModeForPath(_initialPath!),
      ),
      const AppStoreAboutTab(),
    ];

    return Scaffold(
      body: Row(
        children: <Widget>[
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
            decoration: BoxDecoration(
              color: context.vibe.panel,
              border: Border(right: BorderSide(color: context.vibe.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
                  child: Text(
                    'Vibekits',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                for (int index = 0; index < _titles.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      key: Key('app-store-nav-$index'),
                      selected: _selectedIndex == index,
                      leading: Icon(_icons[index]),
                      title: Text(_titles[index]),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onTap: () => setState(() => _selectedIndex = index),
                    ),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '本机离线处理',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: context.vibe.canvas,
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
          ),
        ],
      ),
    );
  }
}
