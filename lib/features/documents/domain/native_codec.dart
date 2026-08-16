import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _MBToWideNative = Int32 Function(
  Uint32 codePage,
  Uint32 flags,
  Pointer<Uint8> multiByteStr,
  Int32 cbMultiByte,
  Pointer<Uint16> wideCharStr,
  Int32 cchWideChar,
);
typedef _MBToWideDart = int Function(
  int codePage,
  int flags,
  Pointer<Uint8> multiByteStr,
  int cbMultiByte,
  Pointer<Uint16> wideCharStr,
  int cchWideChar,
);
typedef _WideToMBNative = Int32 Function(
  Uint32 codePage,
  Uint32 flags,
  Pointer<Uint16> wideCharStr,
  Int32 cchWideChar,
  Pointer<Uint8> multiByteStr,
  Int32 cbMultiByte,
  Pointer<Uint8> defaultChar,
  Pointer<Int32> usedDefaultChar,
);
typedef _WideToMBDart = int Function(
  int codePage,
  int flags,
  Pointer<Uint16> wideCharStr,
  int cchWideChar,
  Pointer<Uint8> multiByteStr,
  int cbMultiByte,
  Pointer<Uint8> defaultChar,
  Pointer<Int32> usedDefaultChar,
);

/// Windows 代码页转换（GB18030/Big5 等），基于 `MultiByteToWideChar`。
///
/// 仅 Windows 可用；其他平台抛 [UnsupportedError]。
abstract final class NativeCodec {
  static const int _cpGbk = 936;
  static const int _cpGb18030 = 54936;
  static const int _cpBig5 = 950;

  static bool get isWindows => Platform.isWindows;

  /// 按 Windows 代码页解码字节为字符串。
  static String decode(int codePage, Uint8List bytes) {
    if (!Platform.isWindows) {
      throw UnsupportedError('该编码仅在 Windows 可用');
    }
    final DynamicLibrary lib = DynamicLibrary.open('kernel32.dll');
    final _MBToWideDart fn = lib.lookupFunction<_MBToWideNative, _MBToWideDart>(
      'MultiByteToWideChar',
    );

    final Pointer<Uint8> src = malloc<Uint8>(bytes.length);
    try {
      for (int index = 0; index < bytes.length; index++) {
        src[index] = bytes[index];
      }
      final int needed = fn(codePage, 0, src, bytes.length, nullptr, 0);
      if (needed == 0) {
        throw const FormatException('无法按该代码页解码');
      }
      final Pointer<Uint16> dst = malloc<Uint16>(needed);
      try {
        fn(codePage, 0, src, bytes.length, dst, needed);
        final List<int> units = List<int>.generate(needed, (int i) => dst[i]);
        return String.fromCharCodes(units);
      } finally {
        malloc.free(dst);
      }
    } finally {
      malloc.free(src);
    }
  }

  static String decodeGb18030(Uint8List bytes) => decode(_cpGb18030, bytes);

  static String decodeBig5(Uint8List bytes) => decode(_cpBig5, bytes);

  static String decodeGbk(Uint8List bytes) => decode(_cpGbk, bytes);

  static Uint8List encode(int codePage, String text) {
    if (!Platform.isWindows) {
      throw UnsupportedError('该编码写入目前仅在 Windows 可用');
    }
    final DynamicLibrary lib = DynamicLibrary.open('kernel32.dll');
    final _WideToMBDart fn = lib.lookupFunction<_WideToMBNative, _WideToMBDart>(
      'WideCharToMultiByte',
    );
    final Pointer<Utf16> source = text.toNativeUtf16();
    final Pointer<Int32> usedDefault = calloc<Int32>();
    try {
      final int length = text.codeUnits.length;
      final int needed = fn(
        codePage,
        0,
        source.cast<Uint16>(),
        length,
        nullptr,
        0,
        nullptr,
        usedDefault,
      );
      if (needed == 0) throw const FormatException('无法按该代码页编码');
      final Pointer<Uint8> output = malloc<Uint8>(needed);
      try {
        final int written = fn(
          codePage,
          0,
          source.cast<Uint16>(),
          length,
          output,
          needed,
          nullptr,
          usedDefault,
        );
        if (written == 0) throw const FormatException('无法按该代码页编码');
        if (usedDefault.value != 0) {
          throw const FormatException('文本含当前编码无法表示的字符');
        }
        return Uint8List.fromList(output.asTypedList(written));
      } finally {
        malloc.free(output);
      }
    } finally {
      calloc.free(usedDefault);
      malloc.free(source);
    }
  }

  static Uint8List encodeGb18030(String text) => encode(_cpGb18030, text);

  static Uint8List encodeBig5(String text) => encode(_cpBig5, text);
}
