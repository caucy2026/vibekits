import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/sqlite_database_service.dart';

typedef SqliteFilePicker = Future<String?> Function();
typedef SqliteInspector = Future<SqliteDatabaseSnapshot> Function(String path);
typedef SqlitePageLoader = Future<SqliteResultPage> Function(
  String path,
  String name,
  int offset,
);
typedef SqliteQueryRunner = Future<SqliteResultPage> Function(
  String path,
  String sql,
);

class DatabaseWorkspace extends StatefulWidget {
  const DatabaseWorkspace({
    super.key,
    this.initialPath,
    this.pickFile,
    this.inspect,
    this.loadPage,
    this.runQuery,
  });

  final String? initialPath;
  final SqliteFilePicker? pickFile;
  final SqliteInspector? inspect;
  final SqlitePageLoader? loadPage;
  final SqliteQueryRunner? runQuery;

  @override
  State<DatabaseWorkspace> createState() => _DatabaseWorkspaceState();
}

class _DatabaseWorkspaceState extends State<DatabaseWorkspace> {
  final TextEditingController _queryController = TextEditingController(
    text: 'SELECT sqlite_version() AS sqlite_version;',
  );
  SqliteDatabaseSnapshot? _snapshot;
  SqliteObjectInfo? _selectedObject;
  SqliteResultPage? _page;
  String? _error;
  bool _busy = false;
  int _mode = 0;

