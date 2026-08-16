import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/serial_port_service.dart';

typedef SerialPortLister = Future<List<SerialPortDescriptor>> Function();
typedef SerialPortOpener = Future<SerialPortSession> Function(
  SerialConnectionSettings settings,
);
typedef SerialLogSaver = Future<void> Function(
  String path,
  List<Map<String, Object?>> entries,
  SerialDataMode displayMode,
);

class SerialPortWorkspace extends StatefulWidget {
  const SerialPortWorkspace({
    super.key,
    this.initialSettings,
    this.onSettingsChanged,
    this.listPorts,
    this.openSession,
    this.saveLog,
  });

  final String? initialSettings;
  final Future<void> Function(String encodedSettings)? onSettingsChanged;
  final SerialPortLister? listPorts;
  final SerialPortOpener? openSession;
  final SerialLogSaver? saveLog;

  @override
  State<SerialPortWorkspace> createState() => _SerialPortWorkspaceState();
}

class _SerialPortWorkspaceState extends State<SerialPortWorkspace> {
  static const int _maxLogEntries = 2000;
  static const int _maxLogBytes = 2 * 1024 * 1024;

  late final SerialConnectionSettings? _restored =
      SerialConnectionSettings.decode(widget.initialSettings);
  late final TextEditingController _portController = TextEditingController(
    text: _restored?.portName ?? '',
  );
  late final TextEditingController _baudController = TextEditingController(
    text: '${_restored?.baudRate ?? 115200}',
  );
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _logScroll = ScrollController();
  late int _dataBits = _restored?.dataBits ?? 8;
  late int _stopBits = _restored?.stopBits ?? 1;
  late SerialParity _parity = _restored?.parity ?? SerialParity.none;
  late SerialFlowControl _flowControl =
      _restored?.flowControl ?? SerialFlowControl.none;
  SerialDataMode _sendMode = SerialDataMode.text;
  SerialDataMode _displayMode = SerialDataMode.text;
  SerialLineEnding _lineEnding = SerialLineEnding.crlf;
  List<SerialPortDescriptor> _ports = const <SerialPortDescriptor>[];
  final List<_SerialLogEntry> _logs = <_SerialLogEntry>[];
  final List<int> _pendingReceived = <int>[];
  final List<String> _sendHistory = <String>[];
  SerialPortSession? _session;
  StreamSubscription<SerialPortEvent>? _eventSubscription;
  Timer? _receiveFlushTimer;
  String? _error;
  String _status = '未连接';
  bool _refreshing = false;
  bool _opening = false;
  bool _advanced = false;
  bool _timestamps = true;
  bool _autoScroll = true;
  int _loggedBytes = 0;

