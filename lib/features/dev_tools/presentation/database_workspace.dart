import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/remote_database_service.dart';
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
typedef RemoteDatabaseInspector = Future<RemoteDatabaseSnapshot> Function(
  RemoteDatabaseProfile profile,
  String password,
);
typedef RemoteDatabasePageLoader = Future<SqliteResultPage> Function(
  RemoteDatabaseProfile profile,
  String password,
  RemoteDatabaseObject object,
  int offset,
);
typedef RemoteDatabaseQueryRunner = Future<SqliteResultPage> Function(
  RemoteDatabaseProfile profile,
  String password,
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
    this.initialRemoteProfiles = const <String>[],
    this.onRemoteProfilesChanged,
    this.remoteInspect,
    this.remoteLoadPage,
    this.remoteRunQuery,
    this.passwordReader,
    this.passwordWriter,
  });

  final String? initialPath;
  final SqliteFilePicker? pickFile;
  final SqliteInspector? inspect;
  final SqlitePageLoader? loadPage;
  final SqliteQueryRunner? runQuery;
  final List<String> initialRemoteProfiles;
  final Future<void> Function(List<String> profiles)? onRemoteProfilesChanged;
  final RemoteDatabaseInspector? remoteInspect;
  final RemoteDatabasePageLoader? remoteLoadPage;
  final RemoteDatabaseQueryRunner? remoteRunQuery;
  final Future<String?> Function(String profileId)? passwordReader;
  final Future<void> Function(String profileId, String password)?
  passwordWriter;

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
  late final List<RemoteDatabaseProfile> _remoteProfiles = widget
      .initialRemoteProfiles
      .map(RemoteDatabaseProfile.decode)
      .whereType<RemoteDatabaseProfile>()
      .toList();
  RemoteDatabaseSnapshot? _remoteSnapshot;
  RemoteDatabaseObject? _selectedRemoteObject;
  String _remotePassword = '';
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
        _remoteSnapshot = null;
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
    final RemoteDatabaseSnapshot? remote = _remoteSnapshot;
    if (remote != null) {
      setState(() {
        _busy = true;
        _error = null;
        _mode = 1;
      });
      try {
        final SqliteResultPage page = widget.remoteRunQuery != null
            ? await widget.remoteRunQuery!(
                remote.profile,
                _remotePassword,
                _queryController.text,
              )
            : await RemoteDatabaseService.query(
                remote.profile,
                _remotePassword,
                _queryController.text,
              );
        if (mounted) setState(() => _page = page);
      } catch (error) {
        if (mounted) setState(() => _error = _errorMessage(error));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
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

  Future<void> _connectRemote() async {
    final _RemoteConnectRequest? request =
        await showDialog<_RemoteConnectRequest>(
          context: context,
          builder: (BuildContext context) => _RemoteConnectionDialog(
            profiles: List<RemoteDatabaseProfile>.unmodifiable(_remoteProfiles),
            passwordReader:
                widget.passwordReader ?? RemoteDatabaseCredentials.read,
          ),
        );
    if (request == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final RemoteDatabaseSnapshot snapshot = widget.remoteInspect != null
          ? await widget.remoteInspect!(request.profile, request.password)
          : await RemoteDatabaseService.inspect(
              request.profile,
              request.password,
            );
      if (request.rememberPassword) {
        await (widget.passwordWriter ?? RemoteDatabaseCredentials.write)(
          request.profile.id,
          request.password,
        );
      }
      _remoteProfiles.removeWhere(
        (RemoteDatabaseProfile profile) => profile.id == request.profile.id,
      );
      _remoteProfiles.insert(0, request.profile);
      if (_remoteProfiles.length > 20) _remoteProfiles.removeLast();
      await widget.onRemoteProfilesChanged?.call(
        _remoteProfiles
            .map((RemoteDatabaseProfile profile) => profile.encode())
            .toList(growable: false),
      );
      if (!mounted) return;
      _queryController.text = 'SELECT version();';
      setState(() {
        _remoteSnapshot = snapshot;
        _remotePassword = request.password;
        _selectedRemoteObject = snapshot.objects.firstOrNull;
        _snapshot = null;
        _selectedObject = null;
        _page = snapshot.initialPage;
        _mode = 0;
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

  Future<void> _selectRemoteObject(
    RemoteDatabaseObject object, {
    int offset = 0,
  }) async {
    final RemoteDatabaseSnapshot? snapshot = _remoteSnapshot;
    if (snapshot == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _selectedRemoteObject = object;
      _mode = 0;
    });
    try {
      final SqliteResultPage page = widget.remoteLoadPage != null
          ? await widget.remoteLoadPage!(
              snapshot.profile,
              _remotePassword,
              object,
              offset,
            )
          : await RemoteDatabaseService.loadTable(
              snapshot.profile,
              _remotePassword,
              object,
              offset: offset,
            );
      if (!mounted || _selectedRemoteObject?.label != object.label) return;
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
    final RemoteDatabaseSnapshot? remote = _remoteSnapshot;
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
              _Badge(
                text: remote == null ? 'SQLite · 本地只读' : 'PostgreSQL · 远程只读',
                color: context.vibe.success,
              ),
              if (snapshot != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    '${_fileName(snapshot.path)} · ${_formatBytes(snapshot.fileSize)} · SQLite ${snapshot.sqliteVersion}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                ),
              if (remote != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    '${remote.profile.endpointLabel} · PostgreSQL ${remote.serverVersion}',
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
              OutlinedButton.icon(
                key: const Key('database-connect-remote'),
                onPressed: _busy ? null : _connectRemote,
                icon: const Icon(Icons.cloud_outlined, size: 17),
                label: Text(
                  remote == null ? '连接远程' : '更换远程（${_remoteProfiles.length}）',
                ),
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
          child: snapshot == null && remote == null
              ? _EmptyDatabase(onOpen: _busy ? null : _pickAndOpen)
              : remote != null
              ? Row(
                  children: <Widget>[
                    _buildRemoteObjectList(remote),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildMainArea()),
                  ],
                )
              : Row(
                  children: <Widget>[
                    _buildObjectList(snapshot!),
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

  Widget _buildRemoteObjectList(RemoteDatabaseSnapshot snapshot) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Text(
              '远程对象 · ${snapshot.objects.length}',
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
                      '没有可访问的表或视图',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: snapshot.objects.length,
                    itemBuilder: (BuildContext context, int index) {
                      final RemoteDatabaseObject object =
                          snapshot.objects[index];
                      return ListTile(
                        key: ValueKey<String>(
                          'remote-database-object-${object.label}',
                        ),
                        dense: true,
                        selected: _selectedRemoteObject?.label == object.label,
                        leading: const Icon(
                          Icons.table_chart_outlined,
                          size: 17,
                        ),
                        title: Text(
                          object.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: _busy ? null : () => _selectRemoteObject(object),
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
                onPressed:
                    _busy ||
                        page.offset == 0 ||
                        (_selectedObject == null &&
                            _selectedRemoteObject == null)
                    ? null
                    : () {
                        final int offset =
                            (page.offset -
                                    SqliteDatabaseService.defaultPageSize)
                                .clamp(0, 1 << 62);
                        if (_remoteSnapshot != null) {
                          _selectRemoteObject(
                            _selectedRemoteObject!,
                            offset: offset,
                          );
                        } else {
                          _selectObject(_selectedObject!, offset: offset);
                        }
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed:
                    _busy ||
                        !page.hasMore ||
                        (_selectedObject == null &&
                            _selectedRemoteObject == null)
                    ? null
                    : () {
                        final int offset =
                            page.offset + SqliteDatabaseService.defaultPageSize;
                        if (_remoteSnapshot != null) {
                          _selectRemoteObject(
                            _selectedRemoteObject!,
                            offset: offset,
                          );
                        } else {
                          _selectObject(_selectedObject!, offset: offset);
                        }
                      },
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

class _RemoteConnectRequest {
  const _RemoteConnectRequest({
    required this.profile,
    required this.password,
    required this.rememberPassword,
  });

  final RemoteDatabaseProfile profile;
  final String password;
  final bool rememberPassword;
}

class _RemoteConnectionDialog extends StatefulWidget {
  const _RemoteConnectionDialog({
    required this.profiles,
    required this.passwordReader,
  });

  final List<RemoteDatabaseProfile> profiles;
  final Future<String?> Function(String profileId) passwordReader;

  @override
  State<_RemoteConnectionDialog> createState() =>
      _RemoteConnectionDialogState();
}

class _RemoteConnectionDialogState extends State<_RemoteConnectionDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '5432');
  final TextEditingController _database = TextEditingController(
    text: 'postgres',
  );
  final TextEditingController _username = TextEditingController(
    text: 'postgres',
  );
  final TextEditingController _password = TextEditingController();
  bool _tls = true;
  bool _remember = true;
  bool _showPassword = false;
  bool _loadingPassword = false;
  String? _selectedId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.profiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _selectProfile(widget.profiles.first),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _database.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _selectProfile(RemoteDatabaseProfile profile) async {
    setState(() {
      _selectedId = profile.id;
      _name.text = profile.name;
      _host.text = profile.host;
      _port.text = '${profile.port}';
      _database.text = profile.database;
      _username.text = profile.username;
      _tls = profile.useTls;
      _password.clear();
      _loadingPassword = true;
      _error = null;
    });
    try {
      final String? saved = await widget.passwordReader(profile.id);
      if (mounted && _selectedId == profile.id && saved != null) {
        _password.text = saved;
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取系统保存的密码，请重新输入');
    } finally {
      if (mounted && _selectedId == profile.id) {
        setState(() => _loadingPassword = false);
      }
    }
  }

  void _submit() {
    final int? port = int.tryParse(_port.text.trim());
    if (_host.text.trim().isEmpty ||
        _database.text.trim().isEmpty ||
        _username.text.trim().isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      setState(() => _error = '请填写有效的主机、端口、数据库和用户名');
      return;
    }
    final String id = RemoteDatabaseProfile.createId(
      host: _host.text.trim(),
      port: port,
      database: _database.text.trim(),
      username: _username.text.trim(),
    );
    Navigator.of(context).pop(
      _RemoteConnectRequest(
        profile: RemoteDatabaseProfile(
          id: id,
          name: _name.text.trim().isEmpty
              ? '${_host.text.trim()}/${_database.text.trim()}'
              : _name.text.trim(),
          host: _host.text.trim(),
          port: port,
          database: _database.text.trim(),
          username: _username.text.trim(),
          useTls: _tls,
        ),
        password: _password.text,
        rememberPassword: _remember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('连接 PostgreSQL'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.profiles.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: const Key('remote-database-history'),
                  initialValue: _selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '最近使用',
                    prefixIcon: Icon(Icons.history),
                  ),
                  items: widget.profiles
                      .map(
                        (RemoteDatabaseProfile profile) =>
                            DropdownMenuItem<String>(
                              value: profile.id,
                              child: Text(
                                '${profile.name} · ${profile.endpointLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (String? id) {
                    final RemoteDatabaseProfile? profile = widget.profiles
                        .where((RemoteDatabaseProfile item) => item.id == id)
                        .firstOrNull;
                    if (profile != null) _selectProfile(profile);
                  },
                ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('remote-database-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: '连接名称（可选）'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const Key('remote-database-host'),
                      controller: _host,
                      decoration: const InputDecoration(labelText: '主机'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('remote-database-port'),
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '端口'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('remote-database-database'),
                controller: _database,
                decoration: const InputDecoration(labelText: '数据库'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('remote-database-user'),
                controller: _username,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('remote-database-password'),
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: _loadingPassword ? '正在读取已保存密码…' : '密码',
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? '隐藏密码' : '显示密码',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _tls,
                onChanged: (bool? value) =>
                    setState(() => _tls = value ?? true),
                title: const Text('使用 TLS'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _remember,
                onChanged: (bool? value) =>
                    setState(() => _remember = value ?? true),
                title: const Text('记住密码'),
                subtitle: const Text('密码保存在 Windows 凭据管理器或 macOS 钥匙串'),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: VibekitsColors.danger,
                      fontSize: 12,
                    ),
                  ),
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
        FilledButton.icon(
          key: const Key('remote-database-submit'),
          onPressed: _loadingPassword ? null : _submit,
          icon: const Icon(Icons.link),
          label: const Text('连接'),
        ),
      ],
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
