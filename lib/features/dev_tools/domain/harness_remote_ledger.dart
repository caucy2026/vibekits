import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'harness_remote_commands.dart';

/// An append-only, exclusively locked journal in the application's private data
/// directory. A persisted claim always precedes execution. An interrupted claim
/// is UNKNOWN, never permission to execute the same command again.
class HarnessRemoteLedger {
  HarnessRemoteLedger._(this._file, this.capacity);

  final RandomAccessFile _file;
  final int capacity;
  final Map<String, Map<String, dynamic>> _entries = {};
  final Map<String, Future<Map<String, dynamic>>> _running = {};
  Future<void> _writes = Future.value();
  bool _closed = false;
  bool _broken = false;
  Future<void>? _closing;
  static const maxJournalBytes = 64 * 1024 * 1024;

  static Future<HarnessRemoteLedger> open(
    File file, {
    int capacity = 4096,
  }) async {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
    // The caller owns provisioning the private directory. Never create an
    // arbitrary caller-supplied parent or follow a journal symlink.
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('REMOTE_LEDGER_NOT_REGULAR_FILE');
    }
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      final ledger = HarnessRemoteLedger._(handle, capacity);
      final size = await handle.length();
      if (size > maxJournalBytes) throw StateError('REMOTE_LEDGER_TOO_LARGE');
      // Use the locked handle itself: a second handle cannot read an exclusive
      // byte-range lock on Windows, even from the same process.
      await handle.setPosition(0);
      final data = utf8.decode(await handle.read(size));
      await handle.setPosition(size);
      if (data.isNotEmpty && !data.endsWith('\n')) {
        throw StateError('REMOTE_LEDGER_INCOMPLETE_RECORD');
      }
      for (final line in const LineSplitter().convert(data)) {
        final row = jsonDecode(line);
        if (row is! Map<String, dynamic> ||
            row['key'] is! String ||
            row['fingerprint'] is! String ||
            !const ['pending', 'complete', 'unknown'].contains(row['state'])) {
          throw const FormatException('Invalid remote ledger record');
        }
        final key = row['key'] as String;
        final previous = ledger._entries[key];
        if (row['state'] == 'pending') {
          if (previous != null) {
            throw StateError('REMOTE_LEDGER_DUPLICATE_CLAIM');
          }
        } else if (previous == null ||
            previous['state'] != 'pending' ||
            previous['fingerprint'] != row['fingerprint']) {
          throw StateError('REMOTE_LEDGER_INVALID_TRANSITION');
        }
        if (row['state'] == 'complete' &&
            row['result'] is! Map<String, dynamic>) {
          throw const FormatException('Invalid remote ledger result');
        }
        ledger._entries[key] = row;
      }
      if (ledger._entries.length > capacity) {
        throw StateError('REMOTE_COMMAND_LEDGER_FULL');
      }
      return ledger;
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  Future<void> _append(Map<String, dynamic> row) {
    final bytes = utf8.encode('${jsonEncode(row)}\n');
    final operation = _writes.then((_) async {
      if (_broken || await _file.length() + bytes.length > maxJournalBytes) {
        throw StateError('REMOTE_LEDGER_WRITE_UNAVAILABLE');
      }
      await _file.writeFrom(bytes);
      await _file.flush();
    });
    _writes = operation.catchError((Object _) {
      _broken = true;
    });
    return operation;
  }

  /// Authorization must be checked by the caller on EVERY invocation, including
  /// cached replies. The journal never stores keys, tokens or raw arguments.
  Future<Map<String, dynamic>> execute(
    String peerId,
    HarnessRemoteCommand command,
    Future<Map<String, Object?>> Function() action,
  ) async {
    if (_closed || _broken) throw StateError('REMOTE_LEDGER_UNAVAILABLE');
    final key = sha256
        .convert(utf8.encode(jsonEncode([peerId, command.id])))
        .toString();
    final fingerprint = sha256
        .convert(utf8.encode(command.fingerprint))
        .toString();
    final previous = _entries[key];
    if (previous != null) {
      if (previous['fingerprint'] != fingerprint) {
        throw StateError('REMOTE_COMMAND_ID_CONFLICT');
      }
      final running = _running[key];
      if (running != null) return _copy(await running);
      if (previous['state'] == 'complete') {
        return _copy(previous['result'] as Map<String, dynamic>);
      }
      throw StateError('REMOTE_OUTCOME_UNKNOWN');
    }
    if (_entries.length >= capacity) {
      throw StateError('REMOTE_COMMAND_LEDGER_FULL');
    }
    final pending = <String, dynamic>{
      'key': key,
      'fingerprint': fingerprint,
      'state': 'pending',
    };
    final done = Completer<Map<String, dynamic>>();
    _entries[key] = pending;
    _running[key] = done.future;
    unawaited(() async {
      try {
        await _append(pending);
        final result = _copy(await action());
        final complete = {...pending, 'state': 'complete', 'result': result};
        await _append(complete);
        _entries[key] = complete;
        done.complete(result);
      } catch (error, stack) {
        // Pending already blocks replay after crash or failed result commit.
        if (!_broken) {
          try {
            final unknown = {...pending, 'state': 'unknown'};
            await _append(unknown);
            _entries[key] = unknown;
          } catch (_) {
            /* fail closed, keep the durable claim */
          }
        }
        done.completeError(error, stack);
      } finally {
        _running.remove(key);
      }
    }());
    return _copy(await done.future);
  }

  static Map<String, dynamic> _copy(Map<String, Object?> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // Never release the lock while a command may still commit its result.
    await Future.wait(
      _running.values.map(
        (future) => future.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      ),
    );
    await _writes;
    await _file.close();
  }
}