  bool get _connected => _session?.isOpen == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPorts());
  }

  @override
  void dispose() {
    _receiveFlushTimer?.cancel();
    _eventSubscription?.cancel();
    final SerialPortSession? session = _session;
    if (session != null) unawaited(session.close());
    _portController.dispose();
    _baudController.dispose();
    _sendController.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _refreshPorts() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final List<SerialPortDescriptor> ports = await (widget.listPorts != null
          ? widget.listPorts!()
          : SerialPortService.listPorts());
      if (!mounted) return;
      setState(() {
        _ports = ports;
        _refreshing = false;
        if (_portController.text.trim().isEmpty && ports.isNotEmpty) {
          _portController.text = ports.first.name;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = '刷新串口失败：$error。仍可手动输入端口名称。';
      });
    }
  }

  SerialConnectionSettings _settings() {
    final int? baudRate = int.tryParse(_baudController.text.trim());
    if (baudRate == null) throw const FormatException('请输入有效波特率');
    final SerialConnectionSettings settings = SerialConnectionSettings(
      portName: _portController.text.trim(),
      baudRate: baudRate,
      dataBits: _dataBits,
      parity: _parity,
      stopBits: _stopBits,
      flowControl: _flowControl,
    );
    settings.validate();
    return settings;
  }

  Future<void> _open() async {
    if (_opening || _connected) return;
    late final SerialConnectionSettings settings;
    try {
      settings = _settings();
    } catch (error) {
      setState(() => _error = _message(error));
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
      _status = '正在打开 ${settings.portName}…';
    });
    try {
      final SerialPortSession session = await (widget.openSession != null
          ? widget.openSession!(settings)
          : SerialPortService.open(settings));
      if (!mounted) {
        await session.close();
        return;
      }
      _session = session;
      _eventSubscription = session.events.listen(_handleEvent);
      await widget.onSettingsChanged?.call(settings.encode());
      setState(() {
        _opening = false;
        _status = '${settings.portName} · ${settings.summary}';
      });
      _appendSystem('已打开 ${settings.portName} · ${settings.summary}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _status = '打开失败';
        _error = '${_message(error)}。请确认端口未被其他程序占用。';
      });
    }
  }

  void _close() {
    final SerialPortSession? session = _session;
    if (session == null) return;
    _flushReceived();
    final StreamSubscription<SerialPortEvent>? subscription =
        _eventSubscription;
    _eventSubscription = null;
    setState(() {
      _session = null;
      _opening = false;
      _status = '未连接';
    });
    _appendSystem('串口已关闭');
    unawaited(_shutdownSession(session, subscription));
  }

  Future<void> _shutdownSession(
    SerialPortSession session,
    StreamSubscription<SerialPortEvent>? subscription,
  ) async {
    try {
      await session.close();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      await subscription?.cancel();
    }
  }

  void _handleEvent(SerialPortEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case SerialPortEventType.received:
        _pendingReceived.addAll(event.bytes ?? const <int>[]);
        _receiveFlushTimer ??= Timer(
          const Duration(milliseconds: 100),
          _flushReceived,
        );
      case SerialPortEventType.sent:
        _appendLog(
          _SerialLogEntry(
            direction: _SerialDirection.tx,
            timestamp: DateTime.now(),
            bytes: event.bytes ?? Uint8List(0),
          ),
        );
      case SerialPortEventType.error:
        _flushReceived();
        setState(() {
          _error = event.message ?? '串口读写失败';
          _status = '连接异常';
        });
        _appendSystem(event.message ?? '串口读写失败');
      case SerialPortEventType.closed:
        _flushReceived();
        setState(() {
          _session = null;
          _opening = false;
          _status = '串口已断开';
        });
    }
  }

  void _flushReceived() {
    _receiveFlushTimer?.cancel();
    _receiveFlushTimer = null;
    if (_pendingReceived.isEmpty || !mounted) return;
    final Uint8List bytes = Uint8List.fromList(_pendingReceived);
    _pendingReceived.clear();
    _appendLog(
      _SerialLogEntry(
        direction: _SerialDirection.rx,
        timestamp: DateTime.now(),
        bytes: bytes,
      ),
    );
  }

  void _appendSystem(String message) {
    if (!mounted) return;
    _appendLog(
      _SerialLogEntry(
        direction: _SerialDirection.system,
        timestamp: DateTime.now(),
        message: message,
      ),
    );
  }

  void _appendLog(_SerialLogEntry entry) {
    setState(() {
      _logs.add(entry);
      _loggedBytes += entry.bytes?.length ?? 0;
      while (_logs.length > _maxLogEntries || _loggedBytes > _maxLogBytes) {
        final _SerialLogEntry removed = _logs.removeAt(0);
        _loggedBytes -= removed.bytes?.length ?? 0;
      }
    });
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.animateTo(
            _logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _send() async {
    final SerialPortSession? session = _session;
    if (session == null || !session.isOpen) {
      setState(() => _error = '请先打开串口');
      return;
    }
    final String source = _sendController.text;
    try {
      final Uint8List bytes = SerialCodec.encode(
        source,
        _sendMode,
        lineEnding: _sendMode == SerialDataMode.text
            ? _lineEnding
            : SerialLineEnding.none,
      );
      if (bytes.isEmpty) throw const FormatException('请输入发送内容');
      setState(() => _error = null);
      await session.send(bytes);
      final String historyValue = source.trim();
      if (historyValue.isNotEmpty) {
        _sendHistory.remove(historyValue);
        _sendHistory.insert(0, historyValue);
        if (_sendHistory.length > 20) _sendHistory.removeLast();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  void _clearLogs() {
    _receiveFlushTimer?.cancel();
    _receiveFlushTimer = null;
    _pendingReceived.clear();
    setState(() {
      _logs.clear();
      _loggedBytes = 0;
    });
  }

  Future<void> _saveLogs() async {
    _flushReceived();
    if (_logs.isEmpty) {
      setState(() => _error = '当前没有可保存的串口日志');
      return;
    }
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName:
          'vibekits-serial-${DateTime.now().millisecondsSinceEpoch}.log',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: '日志文件', extensions: <String>['log', 'txt']),
      ],
    );
    if (location == null) return;
    final List<Map<String, Object?>> entries = _logs
        .map((_SerialLogEntry entry) => entry.toMap())
        .toList(growable: false);
    try {
      await (widget.saveLog ?? _saveSerialLog)(
        location.path,
        entries,
        _displayMode,
      );
      if (mounted) _appendSystem('日志已保存到 ${location.path}');
    } catch (error) {
      if (mounted) setState(() => _error = '保存日志失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool controlsEnabled = !_connected && !_opening;
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
              const Icon(Icons.usb_outlined, size: 21),
              const Text(
                '串口调试',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              _StatusBadge(connected: _connected, text: _status),
              Text(
                '读取与写入均在独立工作线程',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ],
          ),
        ),
        _buildConnectionBar(controlsEnabled),
        if (_opening || _refreshing)
          const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Container(
            key: const Key('serial-error'),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
        const SizedBox(height: 8),
        Expanded(child: _buildLogArea()),
        _buildSendArea(),
      ],
    );
  }

  Widget _buildConnectionBar(bool controlsEnabled) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.vibe.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.vibe.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 250,
                child: TextField(
                  key: const Key('serial-port-name'),
                  controller: _portController,
                  enabled: controlsEnabled,
                  decoration: InputDecoration(
                    labelText: '串口',
                    hintText: Platform.isWindows ? 'COM3' : '/dev/cu.usbserial',
                    isDense: true,
                    suffixIcon: _ports.isEmpty
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: '选择检测到的串口',
                            onSelected: (String value) =>
                                _portController.text = value,
                            itemBuilder: (BuildContext context) => _ports
                                .map(
                                  (SerialPortDescriptor port) =>
                                      PopupMenuItem<String>(
                                        value: port.name,
                                        child: Text(port.label),
                                      ),
                                )
                                .toList(growable: false),
                            icon: const Icon(Icons.arrow_drop_down),
                          ),
                  ),
                ),
              ),
              IconButton.outlined(
                key: const Key('serial-refresh'),
                tooltip: '刷新串口',
                onPressed: controlsEnabled ? _refreshPorts : null,
                icon: const Icon(Icons.refresh, size: 18),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  key: const Key('serial-baud-rate'),
                  controller: _baudController,
                  enabled: controlsEnabled,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '波特率',
                    isDense: true,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('serial-advanced-toggle'),
                onPressed: controlsEnabled
                    ? () => setState(() => _advanced = !_advanced)
                    : null,
                icon: Icon(
                  _advanced ? Icons.expand_less : Icons.tune,
                  size: 17,
                ),
                label: Text(
                  _advanced
                      ? '收起参数'
                      : '$_dataBits-${_parityCode(_parity)}-$_stopBits',
                ),
              ),
              FilledButton.icon(
                key: const Key('serial-open'),
                onPressed: controlsEnabled ? _open : null,
                icon: const Icon(Icons.power_settings_new, size: 17),
                label: const Text('打开串口'),
              ),
              if (_connected)
                OutlinedButton.icon(
                  key: const Key('serial-close'),
                  onPressed: _opening ? null : _close,
                  icon: const Icon(Icons.stop_circle_outlined, size: 17),
                  label: const Text('关闭'),
                ),
            ],
          ),
          if (_advanced) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                _SettingDropdown<int>(
                  label: '数据位',
                  value: _dataBits,
                  values: const <int>[5, 6, 7, 8],
                  text: (int value) => '$value',
                  onChanged: (int value) => setState(() => _dataBits = value),
                ),
                _SettingDropdown<SerialParity>(
                  label: '校验位',
                  value: _parity,
                  values: SerialParity.values,
                  text: (SerialParity value) => value.label,
                  onChanged: (SerialParity value) =>
                      setState(() => _parity = value),
                ),
                _SettingDropdown<int>(
                  label: '停止位',
                  value: _stopBits,
                  values: const <int>[1, 2],
                  text: (int value) => '$value',
                  onChanged: (int value) => setState(() => _stopBits = value),
                ),
                _SettingDropdown<SerialFlowControl>(
                  label: '流控',
                  value: _flowControl,
                  values: SerialFlowControl.values,
                  text: (SerialFlowControl value) => value.label,
                  onChanged: (SerialFlowControl value) =>
                      setState(() => _flowControl = value),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.vibe.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.vibe.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SegmentedButton<SerialDataMode>(
                  key: const Key('serial-display-mode'),
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<SerialDataMode>>[
                    ButtonSegment<SerialDataMode>(
                      value: SerialDataMode.text,
                      label: Text('文本'),
                    ),
                    ButtonSegment<SerialDataMode>(
                      value: SerialDataMode.hex,
                      label: Text('HEX'),
                    ),
                  ],
                  selected: <SerialDataMode>{_displayMode},
                  onSelectionChanged: (Set<SerialDataMode> values) =>
                      setState(() => _displayMode = values.first),
                ),
                FilterChip(
                  label: const Text('时间戳'),
                  selected: _timestamps,
                  onSelected: (bool value) =>
                      setState(() => _timestamps = value),
                ),
                FilterChip(
                  label: const Text('自动滚动'),
                  selected: _autoScroll,
                  onSelected: (bool value) =>
                      setState(() => _autoScroll = value),
                ),
                Text(
                  '${_logs.length} 条 · ${_formatBytes(_loggedBytes)}',
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
                IconButton(
                  tooltip: '保存日志',
                  onPressed: _logs.isEmpty ? null : _saveLogs,
                  icon: const Icon(Icons.save_alt_outlined, size: 18),
                ),
                IconButton(
                  key: const Key('serial-clear-log'),
                  tooltip: '清空日志',
                  onPressed: _logs.isEmpty ? null : _clearLogs,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      _connected ? '等待接收数据…' : '打开串口后在此查看收发数据',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : ListView.builder(
                    key: const Key('serial-log-list'),
                    controller: _logScroll,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _logs.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _buildLogRow(_logs[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogRow(_SerialLogEntry entry) {
    final Color color = switch (entry.direction) {
      _SerialDirection.rx => context.vibe.success,
      _SerialDirection.tx => VibekitsColors.info,
      _SerialDirection.system => context.vibe.muted,
    };
    final String direction = switch (entry.direction) {
      _SerialDirection.rx => 'RX',
      _SerialDirection.tx => 'TX',
      _SerialDirection.system => 'SYS',
    };
    final String value =
        entry.message ??
        SerialCodec.decode(entry.bytes ?? Uint8List(0), _displayMode);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_timestamps) ...<Widget>[
            Text(
              _time(entry.timestamp),
              style: TextStyle(
                fontFamily: 'Cascadia Mono',
                fontSize: 11,
                color: context.vibe.muted,
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 28,
            child: Text(
              direction,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? ' ' : value,
              style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          SegmentedButton<SerialDataMode>(
            key: const Key('serial-send-mode'),
            showSelectedIcon: false,
            segments: const <ButtonSegment<SerialDataMode>>[
              ButtonSegment<SerialDataMode>(
                value: SerialDataMode.text,
                label: Text('文本'),
              ),
              ButtonSegment<SerialDataMode>(
                value: SerialDataMode.hex,
                label: Text('HEX'),
              ),
            ],
            selected: <SerialDataMode>{_sendMode},
            onSelectionChanged: (Set<SerialDataMode> values) =>
                setState(() => _sendMode = values.first),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _send,
              },
              child: TextField(
                key: const Key('serial-send-input'),
                controller: _sendController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: _sendMode == SerialDataMode.text
                      ? '输入内容，Ctrl+Enter 发送'
                      : '01 A0 FF',
                  isDense: true,
                  suffixIcon: _sendHistory.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: '发送历史',
                          onSelected: (String value) =>
                              _sendController.text = value,
                          itemBuilder: (BuildContext context) => _sendHistory
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
                          icon: const Icon(Icons.history),
                        ),
                ),
              ),
            ),
          ),
          if (_sendMode == SerialDataMode.text) ...<Widget>[
            const SizedBox(width: 8),
            DropdownButton<SerialLineEnding>(
              value: _lineEnding,
              items: SerialLineEnding.values
                  .map(
                    (SerialLineEnding value) =>
                        DropdownMenuItem<SerialLineEnding>(
                          value: value,
                          child: Text(value.label),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (SerialLineEnding? value) {
                if (value != null) setState(() => _lineEnding = value);
              },
            ),
          ],
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('serial-send'),
            onPressed: _connected ? _send : null,
            icon: const Icon(Icons.send, size: 17),
            label: const Text('发送'),
          ),
        ],
      ),
    );
  }
}

enum _SerialDirection { rx, tx, system }

class _SerialLogEntry {
  const _SerialLogEntry({
    required this.direction,
    required this.timestamp,
    this.bytes,
    this.message,
  });

  final _SerialDirection direction;
  final DateTime timestamp;
  final Uint8List? bytes;
  final String? message;

  Map<String, Object?> toMap() => <String, Object?>{
    'direction': direction.name,
    'timestamp': timestamp.toIso8601String(),
    'bytes': bytes,
    'message': message,
  };
}

class _SettingDropdown<T> extends StatelessWidget {
  const _SettingDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            items: values
                .map(
                  (T item) =>
                      DropdownMenuItem<T>(value: item, child: Text(text(item))),
                )
                .toList(growable: false),
            onChanged: (T? item) {
              if (item != null) onChanged(item);
            },
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.connected, required this.text});

  final bool connected;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color color = connected ? context.vibe.success : context.vibe.muted;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

Future<void> _saveSerialLog(
  String path,
  List<Map<String, Object?>> entries,
  SerialDataMode displayMode,
) => Isolate.run(() {
  final StringBuffer buffer = StringBuffer();
  for (final Map<String, Object?> entry in entries) {
    final String timestamp = '${entry['timestamp']}';
    final String direction = '${entry['direction']}'.toUpperCase();
    final Object? message = entry['message'];
    final Uint8List bytes = entry['bytes'] is Uint8List
        ? entry['bytes']! as Uint8List
        : Uint8List(0);
    final String value = message == null
        ? SerialCodec.decode(bytes, displayMode)
        : '$message';
    buffer.writeln('$timestamp [$direction] $value');
  }
  File(path).writeAsStringSync(buffer.toString(), flush: true);
});

String _parityCode(SerialParity parity) => switch (parity) {
  SerialParity.none => 'N',
  SerialParity.even => 'E',
  SerialParity.odd => 'O',
  SerialParity.mark => 'M',
  SerialParity.space => 'S',
};

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}.'
    '${value.millisecond.toString().padLeft(3, '0')}';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

String _message(Object error) {
  if (error is FormatException) return error.message;
  if (error is TimeoutException) return error.message ?? '操作超时';
  return '$error';
}
