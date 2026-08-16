import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'supported_file_types.dart';

typedef _RegCreateKeyExWNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Pointer<Uint32>,
);
typedef _RegCreateKeyExWDart = int Function(
  Pointer<Void>,
  Pointer<Utf16>,
  int,
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Pointer<Uint32>,
);
typedef _RegSetValueExWNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Uint8>,
  Uint32,
);
typedef _RegSetValueExWDart = int Function(
  Pointer<Void>,
  Pointer<Utf16>,
  int,
  int,
  Pointer<Uint8>,
  int,
);
typedef _RegCloseKeyNative = Int32 Function(Pointer<Void>);
typedef _RegCloseKeyDart = int Function(Pointer<Void>);
typedef _ShChangeNotifyNative = Void Function(
  Int32,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _ShChangeNotifyDart = void Function(
  int,
  int,
  Pointer<Void>,
  Pointer<Void>,
);

/// Registers supported types for the current Windows user.
///
/// This advertises Vibekits in “Open with” and Default Apps. Windows remains
/// responsible for the user's default-app choice; the app never overwrites it.
abstract final class WindowsFileAssociations {
  static const String documentProgId = 'Vibekits.Document';
  static const String archiveProgId = 'Vibekits.Archive';

  static bool shouldRegisterExecutable(String executable) {
    if (!Platform.isWindows) return false;
    final String name = executable.replaceAll('\\', '/').split('/').last;
    return name.toLowerCase() == 'vibekits.exe';
  }

  static Future<void> registerCurrentExecutable({
    bool throwOnError = false,
  }) async {
    final String executable = Platform.resolvedExecutable;
    if (!shouldRegisterExecutable(executable)) return;
    registerExecutable(executable, throwOnError: throwOnError);
  }

  static void registerExecutable(
    String executable, {
    bool throwOnError = false,
  }) {
    try {
      _register(executable);
    } on Object {
      if (throwOnError) rethrow;
      // Association registration is best-effort and must never block startup.
    }
  }

  static void _register(String executable) {
    final DynamicLibrary advapi = DynamicLibrary.open('advapi32.dll');
    final _RegCreateKeyExWDart createKey = advapi
        .lookupFunction<_RegCreateKeyExWNative, _RegCreateKeyExWDart>(
          'RegCreateKeyExW',
        );
    final _RegSetValueExWDart setValue = advapi
        .lookupFunction<_RegSetValueExWNative, _RegSetValueExWDart>(
          'RegSetValueExW',
        );
    final _RegCloseKeyDart closeKey = advapi
        .lookupFunction<_RegCloseKeyNative, _RegCloseKeyDart>('RegCloseKey');

    void write(String key, String? name, String value) {
      final Pointer<Utf16> keyPointer = key.toNativeUtf16();
      final Pointer<Pointer<Void>> result = calloc<Pointer<Void>>();
      final Pointer<Uint32> disposition = calloc<Uint32>();
      try {
        final int hkeyCurrentUser = sizeOf<IntPtr>() == 8
            ? 0xFFFFFFFF80000001
            : 0x80000001;
        final int status = createKey(
          Pointer<Void>.fromAddress(hkeyCurrentUser),
          keyPointer,
          0,
          nullptr,
          0,
          0x20006, // KEY_WRITE
          nullptr,
          result,
          disposition,
        );
        if (status != 0) {
          throw StateError('RegCreateKeyExW 失败：$status · $key');
        }
        final Pointer<Utf16> valuePointer = value.toNativeUtf16();
        final Pointer<Utf16> namePointer = name == null
            ? nullptr
            : name.toNativeUtf16();
        try {
          final int setStatus = setValue(
            result.value,
            namePointer,
            0,
            1, // REG_SZ
            valuePointer.cast<Uint8>(),
            (value.codeUnits.length + 1) * 2,
          );
          if (setStatus != 0) {
            throw StateError('RegSetValueExW 失败：$setStatus · $key');
          }
        } finally {
          if (name != null) calloc.free(namePointer);
          calloc.free(valuePointer);
          closeKey(result.value);
        }
      } finally {
        calloc.free(keyPointer);
        calloc.free(result);
        calloc.free(disposition);
      }
    }

    final String command = '"$executable" "%1"';
    void progId(String id, String label) {
      final String base = 'Software\\Classes\\$id';
      write(base, null, label);
      write('$base\\DefaultIcon', null, '$executable,0');
      write('$base\\shell\\open\\command', null, command);
    }

    progId(documentProgId, 'Vibekits 文档');
    progId(archiveProgId, 'Vibekits 压缩文件');
    const String appBase = 'Software\\Classes\\Applications\\vibekits.exe';
    write(appBase, 'FriendlyAppName', 'Vibekits');
    write('$appBase\\shell\\open\\command', null, command);

    const String capabilities = 'Software\\Vibekits\\Capabilities';
    write(capabilities, 'ApplicationName', 'Vibekits');
    write(capabilities, 'ApplicationDescription', '本地文件查看、解码、压缩与系统工具融合器');
    write('Software\\RegisteredApplications', 'Vibekits', capabilities);

    for (final String extension in SupportedFileTypes.allExtensions) {
      final String dotted = '.$extension';
      final String progId =
          SupportedFileTypes.archiveExtensions.contains(extension)
          ? archiveProgId
          : documentProgId;
      write('$appBase\\SupportedTypes', dotted, '');
      write('Software\\Classes\\$dotted\\OpenWithProgids', progId, '');
      write('$capabilities\\FileAssociations', dotted, progId);
      final String contextMenu =
          'Software\\Classes\\SystemFileAssociations\\$dotted\\shell\\Vibekits';
      final bool archive = SupportedFileTypes.archiveExtensions.contains(
        extension,
      );
      write(
        contextMenu,
        'MUIVerb',
        archive ? '用 Vibekits 解压或查看' : '用 Vibekits 查看或解码',
      );
      write(contextMenu, 'Icon', '$executable,0');
      write(contextMenu, 'Position', 'Top');
      write(contextMenu, 'MultiSelectModel', 'Single');
      write('$contextMenu\\command', null, command);
    }

    final DynamicLibrary shell32 = DynamicLibrary.open('shell32.dll');
    shell32.lookupFunction<_ShChangeNotifyNative, _ShChangeNotifyDart>(
      'SHChangeNotify',
    )(0x08000000, 0, nullptr, nullptr); // SHCNE_ASSOCCHANGED
  }
}
