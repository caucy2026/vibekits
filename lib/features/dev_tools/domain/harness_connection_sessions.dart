import 'dart:async';
import 'dart:typed_data';

import 'adb_service.dart';
import 'serial_port_service.dart';

typedef HarnessSerialOpener = Future<SerialPortSession> Function(
  SerialConnectionSettings settings,
);
typedef HarnessAdbHealthRunner = Future<AdbCommandResult> Function(
  String serial,
);

/// Owns device handles that must outlive a single Harness tool call.
///
/// A session is explicitly opened, read/written many times and closed. The
/// manager is disposed with its Harness bridge so no COM handle, timer or ADB
/// heartbeat survives the APP process.
class HarnessConnectionSessions {
  HarnessConnectionSessions({HarnessSerialOpener? openSerial, this.checkAdb})
    : _openSerial = openSerial ?? SerialPortService.open;

  static const int maxSerialBufferBytes = 2 * 1024 * 1024;

  final HarnessSerialOpener _openSerial;
  final HarnessAdbHealthRunner? checkAdb;
  final Map<String, _SerialHandle> _serial = <String, _SerialHandle>{};
  final Map<String, _AdbHandle> _adb = <String, _AdbHandle>{};
  int _nextId = 1;

  Future<Map<String, Object?>> openSerial(
    SerialConnectionSettings settings,
  ) async {
    final SerialPortSession session = await _openSerial(settings);
    final String id = 'serial-${_nextId++}';
    final _SerialHandle handle = _SerialHandle(
      id: id,
      settings: settings,
      session: session,
    );
    _serial[id] = handle;
    handle.subscription = session.events.listen(handle.accept);
    return handle.status();
  }

  Map<String, Object?> serialStatus(String id) => _requireSerial(id).status();

  Map<String, Object?> readSerial(
    String id, {
    bool clear = true,
    SerialDataMode mode = SerialDataMode.text,
  }) {
    final _SerialHandle handle = _requireSerial(id);
    final Uint8List bytes = Uint8List.fromList(handle.bytes);
    if (clear) handle.bytes.clear();
    return <String, Object?>{
      ...handle.status(),
      'receivedBytes': bytes.length,
      'data': SerialCodec.decode(bytes, mode),
      'mode': mode.name,
      'cleared': clear,
    };
  }

  Future<Map<String, Object?>> writeSerial(
    String id,
    String data, {
    SerialDataMode mode = SerialDataMode.text,
    SerialLineEnding lineEnding = SerialLineEnding.none,
  }) async {
    final _SerialHandle handle = _requireSerial(id);
    final Uint8List bytes = SerialCodec.encode(
      data,
      mode,
      lineEnding: lineEnding,
    );
    final int sent = await handle.session.send(bytes);
    return <String, Object?>{...handle.status(), 'sentBytes': sent};
  }

  Future<Map<String, Object?>> closeSerial(String id) async {
    final _SerialHandle handle = _requireSerial(id);
    _serial.remove(id);
    await handle.subscription?.cancel();
    await handle.session.close();
    return <String, Object?>{'sessionId': id, 'closed': true};
  }

  Future<Map<String, Object?>> openAdb(
    String serial, {
    int heartbeatSeconds = 10,
  }) async {
    if (checkAdb == null) throw StateError('ADB 长连接执行器不可用');
    final String target = serial.trim();
    if (target.isEmpty || target.contains(RegExp(r'[\r\n\s]'))) {
      throw const FormatException('ADB 设备序列号无效');
    }
    final AdbCommandResult initial = await checkAdb!(target);
    if (initial.exitCode != 0 || initial.stdout.trim() != 'device') {
      throw StateError(
        initial.stderr.trim().isEmpty
            ? 'ADB 设备未处于 device 状态：${initial.stdout.trim()}'
            : initial.stderr.trim(),
      );
    }
    final String id = 'adb-${_nextId++}';
    final _AdbHandle handle = _AdbHandle(id: id, serial: target);
    _adb[id] = handle;
    handle.record(initial);
    handle.timer = Timer.periodic(
      Duration(seconds: heartbeatSeconds.clamp(3, 60)),
      (_) => unawaited(_heartbeatAdb(handle)),
    );
    return handle.status();
  }