  @override
  void initState() {
    super.initState();
    final String? path = widget.initialPath;
    if (path != null && path.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(path));
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _pickAndOpen() async {
    final String? path = widget.pickFile != null
        ? await widget.pickFile!()
        : await _pickSqliteFile();
    if (path != null && path.isNotEmpty) await _open(path);
  }

  Future<void> _open(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final SqliteDatabaseSnapshot snapshot = await (widget.inspect != null
          ? widget.inspect!(path)
          : SqliteDatabaseService.inspect(path));
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _selectedObject = snapshot.objects.firstOrNull;
        _page = snapshot.initialPage;
        _busy = false;
        _mode = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _selectObject(SqliteObjectInfo object, {int offset = 0}) async {
    final SqliteDatabaseSnapshot? snapshot = _snapshot;
    if (snapshot == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _selectedObject = object;
      _mode = 0;
    });
    try {
      final SqliteResultPage page = await (widget.loadPage != null
          ? widget.loadPage!(snapshot.path, object.name, offset)
          : SqliteDatabaseService.loadTable(
              snapshot.path,
              object.name,
              offset: offset,
            ));
      if (!mounted || _selectedObject?.name != object.name) return;
      setState(() {
        _page = page;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _runQuery() async {
    final SqliteDatabaseSnapshot? snapshot = _snapshot;
    if (snapshot == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _mode = 1;
    });
    try {
      final SqliteResultPage page = await (widget.runQuery != null
          ? widget.runQuery!(snapshot.path, _queryController.text)
          : SqliteDatabaseService.query(snapshot.path, _queryController.text));
      if (!mounted) return;
      setState(() {
        _page = page;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SqliteDatabaseSnapshot? snapshot = _snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const Icon(Icons.storage_outlined, size: 21),
              const Text(
                '数据库管理器',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              _Badge(text: 'SQLite · 只读', color: context.vibe.success),
              if (snapshot != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    '${_fileName(snapshot.path)} · ${_formatBytes(snapshot.fileSize)} · SQLite ${snapshot.sqliteVersion}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('database-open'),
                onPressed: _busy ? null : _pickAndOpen,
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: Text(snapshot == null ? '打开数据库' : '更换'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Container(
            key: const Key('database-error'),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VibekitsColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VibekitsColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: snapshot == null
              ? _EmptyDatabase(onOpen: _busy ? null : _pickAndOpen)
              : Row(
                  children: <Widget>[
                    _buildObjectList(snapshot),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildMainArea()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildObjectList(SqliteDatabaseSnapshot snapshot) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Text(
              '对象 · ${snapshot.objects.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.vibe.muted,
              ),
            ),
          ),
          Expanded(
            child: snapshot.objects.isEmpty
                ? Center(
                    child: Text(
                      '空数据库',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: snapshot.objects.length,
                    itemBuilder: (BuildContext context, int index) {
                      final SqliteObjectInfo object = snapshot.objects[index];
                      return Tooltip(
                        message: object.sql.isEmpty ? object.name : object.sql,
                        waitDuration: const Duration(milliseconds: 600),
                        child: ListTile(
                          key: ValueKey<String>(
                            'database-object-${object.name}',
                          ),
                          dense: true,
                          selected:
                              _mode == 0 &&
                              object.name == _selectedObject?.name,
                          leading: Icon(
                            object.kind == SqliteObjectKind.table
                                ? Icons.table_chart_outlined
                                : Icons.visibility_outlined,
                            size: 17,
                          ),
                          title: Text(
                            object.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: _busy ? null : () => _selectObject(object),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.table_rows_outlined, size: 16),
                  label: Text('数据'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.terminal_outlined, size: 16),
                  label: Text('SQL'),
                ),
              ],
              selected: <int>{_mode},
              onSelectionChanged: (Set<int> value) =>
                  setState(() => _mode = value.first),
            ),
          ),
          const SizedBox(height: 8),
          if (_mode == 1) ...<Widget>[
            TextField(
              key: const Key('database-query-input'),
              controller: _queryController,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 13),
              decoration: const InputDecoration(
                hintText: '输入只读 SQL（最多返回 500 行）',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _busy ? null : _runQuery(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('database-run-query'),
                onPressed: _busy ? null : _runQuery,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('运行查询'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(child: _buildResult()),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final SqliteResultPage? page = _page;
    if (page == null) {
      return Center(
        child: Text('没有可显示的数据', style: TextStyle(color: context.vibe.muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${page.label} · ${page.rows.length} 行${page.offset == 0 ? '' : ' · 从 ${page.offset + 1} 开始'}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ),
            if (_mode == 0) ...<Widget>[
              IconButton(
                tooltip: '上一页',
                onPressed: _busy || page.offset == 0 || _selectedObject == null
                    ? null
                    : () => _selectObject(
                        _selectedObject!,
                        offset:
                            (page.offset -
                                    SqliteDatabaseService.defaultPageSize)
                                .clamp(0, 1 << 62),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: _busy || !page.hasMore || _selectedObject == null
                    ? null
                    : () => _selectObject(
                        _selectedObject!,
                        offset:
                            page.offset + SqliteDatabaseService.defaultPageSize,
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: page.columns.isEmpty
              ? const Center(child: Text('查询完成，没有返回列'))
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: context.vibe.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 38,
                          dataRowMaxHeight: 76,
                          columns: page.columns
                              .map(
                                (String column) => DataColumn(
                                  label: Text(
                                    column,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          rows: page.rows
                              .map((List<String> row) {
                                return DataRow(
                                  cells: List<DataCell>.generate(
                                    page.columns.length,
                                    (int index) => DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: 48,
                                          maxWidth: 280,
                                        ),
                                        child: SelectableText(
                                          index < row.length ? row[index] : '',
                                          maxLines: 4,
                                          style: const TextStyle(
                                            fontFamily: 'Cascadia Mono',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyDatabase extends StatelessWidget {
  const _EmptyDatabase({required this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.storage_outlined, size: 42, color: context.vibe.muted),
          const SizedBox(height: 12),
          const Text('拖入 SQLite 数据库，自动显示第一张表'),
          const SizedBox(height: 5),
          Text(
            '.db / .sqlite / .sqlite3 · 默认只读，不修改源文件',
            style: TextStyle(fontSize: 12, color: context.vibe.muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('选择数据库'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

Future<String?> _pickSqliteFile() async {
  final XFile? file = await openFile(
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(
        label: 'SQLite 数据库',
        extensions: <String>['db', 'sqlite', 'sqlite3', 'db3'],
      ),
    ],
  );
  return file?.path;
}

String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
}

String _errorMessage(Object error) {
  if (error is FormatException) return error.message;
  if (error is TimeoutException) return error.message ?? '数据库操作超时';
  if (error is FileSystemException) return error.message;
  return '数据库操作失败：$error';
}
