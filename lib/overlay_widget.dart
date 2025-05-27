import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

// TranslationMaskItem 类，用于表示翻译遮罩的每个条目
class TranslationMaskItem {
  final Rect bbox;
  final String translatedText;
  final String? originalText; // 可选，用于调试或对比

  TranslationMaskItem({
    required this.bbox,
    required this.translatedText,
    this.originalText,
  });

  // 从 JSON Map 创建实例
  factory TranslationMaskItem.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox'];
    return TranslationMaskItem(
      bbox: Rect.fromLTWH(
        (bbox['l'] as num).toDouble(),
        (bbox['t'] as num).toDouble(),
        (bbox['w'] as num).toDouble(),
        (bbox['h'] as num).toDouble(),
      ),
      translatedText: json['translatedText'],
      originalText: json['originalText'],
    );
  }
}

class InteractiveOverlayUI extends StatefulWidget {
  const InteractiveOverlayUI({super.key});

  @override
  State<InteractiveOverlayUI> createState() => _InteractiveOverlayUIState();
}

class _InteractiveOverlayUIState extends State<InteractiveOverlayUI>
    with SingleTickerProviderStateMixin {
  // 状态变量
  bool _isMenuOpen = false; // 菜单是否展开
  bool _showTranslationMask = false; // 是否显示翻译遮罩
  List<TranslationMaskItem> _maskItems = []; // 翻译遮罩项列表

  // 动画控制器
  late AnimationController _menuAnimationController;

  @override
  void initState() {
    super.initState();

    // 初始化菜单展开/折叠的动画控制器
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    print(
        '[OverlayWidget] Initializing and listening to FlutterOverlayWindow.overlayListener.');
    // 监听来自主应用的消息
    FlutterOverlayWindow.overlayListener.listen((event) {
      print('[OverlayWidget] Raw event received by overlayListener: $event');
      _handleMessage(event);
    });
  }

  // 处理来自主应用的消息
  void _handleMessage(dynamic message) {
    if (message == null) {
      print('[OverlayWidget] _handleMessage received null message.');
      return;
    }

    try {
      final Map<String, dynamic> data;
      if (message is String) {
        try {
          data = jsonDecode(message) as Map<String, dynamic>;
        } catch (e) {
          print(
              '[OverlayWidget] Failed to decode JSON message: $message, error: $e');
          return;
        }
      } else if (message is Map<String, dynamic>) {
        data = message;
      } else {
        print(
            '[OverlayWidget] Received message of unexpected type: ${message.runtimeType}, message: $message');
        return;
      }

      final String? type = data['type'] as String?;
      print(
          '[OverlayWidget] _handleMessage processing: type=$type, data=$data');

      if (type == 'display_translation_mask') {
        final List<dynamic>? items = data['items'] as List<dynamic>?;
        if (items != null) {
          setState(() {
            _maskItems = items
                .map((item) =>
                    TranslationMaskItem.fromJson(item as Map<String, dynamic>))
                .toList();
            _showTranslationMask = true;
            if (_isMenuOpen) {
              _isMenuOpen = false;
              _menuAnimationController.reverse();
              FlutterOverlayWindow.resizeOverlay(56, 56, true);
            }
          });
          print('[OverlayWidget] Handled "display_translation_mask".');
        } else {
          print(
              '[OverlayWidget] "display_translation_mask" received null or invalid items.');
        }
      } else if (type == 'reset_overlay_ui') {
        setState(() {
          _showTranslationMask = false;
          _maskItems.clear();
          if (_isMenuOpen) {
            _isMenuOpen = false;
            _menuAnimationController.reverse();
            FlutterOverlayWindow.resizeOverlay(56, 56, true);
          }
        });
        print('[OverlayWidget] Handled "reset_overlay_ui".');
      } else {
        print(
            '[OverlayWidget] Received unhandled message type: "$type". This message might be intended for the main application.');
      }
    } catch (e, s) {
      print('[OverlayWidget] Error in _handleMessage: $e');
      print('[OverlayWidget] Stacktrace: $s');
      print('[OverlayWidget] Original message causing error: $message');
    }
  }

  @override
  void dispose() {
    _menuAnimationController.dispose();
    super.dispose();
  }

  // 构建 FAB
  Widget _buildFab() {
    return GestureDetector(
      onTap: () {
        print("FAB tapped");
        // 如果当前显示翻译遮罩，则关闭遮罩
        if (_showTranslationMask) {
          final command =
              jsonEncode({'type': 'command', 'action': 'reset_overlay_ui'});
          print(
              "[OverlayWidget] FAB tap (close mask): Sending command to main app: $command");
          FlutterOverlayWindow.shareData(command);
          setState(() {
            _showTranslationMask = false;
            _maskItems.clear();
            // 注意：这里 FAB 的颜色会变，但大小不会变，因为菜单未涉及
          });
        } else {
          // 否则，切换菜单展开/折叠状态
          setState(() {
            _isMenuOpen = !_isMenuOpen;
            if (_isMenuOpen) {
              FlutterOverlayWindow.resizeOverlay(56, 56 * 3, true);
              _menuAnimationController.forward();
            } else {
              FlutterOverlayWindow.resizeOverlay(56, 56, true);
              _menuAnimationController.reverse();
            }
          });
        }
      },
      onLongPress: () {
        // 长按触发全屏翻译
        final command = jsonEncode(
            {'type': 'command', 'action': 'start_fullscreen_translation'});
        print(
            "[OverlayWidget] FAB Long press: Sending command to main app: $command");
        FlutterOverlayWindow.shareData(command);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _showTranslationMask
              ? Colors.red
              : Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          _showTranslationMask ? Icons.close : Icons.translate,
          color: Colors.white,
        ),
      ),
    );
  }

  // 构建展开的菜单
  Widget _buildExpandedMenu() {
    return AnimatedOpacity(
      opacity: _isMenuOpen ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !_isMenuOpen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 全屏翻译按钮
            AnimatedBuilder(
              animation: _menuAnimationController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, 60 * _menuAnimationController.value),
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: () {
                  final command = jsonEncode({
                    'type': 'command',
                    'action': 'start_fullscreen_translation'
                  });
                  print(
                      "[OverlayWidget] Fullscreen button tapped: Sending command to main app: $command");
                  FlutterOverlayWindow.shareData(command);
                  // 点击后关闭菜单
                  // setState(() {
                  //   _isMenuOpen = false;
                  //   _menuAnimationController.reverse();
                  // });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fullscreen, color: Colors.white, size: 20),
                      Text('全屏',
                          style: TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),

            // 选区翻译按钮
            AnimatedBuilder(
              animation: _menuAnimationController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, 60 * _menuAnimationController.value),
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: () {
                  final command = jsonEncode(
                      {'type': 'command', 'action': 'start_area_selection'});
                  print(
                      "[OverlayWidget] Area selection button tapped: Sending command to main app: $command");
                  FlutterOverlayWindow.shareData(command);
                  // 点击后关闭菜单
                  setState(() {
                    _isMenuOpen = false;
                    _menuAnimationController.reverse();
                    FlutterOverlayWindow.resizeOverlay(56, 56, true);
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.crop, color: Colors.white, size: 20),
                      Text('选区',
                          style: TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建翻译遮罩
  Widget _buildTranslationMask() {
    if (!_showTranslationMask || _maskItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: _maskItems.map((item) {
        // 计算适当的字体大小 - 可以根据实际情况调整算法
        final fontSize = (item.bbox.height * 0.6).clamp(8.0, 24.0);

        return Positioned(
          left: item.bbox.left,
          top: item.bbox.top,
          width: item.bbox.width,
          height: item.bbox.height,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              border: Border.all(color: Colors.yellow, width: 1.0),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(2.0),
            child: Center(
              child: Text(
                item.translatedText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // 展开的菜单
          _buildExpandedMenu(),
          // FAB
          _buildFab(),
        ],
      ),
    );
  }
}

// 覆盖入口点
@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: InteractiveOverlayUI(),
    ),
  );
}