  Future<void> _heartbeatAdb(_AdbHandle handle) async {
    if (handle.checking || !_adb.containsKey(handle.id)) return;
    handle.checking = true;
    try {
      handle.record(await checkAdb!(handle.serial));
    } on Object catch (error) {
      handle.lastError = '$error';
      handle.connected = false;
    } finally {
      handle.checking = false;
    }
  }

  Map<String, Object?> adbStatus(String id) => _requireAdb(id).status();

  /// Immediately checks the transport while keeping the same logical session.
  Future<Map<String, Object?>> refreshAdb(String id) async {
    final _AdbHandle handle = _requireAdb(id);
    await _heartbeatAdb(handle);
    return handle.status();
  }

  Map<String, Object?> closeAdb(String id) {
    final _AdbHandle handle = _requireAdb(id);
    _adb.remove(id);
    handle.timer?.cancel();
    return <String, Object?>{
      'sessionId': id,
      'serial': handle.serial,
      'closed': true,
    };
  }

  Future<void> dispose() async {
    for (final _AdbHandle handle in _adb.values) {
      handle.timer?.cancel();
    }
    _adb.clear();
    final List<_SerialHandle> serial = _serial.values.toList(growable: false);
    _serial.clear();
    for (final _SerialHandle handle in serial) {
      await handle.subscription?.cancel();
      await handle.session.close();
    }
  }

  _SerialHandle _requireSerial(String id) {
    final _SerialHandle? handle = _serial[id.trim()];
    if (handle == null) throw StateError('串口长连接不存在或已关闭');
    return handle;
  }

  _AdbHandle _requireAdb(String id) {
    final _AdbHandle? handle = _adb[id.trim()];
    if (handle == null) throw StateError('ADB 长连接不存在或已关闭');
    return handle;
  }
}

class _SerialHandle {
  _SerialHandle({
    required this.id,
    required this.settings,
    required this.session,
  });

  final String id;
  final SerialConnectionSettings settings;
  final SerialPortSession session;
  final List<int> bytes = <int>[];
  StreamSubscription<SerialPortEvent>? subscription;
  String lastError = '';

  void accept(SerialPortEvent event) {
    if (event.type == SerialPortEventType.received && event.bytes != null) {
      bytes.addAll(event.bytes!);
      final int overflow =
          bytes.length - HarnessConnectionSessions.maxSerialBufferBytes;
      if (overflow > 0) bytes.removeRange(0, overflow);
    } else if (event.type == SerialPortEventType.error) {
      lastError = event.message ?? '串口错误';
    }
  }

  Map<String, Object?> status() => <String, Object?>{
    'sessionId': id,
    'port': settings.portName,
    'settings': settings.toMap(),
    'open': session.isOpen,
    'bufferedBytes': bytes.length,
    if (lastError.isNotEmpty) 'lastError': lastError,
  };
}

class _AdbHandle {
  _AdbHandle({required this.id, required this.serial});

  final String id;
  final String serial;
  Timer? timer;
  bool checking = false;
  bool connected = false;
  int healthChecks = 0;
  DateTime? lastCheckedAt;
  String lastError = '';

  void record(AdbCommandResult result) {
    healthChecks += 1;
    lastCheckedAt = DateTime.now();
    connected = result.exitCode == 0 && result.stdout.trim() == 'device';
    lastError = result.stderr.trim();
  }

  Map<String, Object?> status() => <String, Object?>{
    'sessionId': id,
    'serial': serial,
    'connected': connected,
    'healthChecks': healthChecks,
    if (lastCheckedAt != null)
      'lastCheckedAt': lastCheckedAt!.toIso8601String(),
    if (lastError.isNotEmpty) 'lastError': lastError,
  };
}
