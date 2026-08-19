import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../app/app_theme.dart';
import '../domain/platform_credential_store.dart';
import '../domain/port_forward_service.dart';
import '../domain/remote_connection_record.dart';
import '../domain/remote_desktop_service.dart';
import '../domain/remote_session.dart';
import '../domain/sftp_service.dart';
import 'sftp_browser.dart';

typedef RemoteSessionStarter = Future<RemoteSessionHandle> Function(
  RemoteLaunchRequest request,
);
typedef SecureRemoteSessionStarter = Future<RemoteSessionHandle> Function(
  RemoteLaunchRequest request,
  String? secret,
  RemoteHostKeyVerifier verifyHostKey,
);
typedef RemoteCredentialReader = Future<String?> Function(String key);
typedef RemoteCredentialWriter = Future<void> Function(
  String key,
  String secret,
);
typedef RemoteCredentialDeleter = Future<void> Function(String key);
typedef RemoteClipboardReader = Future<String?> Function();
typedef RemoteFileConnector = Future<RemoteFileClient> Function(
  RemoteConnectionProfile profile,
  String? secret,
  RemoteHostKeyVerifier verifyHostKey,
);
typedef AuthenticatedRemoteFileConnector = Future<RemoteFileClient> Function(
  RemoteSessionHandle session,
);
typedef PortForwardConnector = Future<PortForwardConnection> Function(
  RemoteConnectionProfile profile,
  String? secret,
  RemoteHostKeyVerifier verifyHostKey,
);
typedef RemoteDesktopLauncher = Future<void> Function(
  RemoteDesktopTarget target,
);

class RemoteWorkspace extends StatefulWidget {
  const RemoteWorkspace({
    super.key,
    this.startSession,
    this.secureStartSession,
    this.initialProfiles = const <String>[],
    this.onProfilesChanged,
    this.readCredential,
    this.writeCredential,
    this.deleteCredential,
    this.profileIdGenerator,
    this.readClipboard,
    this.connectRemoteFiles,
    this.connectAuthenticatedRemoteFiles,
    this.connectPortForwards,
    this.launchRemoteDesktop,
  });

  final RemoteSessionStarter? startSession;
  final SecureRemoteSessionStarter? secureStartSession;
  final List<String> initialProfiles;
  final Future<void> Function(List<String> profiles)? onProfilesChanged;
  final RemoteCredentialReader? readCredential;
  final RemoteCredentialWriter? writeCredential;
  final RemoteCredentialDeleter? deleteCredential;
  final String Function()? profileIdGenerator;
  final RemoteClipboardReader? readClipboard;
  final RemoteFileConnector? connectRemoteFiles;
  final AuthenticatedRemoteFileConnector? connectAuthenticatedRemoteFiles;
  final PortForwardConnector? connectPortForwards;
  final RemoteDesktopLauncher? launchRemoteDesktop;

  @override
  State<RemoteWorkspace> createState() => _RemoteWorkspaceState();
}

