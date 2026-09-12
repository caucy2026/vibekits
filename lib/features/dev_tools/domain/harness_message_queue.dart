import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

enum HarnessMessageMode { steering, queued, interrupt }

enum HarnessMessageSource { localUser, appMcp, localMcp, lanMcp, remotePeer }

enum HarnessQueueStatus {
  draft,
  queued,
  dispatching,
  running,
  completed,
  failed,
  cancelled,
  deleted,
}

class HarnessQueueItem {
  const HarnessQueueItem({
    required this.id,
    required this.sessionId,
    required this.workspaceId,
    required this.text,
    required this.mode,
    required this.source,
    required this.createdAt,
    required this.status,
    required this.attempt,
    this.approvedCallerId = '',
  });

  final String id;
  final String sessionId;
  final String workspaceId;
  final String text;
  final HarnessMessageMode mode;
  final HarnessMessageSource source;
  final DateTime createdAt;
  final HarnessQueueStatus status;
  final int attempt;
  final String approvedCallerId;

  String get idempotencyKey => '$sessionId:$id';
  bool get editable => status == HarnessQueueStatus.queued;

  HarnessQueueItem copyWith({
    String? text,
    HarnessQueueStatus? status,
    int? attempt,
  }) => HarnessQueueItem(
    id: id,
    sessionId: sessionId,
    workspaceId: workspaceId,
    text: text ?? this.text,
    mode: mode,
    source: source,
    createdAt: createdAt,
    status: status ?? this.status,
    attempt: attempt ?? this.attempt,
    approvedCallerId: approvedCallerId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sessionId': sessionId,
    'workspaceId': workspaceId,
    'text': text,
    'mode': mode.name,
    'source': source.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'attempt': attempt,
    if (approvedCallerId.isNotEmpty) 'approvedCallerId': approvedCallerId,
  };

  factory HarnessQueueItem.fromJson(Map<String, Object?> json) {
    T parse<T extends Enum>(List<T> values, String key, T fallback) {
      final String wire = json[key]?.toString() ?? '';
      for (final T value in values) {
        if (value.name == wire) return value;
      }
      return fallback;
    }

    final String id = json['id']?.toString().trim() ?? '';
    final String sessionId = json['sessionId']?.toString().trim() ?? '';
    final String workspaceId = json['workspaceId']?.toString().trim() ?? '';
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt']?.toString() ?? '',
    );
    if (id.isEmpty ||
        sessionId.isEmpty ||
        workspaceId.isEmpty ||
        createdAt == null) {
      throw const FormatException('Harness queue item identity is invalid');
    }
    return HarnessQueueItem(
      id: id,
      sessionId: sessionId,
      workspaceId: workspaceId,
      text: json['text']?.toString() ?? '',
      mode: parse(HarnessMessageMode.values, 'mode', HarnessMessageMode.queued),
      source: parse(
        HarnessMessageSource.values,
        'source',
        HarnessMessageSource.localUser,
      ),
      createdAt: createdAt.toUtc(),
      status: parse(
        HarnessQueueStatus.values,
        'status',
        HarnessQueueStatus.queued,
      ),
      attempt: int.tryParse(json['attempt']?.toString() ?? '') ?? 0,
      approvedCallerId: json['approvedCallerId']?.toString() ?? '',
    );
  }
}

typedef HarnessQueueClock = DateTime Function();
typedef HarnessQueueIdFactory = String Function();

/// VibeKits-owned durable queue. Official DSH owns accepted messages; after
/// `message.accepted`, this store immediately redacts the duplicate body.
class HarnessMessageQueueRepository {
  HarnessMessageQueueRepository({
    required Directory root,
    HarnessQueueClock? clock,
    HarnessQueueIdFactory? idFactory,
  }) : _root = root,
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? _newId;

  final Directory _root;
  final HarnessQueueClock _clock;
  final HarnessQueueIdFactory _idFactory;
  Future<void> _serial = Future<void>.value();
  final Map<String, List<HarnessQueueItem>> _memory =
      <String, List<HarnessQueueItem>>{};
  final Set<String> _pendingPersistence = <String>{};

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${pid.toRadixString(16)}';

  bool persistencePending({
    required String workspaceId,
    required String sessionId,
  }) => _pendingPersistence.contains(_fileFor(workspaceId, sessionId).path);

  Future<List<HarnessQueueItem>> load({
    required String workspaceId,
    required String sessionId,
    bool recover = true,
  }) => _exclusive(() async {
    final File file = _fileFor(workspaceId, sessionId);
    List<HarnessQueueItem> items = await _read(file);
    if (recover) {
      items = <HarnessQueueItem>[
        for (final HarnessQueueItem item in items)
          if (item.status != HarnessQueueStatus.running)
            item.status == HarnessQueueStatus.dispatching
                ? item.copyWith(status: HarnessQueueStatus.queued)
                : item,
      ];
      await _write(file, items);
    }
    return List<HarnessQueueItem>.unmodifiable(items);
  });

