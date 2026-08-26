import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CapturedPacket {
  const CapturedPacket({
    required this.timestamp,
    required this.protocol,
    required this.source,
    required this.destination,
    required this.length,
    this.direction = '',
    this.interfaceIndex = 0,
  });

  final DateTime timestamp;
  final String protocol;
  final String source;
  final String destination;
  final int length;
  final String direction;
  final int interfaceIndex;

  Map<String, Object> toJson() => <String, Object>{
    'timestamp': timestamp.toIso8601String(),
    'protocol': protocol,
    'source': source,
    'destination': destination,
    'length': length,
    'direction': direction,
    'interfaceIndex': interfaceIndex,
  };
}

class PacketCaptureSummary {
  const PacketCaptureSummary({
    required this.path,
    required this.linkType,
    required this.fileBytes,
    required this.packets,
    required this.protocolCounts,
    required this.endpointCounts,
  });

  final String path;
  final int linkType;
  final int fileBytes;
  final List<CapturedPacket> packets;
  final Map<String, int> protocolCounts;
  final Map<String, int> endpointCounts;

  int get packetBytes =>
      packets.fold<int>(0, (int sum, CapturedPacket p) => sum + p.length);

  Map<String, Object> toJson() => <String, Object>{
    'path': path,
    'linkType': linkType,
    'fileBytes': fileBytes,
    'packetCount': packets.length,
    'packetBytes': packetBytes,
    'protocolCounts': protocolCounts,
    'topEndpoints': endpointCounts.entries
        .toList()
        .map(
          (MapEntry<String, int> e) => <String, Object>{
            'endpoint': e.key,
            'packets': e.value,
          },
        )
        .toList(),
    'packets': packets.map((CapturedPacket p) => p.toJson()).toList(),
  };
}

class PacketCaptureService {
  PacketCaptureService({String? helperPath}) : _helperPathOverride = helperPath;

  static final PacketCaptureService instance = PacketCaptureService();

  final String? _helperPathOverride;
  final StreamController<CapturedPacket> _packetController =
      StreamController<CapturedPacket>.broadcast();
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  String? _lastError;
  String? _outputPath;
  int _packetCount = 0;
  Completer<void>? _startCompleter;

  Stream<CapturedPacket> get packets => _packetController.stream;
  bool get isCapturing => _process != null;
  String? get outputPath => _outputPath;
  int get packetCount => _packetCount;
  String? get lastError => _lastError;

  String get helperPath {
    if (_helperPathOverride case final String path) return path;
    final String executableDir = File(Platform.resolvedExecutable).parent.path;
    return '$executableDir${Platform.pathSeparator}tools${Platform.pathSeparator}'
        'packet_capture${Platform.pathSeparator}vibekits_packet_capture.exe';
  }

  Future<String> defaultOutputPath() async {
    final Directory directory = Directory(
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tmp'
      '${Platform.pathSeparator}network-capture',
    );
    await directory.create(recursive: true);
    final String stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return '${directory.path}${Platform.pathSeparator}capture-$stamp.pcap';
  }

