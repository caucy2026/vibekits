import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:libserialport_plus/libserialport_plus.dart' as native;

enum SerialParity { none, even, odd, mark, space }

enum SerialFlowControl {
  none,
  dtrDsr,
  rtsCts,
  xonXoff,
  dtrDsrRtsCts,
  dtrDsrXonXoff,
  rtsCtsXonXoff,
  all,
}

enum SerialDataMode { text, hex }

enum SerialLineEnding { none, lf, crlf, cr }

extension SerialSettingLabels on SerialParity {
  String get label => switch (this) {
    SerialParity.none => '无',
    SerialParity.even => '偶校验',
    SerialParity.odd => '奇校验',
    SerialParity.mark => 'Mark',
    SerialParity.space => 'Space',
  };
}

extension SerialFlowControlLabels on SerialFlowControl {
  String get label => switch (this) {
    SerialFlowControl.none => '无',
    SerialFlowControl.dtrDsr => 'DTR/DSR',
    SerialFlowControl.rtsCts => 'RTS/CTS',
    SerialFlowControl.xonXoff => 'XON/XOFF',
    SerialFlowControl.dtrDsrRtsCts => 'DTR/DSR + RTS/CTS',
    SerialFlowControl.dtrDsrXonXoff => 'DTR/DSR + XON/XOFF',
    SerialFlowControl.rtsCtsXonXoff => 'RTS/CTS + XON/XOFF',
    SerialFlowControl.all => '全部流控',
  };

  bool get usesDtrDsr => switch (this) {
    SerialFlowControl.dtrDsr ||
    SerialFlowControl.dtrDsrRtsCts ||
    SerialFlowControl.dtrDsrXonXoff ||
    SerialFlowControl.all => true,
    _ => false,
  };

  bool get usesRtsCts => switch (this) {
    SerialFlowControl.rtsCts ||
    SerialFlowControl.dtrDsrRtsCts ||
    SerialFlowControl.rtsCtsXonXoff ||
    SerialFlowControl.all => true,
    _ => false,
  };

  bool get usesXonXoff => switch (this) {
    SerialFlowControl.xonXoff ||
    SerialFlowControl.dtrDsrXonXoff ||
    SerialFlowControl.rtsCtsXonXoff ||
    SerialFlowControl.all => true,
    _ => false,
  };
}

extension SerialLineEndingLabels on SerialLineEnding {
  String get label => switch (this) {
    SerialLineEnding.none => '无',
    SerialLineEnding.lf => 'LF',
    SerialLineEnding.crlf => 'CRLF',
    SerialLineEnding.cr => 'CR',
  };

  List<int> get bytes => switch (this) {
    SerialLineEnding.none => const <int>[],
    SerialLineEnding.lf => const <int>[10],
    SerialLineEnding.crlf => const <int>[13, 10],
    SerialLineEnding.cr => const <int>[13],
  };
}

class SerialConnectionSettings {
  const SerialConnectionSettings({
    required this.portName,
    this.baudRate = 115200,
    this.dataBits = 8,
    this.parity = SerialParity.none,
    this.stopBits = 1,
    this.flowControl = SerialFlowControl.none,
  });

  final String portName;
  final int baudRate;
  final int dataBits;
  final SerialParity parity;
  final int stopBits;
  final SerialFlowControl flowControl;

  void validate() {
    if (portName.trim().isEmpty) throw const FormatException('请输入串口名称');
    if (baudRate < 1 || baudRate > 12000000) {
      throw const FormatException('波特率必须在 1 到 12000000 之间');
    }
    if (dataBits < 5 || dataBits > 8) {
      throw const FormatException('数据位仅支持 5、6、7、8');
    }
    if (stopBits != 1 && stopBits != 2) {
      throw const FormatException('停止位仅支持 1 或 2');
    }
  }

  String get summary {
    final String parityCode = switch (parity) {
      SerialParity.none => 'N',
      SerialParity.even => 'E',
      SerialParity.odd => 'O',
      SerialParity.mark => 'M',
      SerialParity.space => 'S',
    };
    return '$baudRate · $dataBits-$parityCode-$stopBits · ${flowControl.label}';
  }

