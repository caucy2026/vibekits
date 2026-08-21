import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum WindowsNodeDeviceStatus { active, disabled, revoked }

class WindowsNodeDevice {
  const WindowsNodeDevice({
    required this.id,
    required this.label,
    required this.publicKey,
    required this.fingerprint,
    required this.status,
    required this.enrolledAt,
    this.lastConnectedAt,
    this.revokedAt,
  });

  final String id;
  final String label;
  final String publicKey;
  final String fingerprint;
  final WindowsNodeDeviceStatus status;
  final DateTime enrolledAt;
  final DateTime? lastConnectedAt;
  final DateTime? revokedAt;

  Map<String, Object?> toJson({bool includePublicKey = true}) =>
      <String, Object?>{
        'id': id,
        'label': label,
        if (includePublicKey) 'publicKey': publicKey,
        'fingerprint': fingerprint,
        'status': status.name,
        'enrolledAt': enrolledAt.toUtc().toIso8601String(),
        'lastConnectedAt': lastConnectedAt?.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
      };

  factory WindowsNodeDevice.fromJson(Map<String, Object?> json) =>
      WindowsNodeDevice(
        id: '${json['id'] ?? ''}',
        label: '${json['label'] ?? ''}',
        publicKey: '${json['publicKey'] ?? ''}',
        fingerprint: '${json['fingerprint'] ?? ''}',
        status: WindowsNodeDeviceStatus.values.firstWhere(
          (WindowsNodeDeviceStatus value) =>
              value.name == '${json['status'] ?? ''}',
          orElse: () => WindowsNodeDeviceStatus.revoked,
        ),
        enrolledAt:
            DateTime.tryParse('${json['enrolledAt'] ?? ''}')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lastConnectedAt: DateTime.tryParse('${json['lastConnectedAt'] ?? ''}')
            ?.toLocal(),
        revokedAt: DateTime.tryParse('${json['revokedAt'] ?? ''}')?.toLocal(),
      );

  WindowsNodeDevice copyWith({
    WindowsNodeDeviceStatus? status,
    DateTime? lastConnectedAt,
    DateTime? revokedAt,
  }) => WindowsNodeDevice(
    id: id,
    label: label,
    publicKey: publicKey,
    fingerprint: fingerprint,
    status: status ?? this.status,
    enrolledAt: enrolledAt,
    lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    revokedAt: revokedAt ?? this.revokedAt,
  );
}

class WindowsNodeOnboarding {
  const WindowsNodeOnboarding({
    required this.host,
    required this.port,
    required this.user,
    required this.hostKeyFingerprint,
    required this.allowedCidr,
  });

  final String host;
  final int port;
  final String user;
  final String hostKeyFingerprint;
  final String allowedCidr;

  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'user': user,
    'hostKeyFingerprint': hostKeyFingerprint,
    'allowedCidr': allowedCidr,
    'sshConfig':
        'Host vibekits-windows-node\n'
        '  HostName $host\n'
        '  Port $port\n'
        '  User $user\n'
        '  IdentitiesOnly yes\n'
        '  StrictHostKeyChecking yes',
    'instructions': <String>[
      '在客户端本机生成独立 Ed25519 密钥；不要复制其他设备私钥。',
      '先人工核对 host key 指纹，再连接 vibekits-windows-node。',
      '私钥只保留在来源设备，onboarding 包不包含密码或私钥。',
    ],
  };
}

