import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class WindowsFileDrop {
  WindowsFileDrop._();

  static final WindowsFileDrop instance = WindowsFileDrop._();

  static const MethodChannel _channel = MethodChannel('vibekits/file_drop');
  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();
  final List<String> _pendingPaths = <String>[];
  Timer? _flushTimer;
  bool _started = false;

  Stream<List<String>> get files => _controller.stream;

  void start() {
    if (_started || !Platform.isWindows) return;
    _started = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'filesDropped') return;
      final List<String> paths = (call.arguments as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false);
      if (paths.isNotEmpty) _enqueue(paths);
    });
  }

  void _enqueue(List<String> paths) {
    for (final String path in paths) {
      if (!_pendingPaths.contains(path)) _pendingPaths.add(path);
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 120), () {
      if (_pendingPaths.isEmpty) return;
      final List<String> batch = List<String>.of(_pendingPaths);
      _pendingPaths.clear();
      _controller.add(batch);
    });
  }
}