  Map<String, Object> toMap() => <String, Object>{
    'portName': portName,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'parity': parity.name,
    'stopBits': stopBits,
    'flowControl': flowControl.name,
  };

  String encode() => jsonEncode(toMap());

  static SerialConnectionSettings? decode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      final Map<String, Object?> map = Map<String, Object?>.from(decoded);
      final SerialConnectionSettings settings = SerialConnectionSettings(
        portName: '${map['portName'] ?? ''}',
        baudRate: map['baudRate'] is int ? map['baudRate']! as int : 115200,
        dataBits: map['dataBits'] is int ? map['dataBits']! as int : 8,
        parity:
            SerialParity.values
                .where((SerialParity value) => value.name == map['parity'])
                .firstOrNull ??
            SerialParity.none,
        stopBits: map['stopBits'] is int ? map['stopBits']! as int : 1,
        flowControl:
            SerialFlowControl.values
                .where(
                  (SerialFlowControl value) => value.name == map['flowControl'],
                )
                .firstOrNull ??
            SerialFlowControl.none,
      );
      settings.validate();
      return settings;
    } on Object {
      return null;
    }
  }
}

class SerialPortDescriptor {
  const SerialPortDescriptor({
    required this.name,
    this.description = '',
    this.transport = '',
    this.vendorId,
    this.productId,
  });

  final String name;
  final String description;
  final String transport;
  final int? vendorId;
  final int? productId;

  String get label {
    final String detail = description.trim();
    return detail.isEmpty ? name : '$name · $detail';
  }

  static SerialPortDescriptor fromMap(Map<String, Object?> map) =>
      SerialPortDescriptor(
        name: '${map['name']}',
        description: '${map['description'] ?? ''}',
        transport: '${map['transport'] ?? ''}',
        vendorId: map['vendorId'] as int?,
        productId: map['productId'] as int?,
      );
}

enum SerialPortEventType { received, sent, error, closed }

class SerialPortEvent {
  const SerialPortEvent(this.type, {this.bytes, this.message});

  final SerialPortEventType type;
  final Uint8List? bytes;
  final String? message;
}

abstract class SerialPortSession {
  Stream<SerialPortEvent> get events;
  bool get isOpen;
  Future<int> send(Uint8List bytes);
  Future<void> close();
}

abstract final class SerialCodec {
  static Uint8List encode(
    String source,
    SerialDataMode mode, {
    SerialLineEnding lineEnding = SerialLineEnding.none,
  }) {
    final List<int> content = switch (mode) {
      SerialDataMode.text => utf8.encode(source),
      SerialDataMode.hex => _parseHex(source),
    };
    return Uint8List.fromList(<int>[...content, ...lineEnding.bytes]);
  }

  static String decode(Uint8List bytes, SerialDataMode mode) => switch (mode) {
    SerialDataMode.text => utf8.decode(bytes, allowMalformed: true),
    SerialDataMode.hex =>
      bytes
          .map(
            (int byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
          )
          .join(' '),
  };

  static List<int> _parseHex(String source) {
    final String compact = source
        .replaceAll(RegExp(r'0[xX]'), '')
        .replaceAll(RegExp(r'[\s,;:_-]'), '');
    if (compact.isEmpty) return <int>[];
    if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
      throw const FormatException('HEX 请输入成对十六进制字节，例如 01 A0 FF');
    }
    return <int>[
      for (int index = 0; index < compact.length; index += 2)
        int.parse(compact.substring(index, index + 2), radix: 16),
    ];
  }
}

/// libserialport is only called from worker isolates. Port enumeration, open,
/// configuration, reads and writes therefore never block Flutter's UI isolate.
abstract final class SerialPortService {
  static Future<List<SerialPortDescriptor>> listPorts() async {
    final List<Map<String, Object?>> maps = await Isolate.run(_listSerialPorts)
        .timeout(const Duration(seconds: 5));
    return maps.map(SerialPortDescriptor.fromMap).toList(growable: false);
  }

  static Future<SerialPortSession> open(SerialConnectionSettings settings) =>
      _WorkerSerialPortSession.open(settings);
}

typedef SerialSessionOpener = Future<SerialPortSession> Function(
  SerialConnectionSettings settings,
);

