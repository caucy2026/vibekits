import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'remote_session.dart';

class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modifiedEpochSeconds,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final int? modifiedEpochSeconds;
}

class SftpTransferCancelled implements Exception {
  const SftpTransferCancelled();

  @override
  String toString() => '传输已取消';
}

class SftpCancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancelledCompleter = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelledCompleter.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledCompleter.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const SftpTransferCancelled();
  }
}

abstract interface class RemoteFileClient {
  Future<String> absolute(String path);
  Future<List<RemoteFileEntry>> listDirectory(String path);
  Future<void> upload(
    String localPath,
    String remotePath, {
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  });
  Future<void> download(
    String remotePath,
    String localPath, {
    required int total,
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  });
  Future<void> close();
}

abstract final class RemoteFileService {
  static Future<RemoteFileClient> connect(
    RemoteConnectionProfile profile, {
    String? secret,
    required RemoteHostKeyVerifier verifyHostKey,
  }) async {
    final SSHClient ssh = await RemoteSshConnector.connect(
      profile,
      secret: secret,
      verifyHostKey: verifyHostKey,
    );
    try {
      final SftpClient sftp = await ssh.sftp();
      return _DartSftpClient(ssh, sftp);
    } on Object {
      ssh.close();
      rethrow;
    }
  }
}

class _DartSftpClient implements RemoteFileClient {
  _DartSftpClient(this._ssh, this._sftp);

  final SSHClient _ssh;
  final SftpClient _sftp;
  bool _closed = false;

  @override
  Future<String> absolute(String path) => _sftp.absolute(path);

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async {
    final String canonical = await _sftp.absolute(path);
    final List<SftpName> names = await _sftp.listdir(canonical);
    final List<RemoteFileEntry> result = names
        .where((SftpName item) => item.filename != '.' && item.filename != '..')
        .map(
          (SftpName item) => RemoteFileEntry(
            name: item.filename,
            path: _joinRemote(canonical, item.filename),
            isDirectory: item.attr.isDirectory,
            size: item.attr.size ?? 0,
            modifiedEpochSeconds: item.attr.modifyTime,
          ),
        )
        .toList(growable: false);
    result.sort((RemoteFileEntry a, RemoteFileEntry b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    cancellation.throwIfCancelled();
    final File source = File(localPath);
    final FileStat sourceStat = await source.stat();
    if (sourceStat.type != FileSystemEntityType.file) {
      throw const FileSystemException('本地源不是普通文件');
    }
    _validateRemotePath(remotePath);
    final String temporary =
        '$remotePath.vibekits-part-${DateTime.now().microsecondsSinceEpoch}';
    SftpFile? remote;
    SftpFileWriter? writer;
    try {
      remote = await _sftp.open(
        temporary,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      writer = remote.write(
        source.openRead().map(Uint8List.fromList),
        onProgress: (int bytes) => onProgress(bytes, sourceStat.size),
      );
      final bool cancelled = await Future.any<bool>(<Future<bool>>[
        writer.done.then((_) => false),
        cancellation.whenCancelled.then((_) => true),
      ]);
      if (cancelled) {
        await writer.abort();
        throw const SftpTransferCancelled();
      }
      cancellation.throwIfCancelled();
      await remote.close();
      remote = null;
      try {
        await _sftp.rename(temporary, remotePath);
      } on SftpStatusError {
        if (!overwrite) rethrow;
        await _sftp.remove(remotePath);
        await _sftp.rename(temporary, remotePath);
      }
      onProgress(sourceStat.size, sourceStat.size);
    } on Object {
      if (writer != null && cancellation.isCancelled) await writer.abort();
      await remote?.close();
      try {
        await _sftp.remove(temporary);
      } on Object {
        // The temporary may not have been created or the connection may be gone.
      }
      rethrow;
    }
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    required int total,
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    cancellation.throwIfCancelled();
    _validateRemotePath(remotePath);
    final File destination = File(localPath);
    final File temporary = File('$localPath.vibekits.part');
    await temporary.parent.create(recursive: true);
    SftpFile? remote;
    IOSink? sink;
    StreamSubscription<Uint8List>? subscription;
    final Completer<void> streamDone = Completer<void>();
    int bytes = 0;
    try {
      remote = await _sftp.open(remotePath, mode: SftpFileOpenMode.read);
      sink = temporary.openWrite(mode: FileMode.writeOnly);
      subscription = remote
          .read(maxPendingRequests: 4)
          .listen(
            (Uint8List chunk) {
              sink!.add(chunk);
              bytes += chunk.length;
              onProgress(bytes, total);
            },
            onError: streamDone.completeError,
            onDone: streamDone.complete,
            cancelOnError: true,
          );
      final bool cancelled = await Future.any<bool>(<Future<bool>>[
        streamDone.future.then((_) => false),
        cancellation.whenCancelled.then((_) => true),
      ]);
      if (cancelled) {
        await subscription.cancel();
        throw const SftpTransferCancelled();
      }
      cancellation.throwIfCancelled();
      await sink.flush();
      await sink.close();
      sink = null;
      await remote.close();
      remote = null;
      if (overwrite && await destination.exists()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
      onProgress(bytes, total);
    } on Object {
      await subscription?.cancel();
      await sink?.close();
      await remote?.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sftp.close();
    _ssh.close();
  }
}

String _joinRemote(String directory, String name) =>
    directory == '/' ? '/$name' : '$directory/$name';

void _validateRemotePath(String path) {
  if (path.isEmpty || path.codeUnits.any((int unit) => unit == 0)) {
    throw const FormatException('远端路径无效');
  }
}
