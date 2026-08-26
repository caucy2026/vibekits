import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/adb_service.dart';
import '../domain/harness_tool_activity_store.dart';

typedef AdbWorkspaceLoader = Future<AdbSnapshot> Function();
typedef AdbWirelessConnector = Future<String> Function(
  String executable,
  String address,
);

class AdbWorkspace extends StatefulWidget {
  const AdbWorkspace({
    super.key,
    this.loadSnapshot,
    this.connectDevice,
    this.runCommand,
    this.initialRecentAddresses = const <String>[],
    this.initialCommandHistory = const <String>[],
    this.onRecentAddressesChanged,
    this.onCommandHistoryChanged,
    this.loadHarnessActivity = HarnessToolActivityStore.load,
    this.deleteHarnessActivity = HarnessToolActivityStore.delete,
    this.clearHarnessActivity = HarnessToolActivityStore.clear,
  });

  final AdbWorkspaceLoader? loadSnapshot;
  final AdbWirelessConnector? connectDevice;
  final AdbCommandRunner? runCommand;
  final List<String> initialRecentAddresses;
  final List<String> initialCommandHistory;
  final Future<void> Function(List<String> history)? onRecentAddressesChanged;
  final Future<void> Function(List<String> history)? onCommandHistoryChanged;
  final HarnessToolActivityLoader loadHarnessActivity;
  final HarnessToolActivityDeleter deleteHarnessActivity;
  final HarnessToolActivityClearer clearHarnessActivity;

  @override
  State<AdbWorkspace> createState() => _AdbWorkspaceState();
}

class _AdbWorkspaceState extends State<AdbWorkspace> {
  static const Set<String> _adbToolIds = <String>{
    'vibekits.adb.list_devices',
    'vibekits.adb.connect',
    'vibekits.adb.command',
    'vibekits.adb.shell',
    'vibekits.adb.logcat',
    'vibekits.adb.install_apk',
    'vibekits.adb.push_file',
    'vibekits.adb.pull_file',
    'vibekits.adb.screenshot',
  };
  final TextEditingController _wirelessAddress = TextEditingController();
  final TextEditingController _command = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  final ScrollController _consoleScroll = ScrollController();
  final List<_AdbConsoleEntry> _console = <_AdbConsoleEntry>[];
  AdbSnapshot? _snapshot;
  String? _selectedSerial;
  String? _error;
  bool _loading = false;
  bool _connecting = false;
  bool _executing = false;
  String? _connectionMessage;
  int _generation = 0;
  late final List<String> _recentAddresses = widget.initialRecentAddresses
      .take(20)
      .toList();
  late final List<String> _commandHistory = widget.initialCommandHistory
      .take(50)
      .toList();

  Future<void> _rememberAddress(String address) async {
    final String value = AdbService.normalizeWirelessAddress(address);
    _recentAddresses.remove(value);
    _recentAddresses.insert(0, value);
    if (_recentAddresses.length > 20) _recentAddresses.removeLast();
    try {
      await widget.onRecentAddressesChanged?.call(
        List<String>.unmodifiable(_recentAddresses),
      );
    } catch (_) {
      // History is a convenience layer. A storage failure must never turn a
      // successful device connection into a failed connection.
    }
  }

  Future<void> _rememberCommand(String command) async {
    final String value = command.trim();
    if (value.isEmpty) return;
    _commandHistory.remove(value);
    _commandHistory.insert(0, value);
    if (_commandHistory.length > 50) _commandHistory.removeLast();
    try {
      await widget.onCommandHistoryChanged?.call(
        List<String>.unmodifiable(_commandHistory),
      );
    } catch (_) {
      // Executing the command is more important than persisting its history.
    }
  }