/// Passive serial configuration discovery used by Harness.
///
/// It never writes probe bytes. Candidates are tried in three bounded stages:
/// common baud rates with 8-N-1, frame formats at the best baud, then flow
/// control. This keeps the default run short while still returning auditable
/// evidence for every attempted configuration.
abstract final class SerialAutoDetector {
  static const List<int> defaultBaudRates = <int>[
    115200,
    921600,
    460800,
    230400,
    57600,
    38400,
    19200,
    9600,
  ];

  static Future<Map<String, Object?>> detect({
    required String portName,
    List<int> baudRates = defaultBaudRates,
    Duration listenDuration = const Duration(milliseconds: 300),
    SerialSessionOpener open = SerialPortService.open,
  }) async {
    final List<Map<String, Object?>> attempts = <Map<String, Object?>>[];
    final Set<String> seen = <String>{};

    Future<_SerialProbe> trySettings(SerialConnectionSettings settings) async {
      final String key = settings.encode();
      if (!seen.add(key)) {
        return const _SerialProbe.empty();
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      SerialPortSession? session;
      StreamSubscription<SerialPortEvent>? subscription;
      String? error;
      try {
        session = await open(settings);
        subscription = session.events.listen((SerialPortEvent event) {
          if (event.type == SerialPortEventType.received &&
              event.bytes != null) {
            bytes.add(event.bytes!);
          }
        });
        await Future<void>.delayed(listenDuration);
      } on Object catch (caught) {
        error = '$caught';
      } finally {
        await session?.close();
        await subscription?.cancel();
      }
      final Uint8List received = bytes.takeBytes();
      final double score = _score(received);
      final Map<String, Object?> evidence = <String, Object?>{
        ...settings.toMap(),
        'summary': settings.summary,
        'receivedBytes': received.length,
        'score': double.parse(score.toStringAsFixed(3)),
        if (received.isNotEmpty)
          'sampleText': SerialCodec.decode(
            Uint8List.sublistView(received, 0, received.length.clamp(0, 256)),
            SerialDataMode.text,
          ),
        if (received.isNotEmpty)
          'sampleHex': SerialCodec.decode(
            Uint8List.sublistView(received, 0, received.length.clamp(0, 64)),
            SerialDataMode.hex,
          ),
        if (error != null) 'error': error,
      };
      attempts.add(evidence);
      return _SerialProbe(settings, received, score, error);
    }

    _SerialProbe best = const _SerialProbe.empty();
    for (final int baudRate in baudRates.toSet()) {
      final _SerialProbe probe = await trySettings(
        SerialConnectionSettings(portName: portName, baudRate: baudRate),
      );
      if (probe.isBetterThan(best)) best = probe;
    }
    if (best.bytes.isEmpty) {
      for (final SerialFlowControl flow in const <SerialFlowControl>[
        SerialFlowControl.rtsCts,
        SerialFlowControl.dtrDsr,
        SerialFlowControl.xonXoff,
      ]) {
        for (final int baudRate in baudRates.toSet()) {
          final _SerialProbe probe = await trySettings(
            SerialConnectionSettings(
              portName: portName,
              baudRate: baudRate,
              flowControl: flow,
            ),
          );
          if (probe.isBetterThan(best)) best = probe;
        }
        if (best.bytes.isNotEmpty && best.score >= 90) break;
      }
    }
    final int bestBaud =
        best.settings?.baudRate ??
        (baudRates.isEmpty ? 115200 : baudRates.first);
    for (final SerialConnectionSettings settings in <SerialConnectionSettings>[
      SerialConnectionSettings(portName: portName, baudRate: bestBaud),
      SerialConnectionSettings(
        portName: portName,
        baudRate: bestBaud,
        parity: SerialParity.even,
      ),
      SerialConnectionSettings(
        portName: portName,
        baudRate: bestBaud,
        dataBits: 7,
        parity: SerialParity.even,
      ),
      SerialConnectionSettings(
        portName: portName,
        baudRate: bestBaud,
        parity: SerialParity.odd,
      ),
      SerialConnectionSettings(
        portName: portName,
        baudRate: bestBaud,
        stopBits: 2,
      ),
    ]) {
      final _SerialProbe probe = await trySettings(settings);
      if (probe.isBetterThan(best)) best = probe;
    }
    final SerialConnectionSettings frame =
        best.settings ??
        SerialConnectionSettings(portName: portName, baudRate: bestBaud);
    for (final SerialFlowControl flow in SerialFlowControl.values) {
      final _SerialProbe probe = await trySettings(
        SerialConnectionSettings(
          portName: portName,
          baudRate: frame.baudRate,
          dataBits: frame.dataBits,
          parity: frame.parity,
          stopBits: frame.stopBits,
          flowControl: flow,
        ),
      );
      if (probe.isBetterThan(best)) best = probe;
    }
    final SerialConnectionSettings selected =
        best.settings ??
        SerialConnectionSettings(portName: portName, baudRate: bestBaud);
    final double confidence = best.bytes.isEmpty
        ? 0
        : (best.score / 120).clamp(0, 1);
    return <String, Object?>{
      'port': portName,
      'selected': selected.toMap(),
      'summary': selected.summary,
      'confidence': double.parse(confidence.toStringAsFixed(3)),
      'passiveOnly': true,
      'receivedBytes': best.bytes.length,
      'attemptCount': attempts.length,
      'attempts': attempts,
      'requiresUserInput': false,
      'nextAction': best.bytes.isEmpty
          ? '未捕获持续数据；可直接用 selected 打开监听，或扩大 listenMs 后重试。'
          : '使用 selected 参数调用 serial.session_open，并用 session_read 持续读取。',
    };
  }

  static double _score(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    int printable = 0;
    int replacement = 0;
    int lines = 0;
    for (final int byte in bytes) {
      if (byte == 10 || byte == 13 || byte == 9 || (byte >= 32 && byte < 127)) {
        printable += 1;
      }
      if (byte == 0xEF) replacement += 1;
      if (byte == 10) lines += 1;
    }
    return (printable / bytes.length) * 100 +
        lines.clamp(0, 10) * 1.5 +
        bytes.length.clamp(0, 512) / 64 -
        replacement * 0.5;
  }
}

class _SerialProbe {
  const _SerialProbe(this.settings, this.bytes, this.score, this.error);
  const _SerialProbe.empty()
    : settings = null,
      bytes = const <int>[],
      score = -1,
      error = null;

