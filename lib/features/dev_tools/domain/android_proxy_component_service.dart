import 'dart:io';

import 'package:flutter/services.dart';

/// Android's signed proxy APK is the only executable Mihomo runtime on PAD.
abstract final class AndroidProxyComponentService {
  static const MethodChannel _channel = MethodChannel(
    'vibekits/proxy-component',
  );

  static Future<Map<String, Object?>> inspect() => _call('inspect');

  static Future<void> start(String configPath) async {
    final Map<String, Object?> result = await _call('start', <String, Object?>{
      'configPath': configPath,
    });
    if (result['running'] != true) {
      throw StateError('${result['message'] ?? 'PAD 代理组件启动失败'}');
    }
  }

  static Future<void> stop() async {
    final Map<String, Object?> result = await _call('stop');
    if (result['available'] != true) {
      throw StateError('${result['message'] ?? 'PAD 代理组件不可用'}');
    }
  }

  static Future<Map<String, Object?>> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!Platform.isAndroid) throw UnsupportedError('仅支持 Android PAD');
    final Map<Object?, Object?>? raw = await _channel
        .invokeMapMethod<Object?, Object?>(method, arguments)
        .timeout(const Duration(seconds: 45));
    return raw?.map((Object? key, Object? value) => MapEntry('$key', value)) ??
        <String, Object?>{'available': false, 'message': '组件无响应'};
  }
}