class WindowsNodeDeviceService {
  WindowsNodeDeviceService({
    Directory? directory,
    DateTime Function()? clock,
    Random? random,
  }) : _directory = directory ?? _defaultDirectory(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Directory _directory;
  final DateTime Function() _clock;
  final Random _random;

  File get registryFile => File(
    '${_directory.path}${Platform.pathSeparator}windows-node-devices.json',
  );

  Future<List<WindowsNodeDevice>> list() async {
    final File file = registryFile;
    if (!await file.exists()) return const <WindowsNodeDevice>[];
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> || decoded['devices'] is! List) {
      throw const FormatException('设备注册表格式无效');
    }
    final List<WindowsNodeDevice> devices = <WindowsNodeDevice>[
      for (final Object? item in decoded['devices']! as List<Object?>)
        if (item is Map)
          WindowsNodeDevice.fromJson(
            item.map(
              (dynamic key, dynamic value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          ),
    ];
    devices.sort(
      (WindowsNodeDevice left, WindowsNodeDevice right) =>
          left.label.toLowerCase().compareTo(right.label.toLowerCase()),
    );
    return List<WindowsNodeDevice>.unmodifiable(devices);
  }

  Future<WindowsNodeDevice> enroll({
    required String label,
    required String publicKey,
  }) async {
    final String safeLabel = _validateLabel(label);
    final _ParsedEd25519Key parsed = _parseEd25519(publicKey);
    final List<WindowsNodeDevice> devices = List<WindowsNodeDevice>.of(
      await list(),
    );
    if (devices.any(
      (WindowsNodeDevice item) => item.fingerprint == parsed.fingerprint,
    )) {
      throw const FormatException('该设备公钥指纹已登记，禁止重复或复用私钥');
    }
    final WindowsNodeDevice device = WindowsNodeDevice(
      id: _randomId(),
      label: safeLabel,
      publicKey: parsed.normalized,
      fingerprint: parsed.fingerprint,
      status: WindowsNodeDeviceStatus.active,
      enrolledAt: _clock(),
    );
    devices.add(device);
    await _save(devices);
    return device;
  }

  Future<WindowsNodeDevice> setEnabled(String id, {required bool enabled}) =>
      _update(
        id,
        (WindowsNodeDevice device) => device.copyWith(
          status: enabled
              ? WindowsNodeDeviceStatus.active
              : WindowsNodeDeviceStatus.disabled,
        ),
      );

  Future<WindowsNodeDevice> revoke(String id) => _update(
    id,
    (WindowsNodeDevice device) => device.copyWith(
      status: WindowsNodeDeviceStatus.revoked,
      revokedAt: _clock(),
    ),
  );

  Future<WindowsNodeDevice> recordConnection(String fingerprint) => _updateBy(
    (WindowsNodeDevice device) => device.fingerprint == fingerprint.trim(),
    (WindowsNodeDevice device) {
      if (device.status != WindowsNodeDeviceStatus.active) {
        throw const FormatException('设备已禁用或撤销，不能记录成功连接');
      }
      return device.copyWith(lastConnectedAt: _clock());
    },
  );

  Future<String> authorizedKeysContents() async => (await list())
      .where(
        (WindowsNodeDevice device) =>
            device.status == WindowsNodeDeviceStatus.active,
      )
      .map(
        (WindowsNodeDevice device) =>
            '${device.publicKey} vibekits:${device.id}:${_comment(device.label)}',
      )
      .join('\n');

  WindowsNodeOnboarding onboarding({
    required String host,
    required int port,
    required String hostKeyFingerprint,
    required String allowedCidr,
    String user = 'kemi-test',
  }) {
    if (host.trim().isEmpty || host.contains(RegExp(r'[\s/@]'))) {
      throw const FormatException('节点主机无效');
    }
    if (port < 1 || port > 65535) throw const FormatException('SSH 端口无效');
    if (!hostKeyFingerprint.startsWith('SHA256:')) {
      throw const FormatException('必须提供 SHA-256 host key 指纹');
    }
    if (!_privateCidr(allowedCidr)) {
      throw const FormatException('防火墙范围必须是私网 IPv4 /24 或更窄');
    }
    return WindowsNodeOnboarding(
      host: host.trim(),
      port: port,
      user: user,
      hostKeyFingerprint: hostKeyFingerprint,
      allowedCidr: allowedCidr,
    );
  }

  Future<WindowsNodeDevice> _update(
    String id,
    WindowsNodeDevice Function(WindowsNodeDevice) update,
  ) => _updateBy((WindowsNodeDevice device) => device.id == id.trim(), update);

  Future<WindowsNodeDevice> _updateBy(
    bool Function(WindowsNodeDevice) matches,
    WindowsNodeDevice Function(WindowsNodeDevice) update,
  ) async {
    final List<WindowsNodeDevice> devices = List<WindowsNodeDevice>.of(
      await list(),
    );
    final int index = devices.indexWhere(matches);
    if (index < 0) throw const FormatException('设备不存在');
    final WindowsNodeDevice changed = update(devices[index]);
    devices[index] = changed;
    await _save(devices);
    return changed;
  }

  Future<void> _save(List<WindowsNodeDevice> devices) async {
    await _directory.create(recursive: true);
    final File target = registryFile;
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': 1,
        'devices': devices
            .map((WindowsNodeDevice device) => device.toJson())
            .toList(growable: false),
      }),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  static _ParsedEd25519Key _parseEd25519(String input) {
    final List<String> fields = input.trim().split(RegExp(r'\s+'));
    if (fields.length < 2 || fields.first != 'ssh-ed25519') {
      throw const FormatException('只接受 OpenSSH Ed25519 公钥，不接受私钥或其他算法');
    }
    late final List<int> blob;
    try {
      blob = base64.decode(fields[1]);
    } on FormatException {
      throw const FormatException('Ed25519 公钥 Base64 无效');
    }
    int offset = 0;
    List<int> field() {
      if (offset + 4 > blob.length) throw const FormatException('公钥结构不完整');
      final int length =
          (blob[offset] << 24) |
          (blob[offset + 1] << 16) |
          (blob[offset + 2] << 8) |
          blob[offset + 3];
      offset += 4;
      if (length < 0 || offset + length > blob.length) {
        throw const FormatException('公钥字段长度无效');
      }
      final List<int> value = blob.sublist(offset, offset + length);
      offset += length;
      return value;
    }

    if (utf8.decode(field()) != 'ssh-ed25519' || field().length != 32) {
      throw const FormatException('Ed25519 公钥结构无效');
    }
    if (offset != blob.length) throw const FormatException('公钥包含多余数据');
    final String fingerprint = base64
        .encode(sha256.convert(blob).bytes)
        .replaceAll('=', '');
    return _ParsedEd25519Key(
      normalized: 'ssh-ed25519 ${fields[1]}',
      fingerprint: 'SHA256:$fingerprint',
    );
  }

  static String _validateLabel(String value) {
    final String label = value.trim();
    if (label.isEmpty ||
        label.length > 80 ||
        label.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('设备标签必须为 1～80 个字符');
    }
    return label;
  }

  static String _comment(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');

  static bool _privateCidr(String value) {
    final RegExpMatch? match = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)$')
        .firstMatch(value.trim());
    if (match == null) return false;
    final List<int> octets = <int>[
      for (int index = 1; index <= 4; index++) int.parse(match.group(index)!),
    ];
    final int prefix = int.parse(match.group(5)!);
    if (octets.any((int value) => value > 255) || prefix < 24 || prefix > 32) {
      return false;
    }
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  String _randomId() => base64Url
      .encode(List<int>.generate(18, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static Directory _defaultDirectory() {
    final String base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return Directory(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}node',
    );
  }
}

class _ParsedEd25519Key {
  const _ParsedEd25519Key({
    required this.normalized,
    required this.fingerprint,
  });

  final String normalized;
  final String fingerprint;
}