  Future<HarnessQueueItem> enqueue({
    required String workspaceId,
    required String sessionId,
    required String text,
    HarnessMessageMode mode = HarnessMessageMode.queued,
    HarnessMessageSource source = HarnessMessageSource.localUser,
    String approvedCallerId = '',
  }) => _exclusive(() async {
    final String body = text.trim();
    if (workspaceId.trim().isEmpty ||
        sessionId.trim().isEmpty ||
        body.isEmpty) {
      throw const FormatException('Harness queue message is incomplete');
    }
    final File file = _fileFor(workspaceId, sessionId);
    final List<HarnessQueueItem> items = await _read(file);
    final HarnessQueueItem item = HarnessQueueItem(
      id: _idFactory(),
      sessionId: sessionId.trim(),
      workspaceId: workspaceId.trim(),
      text: body,
      mode: mode,
      source: source,
      createdAt: _clock().toUtc(),
      status: HarnessQueueStatus.queued,
      attempt: 0,
      approvedCallerId: approvedCallerId.trim(),
    );
    items.add(item);
    await _write(file, items);
    return item;
  });

  Future<void> edit({
    required String workspaceId,
    required String sessionId,
    required String itemId,
    required String text,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    final int index = _editableIndex(items, itemId);
    final String body = text.trim();
    if (body.isEmpty) throw const FormatException('待执行消息不能为空');
    items[index] = items[index].copyWith(text: body);
  });

  Future<void> remove({
    required String workspaceId,
    required String sessionId,
    required String itemId,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    final int index = _editableIndex(items, itemId);
    items.removeAt(index);
  });

  Future<void> move({
    required String workspaceId,
    required String sessionId,
    required String itemId,
    required int delta,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    final int index = _editableIndex(items, itemId);
    final int target = (index + delta).clamp(0, items.length - 1);
    if (target == index || !items[target].editable) return;
    final HarnessQueueItem item = items.removeAt(index);
    items.insert(target, item);
  });

  Future<void> promote({
    required String workspaceId,
    required String sessionId,
    required String itemId,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    final int index = _editableIndex(items, itemId);
    int target = 0;
    while (target < items.length && !items[target].editable) {
      target += 1;
    }
    if (index == target) return;
    final HarnessQueueItem item = items.removeAt(index);
    items.insert(target, item);
  });

  Future<HarnessQueueItem?> claimNext({
    required String workspaceId,
    required String sessionId,
  }) => _exclusive(() async {
    final File file = _fileFor(workspaceId, sessionId);
    final List<HarnessQueueItem> items = await _read(file);
    if (items.any(
      (HarnessQueueItem item) =>
          item.status == HarnessQueueStatus.dispatching ||
          item.status == HarnessQueueStatus.running,
    )) {
      return null;
    }
    final int index = items.indexWhere(
      (HarnessQueueItem item) => item.editable,
    );
    if (index < 0) return null;
    final HarnessQueueItem claimed = items[index].copyWith(
      status: HarnessQueueStatus.dispatching,
      attempt: items[index].attempt + 1,
    );
    items[index] = claimed;
    await _write(file, items);
    return claimed;
  });

  Future<void> markAccepted({
    required String workspaceId,
    required String sessionId,
    required String itemId,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    final int index = items.indexWhere(
      (HarnessQueueItem item) => item.id == itemId,
    );
    if (index < 0 || items[index].status != HarnessQueueStatus.dispatching) {
      return;
    }
    items[index] = items[index].copyWith(
      text: '',
      status: HarnessQueueStatus.running,
    );
  });

  Future<void> release({
    required String workspaceId,
    required String sessionId,
    required String itemId,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    final int index = items.indexWhere(
      (HarnessQueueItem item) => item.id == itemId,
    );
    if (index < 0 || items[index].status != HarnessQueueStatus.dispatching) {
      return;
    }
    items[index] = items[index].copyWith(status: HarnessQueueStatus.queued);
  });

  Future<void> finishRunning({
    required String workspaceId,
    required String sessionId,
  }) => _update(workspaceId, sessionId, (List<HarnessQueueItem> items) {
    items.removeWhere(
      (HarnessQueueItem item) => item.status == HarnessQueueStatus.running,
    );
  });

  Future<void> _update(
    String workspaceId,
    String sessionId,
    void Function(List<HarnessQueueItem> items) update,
  ) => _exclusive(() async {
    final File file = _fileFor(workspaceId, sessionId);
    final List<HarnessQueueItem> items = await _read(file);
    update(items);
    await _write(file, items);
  });

