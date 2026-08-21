import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef SystemProxyProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class SystemProxySnapshot {
  const SystemProxySnapshot({
    required this.enabled,
    required this.server,
    required this.bypass,
  });

  final bool enabled;
  final String? server;
  final String? bypass;

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'server': server,
    'bypass': bypass,
  };

  factory SystemProxySnapshot.fromJson(Map<String, Object?> value) =>
      SystemProxySnapshot(
        enabled: value['enabled'] == true,
        server: value['server']?.toString(),
        bypass: value['bypass']?.toString(),
      );
}

class SystemProxyService {
  SystemProxyService({SystemProxyProcessRunner? runner})
    : _runner = runner ?? _run;

  static const String _key =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  final SystemProxyProcessRunner _runner;

  Future<SystemProxySnapshot> inspect() async {
    _requireWindows();
    final String? enabled = await _readValue('ProxyEnable');
    return SystemProxySnapshot(
      enabled: enabled == '0x1' || enabled == '1',
      server: await _readValue('ProxyServer'),
      bypass: await _readValue('ProxyOverride'),
    );
  }

  Future<SystemProxySnapshot> applyLocal({
    required int port,
    required String dataDirectory,
  }) async {
    _requireWindows();
    if (port < 1 || port > 65535) throw const FormatException('代理端口无效');
    final Directory data = _absoluteDataDirectory(dataDirectory);
    await data.create(recursive: true);
    final File backup = File(
      '${data.path}${Platform.pathSeparator}system-proxy-backup.json',
    );
    final SystemProxySnapshot previous = await inspect();
    if (!await backup.exists()) {
      final File temporary = File('${backup.path}.tmp');
      await temporary.writeAsString(jsonEncode(previous.toJson()), flush: true);
      await temporary.rename(backup.path);
    }
    try {
      await _setDword('ProxyEnable', 1);
      await _setString('ProxyServer', '127.0.0.1:$port');
      await _setString('ProxyOverride', '<local>');
      _notifyWindows();
      return await inspect();
    } on Object {
      await _applySnapshot(previous);
      rethrow;
    }
  }

  Future<SystemProxySnapshot> restore({required String dataDirectory}) async {
    _requireWindows();
    final File backup = File(
      '${_absoluteDataDirectory(dataDirectory).path}${Platform.pathSeparator}system-proxy-backup.json',
    );
    if (!await backup.exists()) return inspect();
    final Object? decoded = jsonDecode(await backup.readAsString());
    if (decoded is! Map) throw const FormatException('系统代理备份已损坏');
    final SystemProxySnapshot snapshot = SystemProxySnapshot.fromJson(
      decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
    );
    await _applySnapshot(snapshot);
    await backup.delete();
    return inspect();
  }

  Future<void> _applySnapshot(SystemProxySnapshot snapshot) async {
    await _setDword('ProxyEnable', snapshot.enabled ? 1 : 0);
    await _setOrDelete('ProxyServer', snapshot.server);
    await _setOrDelete('ProxyOverride', snapshot.bypass);
    _notifyWindows();
  }

  Future<String?> _readValue(String name) async {
    final ProcessResult result = await _runner('reg.exe', <String>[
      'query',
      _key,
      '/v',
      name,
    ]);
    if (result.exitCode != 0) return null;
    final RegExpMatch? match = RegExp(
      '^\\s*${RegExp.escape(name)}\\s+REG_\\w+\\s+(.*?)\\s*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch('${result.stdout}');
    return match?.group(1)?.trim();
  }

  Future<void> _setDword(String name, int value) => _requireSuccess(<String>[
    'add',
    _key,
    '/v',
    name,
    '/t',
    'REG_DWORD',
    '/d',
    '$value',
    '/f',
  ]);

  Future<void> _setString(String name, String value) => _requireSuccess(
    <String>['add', _key, '/v', name, '/t', 'REG_SZ', '/d', value, '/f'],
  );

  Future<void> _setOrDelete(String name, String? value) async {
    if (value == null || value.isEmpty) {
      await _runner('reg.exe', <String>['delete', _key, '/v', name, '/f']);
    } else {
      await _setString(name, value);
    }
  }

  Future<void> _requireSuccess(List<String> arguments) async {
    final ProcessResult result = await _runner('reg.exe', arguments);
    if (result.exitCode != 0) throw StateError('修改系统代理失败：${result.stderr}');
  }

  static void _notifyWindows() {
    if (!Platform.isWindows) return;
    final DynamicLibrary wininet = DynamicLibrary.open('wininet.dll');
    final int Function(Pointer<Void>, int, Pointer<Void>, int) option = wininet
        .lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32),
          int Function(Pointer<Void>, int, Pointer<Void>, int)
        >('InternetSetOptionW');
    option(nullptr, 39, nullptr, 0);
    option(nullptr, 37, nullptr, 0);
  }

  static void _requireWindows() {
    if (!Platform.isWindows) throw UnsupportedError('系统代理切换当前仅支持 Windows');
  }

  static Directory _absoluteDataDirectory(String value) {
    final String path = value.trim();
    final Directory directory = Directory(path);
    if (path.isEmpty || !directory.isAbsolute) {
      throw const FormatException('代理数据目录必须是绝对路径');
    }
    return directory;
  }

  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);
}