  Future<void> start({
    required String outputPath,
    String filter = 'true',
    int maxPackets = 0,
    bool selfTest = false,
  }) async {
    if (_process != null) throw StateError('抓包已在运行');
    final File helper = File(helperPath);
    if (!await helper.exists()) throw StateError('抓包内核不存在：${helper.path}');
    await File(outputPath).parent.create(recursive: true);
    _lastError = null;
    _outputPath = outputPath;
    _packetCount = 0;
    final Completer<void> ready = Completer<void>();
    _startCompleter = ready;
    final List<String> arguments = <String>[
      '--output',
      outputPath,
      '--filter',
      filter.trim().isEmpty ? 'true' : filter.trim(),
      if (maxPackets > 0) ...<String>['--max-packets', '$maxPackets'],
      if (selfTest) '--self-test',
    ];
    final Process process = await Process.start(
      helper.path,
      arguments,
      workingDirectory: helper.parent.path,
      runInShell: false,
    );
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleErrorLine);
    unawaited(process.exitCode.then((int _) => _finishProcess(process)));
    try {
      await ready.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      await stop();
      throw TimeoutException('抓包内核 4 秒内未就绪');
    }
  }

  void _handleLine(String line) {
    try {
      final Object? decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] == 'error') {
        _lastError =
            '${decoded['message'] ?? '抓包失败'} (${decoded['code'] ?? ''})';
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.completeError(
            StateError(_friendlyError(_lastError!)),
          );
        }
        return;
      }
      if (decoded['type'] == 'started') {
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.complete();
        }
        return;
      }
      if (decoded['type'] != 'packet') return;
      _packetCount++;
      _packetController.add(
        CapturedPacket(
          timestamp: DateTime.fromMicrosecondsSinceEpoch(
            (decoded['timestampMicros'] as num?)?.toInt() ?? 0,
          ),
          protocol: '${decoded['protocol'] ?? 'IP'}',
          source: '${decoded['source'] ?? '?'}',
          destination: '${decoded['destination'] ?? '?'}',
          length: (decoded['length'] as num?)?.toInt() ?? 0,
          direction: '${decoded['direction'] ?? ''}',
          interfaceIndex: (decoded['interfaceIndex'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (_) {
      // Ignore non-JSON diagnostic lines from the native runtime.
    }
  }

  void _handleErrorLine(String line) {
    _lastError = line.trim().isEmpty ? _lastError : line.trim();
    _handleLine(line);
  }

  String _friendlyError(String raw) {
    if (raw.contains('WinDivertOpen') || raw.contains('(5)')) {
      return 'Windows 拒绝加载抓包驱动。请关闭 APP 后右键“以管理员身份运行”，再开始抓包。';
    }
    return raw;
  }

  Future<void> _finishProcess(Process process) async {
    if (!identical(_process, process)) return;
    if (!(_startCompleter?.isCompleted ?? true)) {
      _startCompleter!.completeError(
        StateError(_friendlyError(_lastError ?? '抓包内核提前退出')),
      );
    }
    _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _startCompleter = null;
  }

  Future<void> stop() async {
    final Process? process = _process;
    if (process == null) return;
    process.stdin.writeln('stop');
    await process.stdin.flush();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 2));
    }
    await _finishProcess(process);
  }

  Future<PacketCaptureSummary> read(
    String path, {
    int maxPackets = 2000,
  }) async {
    final Uint8List bytes = await File(path).readAsBytes();
    if (bytes.length < 24) throw const FormatException('PCAP 文件头不完整');
    final ByteData data = ByteData.sublistView(bytes);
    final int magic = data.getUint32(0, Endian.little);
    final Endian endian;
    if (magic == 0xa1b2c3d4 || magic == 0xa1b23c4d) {
      endian = Endian.little;
    } else if (data.getUint32(0, Endian.big) == 0xa1b2c3d4) {
      endian = Endian.big;
    } else {
      throw const FormatException('当前只支持标准 PCAP；不是有效 PCAP 文件');
    }
    final int linkType = data.getUint32(20, endian);
    int offset = 24;
    final List<CapturedPacket> packets = <CapturedPacket>[];
    while (offset + 16 <= bytes.length && packets.length < maxPackets) {
      final int seconds = data.getUint32(offset, endian);
      final int micros = data.getUint32(offset + 4, endian);
      final int capturedLength = data.getUint32(offset + 8, endian);
      if (capturedLength < 0 || offset + 16 + capturedLength > bytes.length) {
        break;
      }
      final Uint8List packet = Uint8List.sublistView(
        bytes,
        offset + 16,
        offset + 16 + capturedLength,
      );
      packets.add(_parsePacket(packet, linkType, seconds, micros));
      offset += 16 + capturedLength;
    }
    final Map<String, int> protocols = <String, int>{};
    final Map<String, int> endpoints = <String, int>{};
    for (final CapturedPacket packet in packets) {
      protocols.update(packet.protocol, (int n) => n + 1, ifAbsent: () => 1);
      for (final String endpoint in <String>[
        packet.source,
        packet.destination,
      ]) {
        endpoints.update(endpoint, (int n) => n + 1, ifAbsent: () => 1);
      }
    }
    final List<MapEntry<String, int>> sorted = endpoints.entries.toList()
      ..sort(
        (MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value.compareTo(a.value),
      );
    return PacketCaptureSummary(
      path: path,
      linkType: linkType,
      fileBytes: bytes.length,
      packets: packets,
      protocolCounts: protocols,
      endpointCounts: Map<String, int>.fromEntries(sorted.take(20)),
    );
  }

  CapturedPacket _parsePacket(
    Uint8List frame,
    int linkType,
    int seconds,
    int micros,
  ) {
    int offset = linkType == 1 ? 14 : 0;
    if (frame.length <= offset) return _unknown(frame, seconds, micros);
    final int version = frame[offset] >> 4;
    String source = '?';
    String destination = '?';
    int protocol = 0;
    int transportOffset = offset;
    if (version == 4 && frame.length >= offset + 20) {
      final int headerLength = (frame[offset] & 0x0f) * 4;
      protocol = frame[offset + 9];
      source = frame.sublist(offset + 12, offset + 16).join('.');
      destination = frame.sublist(offset + 16, offset + 20).join('.');
      transportOffset = offset + headerLength;
    } else if (version == 6 && frame.length >= offset + 40) {
      protocol = frame[offset + 6];
      source = _formatIpv6(frame.sublist(offset + 8, offset + 24));
      destination = _formatIpv6(frame.sublist(offset + 24, offset + 40));
      transportOffset = offset + 40;
    }
    String name = switch (protocol) {
      6 => 'TCP',
      17 => 'UDP',
      1 => 'ICMP',
      58 => 'ICMPv6',
      _ => 'IP',
    };
    if ((protocol == 6 || protocol == 17) &&
        frame.length >= transportOffset + 4) {
      final int sourcePort =
          (frame[transportOffset] << 8) | frame[transportOffset + 1];
      final int destinationPort =
          (frame[transportOffset + 2] << 8) | frame[transportOffset + 3];
      source = '$source:$sourcePort';
      destination = '$destination:$destinationPort';
      if (sourcePort == 53 || destinationPort == 53) name = 'DNS';
      if (<int>{80, 8080, 8000}.contains(sourcePort) ||
          <int>{80, 8080, 8000}.contains(destinationPort)) {
        name = 'HTTP';
      }
      if (sourcePort == 443 || destinationPort == 443) {
        name = protocol == 17 ? 'QUIC' : 'TLS';
      }
    }
    return CapturedPacket(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ).add(Duration(microseconds: micros)),
      protocol: name,
      source: source,
      destination: destination,
      length: frame.length,
    );
  }

  CapturedPacket _unknown(Uint8List frame, int seconds, int micros) =>
      CapturedPacket(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).add(Duration(microseconds: micros)),
        protocol: '未知',
        source: '?',
        destination: '?',
        length: frame.length,
      );

  String _formatIpv6(List<int> bytes) {
    final List<String> groups = <String>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      groups.add(((bytes[i] << 8) | bytes[i + 1]).toRadixString(16));
    }
    return '[${groups.join(':')}]';
  }
}
