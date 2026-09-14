import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

typedef SimulatorUpdateProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

final class SimulatorUpdateCandidate {
  const SimulatorUpdateCandidate({
    required this.token,
    required this.packagePath,
    required this.fileName,
    required this.bytes,
    required this.sha256,
    required this.receivedAt,
  });

  final String token;
  final String packagePath;
  final String fileName;
  final int bytes;
  final String sha256;
  final DateTime receivedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'staged': true,
    'token': token,
    'fileName': fileName,
    'bytes': bytes,
    'sha256': sha256,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
  };
}

final class _SimulatorUpdateIntent {
  const _SimulatorUpdateIntent({
    required this.token,
    required this.fileName,
    required this.bytes,
    required this.sha256,
    required this.expiresAt,
  });

  final String token;
  final String fileName;
  final int bytes;
  final String sha256;
  final DateTime expiresAt;
}

/// Receives and applies a VibeKits macOS candidate through the already
/// authorized simulator tunnel. This is deliberately not a general file-write
/// or shell surface: only a bounded ZIP can be staged, and apply accepts only
/// a newer Universal VibeKits bundle signed by the same Developer ID team.
final class SimulatorUpdateService {
  SimulatorUpdateService({
    Directory? stagingRoot,
    SimulatorUpdateProcessRunner? processRunner,
    String Function()? currentBundlePath,
  }) : _stagingRoot = stagingRoot,
       _processRunner = processRunner ?? Process.run,
       _currentBundlePath = currentBundlePath ?? _resolveCurrentBundlePath;

  static final SimulatorUpdateService instance = SimulatorUpdateService();
  static const int maxPackageBytes = 1536 * 1024 * 1024;
  static const String uploadPath = '/vibekits-simulator/v1/update';

  final Directory? _stagingRoot;
  final SimulatorUpdateProcessRunner _processRunner;
  final String Function() _currentBundlePath;
  SimulatorUpdateCandidate? _latest;
  _SimulatorUpdateIntent? _pending;
  bool _receiving = false;
  bool _applying = false;

