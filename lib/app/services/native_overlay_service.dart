import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:transla_screen/app/services/logger_service.dart';
import 'dart:io';

/// 负责与Java原生实现通信的服务，提供悬浮球和译文蒙版功能
class NativeOverlayService {
  static const MethodChannel _channel =
      MethodChannel('com.example.transla_screen/native_overlay');

  /// 单例实例
  static final NativeOverlayService _instance =
      NativeOverlayService._internal();
  factory NativeOverlayService() => _instance;
  NativeOverlayService._internal() {
    _setupMethodCallHandler();
  }

  /// 回调处理
  Function(String action)? onBubbleActionReceived;

  /// 错误处理回调
  Function(String error)? onOverlayError;

  /// 设置方法通道处理器
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      log.i('[NativeOverlayService] 收到方法调用: ${call.method}');

      switch (call.method) {
        case 'translate_fullscreen':
          if (onBubbleActionReceived != null) {
            onBubbleActionReceived!('translate_fullscreen');
          }
          break;
        case 'start_area_selection':
          if (onBubbleActionReceived != null) {
            onBubbleActionReceived!('start_area_selection');
          }
          break;
        case 'mask_closed':
          if (onBubbleActionReceived != null) {
            onBubbleActionReceived!('mask_closed');
          }
          break;
        case 'overlay_permission_denied':
          final errorMsg = call.arguments as String? ?? '悬浮窗权限被拒绝';
          log.e('[NativeOverlayService] 悬浮窗权限错误: $errorMsg');
          if (onOverlayError != null) {
            onOverlayError!(errorMsg);
          }
          break;
        case 'overlay_error':
          final errorMsg = call.arguments as String? ?? '悬浮窗创建失败';
          log.e('[NativeOverlayService] 悬浮窗错误: $errorMsg');
          if (onOverlayError != null) {
            onOverlayError!(errorMsg);
          }
          break;
        case 'overlay_menu_error':
          final errorMsg = call.arguments as String? ?? '悬浮窗菜单创建失败';
          log.e('[NativeOverlayService] 悬浮窗菜单错误: $errorMsg');
          if (onOverlayError != null) {
            onOverlayError!(errorMsg);
          }
          break;
        default:
          log.w('[NativeOverlayService] 未处理的方法调用: ${call.method}');
      }

      return null;
    });
  }

  /// 检查悬浮窗权限
  Future<bool> checkOverlayPermission() async {
    try {
      if (!Platform.isAndroid) return true;

      log.i('[NativeOverlayService] 检查悬浮窗权限');
      final bool hasPermission =
          await _channel.invokeMethod('checkOverlayPermission') ?? false;
      log.i('[NativeOverlayService] 悬浮窗权限状态: $hasPermission');
      return hasPermission;
    } catch (e) {
      log.e('[NativeOverlayService] 检查悬浮窗权限失败', error: e);
      return false;
    }
  }

  /// 请求悬浮窗权限
  Future<bool> requestOverlayPermission() async {
    try {
      if (!Platform.isAndroid) return true;

      log.i('[NativeOverlayService] 请求悬浮窗权限');
      final bool result =
          await _channel.invokeMethod('requestOverlayPermission') ?? false;
      log.i('[NativeOverlayService] 请求悬浮窗权限结果: $result');
      return result;
    } catch (e) {
      log.e('[NativeOverlayService] 请求悬浮窗权限失败', error: e);
      return false;
    }
  }

  /// 显示悬浮球
  Future<bool> showFloatingBubble() async {
    try {
      // 先检查权限
      if (Platform.isAndroid) {
        final bool hasPermission = await checkOverlayPermission();
        if (!hasPermission) {
          await requestOverlayPermission();
          // 再次检查权限
          final bool permissionGranted = await checkOverlayPermission();
          if (!permissionGranted) {
            log.e('[NativeOverlayService] 显示悬浮球失败: 没有悬浮窗权限');
            return false;
          }
        }
      }

      log.i('[NativeOverlayService] 显示悬浮球');
      return await _channel.invokeMethod('showFloatingBubble') ?? false;
    } catch (e) {
      log.e('[NativeOverlayService] 显示悬浮球失败', error: e);
      if (onOverlayError != null) {
        onOverlayError!('显示悬浮球失败: $e');
      }
      return false;
    }
  }

  /// 隐藏悬浮球
  Future<bool> hideFloatingBubble() async {
    try {
      log.i('[NativeOverlayService] 隐藏悬浮球');
      return await _channel.invokeMethod('hideFloatingBubble') ?? false;
    } catch (e) {
      log.e('[NativeOverlayService] 隐藏悬浮球失败', error: e);
      return false;
    }
  }

  /// 显示译文蒙版
  /// [items] 要显示的译文项列表
  Future<bool> showTranslationOverlay(List<Map<String, dynamic>> items) async {
    try {
      // 先检查权限
      if (Platform.isAndroid) {
        final bool hasPermission = await checkOverlayPermission();
        if (!hasPermission) {
          await requestOverlayPermission();
          // 再次检查权限
          final bool permissionGranted = await checkOverlayPermission();
          if (!permissionGranted) {
            log.e('[NativeOverlayService] 显示译文蒙版失败: 没有悬浮窗权限');
            return false;
          }
        }
      }

      log.i('[NativeOverlayService] 显示译文蒙版，项数: ${items.length}');
      final data = {
        'items': items,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      return await _channel.invokeMethod('showTranslationOverlay',
              {'translationData': jsonEncode(data)}) ??
          false;
    } catch (e) {
      log.e('[NativeOverlayService] 显示译文蒙版失败', error: e);
      if (onOverlayError != null) {
        onOverlayError!('显示译文蒙版失败: $e');
      }
      return false;
    }
  }

  /// 隐藏译文蒙版
  Future<bool> hideTranslationOverlay() async {
    try {
      log.i('[NativeOverlayService] 隐藏译文蒙版');
      return await _channel.invokeMethod('hideTranslationOverlay') ?? false;
    } catch (e) {
      log.e('[NativeOverlayService] 隐藏译文蒙版失败', error: e);
      return false;
    }
  }
}
