import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:http/http.dart' as http;

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

  // HTTP 通信相关
  final String _mainAppUrl = 'http://localhost:10080/command';

  Future<void> _sendCommandViaHttp(String action,
      {Map<String, dynamic>? params}) async {
    try {
      final payload = {
        'action': action,
        if (params != null) ...params,
        'timestamp': DateTime.now().millisecondsSinceEpoch
      };
      final response = await http.post(
        Uri.parse(_mainAppUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(payload),
      );
      print(
          '[OverlayWidget] Sent command \'$action\' via HTTP. Response: ${response.statusCode} - ${response.body}');
      if (response.statusCode != 200) {
        print(
            '[OverlayWidget] Error sending command \'$action\': ${response.body}');
      }
    } catch (e) {
      print(
          '[OverlayWidget] Exception sending command \'$action\' via HTTP: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    // 初始化菜单展开/折叠的动画控制器
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    print('[OverlayWidget] Initialized. Communication will be via HTTP.');
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map<String, dynamic>) {
        print('[OverlayWidget] Received data in listener: $event');
        if (event['type'] == 'display_translation_mask' &&
            event['items'] != null) {
          final List<dynamic> itemsJson = event['items'];
          setState(() {
            _maskItems = itemsJson
                .map((item) => TranslationMaskItem.fromJson(item))
                .toList();
            _showTranslationMask = true;
            _isMenuOpen = false; // 收到遮罩数据时，如果菜单是开的就关掉
            _menuAnimationController.reset();
            // TODO: Make overlay fullscreen and non-interactive for mask
            // FlutterOverlayWindow.matchParent(); // This method doesn't exist
            // Attempt to make it very large and non-draggable for the mask.
            FlutterOverlayWindow.resizeOverlay(
                10000, 10000, false); // width, height, draggable
          });
        }
      } else if (event is String) {
        // 处理来自旧的 `FlutterOverlayWindow.shareData("some string");` 的简单字符串消息
        print('[OverlayWidget] Received simple message: $event');
        // 如果需要，可以在这里处理简单消息，例如显示一个 Snackbar 或更新一个文本区域
      } else {
        print('[OverlayWidget] Received unknown data type in listener: $event');
      }
    });
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
        if (_showTranslationMask) {
          _sendCommandViaHttp('reset_overlay_ui');
          setState(() {
            _showTranslationMask = false;
            _maskItems.clear();
            // Restore overlay to draggable and original size
            // Assuming 56*4 was a reasonable default interactive size. The draggable flag is set to true.
            FlutterOverlayWindow.resizeOverlay(56 * 4, 56 * 4, true);
          });
        } else {
          setState(() {
            _isMenuOpen = !_isMenuOpen;
            if (_isMenuOpen) {
              FlutterOverlayWindow.resizeOverlay(
                  56, 56 * 3, true); // 尺寸调整仍需插件API
              _menuAnimationController.forward();
            } else {
              FlutterOverlayWindow.resizeOverlay(56 * 4, 56 * 4, true);
              _menuAnimationController.reverse();
            }
          });
        }
      },
      onLongPress: () {
        _sendCommandViaHttp('start_fullscreen_translation');
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
                  offset: Offset(0, 52 * _menuAnimationController.value),
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: () {
                  _sendCommandViaHttp('start_fullscreen_translation');
                  setState(() {
                    // 点击后关闭菜单
                    _isMenuOpen = false;
                    _menuAnimationController.reverse();
                    FlutterOverlayWindow.resizeOverlay(56 * 4, 56 * 4, true);
                  });
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
                      Icon(Icons.fullscreen, color: Colors.white, size: 18),
                      Text('全屏',
                          style: TextStyle(color: Colors.white, fontSize: 9)),
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
                  offset: Offset(0, 52 * _menuAnimationController.value),
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: () {
                  _sendCommandViaHttp('start_area_selection');
                  setState(() {
                    // 点击后关闭菜单
                    _isMenuOpen = false;
                    _menuAnimationController.reverse();
                    FlutterOverlayWindow.resizeOverlay(56 * 4, 56 * 4, true);
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
                      Icon(Icons.crop, color: Colors.white, size: 18),
                      Text('选区',
                          style: TextStyle(color: Colors.white, fontSize: 9)),
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
          _buildTranslationMask(), // 仍然尝试构建，但数据可能不会更新
        ],
      ),
    );
  }
}