  final SerialConnectionSettings? settings;
  final List<int> bytes;
  final double score;
  final String? error;

  bool isBetterThan(_SerialProbe other) =>
      error == null &&
      (score > other.score ||
          (score == other.score && bytes.length > other.bytes.length));
}

List<Map<String, Object?>> _listSerialPorts() {
  final List<Map<String, Object?>> ports = <Map<String, Object?>>[];
  for (final String name in native.SerialPort.getAvailablePorts()) {
    final native.SerialPort port = native.SerialPort(name);
    try {
      final native.SerialPortInfo info = port.getInfo();
      ports.add(<String, Object?>{
        'name': info.name,
        'description': info.description,
        'transport': info.transport.name,
        'vendorId': info.usbVid,
        'productId': info.usbPid,
      });
    } on Object {
      ports.add(<String, Object?>{'name': name});
    } finally {
      port.dispose();
    }
  }
  ports.sort(
    (Map<String, Object?> a, Map<String, Object?> b) =>
        '${a['name']}'.compareTo('${b['name']}'),
  );
  return ports;
}

class _WorkerSerialPortSession implements SerialPortSession {
  _WorkerSerialPortSession._();

  final ReceivePort _resultPort = ReceivePort();
  final ReceivePort _errorPort = ReceivePort();
  final ReceivePort _exitPort = ReceivePort();
  // A serial session has exactly one consumer (the workspace or one Harness
  // tool call). A single-subscription controller buffers bytes that arrive
  // between the worker reporting `ready` and the caller attaching its
  // listener. A broadcast controller silently dropped that first burst.
  final StreamController<SerialPortEvent> _events =
      StreamController<SerialPortEvent>();
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _closed = Completer<void>();
  final Map<int, Completer<int>> _pendingWrites = <int, Completer<int>>{};
  StreamSubscription<Object?>? _resultSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Isolate? _isolate;
  SendPort? _commandPort;
  int _nextWriteId = 1;
  bool _isOpen = false;
  bool _disposed = false;

