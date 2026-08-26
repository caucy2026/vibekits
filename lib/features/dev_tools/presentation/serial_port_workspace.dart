import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/serial_port_service.dart';
import 'harness_tool_activity_dialog.dart';

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
    this.initialSendHistory = const <String>[],
    this.onSettingsChanged,
    this.onSendHistoryChanged,
    this.listPorts,
    this.openSession,
    this.saveLog,
  });

  final String? initialSettings;
  final List<String> initialSendHistory;
  final Future<void> Function(String encodedSettings)? onSettingsChanged;
  final Future<void> Function(List<String> history)? onSendHistoryChanged;
  final SerialPortLister? listPorts;
  final SerialPortOpener? openSession;
  final SerialLogSaver? saveLog;

  @override
  State<SerialPortWorkspace> createState() => _SerialPortWorkspaceState();
}

class _SerialPortWorkspaceState extends State<SerialPortWorkspace> {
  static const int _maxLogEntries = 2000;
  static const int _maxLogBytes = 2 * 1024 * 1024;
  static const List<int> _commonBaudRates = <int>[
    300,
    600,
    1200,
    2400,
    4800,
    9600,
    14400,
    19200,
    28800,
    38400,
    57600,
    74880,
    115200,
    230400,
    250000,
    460800,
    500000,
    576000,
    921600,
    1000000,
    1500000,
    2000000,
    3000000,
    4000000,
  ];

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
  late final List<String> _sendHistory = widget.initialSendHistory
      .where((String value) => value.trim().isNotEmpty)
      .take(50)
      .toList();
  SerialPortSession? _session;
  StreamSubscription<SerialPortEvent>? _eventSubscription;
  Timer? _receiveFlushTimer;
  Timer? _hotplugTimer;
  String? _error;
  String _status = '未连接';
  bool _refreshing = false;
  bool _opening = false;
  bool _advanced = false;
  bool _timestamps = true;
  bool _autoScroll = true;
  bool _automaticPortApplied = false;
  bool _pollingHotplug = false;
  bool _reconnectAfterHotplug = false;
  String? _recommendedPortName;
  int _loggedBytes = 0;
  int _receivedBytes = 0;
  int _receivedChunks = 0;
  DateTime? _lastReceivedAt;

  bool get _connected => _session?.isOpen == true;

  List<SerialPortDescriptor> get _selectablePorts {
    final List<SerialPortDescriptor> result = _ports.toList();
    result.sort((SerialPortDescriptor a, SerialPortDescriptor b) {
      final int score = _portScore(b).compareTo(_portScore(a));
      if (score != 0) return score;
      int? number(String value) => int.tryParse(
        value.replaceFirst(RegExp(r'^COM', caseSensitive: false), ''),
      );
      final int? left = number(a.name);
      final int? right = number(b.name);
      if (left != null && right != null) return left.compareTo(right);
      return a.name.compareTo(b.name);
    });
    return result;
  }

  static int _portScore(SerialPortDescriptor port) {
    final String detail = '${port.description} ${port.transport}'.toLowerCase();
    int score = 0;
    if (port.vendorId != null || port.productId != null) score += 100;
    if (detail.contains('usb')) score += 80;
    if (detail.contains('ch340') || detail.contains('ch341')) score += 40;
    if (detail.contains('bluetooth') || detail.contains('bth')) score -= 200;
    return score;
  }

  static bool _requiresRtsCts(SerialPortDescriptor port) {
    final String detail = '${port.description} ${port.transport}'.toLowerCase();
    return detail.contains('ch340') ||
        detail.contains('ch341') ||
        (port.vendorId == 0x1a86 && port.productId == 0x7523);
  }

