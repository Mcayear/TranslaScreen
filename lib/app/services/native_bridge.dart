import 'package:flutter/services.dart';
import 'package:transla_screen/app/services/logger_service.dart';

class NativeBridge {
  static const MethodChannel _channel =
      MethodChannel('com.example.transla_screen/screen_capture');

  // 启动屏幕捕获意图并返回截图的字节数据
  static Future<Uint8List?> startScreenCapture() async {
    try {
      final Uint8List? imageBytes =
          await _channel.invokeMethod<Uint8List>('startScreenCapture');
      return imageBytes;
    } on PlatformException catch (e) {
      log.e(
          "[NativeBridge] Failed to start screen capture or get image bytes: '${e.message}'. Code: ${e.code}. Details: ${e.details}",
          error: e
          // stackTrace: e.stacktrace, // Removed as e.stacktrace is String? and logger can handle it from error: e
          );
      return null;
    }
  }
}