  static Future<SerialPortSession> open(
    SerialConnectionSettings settings,
  ) async {
    settings.validate();
    final _WorkerSerialPortSession session = _WorkerSerialPortSession._();
    await session._start(settings);
    return session;
  }

  Future<void> _start(SerialConnectionSettings settings) async {
    _resultSubscription = _resultPort.listen(_handleMessage);
    _errorSubscription = _errorPort.listen((Object? error) {
      _fail(StateError('串口后台线程异常：$error'));
    });
    _exitSubscription = _exitPort.listen((Object? _) {
      if (!_closed.isCompleted) _closed.complete();
      _finishClosed();
    });
    _isolate = await Isolate.spawn<Map<String, Object?>>(
      _serialWorker,
      <String, Object?>{
        'replyPort': _resultPort.sendPort,
        'settings': settings.toMap(),
      },
      debugName: 'vibekits-serial-port',
      onError: _errorPort.sendPort,
      onExit: _exitPort.sendPort,
    );
    try {
      await _ready.future.timeout(const Duration(seconds: 8));
    } on Object {
      await close();
      rethrow;
    }
  }

  void _handleMessage(Object? raw) {
    if (raw is! Map) return;
    final Map<String, Object?> message = Map<String, Object?>.from(raw);
    switch ('${message['type']}') {
      case 'ready':
        _commandPort = message['commandPort']! as SendPort;
        _isOpen = true;
        if (!_ready.isCompleted) _ready.complete();
      case 'data':
        if (!_events.isClosed) {
          _events.add(
            SerialPortEvent(
              SerialPortEventType.received,
              bytes: Uint8List.fromList(message['bytes']! as List<int>),
            ),
          );
        }
      case 'sent':
        final int id = message['id']! as int;
        final int count = message['count']! as int;
        _pendingWrites.remove(id)?.complete(count);
        if (!_events.isClosed) {
          _events.add(
            SerialPortEvent(
              SerialPortEventType.sent,
              bytes: Uint8List.fromList(message['bytes']! as List<int>),
            ),
          );
        }
      case 'error':
        _fail(StateError('${message['message']}'));
      case 'closed':
        if (!_closed.isCompleted) _closed.complete();
        _finishClosed();
    }
  }

  void _fail(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final Completer<int> pending in _pendingWrites.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pendingWrites.clear();
    if (!_events.isClosed) {
      _events.add(
        SerialPortEvent(SerialPortEventType.error, message: '$error'),
      );
    }
  }

  void _finishClosed() {
    if (!_isOpen && _disposed) return;
    _isOpen = false;
    if (!_events.isClosed) {
      _events.add(const SerialPortEvent(SerialPortEventType.closed));
    }
  }

  @override
  Stream<SerialPortEvent> get events => _events.stream;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<int> send(Uint8List bytes) {
    if (!_isOpen || _commandPort == null) {
      throw StateError('串口尚未打开');
    }
    if (bytes.isEmpty) throw const FormatException('没有可发送的数据');
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('单次发送不能超过 1 MiB');
    }
    final int id = _nextWriteId++;
    final Completer<int> completer = Completer<int>();
    _pendingWrites[id] = completer;
    _commandPort!.send(<String, Object?>{
      'type': 'send',
      'id': id,
      'bytes': bytes,
    });
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingWrites.remove(id);
        throw TimeoutException('串口发送超过 5 秒，已停止等待');
      },
    );
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _commandPort?.send(<String, Object?>{'type': 'close'});
    try {
      await _closed.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _isOpen = false;
    for (final Completer<int> pending in _pendingWrites.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('串口已关闭'));
      }
    }
    _pendingWrites.clear();
    await _resultSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _resultPort.close();
    _errorPort.close();
    _exitPort.close();
    if (!_events.isClosed) await _events.close();
  }
}

