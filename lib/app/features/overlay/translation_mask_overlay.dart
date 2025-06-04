import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:overlay_windows_plugin/overlay_windows_plugin.dart';
import 'package:transla_screen/app/services/logger_service.dart';

// 翻译遮罩项模型
class TranslationMaskItem {
  final Rect bbox;
  final String translatedText;
  final String? originalText;

  TranslationMaskItem({
    required this.bbox,
    required this.translatedText,
    this.originalText,
  });

  factory TranslationMaskItem.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox'] as Map<String, dynamic>;
    return TranslationMaskItem(
      bbox: Rect.fromLTWH(
        (bbox['l'] as num).toDouble(),
        (bbox['t'] as num).toDouble(),
        (bbox['w'] as num).toDouble(),
        (bbox['h'] as num).toDouble(),
      ),
      translatedText: json['translatedText'] as String,
      originalText: json['originalText'] as String?,
    );
  }
}

// 翻译遮罩 Overlay Widget
class TranslationMaskOverlay extends StatefulWidget {
  const TranslationMaskOverlay({super.key});

  @override
  _TranslationMaskOverlayState createState() => _TranslationMaskOverlayState();
}

class _TranslationMaskOverlayState extends State<TranslationMaskOverlay> {
  List<TranslationMaskItem> _maskItems = [];
  final _overlayWindowsPlugin = OverlayWindowsPlugin.defaultInstance;

  @override
  void initState() {
    super.initState();
    log.i('[TranslationMaskOverlay] 初始化翻译遮罩');

    _overlayWindowsPlugin.messageStream.listen((event) {
      log.i('[TranslationMaskOverlay] 收到消息: ${event.overlayWindowId}');

      if (event.message is Map<String, dynamic>) {
        final type = event.message['type']?.toString() ?? '';
        if (type == 'display_translation_mask' &&
            event.message['items'] is List) {
          final itemsJson = event.message['items'] as List<dynamic>;
          log.i('[TranslationMaskOverlay] 解析翻译项: ${itemsJson.length}个');

          setState(() {
            _maskItems = itemsJson
                .map((e) =>
                    TranslationMaskItem.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        } else if (type == 'close_translation_mask') {
          setState(() {
            _maskItems = [];
          });
          // 通知控制窗口
          _overlayWindowsPlugin
              .sendMessage(event.overlayWindowId, {'type': 'mask_closed'});
          // 关闭自身overlay
          _closeOverlay();
        }
      }
    });
  }

  /// 关闭当前overlay窗口
  void _closeOverlay() async {
    // 获取当前overlay的ID
    String? currentId;
    try {
      currentId = _overlayWindowsPlugin.messageStream
          .listen((event) {})
          .hashCode
          .toString();
    } catch (e) {
      log.e('[TranslationMaskOverlay] 无法获取当前overlay ID: $e');
    }

    if (currentId != null) {
      await _overlayWindowsPlugin.closeOverlayWindow(currentId);
    } else {
      log.w('[TranslationMaskOverlay] 尝试关闭overlay但无法获取ID');
    }
  }

  @override
  Widget build(BuildContext context) {
    log.i('[TranslationMaskOverlay] 构建UI, 项数: ${_maskItems.length}');

    // 如果测试环境中没有数据，添加测试数据
    if (_maskItems.isEmpty) {
      _maskItems = [
        TranslationMaskItem(
          bbox: Rect.fromLTWH(50, 50, 300, 80),
          translatedText: '这是测试数据1',
          originalText: 'This is test data 1',
        ),
        TranslationMaskItem(
          bbox: Rect.fromLTWH(50, 200, 350, 100),
          translatedText: '这是测试数据2',
          originalText: 'This is test data 2',
        ),
      ];
    }

    // 使用半透明背景
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.black.withOpacity(0.1),
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 添加状态指示
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.yellow, width: 2),
                ),
                child: Text(
                  '译文遮罩活跃中 [${_maskItems.length}项]',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            // 显示译文项
            ..._maskItems.map((item) {
              return Positioned(
                left: item.bbox.left,
                top: item.bbox.top,
                width: item.bbox.width,
                height: item.bbox.height,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    border: Border.all(color: Colors.yellow, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Center(
                    child: Text(
                      item.translatedText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: item.bbox.height * 0.7,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 3,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    ),
                  ),
                ),
              );
            }).toList(),

            // 关闭按钮
            Positioned(
              bottom: 20,
              right: 20,
              child: Material(
                color: Colors.red,
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () {
                    log.i('[TranslationMaskOverlay] 点击关闭按钮');
                    _overlayWindowsPlugin
                        .sendMessage("", {'type': 'mask_closed'});
                    _closeOverlay();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Text(
                      '关闭遮罩',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
