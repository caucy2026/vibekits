import 'package:flutter/services.dart';

/// Android window role supplied by the native dual-screen coordinator.
class AndroidDisplayContext {
  const AndroidDisplayContext({
    required this.mode,
    required this.role,
    required this.displayId,
    required this.virtualWidth,
    required this.virtualHeight,
    required this.viewportTop,
    required this.viewportHeight,
  });

  final String mode;
  final String role;
  final int displayId;
  final int virtualWidth;
  final int virtualHeight;
  final int viewportTop;
  final int viewportHeight;

  bool get isContinuousCanvas => mode == 'dual' && role == 'continuous_canvas';

  static const MethodChannel _channel = MethodChannel('vibekits/display');

  static Future<AndroidDisplayContext> read() async {
    final Map<Object?, Object?>? raw = await _channel
        .invokeMapMethod<Object?, Object?>('getDisplayContext');
    return AndroidDisplayContext(
      mode: raw?['mode']?.toString() ?? 'single',
      role: raw?['role']?.toString() ?? 'primary',
      displayId: raw?['displayId'] is int ? raw!['displayId']! as int : 0,
      virtualWidth: raw?['virtualWidth'] is int
          ? raw!['virtualWidth']! as int
          : 1920,
      virtualHeight: raw?['virtualHeight'] is int
          ? raw!['virtualHeight']! as int
          : 2560,
      viewportTop: raw?['viewportTop'] is int ? raw!['viewportTop']! as int : 0,
      viewportHeight: raw?['viewportHeight'] is int
          ? raw!['viewportHeight']! as int
          : 1280,
    );
  }

  static Future<void> exitApp() => _channel.invokeMethod<void>('exitApp');
}
