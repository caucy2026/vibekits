import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

abstract final class PlatformCredentialStore {
  static Future<String?> read(String key) {
    if (Platform.isWindows) return _WindowsCredentials.read(key);
    if (Platform.isMacOS) return _MacKeychain.read(key);
    if (Platform.isAndroid) return _AndroidKeystore.read(key);
    throw UnsupportedError('当前平台没有可用的系统安全凭据存储');
  }

  static Future<void> write(String key, String value) {
    if (Platform.isWindows) return _WindowsCredentials.write(key, value);
    if (Platform.isMacOS) return _MacKeychain.write(key, value);
    if (Platform.isAndroid) return _AndroidKeystore.write(key, value);
    throw UnsupportedError('当前平台没有可用的系统安全凭据存储');
  }

  static Future<void> delete(String key) {
    if (Platform.isWindows) return _WindowsCredentials.delete(key);
    if (Platform.isMacOS) return _MacKeychain.delete(key);
    if (Platform.isAndroid) return _AndroidKeystore.delete(key);
    throw UnsupportedError('当前平台没有可用的系统安全凭据存储');
  }
}

abstract final class _AndroidKeystore {
  static const MethodChannel _channel = MethodChannel('vibekits/credentials');

  static Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', <String, String>{'key': key});

  static Future<void> write(String key, String value) async {
    await _channel.invokeMethod<void>('write', <String, String>{
      'key': key,
      'value': value,
    });
  }

  static Future<void> delete(String key) async {
    await _channel.invokeMethod<void>('delete', <String, String>{'key': key});
  }
}

final class _Credential extends ffi.Struct {
  @ffi.Uint32()
  external int flags;

  @ffi.Uint32()
  external int type;

  external ffi.Pointer<Utf16> targetName;
  external ffi.Pointer<Utf16> comment;

  @ffi.Uint32()
  external int lastWrittenLow;

  @ffi.Uint32()
  external int lastWrittenHigh;

  @ffi.Uint32()
  external int credentialBlobSize;

  external ffi.Pointer<ffi.Uint8> credentialBlob;

  @ffi.Uint32()
  external int persist;

  @ffi.Uint32()
  external int attributeCount;

  external ffi.Pointer<ffi.Void> attributes;
  external ffi.Pointer<Utf16> targetAlias;
  external ffi.Pointer<Utf16> userName;
}

typedef _CredWriteNative =
    ffi.Int32 Function(ffi.Pointer<_Credential>, ffi.Uint32);
typedef _CredWriteDart = int Function(ffi.Pointer<_Credential>, int);
typedef _CredReadNative =
    ffi.Int32 Function(
      ffi.Pointer<Utf16>,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Pointer<_Credential>>,
    );
typedef _CredReadDart =
    int Function(
      ffi.Pointer<Utf16>,
      int,
      int,
      ffi.Pointer<ffi.Pointer<_Credential>>,
    );
typedef _CredDeleteNative =
    ffi.Int32 Function(ffi.Pointer<Utf16>, ffi.Uint32, ffi.Uint32);
typedef _CredDeleteDart = int Function(ffi.Pointer<Utf16>, int, int);
typedef _CredFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CredFreeDart = void Function(ffi.Pointer<ffi.Void>);
typedef _GetLastErrorNative = ffi.Uint32 Function();
typedef _GetLastErrorDart = int Function();

abstract final class _WindowsCredentials {
  static const int _generic = 1;
  static const int _persistLocalMachine = 2;
  static const int _errorNotFound = 1168;
  static const String _prefix = 'Vibekits/Database/';

  static final ffi.DynamicLibrary _advapi = ffi.DynamicLibrary.open(
    'Advapi32.dll',
  );
  static final ffi.DynamicLibrary _kernel = ffi.DynamicLibrary.open(
    'Kernel32.dll',
  );
  static final _CredWriteDart _write = _advapi
      .lookupFunction<_CredWriteNative, _CredWriteDart>('CredWriteW');
  static final _CredReadDart _read = _advapi
      .lookupFunction<_CredReadNative, _CredReadDart>('CredReadW');
  static final _CredDeleteDart _delete = _advapi
      .lookupFunction<_CredDeleteNative, _CredDeleteDart>('CredDeleteW');
  static final _CredFreeDart _free = _advapi
      .lookupFunction<_CredFreeNative, _CredFreeDart>('CredFree');
  static final _GetLastErrorDart _lastError = _kernel
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  static Future<String?> read(String key) async {
    final ffi.Pointer<Utf16> target = '$_prefix$key'.toNativeUtf16();
    final ffi.Pointer<ffi.Pointer<_Credential>> result =
        calloc<ffi.Pointer<_Credential>>();
    try {
      if (_read(target, _generic, 0, result) == 0) {
        return null;
      }
      final _Credential credential = result.value.ref;
      final int size = credential.credentialBlobSize;
      if (size == 0) return '';
      if (size.isOdd || size > 5120) {
        throw const FormatException('系统凭据内容格式无效');
      }
      final List<int> bytes = credential.credentialBlob.asTypedList(size);
      final List<int> units = <int>[
        for (int index = 0; index < bytes.length; index += 2)
          bytes[index] | (bytes[index + 1] << 8),
      ];
      return String.fromCharCodes(units);
    } finally {
      if (result.value.address != 0) {
        _free(result.value.cast<ffi.Void>());
      }
      calloc.free(result);
      calloc.free(target);
    }
  }

