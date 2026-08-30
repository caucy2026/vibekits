import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// Keep the suffix deliberately short: macOS sockaddr_un.sun_path is only
// about 104 bytes and the per-user Directory.systemTemp prefix is already
// long under /var/folders.
const String harnessStatusSocketName = 'v1.sock';
const String harnessStatusRuntimeDirectoryName = 'vkh';

abstract interface class HarnessStatusIpcConnection {
  Stream<List<int>> get input;

  String? get peerIdentity;

  void add(List<int> data);

  Future<void> flush();

  Future<void> close();

  void destroy();
}

abstract interface class HarnessStatusIpcListener {
  String get endpoint;

  String get localIdentity;

  Stream<HarnessStatusIpcConnection> get connections;

  Future<void> close();
}

/// Native/local transport boundary for the read-only Harness status publisher.
///
/// Windows must inject a named-pipe implementation that enforces a current-user
/// DACL and reports the connected SID through [peerIdentity]. The default is
/// deliberately unavailable; this API never falls back to TCP.
abstract interface class HarnessStatusIpcTransport {
  Future<HarnessStatusIpcListener> bind();
}

class HarnessStatusTransportUnavailable implements Exception {
  const HarnessStatusTransportUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'HarnessStatusTransportUnavailable: $reason';
}

class UnavailableHarnessStatusIpcTransport
    implements HarnessStatusIpcTransport {
  const UnavailableHarnessStatusIpcTransport(this.reason);

  final String reason;

  @override
  Future<HarnessStatusIpcListener> bind() =>
      Future<HarnessStatusIpcListener>.error(
        HarnessStatusTransportUnavailable(reason),
      );
}

abstract final class HarnessStatusIpcTransports {
  static HarnessStatusIpcTransport platformDefault({Directory? runtimeRoot}) {
    if (Platform.isMacOS || Platform.isLinux) {
      return UnixHarnessStatusIpcTransport(runtimeRoot: runtimeRoot);
    }
    if (Platform.isWindows) {
      return const UnavailableHarnessStatusIpcTransport(
        'Secure Windows named-pipe adapter is not installed',
      );
    }
    return UnavailableHarnessStatusIpcTransport(
      'Harness status IPC is unavailable on ${Platform.operatingSystem}',
    );
  }
}

class UnixHarnessStatusIpcTransport implements HarnessStatusIpcTransport {
  UnixHarnessStatusIpcTransport({this.runtimeRoot});

  final Directory? runtimeRoot;

  @override
  Future<HarnessStatusIpcListener> bind() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw const HarnessStatusTransportUnavailable(
        'Unix-domain sockets are unavailable on this platform',
      );
    }
    final int currentUid = _UnixPeerCredentials.currentUserId();
    final Directory root = runtimeRoot ?? _defaultRuntimeRoot();
    final Directory privateDirectory = Directory(
      '${root.path}${Platform.pathSeparator}'
      '$harnessStatusRuntimeDirectoryName',
    );
    await _ensurePrivateDirectory(privateDirectory);
    final String socketPath =
        '${privateDirectory.path}${Platform.pathSeparator}'
        '$harnessStatusSocketName';
    if (utf8Length(socketPath) >= (Platform.isMacOS ? 104 : 108)) {
      throw const HarnessStatusTransportUnavailable(
        'Unix-domain socket path is too long',
      );
    }
    await _removeStaleSocket(socketPath);

    final ServerSocket server;
    try {
      server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        shared: false,
      );
    } on Object catch (_) {
      throw const HarnessStatusTransportUnavailable(
        'Unable to bind the protected Unix-domain socket',
      );
    }
    try {
      await _chmod(socketPath, '600');
      final FileStat socketStat = await FileStat.stat(socketPath);
      if (socketStat.type != FileSystemEntityType.unixDomainSock ||
          socketStat.mode & 0x1ff != 0x180) {
        throw const HarnessStatusTransportUnavailable(
          'Unix-domain socket permissions are not 0600',
        );
      }
      return _UnixHarnessStatusIpcListener(
        server: server,
        socketPath: socketPath,
        currentUid: currentUid,
      );
    } on Object {
      await server.close();
      await _deleteSocketIfOwned(socketPath);
      rethrow;
    }
  }

  Directory _defaultRuntimeRoot() => Directory.systemTemp;

  Future<void> _ensurePrivateDirectory(Directory directory) async {
    final FileSystemEntityType before = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (before == FileSystemEntityType.notFound) {
      await directory.create();
    } else if (before != FileSystemEntityType.directory) {
      throw const HarnessStatusTransportUnavailable(
        'Harness status runtime path is not a directory',
      );
    }
    await _chmod(directory.path, '700');
    final FileStat stat = await directory.stat();
    if (stat.type != FileSystemEntityType.directory ||
        stat.mode & 0x1ff != 0x1c0) {
      throw const HarnessStatusTransportUnavailable(
        'Harness status runtime directory permissions are not 0700',
      );
    }
  }

  Future<void> _removeStaleSocket(String path) async {
    final FileSystemEntityType type = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.unixDomainSock) {
      throw const HarnessStatusTransportUnavailable(
        'Harness status endpoint is not a Unix-domain socket',
      );
    }
    try {
      final Socket socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 100),
      );
      socket.destroy();
      throw const HarnessStatusTransportUnavailable(
        'Another Harness status publisher is already running',
      );
    } on HarnessStatusTransportUnavailable {
      rethrow;
    } on Object {
      await File(path).delete();
    }
  }

  static Future<void> _chmod(String path, String mode) async {
    final ProcessResult result = await Process.run('chmod', <String>[
      mode,
      path,
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw const HarnessStatusTransportUnavailable(
        'Unable to protect Harness status IPC permissions',
      );
    }
  }

  static Future<void> _deleteSocketIfOwned(String path) async {
    final FileSystemEntityType type = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.unixDomainSock) {
      await File(path).delete();
    }
  }
}