  static SerialPortDescriptor? _recommendedPort(
    List<SerialPortDescriptor> ports,
  ) {
    if (ports.isEmpty) return null;
    return ports.reduce(
      (SerialPortDescriptor best, SerialPortDescriptor candidate) =>
          _portScore(candidate) > _portScore(best) ? candidate : best,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPorts();
      if (widget.listPorts == null) {
        _hotplugTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_pollHotplug()),
        );
      }
    });
  }

  @override
  void dispose() {
    _receiveFlushTimer?.cancel();
    _hotplugTimer?.cancel();
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
    final bool firstDiscovery = !_automaticPortApplied;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final List<SerialPortDescriptor> ports = await (widget.listPorts != null
          ? widget.listPorts!()
          : SerialPortService.listPorts());
      if (!mounted) return;
      final SerialPortDescriptor? recommended = _recommendedPort(ports);
      final String current = _portController.text.trim();
      final SerialPortDescriptor? currentPort = ports
          .where(
            (SerialPortDescriptor port) =>
                port.name.toUpperCase() == current.toUpperCase(),
          )
          .firstOrNull;
      final bool shouldAutoOpen =
          firstDiscovery &&
          recommended != null &&
          _portScore(recommended) >= 100 &&
          !_connected &&
          !_opening;
      setState(() {
        _ports = ports;
        _refreshing = false;
        _recommendedPortName = recommended?.name;
        if (!_automaticPortApplied &&
            recommended != null &&
            (currentPort == null ||
                _portScore(recommended) > _portScore(currentPort))) {
          _portController.text = recommended.name;
        }
        if (recommended != null &&
            _requiresRtsCts(recommended) &&
            _flowControl == SerialFlowControl.none) {
          _flowControl = SerialFlowControl.rtsCts;
        }
        _automaticPortApplied = true;
      });
      if (shouldAutoOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _connected || _opening) return;
          setState(() => _status = '已识别 ${recommended.name}，正在自动打开…');
          unawaited(_open());
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = '刷新串口失败：$error。仍可手动输入端口名称。';
      });
    }
  }

  Future<void> _pollHotplug() async {
    if (_pollingHotplug || !mounted) return;
    _pollingHotplug = true;
    try {
      final List<SerialPortDescriptor> ports =
          await SerialPortService.listPorts();
      if (!mounted) return;
      final Set<String> names = ports
          .map((SerialPortDescriptor port) => port.name.toUpperCase())
          .toSet();
      final String selected = _portController.text.trim().toUpperCase();
      final bool present = selected.isNotEmpty && names.contains(selected);

      if (_connected && !present) {
        _reconnectAfterHotplug = true;
        _close(status: '设备已拔出，等待插回…', systemMessage: '设备已拔出');
        if (mounted) setState(() => _ports = ports);
        return;
      }

      if (!_connected && _reconnectAfterHotplug && present && !_opening) {
        setState(() {
          _ports = ports;
          _status = '检测到设备已插回，正在重新打开…';
        });
        await _open();
        if (_connected) {
          _reconnectAfterHotplug = false;
          _appendSystem('设备已插回并自动重新连接');
        }
        return;
      }

      if (!_setEqualsByName(_ports, ports)) {
        setState(() => _ports = ports);
      }
    } on Object {
      // A transient PnP query failure must not interrupt an active session.
    } finally {
      _pollingHotplug = false;
    }
  }

  static bool _setEqualsByName(
    List<SerialPortDescriptor> left,
    List<SerialPortDescriptor> right,
  ) {
    if (left.length != right.length) return false;
    final Set<String> names = left
        .map((SerialPortDescriptor value) => value.name.toUpperCase())
        .toSet();
    return right.every(
      (SerialPortDescriptor value) => names.contains(value.name.toUpperCase()),
    );
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

  void _setFlowControl({bool? dtrDsr, bool? rtsCts, bool? xonXoff}) {
    final bool dtr = dtrDsr ?? _flowControl.usesDtrDsr;
    final bool rts = rtsCts ?? _flowControl.usesRtsCts;
    final bool xon = xonXoff ?? _flowControl.usesXonXoff;
    final int mask = (dtr ? 4 : 0) | (rts ? 2 : 0) | (xon ? 1 : 0);
    setState(() {
      _flowControl = switch (mask) {
        1 => SerialFlowControl.xonXoff,
        2 => SerialFlowControl.rtsCts,
        3 => SerialFlowControl.rtsCtsXonXoff,
        4 => SerialFlowControl.dtrDsr,
        5 => SerialFlowControl.dtrDsrXonXoff,
        6 => SerialFlowControl.dtrDsrRtsCts,
        7 => SerialFlowControl.all,
        _ => SerialFlowControl.none,
      };
    });
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
        _receivedBytes = 0;
        _receivedChunks = 0;
        _lastReceivedAt = null;
        _status = '${settings.portName} · 实时监听中 · ${settings.summary}';
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

  void _close({String status = '未连接', String systemMessage = '串口已关闭'}) {
    final SerialPortSession? session = _session;
    if (session == null) return;
    _flushReceived();
    final StreamSubscription<SerialPortEvent>? subscription =
        _eventSubscription;
    _eventSubscription = null;
    setState(() {
      _session = null;
      _opening = false;
      _status = status;
    });
    _appendSystem(systemMessage);
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
    _receivedBytes += bytes.length;
    _receivedChunks += 1;
    _lastReceivedAt = DateTime.now();
    final String port = _portController.text.trim();
    _status = '$port · 已接收 ${_formatBytes(_receivedBytes)}';
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
        if (_sendHistory.length > 50) _sendHistory.removeLast();
        unawaited(_persistSendHistory());
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _persistSendHistory() async {
    try {
      await widget.onSendHistoryChanged?.call(
        List<String>.unmodifiable(_sendHistory),
      );
    } catch (_) {
      // Sending data must remain successful if local history storage fails.
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
              OutlinedButton.icon(
                key: const Key('serial-harness-activity'),
                onPressed: () => showHarnessToolActivityDialog(
                  context,
                  toolName: '串口调试',
                  toolIds: const <String>{
                    'vibekits.serial.list_ports',
                    'vibekits.serial.transact',
                  },
                ),
                icon: const Icon(Icons.history, size: 17),
                label: const Text('Harness 记录'),
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
                    suffixIcon: PopupMenuButton<String>(
                      tooltip: '选择已检测串口（其他 COM 编号可直接输入）',
                      onSelected: (String value) =>
                          _portController.text = value,
                      itemBuilder: (BuildContext context) => _selectablePorts
                          .map(
                            (
                              SerialPortDescriptor port,
                            ) => PopupMenuItem<String>(
                              value: port.name,
                              child: Text(
                                _ports.any(
                                      (SerialPortDescriptor value) =>
                                          value.name.toUpperCase() ==
                                          port.name.toUpperCase(),
                                    )
                                    ? '${port.label}'
                                          '${port.name == _recommendedPortName ? ' · 推荐' : ''}'
                                    : port.name,
                              ),
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
                  decoration: InputDecoration(
                    labelText: '波特率',
                    isDense: true,
                    suffixIcon: PopupMenuButton<int>(
                      tooltip: '选择常用波特率',
                      onSelected: (int value) =>
                          _baudController.text = '$value',
                      itemBuilder: (BuildContext context) => _commonBaudRates
                          .map(
                            (int value) => PopupMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(growable: false),
                      icon: const Icon(Icons.arrow_drop_down),
                    ),
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
              Tooltip(
                message: '硬件流控；当前 CH340 调试串口必须启用',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Checkbox(
                      key: const Key('serial-rts-cts'),
                      value: _flowControl.usesRtsCts,
                      onChanged: controlsEnabled
                          ? (bool? value) =>
                                _setFlowControl(rtsCts: value == true)
                          : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('RTS/CTS 流控'),
                  ],
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
                  onPressed: _opening ? null : () => _close(),
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
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '流控',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _flowCheckbox(
                        key: const Key('serial-flow-dtr-dsr'),
                        label: 'DTR/DSR',
                        value: _flowControl.usesDtrDsr,
                        onChanged: (bool value) =>
                            _setFlowControl(dtrDsr: value),
                      ),
                      _flowCheckbox(
                        key: const Key('serial-flow-rts-cts'),
                        label: 'RTS/CTS',
                        value: _flowControl.usesRtsCts,
                        onChanged: (bool value) =>
                            _setFlowControl(rtsCts: value),
                      ),
                      _flowCheckbox(
                        key: const Key('serial-flow-xon-xoff'),
                        label: 'XON/XOFF',
                        value: _flowControl.usesXonXoff,
                        onChanged: (bool value) =>
                            _setFlowControl(xonXoff: value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _flowCheckbox({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Checkbox(
          value: value,
          onChanged: (bool? checked) => onChanged(checked == true),
          visualDensity: VisualDensity.compact,
        ),
        Text(label),
      ],
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
                  '${_logs.length} 条 · RX ${_formatBytes(_receivedBytes)}'
                  ' / $_receivedChunks 次'
                  '${_lastReceivedAt == null ? '' : ' · 最近 ${_time(_lastReceivedAt!)}'}',
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
                      _connected
                          ? '串口已打开并实时监听 · 当前接收 0 B\n'
                                '真机没有输出时，请核对端口、波特率、流控，或先发送设备要求的查询命令'
                          : '打开串口后在此查看实时收发数据',
                      textAlign: TextAlign.center,
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