  Future<Map<String, Object?>> begin({
    required int expectedBytes,
    required String expectedSha256,
    required String fileName,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('仿真机自升级当前仅支持 macOS');
    }
    if (_receiving || _applying) throw StateError('已有候选正在处理');
    final String checksum = expectedSha256.trim().toLowerCase();
    final String safeName = _validateMetadata(
      expectedBytes: expectedBytes,
      expectedSha256: checksum,
      fileName: fileName,
    );
    final Random random = Random.secure();
    final String token = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final DateTime expiresAt = DateTime.now().add(const Duration(minutes: 5));
    _pending = _SimulatorUpdateIntent(
      token: token,
      fileName: safeName,
      bytes: expectedBytes,
      sha256: checksum,
      expiresAt: expiresAt,
    );
    return <String, Object?>{
      'accepted': true,
      'uploadToken': token,
      'uploadPath': uploadPath,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  Future<Map<String, Object?>> receive({
    required Stream<List<int>> stream,
    required String uploadToken,
    required int contentLength,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('仿真机自升级当前仅支持 macOS');
    }
    if (_receiving || _applying) throw StateError('已有候选正在处理');
    final intent = _pending;
    _pending = null;
    if (intent == null ||
        uploadToken.trim() != intent.token ||
        DateTime.now().isAfter(intent.expiresAt)) {
      throw const FormatException('上传令牌无效或已过期');
    }
    final int expectedBytes = intent.bytes;
    final String checksum = intent.sha256;
    final String safeName = intent.fileName;
    if (contentLength != expectedBytes) {
      throw const FormatException('HTTP Content-Length 与候选声明不一致');
    }
    _receiving = true;
    final Directory root =
        _stagingRoot ??
        Directory('${Directory.systemTemp.path}/vibekits-simulator-updates');
    await root.create(recursive: true);
    final String stagingId = '${DateTime.now().microsecondsSinceEpoch}';
    final File part = File('${root.path}/$stagingId.part');
    final File complete = File('${root.path}/$stagingId.zip');
    int received = 0;
    IOSink? sink;
    try {
      sink = part.openWrite(mode: FileMode.writeOnly);
      await for (final List<int> chunk in stream) {
        received += chunk.length;
        if (received > expectedBytes || received > maxPackageBytes) {
          throw const FormatException('候选包字节数超过声明');
        }
        sink.add(chunk);
      }
      await sink.close();
      sink = null;
      if (received != expectedBytes) {
        throw const FormatException('候选包字节数与声明不一致');
      }
      final String actual = (await sha256.bind(part.openRead()).first)
          .toString()
          .toLowerCase();
      if (actual != checksum) {
        throw const FormatException('候选包 SHA-256 校验失败');
      }
      if (await complete.exists()) await complete.delete();
      await part.rename(complete.path);
      final previous = _latest;
      _latest = SimulatorUpdateCandidate(
        token: intent.token,
        packagePath: complete.path,
        fileName: safeName,
        bytes: received,
        sha256: actual,
        receivedAt: DateTime.now(),
      );
      if (previous != null && previous.packagePath != complete.path) {
        final old = File(previous.packagePath);
        if (await old.exists()) await old.delete();
      }
      return _latest!.toJson();
    } finally {
      await sink?.close();
      if (await part.exists()) await part.delete();
      _receiving = false;
    }
  }

  Future<Map<String, Object?>> status() async => <String, Object?>{
    'platform': Platform.operatingSystem,
    'receiving': _receiving,
    'applying': _applying,
    'uploadIntentActive':
        _pending != null && DateTime.now().isBefore(_pending!.expiresAt),
    if (_latest case final candidate?) ...candidate.toJson(),
  };

  static String _validateMetadata({
    required int expectedBytes,
    required String expectedSha256,
    required String fileName,
  }) {
    if (expectedBytes <= 0 || expectedBytes > maxPackageBytes) {
      throw const FormatException('候选包大小超出允许范围');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw const FormatException('候选包 SHA-256 无效');
    }
    final String safeName = fileName.trim();
    if (!RegExp(r'^[A-Za-z0-9._+-]{1,160}\.zip$').hasMatch(safeName)) {
      throw const FormatException('候选包必须是安全命名的 ZIP');
    }
    return safeName;
  }

  Future<Map<String, Object?>> apply({required String token}) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('仿真机自升级当前仅支持 macOS');
    }
    if (_applying || _receiving) throw StateError('候选包仍在处理中');
    final candidate = _latest;
    if (candidate == null || token.trim() != candidate.token) {
      throw const FormatException('候选令牌无效或已过期');
    }
    _applying = true;
    try {
      final String currentBundle = _currentBundlePath();
      final Directory current = Directory(currentBundle);
      if (!currentBundle.endsWith('.app') || !await current.exists()) {
        throw StateError('当前 VibeKits App 路径无效');
      }
      final Directory parent = current.parent;
      final File writeProbe = File('${parent.path}/.vibekits-write-probe');
      try {
        await writeProbe.writeAsString('probe', flush: true);
      } finally {
        if (await writeProbe.exists()) await writeProbe.delete();
      }

      final Directory extractRoot = Directory(
        '${candidate.packagePath.substring(0, candidate.packagePath.length - 4)}-extract',
      );
      if (await extractRoot.exists()) await extractRoot.delete(recursive: true);
      await extractRoot.create(recursive: true);
      await _validateArchiveEntries(currentBundle, candidate.packagePath);
      final ProcessResult extracted = await _processRunner(
        '/usr/bin/ditto',
        <String>['-x', '-k', candidate.packagePath, extractRoot.path],
      );
      if (extracted.exitCode != 0) {
        throw StateError('候选包解压失败：${extracted.stderr}');
      }
      final List<Directory> bundles = await extractRoot
          .list(recursive: false, followLinks: false)
          .where(
            (entity) => entity is Directory && entity.path.endsWith('.app'),
          )
          .cast<Directory>()
          .toList();
      if (bundles.length != 1) throw StateError('候选包必须只包含一个 App');
      final String replacement = bundles.single.path;
      final Map<String, Object?> identity = await _validateReplacement(
        currentBundle,
        replacement,
      );
      final int oldBuild = identity['oldBuild']! as int;
      final int newBuild = identity['newBuild']! as int;
      final String suffix = candidate.token;
      final String incoming = '${parent.path}/.Vibekits-update-$suffix.app';
      final String backup =
          '${parent.path}/.Vibekits-rollback-$oldBuild-$suffix.app';
      final String scriptPath = '${extractRoot.path}/apply-update.sh';
      final File script = File(scriptPath);
      await script.writeAsString(_updaterScript, flush: true);
      await _processRunner('/bin/chmod', <String>['700', scriptPath]);
      await Process.start('/bin/sh', <String>[
        scriptPath,
        '$pid',
        currentBundle,
        replacement,
        incoming,
        backup,
      ], mode: ProcessStartMode.detached);
      return <String, Object?>{
        'scheduled': true,
        'oldBuild': oldBuild,
        'newBuild': newBuild,
        'teamIdentifier': identity['teamIdentifier'],
        'message': '签名候选已验证，正在后台替换并重启 VibeKits',
      };
    } finally {
      _applying = false;
    }
  }