  static Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    final List<int> units = value.codeUnits;
    // Windows 7 and later allow credential blobs up to 5 * 512 bytes.
    // Subscription URLs are commonly longer than passwords, so the former
    // 512-byte guard rejected otherwise valid Clash subscriptions.
    if (units.length * 2 > 2560) {
      throw const FormatException('安全凭据超过 Windows 凭据长度上限');
    }
    final ffi.Pointer<Utf16> target = '$_prefix$key'.toNativeUtf16();
    final ffi.Pointer<Utf16> username = key.toNativeUtf16();
    final ffi.Pointer<ffi.Uint8> blob = calloc<ffi.Uint8>(units.length * 2);
    final ffi.Pointer<_Credential> credential = calloc<_Credential>();
    try {
      final List<int> bytes = blob.asTypedList(units.length * 2);
      for (int index = 0; index < units.length; index++) {
        bytes[index * 2] = units[index] & 0xff;
        bytes[index * 2 + 1] = units[index] >> 8;
      }
      credential.ref
        ..flags = 0
        ..type = _generic
        ..targetName = target
        ..comment = ffi.nullptr
        ..lastWrittenLow = 0
        ..lastWrittenHigh = 0
        ..credentialBlobSize = bytes.length
        ..credentialBlob = blob
        ..persist = _persistLocalMachine
        ..attributeCount = 0
        ..attributes = ffi.nullptr
        ..targetAlias = ffi.nullptr
        ..userName = username;
      if (_write(credential, 0) == 0) {
        throw StateError('写入 Windows Credential Manager 失败（${_lastError()}）');
      }
    } finally {
      for (int index = 0; index < units.length * 2; index++) {
        blob[index] = 0;
      }
      calloc.free(credential);
      calloc.free(blob);
      calloc.free(username);
      calloc.free(target);
    }
  }

  static Future<void> delete(String key) async {
    final ffi.Pointer<Utf16> target = '$_prefix$key'.toNativeUtf16();
    try {
      if (_delete(target, _generic, 0) == 0) {
        final int error = _lastError();
        if (error != 0 && error != _errorNotFound) {
          throw StateError('删除 Windows Credential Manager 凭据失败（$error）');
        }
      }
    } finally {
      calloc.free(target);
    }
  }
}

abstract final class _MacKeychain {
  static const String _service = 'com.vibekits.database';
  static const String _encodedPrefix = 'vibekits:b64:';

  static Future<String?> read(String key) async {
    final ProcessResult result = await Process.run('security', <String>[
      'find-generic-password',
      '-a',
      key,
      '-s',
      _service,
      '-w',
    ], runInShell: false).timeout(const Duration(seconds: 10));
    if (result.exitCode == 44) return null;
    if (result.exitCode != 0) {
      throw StateError('读取 macOS Keychain 失败（${result.exitCode}）');
    }
    final String stored = '${result.stdout}'.replaceFirst(
      RegExp(r'\r?\n$'),
      '',
    );
    if (!stored.startsWith(_encodedPrefix)) return stored;
    try {
      return utf8.decode(base64Decode(stored.substring(_encodedPrefix.length)));
    } on Object {
      throw const FormatException('macOS Keychain 凭据编码无效');
    }
  }

  static Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    final ProcessResult result = await Process.run('security', <String>[
      'add-generic-password',
      '-U',
      '-a',
      key,
      '-s',
      _service,
      '-w',
      '$_encodedPrefix${base64Encode(utf8.encode(value))}',
    ], runInShell: false).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      throw StateError('写入 macOS Keychain 失败（${result.exitCode}）');
    }
  }

  static Future<void> delete(String key) async {
    final ProcessResult result = await Process.run('security', <String>[
      'delete-generic-password',
      '-a',
      key,
      '-s',
      _service,
    ], runInShell: false).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0 && result.exitCode != 44) {
      throw StateError('删除 macOS Keychain 凭据失败（${result.exitCode}）');
    }
  }
}