@pragma('vm:entry-point')
Future<void> _serialWorker(Map<String, Object?> request) async {
  final SendPort replyPort = request['replyPort']! as SendPort;
  final Map<String, Object?> settingsMap = Map<String, Object?>.from(
    request['settings']! as Map,
  );
  final SerialConnectionSettings? settings = SerialConnectionSettings.decode(
    jsonEncode(settingsMap),
  );
  if (settings == null) {
    replyPort.send(<String, Object?>{'type': 'error', 'message': '串口参数无效'});
    return;
  }

  final ReceivePort commandPort = ReceivePort();
  final Queue<Map<String, Object?>> commands = Queue<Map<String, Object?>>();
  bool running = true;
  final StreamSubscription<Object?> subscription = commandPort.listen((
    Object? raw,
  ) {
    if (raw is! Map) return;
    final Map<String, Object?> command = Map<String, Object?>.from(raw);
    if (command['type'] == 'close') {
      running = false;
    } else {
      commands.add(command);
    }
  });
  native.SerialPort? port;
  try {
    port = native.SerialPort(settings.portName);
    port.open(native.SerialPortMode.readWrite);
    port.setConfig(_nativeConfig(settings));
    replyPort.send(<String, Object?>{
      'type': 'ready',
      'commandPort': commandPort.sendPort,
    });
    while (running) {
      await Future<void>.delayed(Duration.zero);
      while (commands.isNotEmpty) {
        final Map<String, Object?> command = commands.removeFirst();
        if (command['type'] != 'send') continue;
        final Uint8List bytes = Uint8List.fromList(
          command['bytes']! as List<int>,
        );
        int offset = 0;
        while (offset < bytes.length) {
          final int written = port.write(
            Uint8List.sublistView(bytes, offset),
            timeout: 500,
          );
          if (written <= 0) throw StateError('串口没有接受发送数据');
          offset += written;
        }
        replyPort.send(<String, Object?>{
          'type': 'sent',
          'id': command['id'],
          'count': offset,
          'bytes': bytes,
        });
      }
      final Uint8List bytes = port.read(4096, timeout: 50);
      if (bytes.isNotEmpty) {
        replyPort.send(<String, Object?>{'type': 'data', 'bytes': bytes});
      }
    }
  } catch (error) {
    replyPort.send(<String, Object?>{
      'type': 'error',
      'message': _serialErrorMessage(error, settings.portName),
    });
  } finally {
    try {
      if (port?.isOpen() == true) port?.close();
    } on Object {
      // The device may already be unplugged.
    }
    port?.dispose();
    await subscription.cancel();
    commandPort.close();
    replyPort.send(<String, Object?>{'type': 'closed'});
  }
}

native.SerialPortConfig _nativeConfig(SerialConnectionSettings settings) {
  final native.SerialPortParity parity = switch (settings.parity) {
    SerialParity.none => native.SerialPortParity.none,
    SerialParity.even => native.SerialPortParity.even,
    SerialParity.odd => native.SerialPortParity.odd,
    SerialParity.mark => native.SerialPortParity.mark,
    SerialParity.space => native.SerialPortParity.space,
  };
  return native.SerialPortConfig(
    baudRate: settings.baudRate,
    bits: settings.dataBits,
    parity: parity,
    stopBits: settings.stopBits,
    rts: settings.flowControl.usesRtsCts
        ? native.SerialPortRts.flowControl
        : native.SerialPortRts.off,
    cts: settings.flowControl.usesRtsCts
        ? native.SerialPortCts.flowControl
        : native.SerialPortCts.ignore,
    dtr: settings.flowControl.usesDtrDsr
        ? native.SerialPortDtr.flowControl
        : native.SerialPortDtr.on,
    dsr: settings.flowControl.usesDtrDsr
        ? native.SerialPortDsr.flowControl
        : native.SerialPortDsr.ignore,
    xonXoff: settings.flowControl.usesXonXoff
        ? native.SerialPortXonXoff.inputOutput
        : native.SerialPortXonXoff.disabled,
  );
}

String _serialErrorMessage(Object error, String portName) {
  final String source = '$error';
  if (source.toLowerCase().contains('access') ||
      source.contains('拒绝访问') ||
      source.toLowerCase().contains('busy')) {
    return '$portName 已被其他程序占用或当前用户没有权限';
  }
  return '$portName 操作失败：$source';
}