  int _editableIndex(List<HarnessQueueItem> items, String itemId) {
    final int index = items.indexWhere(
      (HarnessQueueItem item) => item.id == itemId,
    );
    if (index < 0) throw StateError('待执行消息不存在');
    if (!items[index].editable) throw StateError('只有待执行消息可以修改');
    return index;
  }

  File _fileFor(String workspaceId, String sessionId) {
    final String digest = sha256
        .convert(utf8.encode('${workspaceId.trim()}\u0000${sessionId.trim()}'))
        .toString();
    return File('${_root.path}${Platform.pathSeparator}$digest.json');
  }

  Future<List<HarnessQueueItem>> _read(File file) async {
    if (_pendingPersistence.contains(file.path)) {
      return List<HarnessQueueItem>.of(
        _memory[file.path] ?? const <HarnessQueueItem>[],
      );
    }
    final File backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    if (!await file.exists()) return <HarnessQueueItem>[];
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on Object {
      if (!await backup.exists()) rethrow;
      decoded = jsonDecode(await backup.readAsString());
    }
    if (decoded is! Map || decoded['items'] is! List) {
      throw const FormatException('Harness queue file is invalid');
    }
    final List<HarnessQueueItem> items = <HarnessQueueItem>[
      for (final Object? value in decoded['items'] as List)
        if (value is Map)
          HarnessQueueItem.fromJson(value.cast<String, Object?>()),
    ];
    _memory[file.path] = List<HarnessQueueItem>.of(items);
    return items;
  }

  Future<void> _write(File file, List<HarnessQueueItem> items) async {
    _memory[file.path] = List<HarnessQueueItem>.of(items);
    await file.parent.create(recursive: true);
    final File temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final File backup = File('${file.path}.bak');
    try {
      await _retryIo(() async {
        await temporary.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 1,
            'items': items
                .map((HarnessQueueItem item) => item.toJson())
                .toList(),
          }),
          flush: true,
        );
        if (await backup.exists()) await backup.delete();
        if (await file.exists()) await file.rename(backup.path);
        await temporary.rename(file.path);
        if (await backup.exists()) await backup.delete();
      });
      _pendingPersistence.remove(file.path);
    } on Object {
      _pendingPersistence.add(file.path);
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<T> _retryIo<T>(Future<T> Function() operation) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (int attempt = 0; attempt < 5; attempt += 1) {
      try {
        return await operation();
      } on FileSystemException catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt < 4) {
          await Future<void>.delayed(
            Duration(milliseconds: 40 * (1 << attempt)),
          );
        }
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _serial = _serial.then((_) async {
      RandomAccessFile? lock;
      try {
        await _root.create(recursive: true);
        lock = await File(
          '${_root.path}${Platform.pathSeparator}.queue.lock',
        ).open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (lock != null) {
          try {
            await lock.unlock();
          } on Object {
            // Closing the descriptor also releases the operating-system lock.
          }
          await lock.close();
        }
      }
    });
    return completer.future;
  }
}

typedef HarnessQueuedSubmit =
    Future<bool> Function(String text, String idempotencyKey);

class HarnessMessageQueueScheduler {
  HarnessMessageQueueScheduler({
    required this.repository,
    required this.workspaceId,
    required this.sessionId,
    required this.submit,
  });

  final HarnessMessageQueueRepository repository;
  final String workspaceId;
  final String sessionId;
  final HarnessQueuedSubmit submit;
  bool _busy = false;
  bool _approvalWaiting = false;
  bool _dispatching = false;

  void updateHarnessState({required bool busy, required bool approvalWaiting}) {
    _busy = busy;
    _approvalWaiting = approvalWaiting;
    if (!busy && !approvalWaiting) unawaited(dispatchNext());
  }

  Future<bool> dispatchNext() async {
    if (_busy || _approvalWaiting || _dispatching) return false;
    _dispatching = true;
    try {
      final HarnessQueueItem? item = await repository.claimNext(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
      if (item == null) return false;
      final bool accepted = await submit(item.text, item.idempotencyKey);
      if (accepted) {
        await repository.markAccepted(
          workspaceId: workspaceId,
          sessionId: sessionId,
          itemId: item.id,
        );
        _busy = true;
      } else {
        await repository.release(
          workspaceId: workspaceId,
          sessionId: sessionId,
          itemId: item.id,
        );
      }
      return accepted;
    } finally {
      _dispatching = false;
    }
  }

  Future<void> onTurnFinished() async {
    await repository.finishRunning(
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    _busy = false;
    _approvalWaiting = false;
    await dispatchNext();
  }
}