  Future<Map<String, Object?>> _validateReplacement(
    String currentBundle,
    String replacement,
  ) async {
    Future<String> plist(String bundle, String key) async {
      final result = await _processRunner('/usr/libexec/PlistBuddy', <String>[
        '-c',
        'Print :$key',
        '$bundle/Contents/Info.plist',
      ]);
      if (result.exitCode != 0) throw StateError('候选 App 元数据无效');
      return '${result.stdout}'.trim();
    }

    final String oldId = await plist(currentBundle, 'CFBundleIdentifier');
    final String newId = await plist(replacement, 'CFBundleIdentifier');
    if (oldId != newId || oldId != 'com.caucy.vibekits') {
      throw StateError('候选 App 包名不匹配');
    }
    final int? oldBuild = int.tryParse(
      await plist(currentBundle, 'CFBundleVersion'),
    );
    final int? newBuild = int.tryParse(
      await plist(replacement, 'CFBundleVersion'),
    );
    if (oldBuild == null || newBuild == null || newBuild <= oldBuild) {
      throw StateError('候选版本必须高于当前版本');
    }
    final ProcessResult verified = await _processRunner(
      '/usr/bin/codesign',
      <String>['--verify', '--deep', '--strict', '--verbose=2', replacement],
    );
    if (verified.exitCode != 0) throw StateError('候选 App 签名验证失败');
    Future<String> team(String bundle) async {
      final result = await _processRunner('/usr/bin/codesign', <String>[
        '-d',
        '--verbose=4',
        bundle,
      ]);
      final text = '${result.stdout}\n${result.stderr}';
      return RegExp(r'TeamIdentifier=([A-Z0-9]+)').firstMatch(text)?.group(1) ??
          '';
    }

    final String oldTeam = await team(currentBundle);
    final String newTeam = await team(replacement);
    if (oldTeam.isEmpty || newTeam != oldTeam) {
      throw StateError('候选 App Developer ID 团队不匹配');
    }
    final String executable = await plist(replacement, 'CFBundleExecutable');
    final String executablePath = '$replacement/Contents/MacOS/$executable';
    final File executableFile = File(executablePath);
    final RandomAccessFile reader = await executableFile.open();
    late final Uint8List machOHeader;
    try {
      machOHeader = await reader.read(
        (await executableFile.length()).clamp(0, 4096),
      );
    } finally {
      await reader.close();
    }
    final Set<int> cpuTypes = parseUniversalMachOCpuTypes(machOHeader);
    if (!cpuTypes.contains(0x01000007) || !cpuTypes.contains(0x0100000c)) {
      throw StateError('候选 App 不是 Intel/Apple Silicon Universal');
    }
    final Match? minimumSystem = RegExp(
      r'^(\d+)\.(\d+)',
    ).firstMatch(await plist(replacement, 'LSMinimumSystemVersion'));
    if (minimumSystem == null ||
        int.parse(minimumSystem.group(1)!) > 12 ||
        (int.parse(minimumSystem.group(1)!) == 12 &&
            int.parse(minimumSystem.group(2)!) > 0)) {
      throw StateError('候选 App 不满足 macOS 12+ 兼容门禁');
    }
    return <String, Object?>{
      'oldBuild': oldBuild,
      'newBuild': newBuild,
      'teamIdentifier': newTeam,
    };
  }

