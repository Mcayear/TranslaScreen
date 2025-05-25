import 'dart:typed_data';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _channel =
      MethodChannel('com.translascreen/native_bridge');

  // requestSystemAlertWindowPermission and canDrawOverlays are now handled by flutter_overlay_window plugin
  // static Future<bool> requestSystemAlertWindowPermission() async { ... }
  // static Future<bool> canDrawOverlays() async { ... }

  // 启动屏幕捕获意图并返回截图的字节数据
  static Future<Uint8List?> startScreenCapture() async {
    try {
      final Uint8List? imageBytes =
          await _channel.invokeMethod<Uint8List>('startScreenCapture');
      return imageBytes;
    } on PlatformException catch (e) {
      print(
          "Failed to start screen capture or get image bytes: '${e.message}'.");
      return null;
    }
  }
}