class _UnixHarnessStatusIpcListener implements HarnessStatusIpcListener {
  _UnixHarnessStatusIpcListener({
    required ServerSocket server,
    required this.socketPath,
    required this.currentUid,
  }) : _server = server,
       _connections = server.map(_wrap);

  final ServerSocket _server;
  final String socketPath;
  final int currentUid;
  final Stream<HarnessStatusIpcConnection> _connections;
  bool _closed = false;

  static HarnessStatusIpcConnection _wrap(Socket socket) =>
      _UnixHarnessStatusIpcConnection(socket);

  @override
  String get endpoint => socketPath;

  @override
  String get localIdentity => currentUid.toString();

  @override
  Stream<HarnessStatusIpcConnection> get connections => _connections;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    await UnixHarnessStatusIpcTransport._deleteSocketIfOwned(socketPath);
  }
}

class _UnixHarnessStatusIpcConnection implements HarnessStatusIpcConnection {
  _UnixHarnessStatusIpcConnection(this._socket)
    : peerIdentity = _UnixPeerCredentials.peerUserId(_socket)?.toString();

  final Socket _socket;

  @override
  final String? peerIdentity;

  @override
  Stream<List<int>> get input => _socket;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  void destroy() => _socket.destroy();
}

abstract final class _UnixPeerCredentials {
  static int currentUserId() {
    final DynamicLibrary process = DynamicLibrary.process();
    final int Function() getuid = process
        .lookupFunction<Uint32 Function(), int Function()>('getuid');
    return getuid();
  }

  static int? peerUserId(Socket socket) {
    try {
      if (Platform.isMacOS) {
        // sys/un.h: SOL_LOCAL=0, LOCAL_PEERCRED=1. xucred.cr_uid is
        // the second uint32 in the returned structure.
        final Uint8List value = socket.getRawOption(
          RawSocketOption(0, 1, Uint8List(76)),
        );
        if (value.length < 8) return null;
        return ByteData.sublistView(value).getUint32(4, Endian.host);
      }
      if (Platform.isLinux) {
        // SOL_SOCKET=1, SO_PEERCRED=17. struct ucred is pid, uid, gid.
        final Uint8List value = socket.getRawOption(
          RawSocketOption(1, 17, Uint8List(12)),
        );
        if (value.length < 12) return null;
        return ByteData.sublistView(value).getUint32(4, Endian.host);
      }
    } on Object {
      return null;
    }
    return null;
  }
}

int utf8Length(String value) => utf8.encode(value).length;