  AdbDevice? get _selected => _snapshot?.devices
      .where((AdbDevice device) => device.serial == _selectedSerial)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final int generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AdbSnapshot snapshot =
          await (widget.loadSnapshot?.call() ?? AdbService.discoverAndList());
      if (!mounted || generation != _generation) return;
      final bool selectionExists = snapshot.devices.any(
        (AdbDevice device) => device.serial == _selectedSerial,
      );
      setState(() {
        _snapshot = snapshot;
        _selectedSerial = selectionExists
            ? _selectedSerial
            : snapshot.devices
                  .where((AdbDevice device) => device.ready)
                  .firstOrNull
                  ?.serial;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _connect() async {
    final AdbInstallation? installation = _snapshot?.installation;
    if (installation == null || _connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
      _connectionMessage = null;
    });
    try {
      final String message =
          await (widget.connectDevice?.call(
                installation.executable,
                _wirelessAddress.text,
              ) ??
              AdbService.connect(
                installation.executable,
                _wirelessAddress.text,
              ));
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectionMessage = message;
      });
      unawaited(_rememberAddress(_wirelessAddress.text));
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _executeCommand() async {
    final AdbInstallation? installation = _snapshot?.installation;
    final AdbDevice? device = _selected;
    if (installation == null || device == null || !device.ready || _executing) {
      return;
    }
    List<String> command;
    try {
      command = AdbService.parseUserCommand(_command.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final List<String> arguments = <String>['-s', device.serial, ...command];
    final String display = command.join(' ');
    unawaited(_rememberCommand(display));
    final Stopwatch elapsed = Stopwatch()..start();
    setState(() {
      _executing = true;
      _error = null;
    });
    try {
      final AdbCommandResult result = widget.runCommand == null
          ? await AdbService.runCommand(
              installation.executable,
              arguments,
              audit: AdbCommandAudit(
                toolId: 'vibekits.adb.command',
                toolName: '手动执行 ADB 命令',
                target: device.serial,
              ),
            )
          : await widget.runCommand!(installation.executable, arguments);
      elapsed.stop();
      if (!mounted) return;
      setState(() {
        _executing = false;
        _console.insert(
          0,
          _AdbConsoleEntry(
            command: display,
            result: result,
            elapsed: elapsed.elapsed,
            time: DateTime.now(),
          ),
        );
        if (_console.length > 100) _console.removeRange(100, _console.length);
        if (result.exitCode == 0) _command.clear();
      });
      _commandFocus.requestFocus();
    } on Object catch (caught) {
      elapsed.stop();
      if (!mounted) return;
      setState(() {
        _executing = false;
        _console.insert(
          0,
          _AdbConsoleEntry.error(
            command: display,
            error: caught.toString().replaceFirst('Bad state: ', ''),
            elapsed: elapsed.elapsed,
            time: DateTime.now(),
          ),
        );
      });
      _commandFocus.requestFocus();
    }
  }

  Future<void> _showHarnessActivity() async {
    List<HarnessToolActivity> entries = <HarnessToolActivity>[];
    bool loading = true;
    bool loadScheduled = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setDialogState,
            ) {
              Future<void> reload() async {
                setDialogState(() {
                  loading = true;
                  error = null;
                });
                try {
                  final List<HarnessToolActivity> loaded = await widget
                      .loadHarnessActivity(_adbToolIds);
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    entries = loaded;
                    loading = false;
                  });
                } on Object catch (caught) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    loading = false;
                    error = '$caught';
                  });
                }
              }

              if (loading &&
                  !loadScheduled &&
                  entries.isEmpty &&
                  error == null) {
                loadScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) => reload());
              }
              return AlertDialog(
                title: const Text(
                  'Harness 调用记录',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                content: SizedBox(
                  width: 720,
                  height: 430,
                  child: loading && entries.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                      ? Center(child: Text('读取失败：$error'))
                      : entries.isEmpty
                      ? const Center(child: Text('暂无 Harness ADB 调用'))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (BuildContext context, int index) {
                            final HarnessToolActivity entry = entries[index];
                            return ListTile(
                              key: Key('adb-harness-activity-${entry.id}'),
                              dense: true,
                              visualDensity: const VisualDensity(
                                horizontal: -3,
                                vertical: -3,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              leading: Icon(
                                _activityIcon(entry.status),
                                color: _activityColor(context, entry.status),
                                size: 19,
                              ),
                              title: Text(
                                '${entry.toolName} · ${_activityLabel(entry.status)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _activityDetails(entry),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.25,
                                  color: context.vibe.muted,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                              trailing: IconButton(
                                key: Key('adb-harness-delete-${entry.id}'),
                                tooltip: '删除这条记录',
                                onPressed: () async {
                                  await widget.deleteHarnessActivity(entry.id);
                                  if (dialogContext.mounted) await reload();
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 17,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                actions: <Widget>[
                  TextButton.icon(
                    onPressed: loading ? null : reload,
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('刷新'),
                  ),
                  TextButton.icon(
                    key: const Key('adb-harness-clear'),
                    onPressed: entries.isEmpty
                        ? null
                        : () async {
                            await widget.clearHarnessActivity(_adbToolIds);
                            if (dialogContext.mounted) await reload();
                          },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                    label: const Text('清空'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('完成'),
                  ),
                ],
              );
            },
      ),
    );
  }

  Widget _buildDeviceWorkbench(AdbDevice device) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DeviceSummary(device: device),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Icon(Icons.terminal_rounded, size: 17),
            const SizedBox(width: 6),
            const Text(
              'ADB 命令',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _console.isEmpty
                  ? null
                  : () => setState(_console.clear),
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('清空输出'),
            ),
          ],
        ),
        Expanded(
          child: Container(
            key: const Key('adb-command-output'),
            decoration: BoxDecoration(
              color: context.vibe.panelRaised,
              border: Border.all(color: context.vibe.border),
              borderRadius: BorderRadius.circular(7),
            ),
            child: _console.isEmpty
                ? Center(
                    child: Text(
                      '输入 getprop ro.product.model 开始调试',
                      style: TextStyle(color: context.vibe.muted, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    controller: _consoleScroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: _console.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (BuildContext context, int index) =>
                        _AdbConsoleTile(
                          entry: _console[index],
                          serial: device.serial,
                        ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('adb-command-input'),
                controller: _command,
                focusNode: _commandFocus,
                enabled: device.ready && !_executing,
                onSubmitted: (_) => _executeCommand(),
                textInputAction: TextInputAction.send,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: '命令',
                  hintText: 'getprop ro.product.model',
                  helperText: '固定设备 ${device.serial} · 普通命令自动使用 shell',
                  isDense: true,
                  prefixText: 'adb > ',
                  suffixIcon: _commandHistory.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: '常用命令',
                          onSelected: (String value) => _command.text = value,
                          itemBuilder: (BuildContext context) => _commandHistory
                              .map(
                                (String value) => PopupMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          icon: const Icon(Icons.history_rounded),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 42,
              child: FilledButton.icon(
                key: const Key('adb-command-run'),
                onPressed: device.ready && !_executing ? _executeCommand : null,
                icon: _executing
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(_executing ? '执行中' : '执行'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _generation += 1;
    _wirelessAddress.dispose();
    _command.dispose();
    _commandFocus.dispose();
    _consoleScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdbInstallation? installation = _snapshot?.installation;
    final List<AdbDevice> devices = _snapshot?.devices ?? const <AdbDevice>[];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.android_rounded, size: 22),
              const SizedBox(width: 8),
              const Text(
                'ADB 设备',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              OutlinedButton.icon(
                key: const Key('adb-harness-activity'),
                onPressed: _showHarnessActivity,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('Harness 记录'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('adb-refresh'),
                onPressed: _loading ? null : _refresh,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_loading ? '刷新中' : '刷新设备'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.vibe.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.vibe.border),
            ),
            child: installation == null
                ? Text(
                    _loading ? '正在查找 Android SDK Platform-Tools…' : '尚未识别 ADB',
                    style: TextStyle(color: context.vibe.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('ADB ${installation.version}'),
                      const SizedBox(height: 3),
                      SelectableText(
                        installation.executable,
                        key: const Key('adb-executable-path'),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.vibe.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('adb-error'),
              style: const TextStyle(color: VibekitsColors.danger),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('adb-wireless-address'),
                  controller: _wirelessAddress,
                  enabled: installation != null && !_connecting,
                  onSubmitted: (_) => _connect(),
                  decoration: InputDecoration(
                    labelText: '无线设备',
                    hintText: '192.168.3.63（默认端口 5555）',
                    prefixIcon: const Icon(Icons.wifi_rounded, size: 19),
                    isDense: true,
                    suffixIcon: _recentAddresses.isEmpty
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: '最近设备',
                            onSelected: (String value) =>
                                _wirelessAddress.text = value,
                            itemBuilder: (BuildContext context) =>
                                _recentAddresses
                                    .map(
                                      (String value) => PopupMenuItem<String>(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(growable: false),
                            icon: const Icon(Icons.history_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('adb-connect'),
                onPressed: installation == null || _connecting
                    ? null
                    : _connect,
                icon: _connecting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded, size: 18),
                label: Text(_connecting ? '连接中' : '连接'),
              ),
            ],
          ),
          if (_connectionMessage != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              _connectionMessage!,
              key: const Key('adb-connect-result'),
              style: TextStyle(fontSize: 12, color: context.vibe.success),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 4,
                  child: Container(
                    key: const Key('adb-device-list'),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.vibe.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: devices.isEmpty
                        ? Center(
                            child: Text(
                              _loading ? '正在读取设备…' : '没有检测到设备',
                              style: TextStyle(color: context.vibe.muted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final AdbDevice device = devices[index];
                              return ListTile(
                                key: Key('adb-device-${device.serial}'),
                                selected: device.serial == _selectedSerial,
                                leading: Icon(
                                  Icons.phone_android_rounded,
                                  color: device.ready
                                      ? context.vibe.success
                                      : context.vibe.muted,
                                ),
                                title: Text(device.model ?? device.serial),
                                subtitle: Text(device.serial),
                                trailing: _StateBadge(state: device.state),
                                onTap: () => setState(
                                  () => _selectedSerial = device.serial,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Container(
                    key: const Key('adb-device-detail'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.vibe.canvas,
                      border: Border.all(color: context.vibe.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _selected == null
                        ? Center(
                            child: Text(
                              '选择一个设备',
                              style: TextStyle(color: context.vibe.muted),
                            ),
                          )
                        : _buildDeviceWorkbench(_selected!),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _activityIcon(HarnessToolActivityStatus status) => switch (status) {
  HarnessToolActivityStatus.succeeded => Icons.check_circle_outline,
  HarnessToolActivityStatus.failed => Icons.error_outline,
  HarnessToolActivityStatus.denied => Icons.block,
};

Color _activityColor(BuildContext context, HarnessToolActivityStatus status) =>
    switch (status) {
      HarnessToolActivityStatus.succeeded => context.vibe.success,
      HarnessToolActivityStatus.failed => VibekitsColors.danger,
      HarnessToolActivityStatus.denied => VibekitsColors.warning,
    };

String _activityLabel(HarnessToolActivityStatus status) => switch (status) {
  HarnessToolActivityStatus.succeeded => '成功',
  HarnessToolActivityStatus.failed => '失败',
  HarnessToolActivityStatus.denied => '已拒绝',
};

String _activityDetails(HarnessToolActivity entry) {
  final List<String> lines = <String>[
    '${_formatTime(entry.startedAt)} · ${entry.elapsedMs} ms',
    if (entry.target.isNotEmpty) '目标  ${entry.target}',
  ];
  try {
    final Object? decoded = jsonDecode(entry.argumentsSummary);
    if (decoded is Map && decoded['arguments'] is List) {
      lines.add(
        '命令  ${(decoded['arguments']! as List).map((Object? value) => '$value').join(' ')}',
      );
    } else {
      lines.add('参数  ${entry.argumentsSummary}');
    }
  } on Object {
    lines.add('参数  ${entry.argumentsSummary}');
  }
  try {
    final Object? decoded = jsonDecode(entry.resultSummary);
    if (decoded is Map) {
      final String exitCode = '${decoded['exitCode'] ?? decoded['code'] ?? ''}';
      final String stdout = '${decoded['stdout'] ?? ''}'
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();
      final String stderr = '${decoded['stderr'] ?? ''}'
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();
      if (exitCode.isNotEmpty) lines.add('退出  $exitCode');
      if (stdout.isNotEmpty) {
        lines.add('输出  ${_shorten(stdout, 260)}');
      }
      if (stderr.isNotEmpty) {
        lines.add('错误  ${_shorten(stderr, 180)}');
      }
    } else if (entry.resultSummary.isNotEmpty) {
      lines.add('结果  ${_shorten(entry.resultSummary, 260)}');
    }
  } on Object {
    if (entry.resultSummary.isNotEmpty) {
      lines.add('结果  ${_shorten(entry.resultSummary, 260)}');
    }
  }
  return lines.join('\n');
}

String _shorten(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max)}…';

String _formatTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';

class _AdbConsoleEntry {
  const _AdbConsoleEntry({
    required this.command,
    required this.result,
    required this.elapsed,
    required this.time,
  }) : error = null;

  const _AdbConsoleEntry.error({
    required this.command,
    required this.error,
    required this.elapsed,
    required this.time,
  }) : result = null;

  final String command;
  final AdbCommandResult? result;
  final String? error;
  final Duration elapsed;
  final DateTime time;

  bool get succeeded => result?.exitCode == 0 && error == null;

  String output(String serial) {
    final StringBuffer text = StringBuffer(r'$ adb -s ')
      ..write(serial)
      ..write(' ')
      ..writeln(command);
    if (result?.stdout.trim().isNotEmpty == true) {
      text.writeln(result!.stdout.trim());
    }
    if (result?.stderr.trim().isNotEmpty == true) {
      text.writeln(result!.stderr.trim());
    }
    if (error != null) text.writeln(error);
    return text.toString().trimRight();
  }
}

class _AdbConsoleTile extends StatelessWidget {
  const _AdbConsoleTile({required this.entry, required this.serial});

  final _AdbConsoleEntry entry;
  final String serial;

  @override
  Widget build(BuildContext context) {
    final String output = entry.output(serial);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              entry.succeeded
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 15,
              color: entry.succeeded
                  ? context.vibe.success
                  : VibekitsColors.danger,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '${_formatTime(entry.time)} · ${entry.elapsed.inMilliseconds} ms'
                '${entry.result == null ? '' : ' · exit ${entry.result!.exitCode}'}',
                style: TextStyle(fontSize: 10.5, color: context.vibe.muted),
              ),
            ),
            IconButton(
              tooltip: '复制命令和输出',
              visualDensity: VisualDensity.compact,
              onPressed: () => Clipboard.setData(ClipboardData(text: output)),
              icon: const Icon(Icons.copy_outlined, size: 15),
            ),
          ],
        ),
        SelectableText(
          output,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11.5,
            height: 1.35,
            color: entry.succeeded
                ? Theme.of(context).colorScheme.onSurface
                : VibekitsColors.danger,
          ),
        ),
      ],
    );
  }
}

class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        device.model ?? device.serial,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      SelectableText(device.serial),
      const SizedBox(height: 10),
      Text(
        device.ready
            ? '设备已授权，可以继续使用 Shell、文件、日志和截图。'
            : _stateHelp(device.state),
        style: TextStyle(
          color: device.ready ? context.vibe.success : context.vibe.muted,
        ),
      ),
    ],
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final AdbDeviceState state;

  @override
  Widget build(BuildContext context) => Text(
    _stateLabel(state),
    key: Key('adb-state-${state.name}'),
    style: TextStyle(
      fontSize: 11,
      color: state == AdbDeviceState.device
          ? context.vibe.success
          : state == AdbDeviceState.unauthorized
          ? VibekitsColors.warning
          : context.vibe.muted,
    ),
  );
}

String _stateLabel(AdbDeviceState state) => switch (state) {
  AdbDeviceState.device => '可用',
  AdbDeviceState.unauthorized => '未授权',
  AdbDeviceState.offline => '离线',
  AdbDeviceState.unknown => '未知',
};

String _stateHelp(AdbDeviceState state) => switch (state) {
  AdbDeviceState.device => '设备可用',
  AdbDeviceState.unauthorized => '请解锁设备并确认 USB 调试授权。',
  AdbDeviceState.offline => '设备离线；请重新连接 USB 或无线调试。',
  AdbDeviceState.unknown => '设备状态未知，请刷新或重启 ADB 服务。',
};
