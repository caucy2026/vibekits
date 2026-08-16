import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _CreateSessionNative = Pointer<Void> Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Int32,
);
typedef _CreateSessionDart = Pointer<Void> Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
);
typedef _ReleaseSessionNative = Void Function(Pointer<Void>);
typedef _ReleaseSessionDart = void Function(Pointer<Void>);
typedef _RunFloatNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Float>,
  Size,
  Pointer<Int64>,
  Size,
);
typedef _RunFloatDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Float>,
  int,
  Pointer<Int64>,
  int,
);
typedef _ResultDataNative = Pointer<Float> Function(Pointer<Void>);
typedef _ResultDataDart = Pointer<Float> Function(Pointer<Void>);
typedef _ResultSizeNative = Size Function(Pointer<Void>);
typedef _ResultSizeDart = int Function(Pointer<Void>);
typedef _ResultDimensionNative = Int64 Function(Pointer<Void>, Size);
typedef _ResultDimensionDart = int Function(Pointer<Void>, int);
typedef _ReleaseResultNative = Void Function(Pointer<Void>);
typedef _ReleaseResultDart = void Function(Pointer<Void>);
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();

class OnnxTensorResult {
  const OnnxTensorResult({required this.values, required this.shape});

  final Float32List values;
  final List<int> shape;
}

class OnnxBridge {
  OnnxBridge._(this.library, this.runtimePath)
    : _createSession = library
          .lookupFunction<_CreateSessionNative, _CreateSessionDart>(
            'vibekits_ort_create_session',
          ),
      _releaseSession = library
          .lookupFunction<_ReleaseSessionNative, _ReleaseSessionDart>(
            'vibekits_ort_release_session',
          ),
      _runFloat = library.lookupFunction<_RunFloatNative, _RunFloatDart>(
        'vibekits_ort_run_float',
      ),
      _resultData = library.lookupFunction<_ResultDataNative, _ResultDataDart>(
        'vibekits_ort_result_data',
      ),
      _resultLength = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'vibekits_ort_result_length',
          ),
      _resultRank = library.lookupFunction<_ResultSizeNative, _ResultSizeDart>(
        'vibekits_ort_result_rank',
      ),
      _resultDimension = library
          .lookupFunction<_ResultDimensionNative, _ResultDimensionDart>(
            'vibekits_ort_result_dimension',
          ),
      _releaseResult = library
          .lookupFunction<_ReleaseResultNative, _ReleaseResultDart>(
            'vibekits_ort_release_result',
          ),
      _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'vibekits_ort_last_error',
      );

  /// Keeps the native bridge loaded for the lifetime of all sessions.
  final DynamicLibrary library;
  final String runtimePath;
  final _CreateSessionDart _createSession;
  final _ReleaseSessionDart _releaseSession;
  final _RunFloatDart _runFloat;
  final _ResultDataDart _resultData;
  final _ResultSizeDart _resultLength;
  final _ResultSizeDart _resultRank;
  final _ResultDimensionDart _resultDimension;
  final _ReleaseResultDart _releaseResult;
  final _LastErrorDart _lastError;

  static OnnxBridge load({String? nativeDirectory}) {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前 ONNX 桥接只完成 Windows；macOS 运行时由平台适配层提供。');
    }
    final String directory =
        nativeDirectory ?? File(Platform.resolvedExecutable).parent.path;
    final String bridgePath = _join(directory, 'vibekits_onnx.dll');
    final String runtimePath = _join(directory, 'onnxruntime.dll');
    if (!File(bridgePath).existsSync()) {
      throw StateError('找不到 ONNX 桥接：$bridgePath');
    }
    if (!File(runtimePath).existsSync()) {
      throw StateError('找不到 ONNX Runtime：$runtimePath');
    }
    return OnnxBridge._(DynamicLibrary.open(bridgePath), runtimePath);
  }

  OnnxSession openSession(String modelPath, {int threadCount = 1}) {
    if (!File(modelPath).existsSync()) {
      throw ArgumentError.value(modelPath, 'modelPath', '模型文件不存在');
    }
    final Pointer<Utf16> runtime = runtimePath.toNativeUtf16();
    final Pointer<Utf16> model = modelPath.toNativeUtf16();
    try {
      final Pointer<Void> handle = _createSession(
        runtime,
        model,
        threadCount.clamp(1, 32),
      );
      if (handle == nullptr) throw StateError(_errorMessage());
      return OnnxSession._(this, handle);
    } finally {
      calloc.free(runtime);
      calloc.free(model);
    }
  }

  String _errorMessage() {
    final Pointer<Utf8> value = _lastError();
    if (value == nullptr) return 'ONNX Runtime 返回未知错误';
    final String text = value.toDartString();
    return text.isEmpty ? 'ONNX Runtime 返回未知错误' : text;
  }

  static String _join(String parent, String child) {
    final String separator = Platform.pathSeparator;
    return parent.endsWith(separator)
        ? '$parent$child'
        : '$parent$separator$child';
  }
}

class OnnxSession {
  OnnxSession._(this._bridge, this._handle);

  final OnnxBridge _bridge;
  Pointer<Void> _handle;

  bool get isClosed => _handle == nullptr;

  OnnxTensorResult run(Float32List input, List<int> shape) {
    if (isClosed) throw StateError('ONNX 会话已释放');
    if (input.isEmpty || shape.isEmpty || shape.any((int value) => value < 1)) {
      throw ArgumentError('ONNX 输入和形状不能为空或包含非正维度');
    }
    final int expected = shape.fold<int>(1, (int a, int b) => a * b);
    if (expected != input.length) {
      throw ArgumentError('输入长度 ${input.length} 与形状 $shape（$expected）不一致');
    }

    final Pointer<Float> nativeInput = calloc<Float>(input.length);
    final Pointer<Int64> nativeShape = calloc<Int64>(shape.length);
    nativeInput.asTypedList(input.length).setAll(0, input);
    nativeShape.asTypedList(shape.length).setAll(0, shape);
    Pointer<Void> result = nullptr;
    try {
      result = _bridge._runFloat(
        _handle,
        nativeInput,
        input.length,
        nativeShape,
        shape.length,
      );
      if (result == nullptr) throw StateError(_bridge._errorMessage());
      final int rank = _bridge._resultRank(result);
      final int length = _bridge._resultLength(result);
      final List<int> outputShape = List<int>.generate(
        rank,
        (int index) => _bridge._resultDimension(result, index),
        growable: false,
      );
      final Pointer<Float> output = _bridge._resultData(result);
      if (length > 0 && output == nullptr) {
        throw StateError('ONNX 输出指针为空');
      }
      return OnnxTensorResult(
        values: Float32List.fromList(output.asTypedList(length)),
        shape: outputShape,
      );
    } finally {
      if (result != nullptr) _bridge._releaseResult(result);
      calloc.free(nativeInput);
      calloc.free(nativeShape);
    }
  }

  void close() {
    if (isClosed) return;
    _bridge._releaseSession(_handle);
    _handle = nullptr;
  }
}
