import 'dart:typed_data';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _channel =
      MethodChannel('com.translascreen/native_bridge');

  // 检查并请求 SYSTEM_ALERT_WINDOW 权限
  // 返回 true 如果权限已授予，否则返回 false
  static Future<bool> requestSystemAlertWindowPermission() async {
    try {
      final bool? granted = await _channel
          .invokeMethod<bool>('requestSystemAlertWindowPermission');
      return granted ?? false;
    } on PlatformException catch (e) {
      print(
          "Failed to request System Alert Window permission: '${e.message}'.");
      return false;
    }
  }

  // 检查 SYSTEM_ALERT_WINDOW 权限是否已授予
  static Future<bool> canDrawOverlays() async {
    try {
      final bool? granted =
          await _channel.invokeMethod<bool>('canDrawOverlays');
      return granted ?? false;
    } on PlatformException catch (e) {
      print("Failed to check canDrawOverlays: '${e.message}'.");
      return false;
    }
  }

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