  /// Reads CPU types from a Mach-O fat header without requiring Xcode command
  /// line tools. Clean user Macs expose `/usr/bin/lipo` as an installer shim.
  static Set<int> parseUniversalMachOCpuTypes(Uint8List bytes) {
    if (bytes.length < 8) return const <int>{};
    final ByteData data = ByteData.sublistView(bytes);
    final int bigMagic = data.getUint32(0, Endian.big);
    final bool bigEndian;
    final int entrySize;
    if (bigMagic == 0xcafebabe) {
      bigEndian = true;
      entrySize = 20;
    } else if (bigMagic == 0xcafebabf) {
      bigEndian = true;
      entrySize = 32;
    } else if (bigMagic == 0xbebafeca) {
      bigEndian = false;
      entrySize = 20;
    } else if (bigMagic == 0xbfbafeca) {
      bigEndian = false;
      entrySize = 32;
    } else {
      return const <int>{};
    }
    final Endian endian = bigEndian ? Endian.big : Endian.little;
    final int count = data.getUint32(4, endian);
    if (count == 0 || count > 64 || 8 + count * entrySize > bytes.length) {
      return const <int>{};
    }
    return Set<int>.unmodifiable(<int>{
      for (int index = 0; index < count; index++)
        data.getUint32(8 + index * entrySize, endian),
    });
  }

  Future<void> _validateArchiveEntries(
    String currentBundle,
    String packagePath,
  ) async {
    final String sevenZip = '$currentBundle/Contents/Resources/tools/7zip/7zz';
    if (!await File(sevenZip).exists()) {
      throw StateError('内置 7-Zip 缺失，不能安全检查候选包');
    }
    final ProcessResult listed = await _processRunner(sevenZip, <String>[
      'l',
      '-slt',
      packagePath,
    ]);
    if (listed.exitCode != 0) throw StateError('候选 ZIP 目录读取失败');
    final List<String> paths = '${listed.stdout}'
        .split('\n')
        .where((String line) => line.startsWith('Path = '))
        .map((String line) => line.substring(7).trim())
        .where((String path) => path != packagePath && path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty ||
        paths.any(
          (String path) =>
              path != 'Vibekits.app' && !path.startsWith('Vibekits.app/'),
        )) {
      throw StateError('候选 ZIP 条目必须全部位于 Vibekits.app 根目录');
    }
    if (paths.any((String path) => path.split('/').contains('..'))) {
      throw StateError('候选 ZIP 包含不安全路径');
    }
  }

  static String _resolveCurrentBundlePath() {
    Directory current = File(Platform.resolvedExecutable).absolute.parent;
    while (current.parent.path != current.path) {
      if (current.path.endsWith('.app')) return current.path;
      current = current.parent;
    }
    throw StateError('无法定位当前 VibeKits App');
  }

  static const String _updaterScript = r'''#!/bin/sh
set -eu
old_pid="$1"
current="$2"
replacement="$3"
incoming="$4"
backup="$5"

/usr/bin/ditto "$replacement" "$incoming"
/bin/sleep 2
/bin/kill -TERM "$old_pid" 2>/dev/null || true
attempt=0
while /bin/kill -0 "$old_pid" 2>/dev/null && [ "$attempt" -lt 80 ]; do
  /bin/sleep 0.1
  attempt=$((attempt + 1))
done
if /bin/kill -0 "$old_pid" 2>/dev/null; then
  /bin/kill -KILL "$old_pid" 2>/dev/null || true
fi
/bin/mv "$current" "$backup"
if ! /bin/mv "$incoming" "$current"; then
  /bin/mv "$backup" "$current"
  exit 1
fi
if ! /usr/bin/open -g "$current"; then
  /bin/rm -rf "$current"
  /bin/mv "$backup" "$current"
  /usr/bin/open -g "$current" || true
  exit 1
fi
''';
}
