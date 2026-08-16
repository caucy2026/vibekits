import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/remote_session.dart';

typedef RemoteSessionStarter = Future<RemoteSessionHandle> Function(
  RemoteLaunchRequest request,
);

class RemoteWorkspace extends StatefulWidget {
  const RemoteWorkspace({super.key, this.startSession});

  final RemoteSessionStarter? startSession;

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
  final ScrollController _outputScroll = ScrollController();
  RemoteSessionMode _mode = RemoteSessionMode.ssh;
  RemoteSessionHandle? _session;
  StreamSubscription<String>? _outputSubscription;
  String _output = '';
  String? _error;
  bool _starting = false;

  bool get _running => _session?.running == true;

  @override
  void dispose() {
    _outputSubscription?.cancel();
    final RemoteSessionHandle? session = _session;
    if (session != null) unawaited(session.stop());
    for (final TextEditingController controller in <TextEditingController>[
      _host,
      _user,
      _port,
      _identity,
      _localPort,
      _targetHost,
      _targetPort,
      _command,
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

  Future<void> _start() async {
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
      final RemoteSessionHandle session = await (widget.startSession != null
          ? widget.startSession!(request)
          : RemoteSessionService.start(request));
      if (!mounted) {
        await session.stop();
        return;
      }
      _session = session;
      _outputSubscription = session.output.listen(_appendOutput);
      setState(() {
        _starting = false;
        _output = _mode == RemoteSessionMode.localForward
            ? '正在建立本地转发…\n'
            : '正在连接；首次主机请核对指纹后输入 yes。\n';
      });
      unawaited(
        session.exitCode.then((int code) {
          if (!mounted || _session != session) return;
          _appendOutput('\n[会话已结束 · exit $code]\n');
          setState(() {});
        }),
      );
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

  void _appendOutput(String chunk) {
    if (!mounted) return;
    setState(() {
      _output = '$_output$chunk';
      if (_output.length > 200000) {
        _output = '[较早输出已截断]\n${_output.substring(_output.length - 180000)}';
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScroll.hasClients) {
        _outputScroll.jumpTo(_outputScroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final String line = _command.text;
    if (!_running || line.isEmpty) return;
    _session!.sendLine(line);
    _command.clear();
  }

  Future<void> _stop() async {
    final RemoteSessionHandle? session = _session;
    if (session == null) return;
    await session.stop();
    await _outputSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _session = null;
      _outputSubscription = null;
    });
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
              _RemoteBadge(text: '系统 OpenSSH', color: context.vibe.success),
              Text(
                '仅密钥 / ssh-agent · 不保存密码',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            ],
            selected: <RemoteSessionMode>{_mode},
            onSelectionChanged: _running || _starting
                ? null
                : (Set<RemoteSessionMode> value) =>
                      setState(() => _mode = value.first),
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
              ),
              _Field(
                width: 150,
                controller: _user,
                label: '用户名',
                hint: 'developer',
                keyName: 'remote-user',
              ),
              _Field(
                width: 90,
                controller: _port,
                label: '端口',
                keyName: 'remote-port',
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  key: const Key('remote-identity'),
                  controller: _identity,
                  enabled: !_running && !_starting,
                  decoration: InputDecoration(
                    labelText: '私钥（可选，默认 ssh-agent）',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '选择私钥',
                      onPressed: _running || _starting ? null : _pickIdentity,
                      icon: const Icon(Icons.key_outlined, size: 17),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_mode == RemoteSessionMode.localForward) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _Field(
                  width: 130,
                  controller: _localPort,
                  label: '本地端口',
                  keyName: 'remote-local-port',
                ),
                _Field(
                  width: 230,
                  controller: _targetHost,
                  label: '远端可访问的目标',
                  keyName: 'remote-target-host',
                ),
                _Field(
                  width: 130,
                  controller: _targetPort,
                  label: '目标端口',
                  keyName: 'remote-target-port',
                ),
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
                    ? null
                    : _running
                    ? _stop
                    : _start,
                icon: Icon(
                  _running ? Icons.stop_rounded : Icons.power_settings_new,
                  size: 18,
                ),
                label: Text(
                  _starting
                      ? '连接中…'
                      : _running
                      ? '断开'
                      : _mode == RemoteSessionMode.localForward
                      ? '启动转发'
                      : '连接',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _mode == RemoteSessionMode.sftp
                      ? '连接后输入 ls / cd / get / put；路径由 OpenSSH 解析。'
                      : _mode == RemoteSessionMode.localForward
                      ? '仅监听 127.0.0.1，停止会话即关闭转发。'
                      : '首次连接必须核对服务端主机指纹；不会自动跳过验证。',
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              key: const Key('remote-output'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.vibe.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.vibe.border),
              ),
              child: SingleChildScrollView(
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
          if (_mode != RemoteSessionMode.localForward) ...<Widget>[
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

class _Field extends StatelessWidget {
  const _Field({
    required this.width,
    required this.controller,
    required this.label,
    required this.keyName,
    this.hint,
  });

  final double width;
  final TextEditingController controller;
  final String label;
  final String keyName;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        key: Key(keyName),
        controller: controller,
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