class _RemoteWorkspaceState extends State<RemoteWorkspace> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '22');
  final TextEditingController _identity = TextEditingController();
  final TextEditingController _localPort = TextEditingController(text: '8080');
  final TextEditingController _targetHost = TextEditingController(
    text: '127.0.0.1',
  );
  final TextEditingController _targetPort = TextEditingController(text: '80');
  final TextEditingController _command = TextEditingController();
  final TextEditingController _terminalSearch = TextEditingController();
  final ScrollController _outputScroll = ScrollController();
  Terminal _terminal = Terminal(maxLines: 10000);
  RemoteSessionMode _mode = RemoteSessionMode.ssh;
  PortForwardKind _forwardKind = PortForwardKind.local;
  RemoteSessionHandle? _session;
  RemoteFileClient? _sftpClient;
  PortForwardConnection? _forwardConnection;
  final List<_PortForwardItem> _forwardItems = <_PortForwardItem>[];
  StreamSubscription<String>? _outputSubscription;
  String _output = '';
  final List<_RemoteTerminalTab> _terminalTabs = <_RemoteTerminalTab>[];
  int _activeTerminalTab = -1;
  String? _error;
  String? _desktopStatus;
  bool _starting = false;
  bool _openingSessionFiles = false;
  int _connectGeneration = 0;
  late final List<RemoteConnectionRecord> _profiles =
      RemoteConnectionRecord.decodeMany(widget.initialProfiles);
  String? _selectedProfileId;
  bool _savedCredentialAvailable = false;
  bool _searchVisible = false;
  int _terminalSearchMatches = 0;

  bool get _running => _session?.running == true;
  bool get _connected =>
      _running || _sftpClient != null || _forwardConnection != null;
  bool get _interactive => _session is RemoteInteractiveSessionHandle;
  bool get _canOpenSessionFiles =>
      _sftpClient == null &&
      _session?.running == true &&
      (widget.connectAuthenticatedRemoteFiles != null ||
          _session is RemoteSftpSessionHandle);
  _RemoteTerminalTab? get _activeTab =>
      _activeTerminalTab >= 0 && _activeTerminalTab < _terminalTabs.length
      ? _terminalTabs[_activeTerminalTab]
      : null;

  RemoteConnectionRecord? get _selectedProfile => _profiles
      .where(
        (RemoteConnectionRecord profile) => profile.id == _selectedProfileId,
      )
      .firstOrNull;

  Future<String?> _readCredential(String key) => widget.readCredential != null
      ? widget.readCredential!(key)
      : PlatformCredentialStore.read(key);

  Future<void> _writeCredential(String key, String secret) =>
      widget.writeCredential != null
      ? widget.writeCredential!(key, secret)
      : PlatformCredentialStore.write(key, secret);

  Future<void> _deleteCredential(String key) => widget.deleteCredential != null
      ? widget.deleteCredential!(key)
      : PlatformCredentialStore.delete(key);

  Future<void> _persistProfiles() async {
    _profiles.sort((RemoteConnectionRecord a, RemoteConnectionRecord b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.lastUsedEpochMs.compareTo(a.lastUsedEpochMs);
    });
    await widget.onProfilesChanged?.call(
      _profiles
          .take(50)
          .map((RemoteConnectionRecord profile) => profile.encode())
          .toList(growable: false),
    );
  }

  @override
  void initState() {
    super.initState();
  }

  Terminal _terminalFor(RemoteSessionHandle session) => Terminal(
    maxLines: 10000,
    onOutput: (String data) {
      if (session is RemoteInteractiveSessionHandle) session.send(data);
    },
    onResize: (int columns, int rows, int pixelWidth, int pixelHeight) {
      if (session is RemoteInteractiveSessionHandle) {
        session.resize(columns, rows, pixelWidth, pixelHeight);
      }
    },
  );

  void _activateTerminalTab(int index) {
    if (index < 0 || index >= _terminalTabs.length) return;
    final _RemoteTerminalTab tab = _terminalTabs[index];
    setState(() {
      _activeTerminalTab = index;
      _session = tab.session;
      _outputSubscription = tab.outputSubscription;
      _terminal = tab.terminal;
      _output = tab.output;
      _error = null;
    });
  }

  void _prepareNewTerminal() {
    setState(() {
      _activeTerminalTab = -1;
      _session = null;
      _outputSubscription = null;
      _terminal = Terminal(maxLines: 10000);
      _output = '';
      _error = null;
      _searchVisible = false;
      _terminalSearchMatches = 0;
    });
  }

  void _toggleTerminalSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _terminalSearch.clear();
        _terminalSearchMatches = 0;
        _activeTab?.controller.clearSelection();
      }
    });
  }

  void _searchCurrentTerminal(String query) {
    final _RemoteTerminalTab? tab = _activeTab;
    if (tab == null) return;
    final String needle = query;
    int matches = 0;
    int? firstLine;
    int firstColumn = 0;
    if (needle.isNotEmpty) {
      for (int line = 0; line < tab.terminal.buffer.height; line += 1) {
        final String text = tab.terminal.buffer.lines[line].getText();
        int offset = 0;
        while (offset <= text.length - needle.length) {
          final int found = text.indexOf(needle, offset);
          if (found < 0) break;
          firstLine ??= line;
          if (matches == 0) firstColumn = found;
          matches += 1;
          offset = found + needle.length;
        }
      }
    }
    tab.controller.clearSelection();
    if (firstLine != null) {
      tab.controller.setSelection(
        tab.terminal.buffer.createAnchor(firstColumn, firstLine),
        tab.terminal.buffer.createAnchor(
          firstColumn + needle.length,
          firstLine,
        ),
      );
    }
    setState(() => _terminalSearchMatches = matches);
  }

  void _clearCurrentTerminal() {
    final _RemoteTerminalTab? tab = _activeTab;
    if (tab == null) return;
    tab.terminal.buffer.clear();
    tab.terminal.buffer.setCursor(0, 0);
    tab.output = '';
    setState(() {
      _output = '';
      _terminalSearchMatches = 0;
    });
  }

  Future<void> _safePaste() async {
    final _RemoteTerminalTab? tab = _activeTab;
    if (tab == null || !tab.session.running) return;
    final String? text = widget.readClipboard != null
        ? await widget.readClipboard!()
        : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || !mounted) return;
    final int lineCount = '\n'.allMatches(text).length + 1;
    if (lineCount == 1) {
      tab.terminal.paste(text);
      return;
    }
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('粘贴并发送 $lineCount 行？'),
        content: SizedBox(
          width: 520,
          child: SelectableText(
            text.length > 4000 ? '${text.substring(0, 4000)}\n…' : text,
            key: const Key('remote-paste-preview'),
            style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 12),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('remote-paste-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (accepted == true && tab.session.running) tab.terminal.paste(text);
  }

  void _disposeDialogControllersLater(
    TextEditingController first,
    TextEditingController second,
  ) {
    // showDialog completes when pop begins; its reverse transition can still
    // build TextField for a few frames. Dispose only after that route is gone.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        first.dispose();
        second.dispose();
      }),
    );
  }

  Future<void> _selectProfile(String? id) async {
    if (id == null) {
      _newProfile();
      return;
    }
    final RemoteConnectionRecord profile = _profiles.firstWhere(
      (RemoteConnectionRecord item) => item.id == id,
    );
    _selectedProfileId = profile.id;
    _mode = profile.mode;
    _host.text = profile.host;
    _user.text = profile.user;
    _port.text = '${profile.port}';
    _identity.text = profile.identityFile ?? '';
    setState(() {
      _savedCredentialAvailable = false;
      _error = null;
      _desktopStatus = null;
    });
    if (profile.mode == RemoteSessionMode.remoteDesktop) return;
    final String? secret = await _readCredential(profile.credentialKey);
    if (!mounted || _selectedProfileId != profile.id) return;
    setState(() => _savedCredentialAvailable = secret?.isNotEmpty == true);
  }

  void _newProfile() {
    setState(() {
      _selectedProfileId = null;
      _savedCredentialAvailable = false;
      _mode = RemoteSessionMode.ssh;
      _host.clear();
      _user.clear();
      _port.text = '22';
      _identity.clear();
      _error = null;
      _desktopStatus = null;
    });
  }

  void _selectMode(RemoteSessionMode mode) {
    if (_mode == mode) return;
    final bool enteringDesktop = mode == RemoteSessionMode.remoteDesktop;
    final bool leavingDesktop = _mode == RemoteSessionMode.remoteDesktop;
    setState(() {
      _mode = mode;
      _desktopStatus = null;
      _error = null;
      if (enteringDesktop && _port.text == '22') {
        _port.text = '${RemoteDesktopService.defaultPort()}';
      } else if (leavingDesktop &&
          (_port.text == '3389' || _port.text == '5900')) {
        _port.text = '22';
      }
    });
  }

  Future<void> _saveProfile() async {
    final bool desktop = _mode == RemoteSessionMode.remoteDesktop;
    final RemoteLaunchRequest request = RemoteLaunchRequest(
      mode: _mode,
      profile: RemoteConnectionProfile(
        host: _host.text,
        user: _user.text,
        port: int.tryParse(_port.text) ?? 0,
        identityFile: _identity.text.trim().isEmpty ? null : _identity.text,
      ),
      localPort: int.tryParse(_localPort.text),
      targetHost: _targetHost.text,
      targetPort: int.tryParse(_targetPort.text),
    );
    try {
      if (desktop) {
        RemoteDesktopTarget(
          host: _host.text,
          port: int.tryParse(_port.text) ?? 0,
        ).validate();
      } else {
        request.buildArguments();
      }
    } on Object catch (error) {
      setState(() {
        _error = error is FormatException ? error.message : '$error';
      });
      return;
    }
    final RemoteConnectionRecord? selected = _selectedProfile;
    final TextEditingController name = TextEditingController(
      text:
          selected?.name ??
          (desktop
              ? _host.text.trim()
              : '${_user.text.trim()}@${_host.text.trim()}'),
    );
    final TextEditingController secret = TextEditingController();
    bool favorite = selected?.favorite ?? false;
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              title: Text(selected == null ? '保存远程会话' : '更新远程会话'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      key: const Key('remote-profile-name'),
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '会话名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (!desktop) ...<Widget>[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('remote-profile-secret'),
                        controller: secret,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: selected == null
                              ? '密码或口令（可选）'
                              : '密码或口令（留空不修改）',
                          helperText: '只保存到系统安全凭据，不写入普通设置',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                    CheckboxListTile(
                      key: const Key('remote-profile-favorite'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('收藏'),
                      value: favorite,
                      onChanged: (bool? value) =>
                          setDialogState(() => favorite = value ?? false),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('remote-profile-confirm-save'),
                  onPressed: () {
                    if (name.text.trim().isEmpty) return;
                    Navigator.pop(context, true);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
      ),
    );
    if (accepted != true || !mounted) {
      _disposeDialogControllersLater(name, secret);
      return;
    }
    final String id =
        selected?.id ??
        (widget.profileIdGenerator?.call() ??
            'remote_${DateTime.now().microsecondsSinceEpoch}');
    final RemoteConnectionRecord updated = RemoteConnectionRecord(
      id: id,
      name: name.text.trim(),
      mode: _mode,
      host: _host.text.trim(),
      user: desktop ? '' : _user.text.trim(),
      port: int.parse(_port.text),
      identityFile: desktop || _identity.text.trim().isEmpty
          ? null
          : _identity.text.trim(),
      favorite: favorite,
      lastUsedEpochMs: selected?.lastUsedEpochMs ?? 0,
      hostKeyType:
          !desktop &&
              selected?.host == _host.text.trim() &&
              selected?.port == int.parse(_port.text)
          ? selected?.hostKeyType
          : null,
      hostKeyFingerprint:
          !desktop &&
              selected?.host == _host.text.trim() &&
              selected?.port == int.parse(_port.text)
          ? selected?.hostKeyFingerprint
          : null,
    );
    final String newSecret = desktop ? '' : secret.text;
    _disposeDialogControllersLater(name, secret);
    if (selected == null) {
      _profiles.add(updated);
    } else {
      _profiles[_profiles.indexOf(selected)] = updated;
    }
    if (desktop && selected != null) {
      await _deleteCredential(updated.credentialKey);
      _savedCredentialAvailable = false;
    } else if (newSecret.isNotEmpty) {
      await _writeCredential(updated.credentialKey, newSecret);
      _savedCredentialAvailable = true;
    }
    _selectedProfileId = updated.id;
    await _persistProfiles();
    if (!mounted) return;
    setState(() => _error = null);
  }

  Future<void> _deleteProfile() async {
    final RemoteConnectionRecord? profile = _selectedProfile;
    if (profile == null) return;
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除远程会话？'),
        content: Text('将删除“${profile.name}”及其系统安全凭据。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('remote-profile-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _deleteCredential(profile.credentialKey);
    _profiles.remove(profile);
    _newProfile();
    await _persistProfiles();
  }

  Future<void> _toggleFavorite() async {
    final RemoteConnectionRecord? profile = _selectedProfile;
    if (profile == null) return;
    _profiles[_profiles.indexOf(profile)] = profile.copyWith(
      favorite: !profile.favorite,
    );
    await _persistProfiles();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final _RemoteTerminalTab tab in _terminalTabs) {
      unawaited(tab.outputSubscription.cancel());
      unawaited(tab.session.stop());
      tab.controller.dispose();
    }
    final RemoteFileClient? sftp = _sftpClient;
    if (sftp != null) unawaited(sftp.close());
    final PortForwardConnection? forwards = _forwardConnection;
    if (forwards != null) unawaited(forwards.close());
    for (final TextEditingController controller in <TextEditingController>[
      _host,
      _user,
      _port,
      _identity,
      _localPort,
      _targetHost,
      _targetPort,
      _command,
      _terminalSearch,
    ]) {
      controller.dispose();
    }
    _outputScroll.dispose();
    super.dispose();
  }

  Future<void> _pickIdentity() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[XTypeGroup(label: 'OpenSSH 私钥')],
    );
    if (file != null) _identity.text = file.path;
  }

  Future<String?> _requestSessionSecret() async {
    final TextEditingController secret = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('输入 SSH 密码'),
        content: SizedBox(
          width: 380,
          child: TextField(
            key: const Key('remote-session-secret'),
            controller: secret,
            autofocus: true,
            obscureText: true,
            onSubmitted: (String value) => Navigator.pop(context, value),
            decoration: const InputDecoration(
              labelText: '仅用于本次连接',
              helperText: '不会写入设置或日志；可先保存会话以安全记住密码',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('remote-session-secret-confirm'),
            onPressed: () => Navigator.pop(context, secret.text),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    _disposeDialogControllersLater(secret, TextEditingController());
    return result;
  }

  Future<bool> _verifyHostKey(String type, String fingerprint) async {
    final RemoteConnectionRecord? selected = _selectedProfile;
    final bool known =
        selected?.hostKeyType == type &&
        selected?.hostKeyFingerprint == fingerprint;
    if (known) return true;
    if (!mounted) return false;
    final bool changed = selected?.hostKeyFingerprint?.isNotEmpty == true;
    final bool? accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        icon: Icon(
          changed ? Icons.warning_amber_rounded : Icons.security_rounded,
          color: changed ? VibekitsColors.danger : context.vibe.glow,
        ),
        title: Text(changed ? '主机指纹已变化' : '确认主机指纹'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                changed
                    ? '这可能表示服务器重装，也可能是中间人攻击。请通过可信渠道核对后再继续。'
                    : '首次连接必须核对服务器指纹。确认后会绑定到当前会话记录。',
              ),
              const SizedBox(height: 12),
              SelectableText(
                '$type\n$fingerprint',
                key: const Key('remote-host-fingerprint'),
                style: const TextStyle(
                  fontFamily: 'Cascadia Mono',
                  fontSize: 12,
                ),
              ),
              if (changed) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  '原指纹：${selected!.hostKeyFingerprint}',
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消连接'),
          ),
          FilledButton(
            key: const Key('remote-host-fingerprint-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(changed ? '已核对，更新指纹' : '指纹一致，连接'),
          ),
        ],
      ),
    );
    if (accepted == true && selected != null) {
      _profiles[_profiles.indexOf(selected)] = selected.copyWith(
        hostKeyType: type,
        hostKeyFingerprint: fingerprint,
      );
      await _persistProfiles();
    }
    return accepted == true;
  }

  PortForwardSpec _buildForwardSpec() => PortForwardSpec(
    kind: _forwardKind,
    listenPort: int.tryParse(_localPort.text) ?? 0,
    targetHost: _targetHost.text,
    targetPort: int.tryParse(_targetPort.text),
  );

  Future<void> _startForward() async {
    final int generation = ++_connectGeneration;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final RemoteConnectionProfile profile = RemoteConnectionProfile(
        host: _host.text,
        user: _user.text,
        port: int.tryParse(_port.text) ?? 0,
        identityFile: _identity.text.trim().isEmpty ? null : _identity.text,
      );
      profile.validate();
      final PortForwardSpec spec = _buildForwardSpec()..validate();
      PortForwardConnection? connection = _forwardConnection;
      if (connection == null || !connection.connected) {
        String? secret;
        final RemoteConnectionRecord? selected = _selectedProfile;
        if (selected != null) {
          secret = await _readCredential(selected.credentialKey);
        }
        if (secret?.isNotEmpty != true &&
            profile.identityFile?.isNotEmpty != true) {
          secret = await _requestSessionSecret();
          if (secret == null) {
            if (mounted) setState(() => _starting = false);
            return;
          }
        }
        Future<bool> verifier(String type, String fingerprint) =>
            generation == _connectGeneration
            ? _verifyHostKey(type, fingerprint)
            : Future<bool>.value(false);
        connection = await (widget.connectPortForwards != null
            ? widget.connectPortForwards!(profile, secret, verifier)
            : PortForwardService.connect(
                profile,
                secret: secret,
                verifyHostKey: verifier,
              ));
        if (!mounted || generation != _connectGeneration) {
          await connection.close();
          return;
        }
        _forwardConnection = connection;
        final PortForwardConnection activeConnection = connection;
        unawaited(
          activeConnection.done.whenComplete(() {
            if (!mounted || !identical(_forwardConnection, activeConnection)) {
              return;
            }
            _forwardConnection = null;
            for (final _PortForwardItem item in _forwardItems) {
              item.stopped = true;
            }
            setState(() => _error = 'SSH 转发连接已断开');
          }),
        );
      }
      final PortForwardHandle handle = await connection.start(spec);
      if (!mounted || generation != _connectGeneration) {
        await handle.stop();
        return;
      }
      setState(() {
        _starting = false;
        _forwardItems.add(_PortForwardItem(handle));
      });
      final RemoteConnectionRecord? selected = _selectedProfile;
      if (selected != null) {
        _profiles[_profiles.indexOf(selected)] = selected.copyWith(
          lastUsedEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        unawaited(_persistProfiles());
      }
    } catch (error) {
      if (!mounted || generation != _connectGeneration) return;
      setState(() {
        _starting = false;
        _error = error is FormatException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _stopForward(_PortForwardItem item) async {
    if (item.stopped) return;
    item.stopped = true;
    setState(() {});
    await item.handle.stop();
  }

  Future<void> _disconnectForwards() async {
    final PortForwardConnection? connection = _forwardConnection;
    if (connection == null) return;
    _connectGeneration += 1;
    _forwardConnection = null;
    for (final _PortForwardItem item in _forwardItems) {
      item.stopped = true;
    }
    setState(() {});
    await connection.close();
  }

  Future<void> _launchDesktop() async {
    setState(() {
      _starting = true;
      _error = null;
      _desktopStatus = null;
    });
    try {
      final RemoteDesktopTarget target = RemoteDesktopTarget(
        host: _host.text,
        port: int.tryParse(_port.text) ?? 0,
      )..validate();
      await (widget.launchRemoteDesktop != null
          ? widget.launchRemoteDesktop!(target)
          : RemoteDesktopService.launch(target));
      if (!mounted) return;
      setState(() {
        _starting = false;
        _desktopStatus = '已交给系统远程桌面客户端：${target.authority}';
      });
      final RemoteConnectionRecord? selected = _selectedProfile;
      if (selected != null) {
        _profiles[_profiles.indexOf(selected)] = selected.copyWith(
          lastUsedEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        unawaited(_persistProfiles());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = error is FormatException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _start() async {
    if (_mode == RemoteSessionMode.remoteDesktop) {
      await _launchDesktop();
      return;
    }
    if (_mode == RemoteSessionMode.localForward) {
      await _startForward();
      return;
    }
    final int generation = ++_connectGeneration;
    setState(() {
      _starting = true;
      _error = null;
      _output = '';
    });
    try {
      final RemoteLaunchRequest request = RemoteLaunchRequest(
        mode: _mode,
        profile: RemoteConnectionProfile(
          host: _host.text,
          user: _user.text,
          port: int.tryParse(_port.text) ?? 0,
          identityFile: _identity.text.trim().isEmpty ? null : _identity.text,
        ),
        localPort: int.tryParse(_localPort.text),
        targetHost: _targetHost.text,
        targetPort: int.tryParse(_targetPort.text),
      );
      // Build first so validation errors appear before process creation.
      request.buildArguments();
      String? secret;
      if (widget.startSession == null &&
          (_mode == RemoteSessionMode.ssh || _mode == RemoteSessionMode.sftp)) {
        final RemoteConnectionRecord? selected = _selectedProfile;
        if (selected != null) {
          secret = await _readCredential(selected.credentialKey);
        }
        if (secret?.isNotEmpty != true &&
            request.profile.identityFile?.isNotEmpty != true) {
          secret = await _requestSessionSecret();
          if (secret == null) {
            if (mounted) setState(() => _starting = false);
            return;
          }
        }
      }
      Future<bool> verifier(String type, String fingerprint) =>
          generation == _connectGeneration
          ? _verifyHostKey(type, fingerprint)
          : Future<bool>.value(false);
      if (_mode == RemoteSessionMode.sftp && widget.startSession == null) {
        final RemoteFileClient client = await (widget.connectRemoteFiles != null
            ? widget.connectRemoteFiles!(request.profile, secret, verifier)
            : RemoteFileService.connect(
                request.profile,
                secret: secret,
                verifyHostKey: verifier,
              ));
        if (!mounted || generation != _connectGeneration) {
          await client.close();
          return;
        }
        _sftpClient = client;
        setState(() => _starting = false);
        final RemoteConnectionRecord? selected = _selectedProfile;
        if (selected != null) {
          _profiles[_profiles.indexOf(selected)] = selected.copyWith(
            lastUsedEpochMs: DateTime.now().millisecondsSinceEpoch,
          );
          unawaited(_persistProfiles());
        }
        return;
      }
      final RemoteSessionHandle session = await (widget.startSession != null
          ? widget.startSession!(request)
          : widget.secureStartSession != null
          ? widget.secureStartSession!(request, secret, verifier)
          : RemoteSessionService.start(
              request,
              secret: secret,
              verifyHostKey: verifier,
            ));
      if (!mounted || generation != _connectGeneration) {
        await session.stop();
        return;
      }
      final Terminal terminal = _terminalFor(session);
      final _RemoteTerminalTab tab = _RemoteTerminalTab(
        id: 'terminal_${DateTime.now().microsecondsSinceEpoch}',
        title: '${request.profile.user.trim()}@${request.profile.host.trim()}',
        session: session,
        terminal: terminal,
        output: _mode == RemoteSessionMode.localForward ? '正在建立本地转发…\n' : '',
      );
      tab.outputSubscription = session.output.listen(
        (String chunk) => _appendOutput(tab, chunk),
      );
      _terminalTabs.add(tab);
      _activeTerminalTab = _terminalTabs.length - 1;
      _session = session;
      _outputSubscription = tab.outputSubscription;
      _terminal = terminal;
      setState(() {
        _starting = false;
        _output = tab.output;
      });
      final RemoteConnectionRecord? selected = _selectedProfile;
      if (selected != null) {
        _profiles[_profiles.indexOf(selected)] = selected.copyWith(
          lastUsedEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        unawaited(_persistProfiles());
      }
      unawaited(
        session.exitCode.then((int code) {
          if (!mounted) return;
          _appendOutput(tab, '\n[会话已结束 · exit $code]\n');
        }),
      );
    } catch (error) {
      if (!mounted || generation != _connectGeneration) return;
      setState(() {
        _starting = false;
        _error = error is FormatException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _cancelStart() {
    if (!_starting) return;
    _connectGeneration += 1;
    setState(() {
      _starting = false;
      _error = '连接已取消；迟到的网络连接会在建立后立即释放。';
    });
  }

  void _appendOutput(_RemoteTerminalTab tab, String chunk) {
    if (!mounted) return;
    if (tab.session is RemoteInteractiveSessionHandle) {
      tab.terminal.write(chunk);
    }
    tab.output = '${tab.output}$chunk';
    if (tab.output.length > 200000) {
      tab.output =
          '[较早输出已截断]\n${tab.output.substring(tab.output.length - 180000)}';
    }
    if (_activeTab == tab) {
      setState(() => _output = tab.output);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_outputScroll.hasClients) {
          _outputScroll.jumpTo(_outputScroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _send() {
    final String line = _command.text;
    if (!_running || line.isEmpty) return;
    _session!.sendLine(line);
    _command.clear();
  }

  Future<void> _stop() async {
    final _RemoteTerminalTab? tab = _activeTab;
    final RemoteSessionHandle? session = tab?.session ?? _session;
    if (session == null) return;
    await session.stop();
    await (tab?.outputSubscription ?? _outputSubscription)?.cancel();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _disconnectSftp() async {
    final RemoteFileClient? client = _sftpClient;
    if (client == null) return;
    _sftpClient = null;
    setState(() {});
    await client.close();
  }

  Future<void> _openSftpFromActiveSession() async {
    final RemoteSessionHandle? session = _activeTab?.session ?? _session;
    if (session == null || !session.running || _openingSessionFiles) return;
    if (widget.connectAuthenticatedRemoteFiles == null &&
        session is! RemoteSftpSessionHandle) {
      return;
    }
    setState(() {
      _openingSessionFiles = true;
      _error = null;
    });
    try {
      final RemoteFileClient client =
          await (widget.connectAuthenticatedRemoteFiles != null
              ? widget.connectAuthenticatedRemoteFiles!(session)
              : RemoteFileService.connectAuthenticated(
                  session as RemoteSftpSessionHandle,
                ));
      if (!mounted || !session.running || session != _session) {
        await client.close();
        return;
      }
      setState(() {
        _sftpClient = client;
        _openingSessionFiles = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _openingSessionFiles = false;
        _error =
            '打开当前会话的 SFTP 失败：${error.toString().replaceFirst('Bad state: ', '')}';
      });
    }
  }

  Future<void> _closeTerminalTab(int index) async {
    if (index < 0 || index >= _terminalTabs.length) return;
    final _RemoteTerminalTab tab = _terminalTabs[index];
    await tab.session.stop();
    await tab.outputSubscription.cancel();
    tab.controller.dispose();
    if (!mounted) return;
    _terminalTabs.removeAt(index);
    if (_terminalTabs.isEmpty) {
      _prepareNewTerminal();
      return;
    }
    _activateTerminalTab(index.clamp(0, _terminalTabs.length - 1));
  }

  @override
  Widget build(BuildContext context) {
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
              const Icon(Icons.lan_outlined, size: 21),
              const Text(
                '远程连接',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              _RemoteBadge(text: '交互式 SSH', color: context.vibe.success),
              Text(
                '密码进系统凭据 · 主机指纹强校验',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'remote-profile-picker-${_selectedProfileId ?? 'new'}',
                  ),
                  initialValue: _selectedProfileId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '最近会话',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _profiles
                      .map(
                        (
                          RemoteConnectionRecord profile,
                        ) => DropdownMenuItem<String>(
                          value: profile.id,
                          child: Text(
                            '${profile.favorite ? '★ ' : ''}${profile.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _connected || _starting ? null : _selectProfile,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('remote-profile-save'),
                onPressed: _connected || _starting ? null : _saveProfile,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(_selectedProfile == null ? '保存会话' : '更新'),
              ),
              IconButton(
                key: const Key('remote-profile-new'),
                tooltip: '新建会话',
                onPressed: _connected || _starting ? null : _newProfile,
                icon: const Icon(Icons.add_rounded),
              ),
              IconButton(
                key: const Key('remote-profile-favorite-toggle'),
                tooltip: _selectedProfile?.favorite == true ? '取消收藏' : '收藏',
                onPressed: _selectedProfile == null || _connected || _starting
                    ? null
                    : _toggleFavorite,
                icon: Icon(
                  _selectedProfile?.favorite == true
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                ),
              ),
              IconButton(
                key: const Key('remote-profile-delete'),
                tooltip: '删除会话',
                onPressed: _selectedProfile == null || _connected || _starting
                    ? null
                    : _deleteProfile,
                icon: const Icon(Icons.delete_outline),
              ),
              if (_savedCredentialAvailable &&
                  _mode != RemoteSessionMode.remoteDesktop)
                _RemoteBadge(text: '系统凭据已保存', color: context.vibe.success),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<RemoteSessionMode>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<RemoteSessionMode>>[
              ButtonSegment<RemoteSessionMode>(
                value: RemoteSessionMode.ssh,
                icon: Icon(Icons.terminal_outlined, size: 16),
                label: Text('SSH'),
              ),
              ButtonSegment<RemoteSessionMode>(
                value: RemoteSessionMode.sftp,
                icon: Icon(Icons.folder_copy_outlined, size: 16),
                label: Text('SFTP'),
              ),
              ButtonSegment<RemoteSessionMode>(
                value: RemoteSessionMode.localForward,
                icon: Icon(Icons.swap_horiz, size: 16),
                label: Text('端口转发'),
              ),
              ButtonSegment<RemoteSessionMode>(
                value: RemoteSessionMode.remoteDesktop,
                icon: Icon(Icons.desktop_windows_outlined, size: 16),
                label: Text('桌面'),
              ),
            ],
            selected: <RemoteSessionMode>{_mode},
            onSelectionChanged: _connected || _starting
                ? null
                : (Set<RemoteSessionMode> value) => _selectMode(value.first),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _Field(
                width: 230,
                controller: _host,
                label: '主机',
                hint: 'server.example.com',
                keyName: 'remote-host',
                enabled: !_connected && !_starting,
              ),
              if (_mode != RemoteSessionMode.remoteDesktop)
                _Field(
                  width: 150,
                  controller: _user,
                  label: '用户名',
                  hint: 'developer',
                  keyName: 'remote-user',
                  enabled: !_connected && !_starting,
                ),
              _Field(
                width: 90,
                controller: _port,
                label: '端口',
                keyName: 'remote-port',
                enabled: !_connected && !_starting,
              ),
              if (_mode != RemoteSessionMode.remoteDesktop)
                SizedBox(
                  width: 300,
                  child: TextField(
                    key: const Key('remote-identity'),
                    controller: _identity,
                    enabled: !_connected && !_starting,
                    decoration: InputDecoration(
                      labelText: '私钥（可选）',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '选择私钥',
                        onPressed: _connected || _starting
                            ? null
                            : _pickIdentity,
                        icon: const Icon(Icons.key_outlined, size: 17),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_mode == RemoteSessionMode.localForward) ...<Widget>[
            const SizedBox(height: 10),
            SegmentedButton<PortForwardKind>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<PortForwardKind>>[
                ButtonSegment<PortForwardKind>(
                  value: PortForwardKind.local,
                  label: Text('本地'),
                ),
                ButtonSegment<PortForwardKind>(
                  value: PortForwardKind.remote,
                  label: Text('远程'),
                ),
                ButtonSegment<PortForwardKind>(
                  value: PortForwardKind.dynamic,
                  label: Text('SOCKS5'),
                ),
              ],
              selected: <PortForwardKind>{_forwardKind},
              onSelectionChanged: _starting
                  ? null
                  : (Set<PortForwardKind> value) =>
                        setState(() => _forwardKind = value.first),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _Field(
                  width: 130,
                  controller: _localPort,
                  label: _forwardKind == PortForwardKind.remote
                      ? '远端监听端口'
                      : '本地监听端口',
                  keyName: 'remote-local-port',
                ),
                if (_forwardKind != PortForwardKind.dynamic) ...<Widget>[
                  _Field(
                    width: 230,
                    controller: _targetHost,
                    label: _forwardKind == PortForwardKind.remote
                        ? '本机目标主机'
                        : '远端目标主机',
                    keyName: 'remote-target-host',
                  ),
                  _Field(
                    width: 130,
                    controller: _targetPort,
                    label: '目标端口',
                    keyName: 'remote-target-port',
                  ),
                ],
              ],
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('remote-error'),
              style: const TextStyle(
                color: VibekitsColors.danger,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton.icon(
                key: const Key('remote-primary-action'),
                onPressed: _starting
                    ? _mode == RemoteSessionMode.remoteDesktop
                          ? null
                          : _cancelStart
                    : _sftpClient != null
                    ? _disconnectSftp
                    : _mode == RemoteSessionMode.localForward
                    ? _start
                    : _running
                    ? _stop
                    : _start,
                icon: Icon(
                  _starting
                      ? _mode == RemoteSessionMode.remoteDesktop
                            ? Icons.hourglass_top_rounded
                            : Icons.close_rounded
                      : _sftpClient != null
                      ? Icons.stop_rounded
                      : _mode == RemoteSessionMode.localForward
                      ? Icons.add_rounded
                      : _mode == RemoteSessionMode.remoteDesktop
                      ? Icons.desktop_windows_outlined
                      : _running
                      ? Icons.stop_rounded
                      : Icons.power_settings_new,
                  size: 18,
                ),
                label: Text(
                  _starting
                      ? _mode == RemoteSessionMode.remoteDesktop
                            ? '正在打开…'
                            : '取消连接'
                      : _sftpClient != null
                      ? '断开 SFTP'
                      : _mode == RemoteSessionMode.localForward
                      ? _forwardConnection == null
                            ? '启动转发'
                            : '添加转发'
                      : _mode == RemoteSessionMode.remoteDesktop
                      ? '打开桌面'
                      : _running
                      ? '断开'
                      : '连接',
                ),
              ),
              if (_mode == RemoteSessionMode.localForward &&
                  _forwardConnection != null) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('remote-forward-disconnect-all'),
                  onPressed: _disconnectForwards,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('全部断开'),
                ),
              ],
              if (_running) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('remote-new-terminal'),
                  onPressed: _starting ? null : _prepareNewTerminal,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建终端'),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _mode == RemoteSessionMode.sftp
                      ? '连接后直接在本地/远端双栏拖放；同名文件先确认。'
                      : _mode == RemoteSessionMode.localForward
                      ? '本地/SOCKS 只监听 127.0.0.1；每条可独立停止。'
                      : _mode == RemoteSessionMode.remoteDesktop
                      ? '调用系统客户端；登录和凭据由 Windows/macOS 管理。'
                      : '首次连接必须核对服务端主机指纹；不会自动跳过验证。',
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
              ),
            ],
          ),
          if (_sftpClient == null && _terminalTabs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView.separated(
                key: const Key('remote-terminal-tabs'),
                scrollDirection: Axis.horizontal,
                itemCount: _terminalTabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int index) {
                  final _RemoteTerminalTab tab = _terminalTabs[index];
                  return InputChip(
                    key: Key('remote-terminal-tab-${tab.id}'),
                    selected: index == _activeTerminalTab,
                    showCheckmark: false,
                    avatar: Icon(
                      tab.session.running
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 9,
                      color: tab.session.running
                          ? context.vibe.success
                          : context.vibe.muted,
                    ),
                    label: Text(tab.title),
                    onSelected: (_) => _activateTerminalTab(index),
                    onDeleted: () => _closeTerminalTab(index),
                    deleteIcon: const Icon(Icons.close_rounded, size: 15),
                    deleteButtonTooltipMessage: '关闭终端',
                  );
                },
              ),
            ),
          ],
          if (_sftpClient == null && _interactive) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                if (_canOpenSessionFiles) ...<Widget>[
                  FilledButton.icon(
                    key: const Key('remote-open-session-sftp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.vibe.success,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _openingSessionFiles
                        ? null
                        : _openSftpFromActiveSession,
                    icon: _openingSessionFiles
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.folder_copy_outlined, size: 17),
                    label: const Text('SFTP 文件'),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  key: const Key('remote-terminal-search-toggle'),
                  tooltip: '搜索 (Ctrl+F)',
                  onPressed: _toggleTerminalSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                ),
                IconButton(
                  key: const Key('remote-terminal-paste'),
                  tooltip: '安全粘贴',
                  onPressed: _running ? _safePaste : null,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                ),
                IconButton(
                  key: const Key('remote-terminal-clear'),
                  tooltip: '清屏',
                  onPressed: _clearCurrentTerminal,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                ),
                if (_searchVisible) ...<Widget>[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      key: const Key('remote-terminal-search'),
                      controller: _terminalSearch,
                      autofocus: true,
                      onChanged: _searchCurrentTerminal,
                      onSubmitted: _searchCurrentTerminal,
                      decoration: InputDecoration(
                        hintText: '搜索当前终端',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixText: '$_terminalSearchMatches 个匹配',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: _mode == RemoteSessionMode.localForward
                ? _PortForwardList(
                    items: _forwardItems,
                    connected: _forwardConnection != null,
                    onStop: _stopForward,
                  )
                : _mode == RemoteSessionMode.remoteDesktop
                ? _RemoteDesktopPanel(status: _desktopStatus)
                : _sftpClient != null
                ? SftpBrowser(
                    key: const Key('sftp-browser'),
                    client: _sftpClient!,
                  )
                : Container(
                    key: const Key('remote-output'),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.vibe.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.vibe.border),
                    ),
                    child: _interactive
                        ? CallbackShortcuts(
                            bindings: <ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.keyV,
                                control: true,
                              ): () =>
                                  unawaited(_safePaste()),
                              const SingleActivator(
                                LogicalKeyboardKey.keyV,
                                meta: true,
                              ): () =>
                                  unawaited(_safePaste()),
                              const SingleActivator(
                                LogicalKeyboardKey.keyF,
                                control: true,
                              ): _toggleTerminalSearch,
                              const SingleActivator(
                                LogicalKeyboardKey.keyF,
                                meta: true,
                              ): _toggleTerminalSearch,
                            },
                            child: TerminalView(
                              _terminal,
                              key: const Key('remote-interactive-terminal'),
                              controller: _activeTab?.controller,
                              autofocus: true,
                              padding: const EdgeInsets.all(4),
                              shortcuts:
                                  Map<ShortcutActivator, Intent>.of(
                                    defaultTerminalShortcuts,
                                  )..removeWhere(
                                    (_, Intent intent) =>
                                        intent is PasteTextIntent,
                                  ),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: _outputScroll,
                            child: SelectableText(
                              _output.isEmpty ? '会话输出会显示在这里。' : _output,
                              style: const TextStyle(
                                fontFamily: 'Cascadia Mono',
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                  ),
          ),
          if (_sftpClient == null &&
              _mode != RemoteSessionMode.localForward &&
              _mode != RemoteSessionMode.remoteDesktop &&
              !_interactive) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote-command'),
              controller: _command,
              enabled: _running,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 13),
              decoration: InputDecoration(
                hintText: _mode == RemoteSessionMode.sftp
                    ? 'SFTP 命令，例如：ls'
                    : '远程命令或主机指纹确认 yes',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: '发送',
                  onPressed: _running ? _send : null,
                  icon: const Icon(Icons.send_outlined, size: 18),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortForwardItem {
  _PortForwardItem(this.handle);

  final PortForwardHandle handle;
  bool stopped = false;
}

class _RemoteDesktopPanel extends StatelessWidget {
  const _RemoteDesktopPanel({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('remote-desktop-panel'),
    decoration: BoxDecoration(
      color: context.vibe.canvas,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.vibe.border),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.desktop_windows_outlined,
            size: 42,
            color: context.vibe.glow,
          ),
          const SizedBox(height: 10),
          Text(
            status ?? '输入主机和端口，然后打开系统远程桌面。',
            key: const Key('remote-desktop-status'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Vibekits 不读取或传递远程桌面密码。',
            style: TextStyle(fontSize: 11, color: context.vibe.muted),
          ),
        ],
      ),
    ),
  );
}

class _PortForwardList extends StatelessWidget {
  const _PortForwardList({
    required this.items,
    required this.connected,
    required this.onStop,
  });

  final List<_PortForwardItem> items;
  final bool connected;
  final Future<void> Function(_PortForwardItem item) onStop;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('remote-forward-list'),
    decoration: BoxDecoration(
      color: context.vibe.canvas,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.vibe.border),
    ),
    child: items.isEmpty
        ? Center(
            child: Text(
              connected ? '连接已就绪，添加第一条转发。' : '填写规则后启动转发。',
              style: TextStyle(color: context.vibe.muted),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final _PortForwardItem item = items[index];
              final bool running = !item.stopped && item.handle.running;
              return ListTile(
                key: Key('remote-forward-item-$index'),
                dense: true,
                leading: Icon(
                  running ? Icons.swap_horiz_rounded : Icons.stop_rounded,
                  color: running ? context.vibe.success : context.vibe.muted,
                ),
                title: Text(item.handle.spec.description),
                subtitle: Text(running ? '运行中' : '已停止'),
                trailing: running
                    ? TextButton(
                        key: Key('remote-forward-stop-$index'),
                        onPressed: () => onStop(item),
                        child: const Text('停止'),
                      )
                    : null,
              );
            },
          ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.width,
    required this.controller,
    required this.label,
    required this.keyName,
    this.hint,
    this.enabled = true,
  });

  final double width;
  final TextEditingController controller;
  final String label;
  final String keyName;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        key: Key(keyName),
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _RemoteTerminalTab {
  _RemoteTerminalTab({
    required this.id,
    required this.title,
    required this.session,
    required this.terminal,
    required this.output,
  });

  final String id;
  final String title;
  final RemoteSessionHandle session;
  final Terminal terminal;
  final TerminalController controller = TerminalController();
  late StreamSubscription<String> outputSubscription;
  String output;
}

class _RemoteBadge extends StatelessWidget {
  const _RemoteBadge({required this.text, required this.color});

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
